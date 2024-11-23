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

# Start background services once, outside the loop
/usr/bin/metrics-exporter &
caddy run --config /etc/caddy/Caddyfile &

# Retry loop for just the main process
while true; do
    echo "Starting renterd..."
    renterd -env -s3.address :9981 -dir ./data

    # If we get here, renterd exited
    echo "Process exited, restarting in 5 seconds..."
    sleep 5
done