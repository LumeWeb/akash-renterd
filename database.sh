#!/bin/sh

# Source the retry functionality
. /retry.sh

# Escape special characters in database passwords
escape_db_password() {
    local pwd="$1"
    # Escape backslashes first, then quotes for MySQL config file
    echo "$pwd" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\x27/\\\x27/g'
}

# Source the retry functionality
. /retry.sh

# Escape special characters in database passwords
escape_db_password() {
    local pwd="$1"
    # Escape backslashes first, then quotes for MySQL config file
    echo "$pwd" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\x27/\\\x27/g'
}

setup_database() {
    if [ ! -z "$RENTERD_DB_URI" ]; then
        echo "MySQL mode detected"

        # Extract host and port from URI
        DB_HOST=$(echo $RENTERD_DB_URI | cut -d: -f1)
        DB_PORT=$(echo $RENTERD_DB_URI | cut -d: -f2)

        # Escape password before updating config
        local escaped_password
        escaped_password=$(escape_db_password "$RENTERD_DB_PASSWORD")

        # Create a new config file with proper values
        cat > /etc/my.cnf.d/client.cnf << EOF
[client]
ssl=true
ssl-verify-server-cert=false
user="$RENTERD_DB_USER"
password="$escaped_password"
host="$DB_HOST"
port="$DB_PORT"
EOF

        echo "Waiting for MySQL to be ready..."
        # Try to connect to MySQL with retries
        retry_command "mariadb -e 'SELECT 1 FROM DUAL;' >/dev/null 2>&1"

        if [ $? -eq 0 ]; then
            echo "Creating databases if they don't exist..."
            # Create databases with retry
            retry_command "mariadb -e 'CREATE DATABASE IF NOT EXISTS $RENTERD_DB_NAME;'"

            retry_command "mariadb -e 'CREATE DATABASE IF NOT EXISTS $RENTERD_DB_METRICS_NAME;'"

            echo "MySQL databases ready"
        else
            echo "Failed to connect to MySQL after multiple attempts"
            exit 1
        fi
    else
        echo "SQLite mode detected"
    fi
}
