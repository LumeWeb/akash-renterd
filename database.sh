#!/bin/sh

# Source the retry functionality
. /retry.sh

setup_database() {
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
}
