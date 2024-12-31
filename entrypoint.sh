#!/bin/sh

# Source the retry functionality
. /retry.sh

# Validate required environment variables
validate_env() {
    if [ -n "$METRICS_SERVICE_NAME" ] && [ -z "$METRICS_PASSWORD" ]; then
        echo "Error: METRICS_PASSWORD is required when METRICS_SERVICE_NAME is set"
        exit 1
    fi

    if [ "$RENTERD_CLUSTER_ENABLED" = "true" ]; then
        if [ -z "$ETCD_ENDPOINTS" ]; then
            echo "Error: ETCD_ENDPOINTS is required when RENTERD_CLUSTER_ENABLED is true"
            exit 1
        fi
        if [ -z "$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX" ]; then
            echo "Error: RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX is required when RENTERD_CLUSTER_ENABLED is true"
            exit 1
        fi
    fi
}

# Determine node type based on environment variables
get_node_type() {
    if [ "$RENTERD_AUTOPILOT_ENABLED" != "true" ] && [ "$RENTERD_WORKER_ENABLED" != "true" ]; then
        echo "bus"
    elif [ -n "$RENTERD_BUS_REMOTE_ADDR" ] && [ "$RENTERD_AUTOPILOT_ENABLED" != "true" ]; then
        echo "worker"
    elif [ "$RENTERD_WORKER_ENABLED" != "true" ] && [ -n "$RENTERD_BUS_REMOTE_ADDR" ]; then
        echo "autopilot"
    else
        echo "Error: Unable to determine node type from environment variables"
        exit 1
    fi
}

# Initialize ETCD connection and verify it works
init_etcd() {
    local etcd_args="--endpoints=$ETCD_ENDPOINTS"
    if [ -n "$ETCD_USERNAME" ] && [ -n "$ETCD_PASSWORD" ]; then
        etcd_args="$etcd_args --user=$ETCD_USERNAME:$ETCD_PASSWORD"
    fi
    
    if ! retry_command etcdctl $etcd_args endpoint health; then
        echo "Failed to connect to ETCD"
        exit 1
    fi
    echo $etcd_args
}

# Register node in ETCD with lease
register_node() {
    local node_type=$1
    local etcd_args=$2
    local node_url="$RENTERD_HTTP_ADDRESS"
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/discovery/renterd/$node_url"
    
    # Create lease
    LEASE_ID=$(etcdctl $etcd_args lease grant 60 | grep -o 'ID: [0-9]*' | cut -d' ' -f2)
    
    # Create JSON payload
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json=$(jq -n \
        --arg url "$node_url" \
        --arg type "$node_type" \
        --arg ts "$timestamp" \
        '{url: $url, type: $type, last_seen: $ts, priority: 0, is_healthy: true}')
    
    # Put key with lease
    echo "$json" | etcdctl $etcd_args --lease=$LEASE_ID put "$key" -
    
    echo "$LEASE_ID"
}

# Update node heartbeat
update_heartbeat() {
    local node_type=$1
    local etcd_args=$2
    local lease_id=$3
    local node_url="$RENTERD_HTTP_ADDRESS"
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/discovery/renterd/$node_url"
    
    while true; do
        # Keep lease alive
        etcdctl $etcd_args lease keep-alive $lease_id >/dev/null 2>&1 &
        
        # Update timestamp
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local json=$(jq -n \
            --arg url "$node_url" \
            --arg type "$node_type" \
            --arg ts "$timestamp" \
            '{url: $url, type: $type, last_seen: $ts, priority: 0, is_healthy: true}')
        
        echo "$json" | etcdctl $etcd_args put "$key" -
        sleep 30
    done
}

# Cleanup function
cleanup() {
    local etcd_args=$1
    local node_url="$RENTERD_HTTP_ADDRESS"
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/discovery/renterd/$node_url"
    
    # Remove node from ETCD
    etcdctl $etcd_args del "$key"
    
    # Kill all background processes
    kill $(jobs -p) 2>/dev/null
}

validate_env

# Setup database if MySQL URI is provided
if [ ! -z "$RENTERD_DB_URI" ]; then
    echo "MySQL mode detected"
    
    # Extract host and port from URI
    DB_HOST=$(echo $RENTERD_DB_URI | cut -d: -f1)
    DB_PORT=$(echo $RENTERD_DB_URI | cut -d: -f2)
    
    echo "Waiting for MySQL to be ready..."
    # Try to connect to MySQL with retries
    retry_command mariadb -h"$DB_HOST" \
        -P"$DB_PORT" \
        -u"$RENTERD_DB_USER" \
        -p"$RENTERD_DB_PASSWORD" \
        -e "SELECT 1;"
    
    if [ $? -eq 0 ]; then
        echo "Creating databases if they don't exist..."
        # Create databases with retry
        retry_command mariadb -h"$DB_HOST" \
            -P"$DB_PORT" \
            -u"$RENTERD_DB_USER" \
            -p"$RENTERD_DB_PASSWORD" \
            -e "CREATE DATABASE IF NOT EXISTS $RENTERD_DB_NAME;"

        retry_command mariadb -h"$DB_HOST" \
            -P"$DB_PORT" \
            -u"$RENTERD_DB_USER" \
            -p"$RENTERD_DB_PASSWORD" \
            -e "CREATE DATABASE IF NOT EXISTS $RENTERD_DB_METRICS_NAME;"
        
        echo "MySQL databases ready"
    else
        echo "Failed to connect to MySQL after multiple attempts"
        exit 1
    fi
else
    echo "SQLite mode detected"
fi

# Start background services once, outside the loop
#caddy run --config /etc/caddy/Caddyfile &

akash-metrics-exporter &

# Setup cluster if enabled
if [ "$RENTERD_CLUSTER_ENABLED" = "true" ]; then
    NODE_TYPE=$(get_node_type)
    ETCD_ARGS=$(init_etcd)
    LEASE_ID=$(register_node "$NODE_TYPE" "$ETCD_ARGS")
    
    # Start heartbeat in background
    update_heartbeat "$NODE_TYPE" "$ETCD_ARGS" "$LEASE_ID" &
    
    # Setup trap for cleanup
    trap "cleanup '$ETCD_ARGS'" EXIT INT TERM
fi

# Start background services
akash-metrics-exporter &

# Retry loop for just the main process
while true; do
    echo "Starting renterd..."
    if [ -z "$RENTERD_BUS_REMOTE_ADDR" ]; then
        renterd -env -http $RENTERD_HTTP_ADDRESS -dir ./data
    else
        renterd -env -http $RENTERD_HTTP_ADDRESS
    fi

    # If we get here, renterd exited
    echo "Process exited, restarting in 5 seconds..."
    sleep 5
done
