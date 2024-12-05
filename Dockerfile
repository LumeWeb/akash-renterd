ARG RENTERD_VERSION=1.0.8
ARG METRICS_EXPORTER_VERSION=develop

# Use the official Renterd image as base
FROM ghcr.io/lumeweb/akash-metrics-exporter:${METRICS_EXPORTER_VERSION} AS metrics-exporter
FROM ghcr.io/siafoundation/renterd:${RENTERD_VERSION} AS renterd

# Switch to root to perform installations
USER root

FROM alpine:latest

# Install MySQL client, authentication plugins, and Caddy
RUN apk add --no-cache mysql-client mariadb-connector-c caddy

# Copy the built executables from the builder stages
COPY --from=metrics-exporter /usr/bin/metrics-exporter /usr/bin/akash-metrics-exporter
COPY --from=renterd /usr/bin/renterd /usr/bin/renterd
COPY --from=renterd /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

VOLUME [ "/data" ]

# Create log directory for Caddy
RUN mkdir -p /var/log/caddy

# Copy configuration files
COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set environment variables with defaults
ENV METRICS_PORT=9104
ENV METRICS_USERNAME=admin
ENV METRICS_PASSWORD=
ENV METRICS_TLS_ENABLED=false

# Expose ports
EXPOSE 443 444 8080

# Use entrypoint
ENTRYPOINT ["/entrypoint.sh"]
