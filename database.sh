#!/bin/sh

# Source the retry functionality
. /retry.sh

# Escape special characters in database passwords
escape_db_password() {
    local pwd="$1"
    # Escape special characters for MySQL config
    echo "$pwd" | sed 's/[\\&@]/\\&/g'
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
        
        # Update client.cnf with actual values
        sed -i "s/RENTERD_DB_USER/$RENTERD_DB_USER/g" /etc/my.cnf.d/client.cnf
        sed -i "s/RENTERD_DB_PASSWORD/$escaped_password/g" /etc/my.cnf.d/client.cnf
        sed -i "s/RENTERD_DB_HOST/$DB_HOST/g" /etc/my.cnf.d/client.cnf
        sed -i "s/RENTERD_DB_PORT/$DB_PORT/g" /etc/my.cnf.d/client.cnf
        
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
