#!/bin/sh

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
    
    # Setup database
    setup_database
    
    # Start metrics exporter
    akash-metrics-exporter &
    
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
