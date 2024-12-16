#!/bin/sh

# Load environment variables
export METRICS_USERNAME=${METRICS_USERNAME:-admin}
export METRICS_PASSWORD=${METRICS_PASSWORD}
export METRICS_PORT=${METRICS_PORT:-9104}
export METRICS_TLS_ENABLED=${METRICS_TLS_ENABLED:-false}
export DOMAIN_NAME=${DOMAIN_NAME:-renterd.example.com}

if [ -z "$METRICS_PASSWORD" ]; then
  echo "Error: METRICS_PASSWORD is not set"
  exit 1
fi

# Source the retry functionality
. /retry.sh

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
#/usr/bin/akash-metrics-exporter &
#caddy run --config /etc/caddy/Caddyfile &

# Retry loop for just the main process
while true; do
    echo "Starting renterd..."
    renterd -env -http $RENTERD_HTTP_ADDRESS -s3.address $RENTERD_S3_ADDRESS -dir ./data

    # If we get here, renterd exited
    echo "Process exited, restarting in 5 seconds..."
    sleep 5
done
