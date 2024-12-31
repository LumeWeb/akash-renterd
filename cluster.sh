#!/bin/sh

# Source the retry functionality
. /retry.sh

# Determine node type based on environment variables
get_node_type() {
    if [ -n "$RENTERD_BUS_REMOTE_ADDR" ]; then
        if [ "$RENTERD_AUTOPILOT_ENABLED" = "true" ]; then
            echo "autopilot"
        else
            echo "worker"
        fi
    else
        if [ "$RENTERD_AUTOPILOT_ENABLED" != "true" ] && [ "$RENTERD_WORKER_ENABLED" != "true" ]; then
            echo "bus"
        else
            echo "Error: Unable to determine node type from environment variables"
            exit 1
        fi
    fi
}

# Initialize ETCD connection and verify it works
init_etcd() {
    local etcd_args="--endpoints=$ETCD_ENDPOINTS"
    if [ -n "$ETCD_USERNAME" ] && [ -n "$ETCD_PASSWORD" ]; then
        etcd_args="$etcd_args --user=$ETCD_USERNAME:$ETCD_PASSWORD"
    fi
    
    # Keep retrying until health check succeeds, but discard output
    retry_command etcdctl ${etcd_args} endpoint health >/dev/null
    
    # Return clean etcd args
    echo "$etcd_args"
}

# Register node in ETCD with lease
register_node() {
    local node_type=$1
    local etcd_args=$2
    # Extract the unique ID from AKASH_INGRESS_HOST (part before first dot)
    local node_id=$(echo "$AKASH_INGRESS_HOST" | cut -d. -f1)
    if [ -z "$node_id" ]; then
        echo "Failed to extract node ID from AKASH_INGRESS_HOST"
        exit 1
    fi
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/renterd/$node_id"
    
    # Set node URL based on type
    local node_url
    if [ "$node_type" = "worker" ]; then
        node_url="$RENTERD_WORKER_EXTERNAL_ADDR"
    elif [ "$node_type" = "bus" ]; then
        node_url="http://$AKASH_INGRESS_HOST"
    elif [ "$node_type" = "autopilot" ]; then
        node_url="http://$AKASH_INGRESS_HOST"
    else
        echo "Invalid node type: $node_type"
        exit 1
    fi
    
    # Create lease with retry
    local lease_output
    lease_output=$(retry_command etcdctl ${etcd_args} lease grant 60)
    LEASE_ID=$(echo "$lease_output" | grep -oE 'ID: [0-9a-fA-F]+' | cut -d' ' -f2)
    if [ -z "$LEASE_ID" ]; then
        echo "Failed to obtain valid lease ID"
        exit 1
    fi
    
    # Create JSON payload
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json=$(jq -n \
        --arg url "$node_url" \
        --arg type "$node_type" \
        --arg ts "$timestamp" \
        '{url: $url, type: $type, last_seen: $ts, priority: 0, is_healthy: true}')
    
    # Put key with lease
    echo "$json" | etcdctl ${etcd_args} --lease=$LEASE_ID put "$key" -
    
    echo "$LEASE_ID"
}

# Update node heartbeat
update_heartbeat() {
    local node_type=$1
    local etcd_args=$2
    local lease_id=$3
    local node_id=$(echo "$AKASH_INGRESS_HOST" | cut -d. -f1)
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/renterd/$node_id"
    
    # Set node URL based on type
    local node_url
    if [ "$node_type" = "worker" ]; then
        node_url="$RENTERD_WORKER_EXTERNAL_ADDR"
    elif [ "$node_type" = "bus" ]; then
        node_url="http://$AKASH_INGRESS_HOST"
    elif [ "$node_type" = "autopilot" ]; then
        node_url="http://$AKASH_INGRESS_HOST"
    else
        echo "Invalid node type: $node_type"
        exit 1
    fi
    
    while true; do
        # Keep lease alive with retry
        retry_command etcdctl ${etcd_args} lease keep-alive $lease_id >/dev/null 2>&1 &
        
        # Update timestamp
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local json=$(jq -n \
            --arg url "$node_url" \
            --arg type "$node_type" \
            --arg ts "$timestamp" \
            '{url: $url, type: $type, last_seen: $ts, priority: 0, is_healthy: true}')
        
        # Put with retry
        echo "$json" | retry_command etcdctl ${etcd_args} put "$key" -
        sleep 30
    done
}

# Cleanup function
cleanup() {
    local etcd_args=$1
    local node_id=$(echo "$AKASH_INGRESS_HOST" | cut -d. -f1)
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/renterd/$node_id"
    
    # Remove node from ETCD with retry
    retry_command etcdctl ${etcd_args} del "$key"
    
    # Kill all background processes
    kill $(jobs -p) 2>/dev/null
}

setup_cluster() {
    if [ "$RENTERD_CLUSTER_ENABLED" = "true" ]; then
        NODE_TYPE=$(get_node_type)
        ETCD_ARGS=$(init_etcd)
        LEASE_ID=$(register_node "$NODE_TYPE" "$ETCD_ARGS")
        
        # Start heartbeat in background
        update_heartbeat "$NODE_TYPE" "$ETCD_ARGS" "$LEASE_ID" &
        
        # Return ETCD_ARGS for cleanup
        echo "$ETCD_ARGS"
    fi
}
