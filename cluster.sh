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
    
    # Keep retrying until health check succeeds
    local health_output
    health_output=$(etcdctl ${etcd_args} endpoint health -w json)
    if ! echo "$health_output" | jq -e '.[-1].health' >/dev/null 2>&1; then
        echo >&2 "Failed to verify etcd health: $health_output"
        return 1
    fi
    
    # Return clean etcd args
    echo "$etcd_args"
}

# Get the URL for a node based on its type
get_node_url() {
    local node_type=$1
    case "$node_type" in
        "worker")
            echo "$RENTERD_WORKER_EXTERNAL_ADDR"
            ;;
        "bus")
            # Extract port from RENTERD_HTTP_ADDRESS (strip colon)
            local port=$(echo "$RENTERD_HTTP_ADDRESS" | sed 's/^://')
            # Try custom host first, fall back to default
            local host_var="AKASH_INGRESS_CUSTOM_HOST_${port}_0"
            local host=${!host_var:-$AKASH_INGRESS_HOST}
            echo "http://$host"
            ;;
        "autopilot")
            echo "http://$AKASH_INGRESS_HOST"
            ;;
        *)
            echo "Invalid node type: $node_type" >&2
            return 1
            ;;
    esac
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
    
    # Get node URL
    local node_url
    node_url=$(get_node_url "$node_type")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Create lease with retry and get JSON output
    local lease_output
    lease_output=$(retry_command etcdctl ${etcd_args} lease --hex grant 60 -w json)
    
    # Extract decimal lease ID and convert to hex
    local lease_id_dec
    lease_id_dec=$(echo "$lease_output" | jq -r .ID)
    if [ -z "$lease_id_dec" ] || [ "$lease_id_dec" = "null" ]; then
        echo "Failed to obtain valid lease ID from output: $lease_output"
        exit 1
    fi
    
    # Convert decimal to hex
    LEASE_ID=$(printf "%x\n" "$lease_id_dec")
    if [ -z "$LEASE_ID" ]; then
        echo "Failed to convert lease ID to hex: $lease_id_dec"
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
        
        # Initialize etcd connection with retries
        ETCD_ARGS=$(retry_command init_etcd)
        if [ -z "$ETCD_ARGS" ]; then
            echo "Failed to initialize etcd connection after multiple retries"
            exit 1
        fi

        LEASE_ID=$(retry_command register_node "$NODE_TYPE" "$ETCD_ARGS")
        if [ -z "$LEASE_ID" ]; then
            echo "Failed to register node after multiple retries"
            exit 1
        fi
        
        # Start heartbeat daemon
        /heartbeat.sh "$NODE_TYPE" "$ETCD_ARGS" "$LEASE_ID" </dev/null >/dev/null 2>&1 &
        
        # Return ETCD_ARGS for cleanup
        echo "$ETCD_ARGS"
    fi
}
