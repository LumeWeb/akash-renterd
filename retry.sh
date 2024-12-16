#!/bin/sh

# Retry function with exponential backoff
retry_command() {
    local max_attempts=5
    local timeout=1
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]
    do
        "$@"
        exitCode=$?

        if [ $exitCode = 0 ]
        then
            break
        fi

        echo "Command failed (Attempt $attempt/$max_attempts). Retrying in $timeout seconds..."
        sleep $timeout
        timeout=$((timeout * 2))
        attempt=$((attempt + 1))
    done

    if [ $exitCode != 0 ]
    then
        echo "Command failed after $max_attempts attempts"
        return $exitCode
    fi

    return 0
} 