#!/bin/bash
# This is the core logging daemon, adapted from the user-provided install script.
# It runs in a loop to log Docker containers from the host.

# --- Configuration ---
# The log directory is now /data/logs for better separation.
LOG_DIR="/data/logs"
DAEMON_LOG_FILE="${LOG_DIR}/daemon.log"

# Get the container's own ID at startup. The `hostname` command inside a
# container returns its short container ID.
MY_CONTAINER_ID=$(hostname)

# Use associative arrays to track the PIDs of the 'docker logs' processes
# and the start times of the containers they are tracking.
declare -A logging_pids
declare -A container_start_times

# --- Helper Functions ---

# Function to log the daemon's own activity for debugging purposes.
log_message() {
    mkdir -p "$(dirname "$DAEMON_LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$DAEMON_LOG_FILE"
}

# Archives the old log file when a container restarts or the daemon starts.
archive_log() {
    local container_name=$1
    local container_log_dir="${LOG_DIR}/${container_name}"
    local log_file="${container_log_dir}/${container_name}.log"

    if [ -f "$log_file" ]; then
        local timestamp=$(date '+%Y%m%d-%H%M%S')
        local archive_file="${container_log_dir}/${container_name}-${timestamp}.log.archived"
        log_message "Archiving ${log_file} to ${archive_file}"
        mv "$log_file" "$archive_file"
    fi
}

# Starts following logs for a specific container.
start_logging_for() {
    local container_name=$1
    local container_log_dir="${LOG_DIR}/${container_name}"
    
    mkdir -p "$container_log_dir"
    log_message "Starting log watch for container: ${container_name}"
    archive_log "$container_name"
    
    # Run 'docker logs -f' in the background to follow the log stream.
    /usr/bin/docker logs -f "$container_name" >> "${container_log_dir}/${container_name}.log" 2>&1 &
    
    logging_pids[$container_name]=$!
    container_start_times[$container_name]=$(docker inspect -f '{{.State.StartedAt}}' "$container_name")
}

# Stops the 'docker logs' process for a container that has stopped.
stop_logging_for() {
    local container_name=$1
    log_message "Stopping log watch for container: ${container_name}"
    if [[ -n "${logging_pids[$container_name]}" ]]; then
        kill "${logging_pids[$container_name]}"
        wait "${logging_pids[$container_name]}" 2>/dev/null
    fi
    archive_log "$container_name"
    unset logging_pids[$container_name]
    unset container_start_times[$container_name]
}

# --- Main Execution ---

log_message "--- Docker Log Daemon Started (Container ID: ${MY_CONTAINER_ID}) ---"

# Set up a trap to gracefully shut down logging processes on exit.
cleanup() {
    log_message "--- Docker Log Daemon Shutting Down ---"
    for name in "${!logging_pids[@]}"; do
        stop_logging_for "$name"
    done
    log_message "--- Shutdown complete ---"
    exit 0
}
trap cleanup SIGINT SIGTERM

# This is the main monitoring loop.
while true; do
    # Read all running containers, getting both their full ID and name.
    while read -r container_id container_name; do
        # Dynamically skip logging this container itself.
        # We use a glob match because `hostname` gives the short ID.
        if [[ "$container_id" == "$MY_CONTAINER_ID"* ]]; then
            continue
        fi

        # If we aren't already logging this container, start now.
        if [[ -z "${logging_pids[$container_name]}" ]]; then
            start_logging_for "$container_name"
        fi
    done < <(docker ps --format "{{.ID}} {{.Names}}")

    # Check our list of logged containers to see if any have stopped or restarted.
    for name in "${!logging_pids[@]}"; do
        if ! docker ps -q --filter "name=^${name}$" --filter "status=running" | grep -q .; then
            stop_logging_for "$name"
        else
            current_start_time=$(docker inspect -f '{{.State.StartedAt}}' "$name")
            if [[ "${container_start_times[$name]}" != "$current_start_time" ]]; then
                log_message "Restart detected for container: ${name}. Rotating logs."
                kill "${logging_pids[$name]}"
                wait "${logging_pids[$name]}" 2>/dev/null
                archive_log "$name"
                unset logging_pids[$name]
                unset container_start_times[$name]
            fi
        fi
    done

    sleep 10
done
```

### Important Next Steps

For the change to `/data/logs` to work correctly across the entire application, you will also need to update two other files:

1.  **`docker-compose.yml`**: Change the volume mount to point to the new path.
    ```yaml
    # ...
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      # UPDATE THIS LINE
      - ./generated-logs:/data/logs 
    ```

2.  **`app/app.py`**: Update the `POSSIBLE_LOG_DIRS` list so Flask knows where to look for the logs.
    ```python
    # ...
    # UPDATE THIS LIST
    POSSIBLE_LOG_DIRS = [
        "/data/logs/",      # Primary path inside the container
        "/var/log/docker/"  # Keep as a fallback
    ]
    # ...
    
