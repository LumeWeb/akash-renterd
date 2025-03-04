#!/bin/sh

if [ -f /akash-cfg/etcd.env ]; then
  set -a
  source /akash-cfg/config.env
  set +a
fi

# Source required modules
. /retry.sh
. /database.sh
. /cluster.sh

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

main() {
    validate_env
    
    # Start metrics exporter
    akash-metrics-exporter &
    
    # Setup database if we're a bus node
    if [ "$RENTERD_CLUSTER_ENABLED" = "true" ]; then
        NODE_TYPE=$(get_node_type)
        if [ "$NODE_TYPE" = "bus" ]; then
            setup_database
        fi
    else
        # When clustering is disabled, we're always a bus node
        setup_database
    fi
    
    # Setup cluster if enabled
    ETCD_ARGS=""
    if [ "$RENTERD_CLUSTER_ENABLED" = "true" ]; then
        ETCD_ARGS=$(setup_cluster)
        trap "cleanup '$ETCD_ARGS'" EXIT INT TERM
    fi
    
    # Retry loop for renterd process
    while true; do
        echo "Starting renterd..."
        if [ -z "$RENTERD_BUS_REMOTE_ADDR" ]; then
            renterd -env -http $RENTERD_HTTP_ADDRESS -dir ./data
        else
            renterd -env -http $RENTERD_HTTP_ADDRESS
        fi
        
        echo "Process exited, restarting in 5 seconds..."
        sleep 5
    done
}

main
