# Build stage for renterd
FROM golang:1.23 AS builder

# Install git
RUN apt-get update && apt-get install -y git

# Set working directory
WORKDIR /build

# Clone the repository
RUN git clone https://github.com/LumeWeb/renterd .
RUN git checkout lumeweb

# Generate build metadata
RUN go generate ./...

# Build renterd using the workflow build command
RUN CGO_ENABLED=1 go build -trimpath -a -ldflags '-s -w -linkmode external -extldflags "-static"' ./cmd/renterd

# Metrics exporter stage
FROM ghcr.io/lumeweb/akash-metrics-exporter:develop AS metrics-exporter

# Final stage
FROM alpine:latest

# Install required packages
RUN apk add --no-cache mysql-client mariadb-connector-c caddy

# Create MySQL config directory
RUN mkdir -p /etc/my.cnf.d
COPY client.cnf /etc/my.cnf.d/client.cnf

# Copy binaries and certificates
COPY --from=builder /build/renterd /usr/bin/renterd
COPY --from=metrics-exporter /usr/bin/metrics-exporter /usr/bin/akash-metrics-exporter
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Create required directories
RUN mkdir -p /var/log/caddy /data

# Copy configuration files
COPY Caddyfile /etc/caddy/Caddyfile
COPY retry.sh /retry.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /retry.sh

# Set environment variables
ENV PUID=0
ENV PGID=0
ENV RENTERD_API_PASSWORD=
ENV RENTERD_SEED=
ENV RENTERD_CONFIG_FILE=/data/renterd.yml
ENV RENTERD_NETWORK='mainnet'
ENV METRICS_PORT=9104
ENV METRICS_USERNAME=admin
ENV METRICS_PASSWORD=
ENV METRICS_TLS_ENABLED=false

# Setup volumes
VOLUME [ "/data" ]

# Expose ports
EXPOSE 443 444 8080 9980

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]