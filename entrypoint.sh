#!/bin/sh
set -e

# Load environment variables
export METRICS_USERNAME=${METRICS_USERNAME:-admin}
export METRICS_PASSWORD=${METRICS_PASSWORD}
export METRICS_PORT=${METRICS_PORT:-9104}
export METRICS_TLS_ENABLED=${METRICS_TLS_ENABLED:-false}
export DOMAIN_NAME=${DOMAIN_NAME:-renterd.example.com}

if [ -z "$METRICS_PASSWORD" ]; then
    METRICS_PASSWORD=$(openssl rand -base64 12)
    echo "Generated metrics password: $METRICS_PASSWORD"
fi

# Start metrics exporter in background
/usr/bin/metrics-exporter &

# Start Caddy with authentication and SSL
caddy run --config /etc/caddy/Caddyfile &

# Start Renterd
renterd -env -http :9980 -s3.address :9981 -dir ./data
