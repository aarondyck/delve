#!/bin/bash
# This is the core logging daemon. It runs in a loop to log Docker containers
# from the host, while respecting an exclusion list.

# --- Configuration ---
LOG_DIR="/data/logs"
DAEMON_LOG_FILE="${LOG_DIR}/daemon.log"
# The daemon will check this file for a list of container names to ignore.
EXCLUDE_FILE="/data/exclude.list"

# Get the container's own ID at startup to avoid logging itself.
MY_CONTAINER_ID=$(hostname)

# Use associative arrays to track PIDs and container start times.
declare -A logging_pids
declare -A container_start_times

# --- Helper Functions ---

# Logs the daemon's own activity for debugging.
log_message() {
    mkdir -p "$(dirname "$DAEMON_LOG_FILE")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$DAEMON_LOG_FILE"
}

# Archives the old log file when a container restarts or stops being logged.
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
    
    /usr/bin/docker logs -f "$container_name" >> "${container_log_dir}/${container_name}.log" 2>&1 &
    
    logging_pids[$container_name]=$!
    container_start_times[$container_name]=$(docker inspect -f '{{.State.StartedAt}}' "$container_name")
}

# Stops the 'docker logs' process for a container.
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

# Gracefully shut down logging processes on exit.
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
    # --- Read the exclusion list into an associative array for fast lookups ---
    declare -A excluded_containers
    # Ensure the directory for the exclude file exists before trying to read it
    mkdir -p "$(dirname "$EXCLUDE_FILE")"
    if [ -f "$EXCLUDE_FILE" ]; then
        while read -r line || [[ -n "$line" ]]; do
            # Ignore comments and empty lines
            [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]] && continue
            excluded_containers["$line"]=1
        done < "$EXCLUDE_FILE"
    fi

    # --- Check for new, un-excluded containers to start logging ---
    while read -r container_id container_name; do
        # Condition 1: Skip logging this container itself.
        if [[ "$container_id" == "$MY_CONTAINER_ID"* ]]; then
            continue
        fi

        # Condition 2: Skip if the container is in the exclusion list.
        if [[ -n "${excluded_containers[$container_name]}" ]]; then
            continue
        fi

        # Condition 3: Skip if we are already logging this container.
        if [[ -n "${logging_pids[$container_name]}" ]]; then
            continue
        fi

        # If all checks pass, start logging.
        start_logging_for "$container_name"
    done < <(docker ps --format "{{.ID}} {{.Names}}")

    # --- Check currently logged containers for state changes ---
    for name in "${!logging_pids[@]}"; do
        # Condition 1: Stop logging if the container is no longer running.
        if ! docker ps -q --filter "name=^${name}$" --filter "status=running" | grep -q .; then
            stop_logging_for "$name"
            continue # Move to the next container in the loop
        fi

        # Condition 2: Stop logging if the container has been added to the exclusion list.
        if [[ -n "${excluded_containers[$name]}" ]]; then
            log_message "Container '${name}' is now excluded. Stopping log watch."
            stop_logging_for "$name"
            continue
        fi

        # Condition 3: Handle container restarts.
        current_start_time=$(docker inspect -f '{{.State.StartedAt}}' "$name")
        if [[ "${container_start_times[$name]}" != "$current_start_time" ]]; then
            log_message "Restart detected for container: ${name}. Rotating logs."
            kill "${logging_pids[$name]}"
            wait "${logging_pids[$name]}" 2>/dev/null
            archive_log "$name"
            unset logging_pids[$name]
            unset container_start_times[$name]
        fi
    done

    sleep 10
done
