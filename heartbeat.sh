#!/bin/sh

# Source the retry functionality
. /retry.sh

# Main heartbeat daemon function
run_heartbeat() {
    local node_type=$1
    local etcd_args=$2
    local lease_id=$3
    local node_id=$(echo "$AKASH_INGRESS_HOST" | cut -d. -f1)
    local key="$RENTERD_CLUSTER_ETCD_DISCOVERY_PREFIX/renterd/$node_id"

    # Get node URL
    local node_url
    node_url=$(get_node_url "$node_type")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Start lease keep-alive in background
    etcdctl ${etcd_args} lease keep-alive $lease_id >/dev/null 2>&1 &
    local keep_alive_pid=$!

    # Trap to clean up background process
    trap 'kill $keep_alive_pid 2>/dev/null' EXIT

    # Main heartbeat loop
    while true; do
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local json=$(jq -n \
            --arg url "$node_url" \
            --arg type "$node_type" \
            --arg ts "$timestamp" \
            '{url: $url, type: $type, last_seen: $ts, priority: 0, is_healthy: true}')

        echo "$json" | retry_command etcdctl ${etcd_args} put "$key" -
        sleep 30
    done
}

# Start heartbeat if called directly
if [ "$#" -eq 3 ]; then
    run_heartbeat "$1" "$2" "$3"
fi
