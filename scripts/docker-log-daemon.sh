#!/bin/bash
# This script runs as root to log Docker containers from the host,
# while setting file ownership based on PUID/PGID environment variables.

# --- Configuration ---
LOG_DIR="/data/logs"
DAEMON_LOG_FILE="${LOG_DIR}/daemon.log"
EXCLUDE_FILE="/data/exclude.list"

# Default to root (0) if PUID/PGID are not set.
PUID=${PUID:-0}
PGID=${PGID:-0}

# Get the container's own ID at startup to avoid logging itself.
MY_CONTAINER_ID=$(hostname)

# Use associative arrays to track PIDs and container start times.
declare -A logging_pids
declare -A container_start_times

# --- Helper Functions ---

# Logs the daemon's own activity for debugging.
log_message() {
    # Ensure the directory and file exist with the correct ownership before writing.
    mkdir -p "$(dirname "$DAEMON_LOG_FILE")"
    chown "${PUID}:${PGID}" "$(dirname "$DAEMON_LOG_FILE")"
    touch "$DAEMON_LOG_FILE"
    chown "${PUID}:${PGID}" "$DAEMON_LOG_FILE"
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
        # Ensure the archived file has the correct ownership.
        chown "${PUID}:${PGID}" "$archive_file"
    fi
}

# Starts following logs for a specific container.
start_logging_for() {
    local container_name=$1
    local container_log_dir="${LOG_DIR}/${container_name}"
    local log_file="${container_log_dir}/${container_name}.log"
    
    # Create directory and set ownership.
    mkdir -p "$container_log_dir"
    chown "${PUID}:${PGID}" "$container_log_dir"
    
    log_message "Starting log watch for container: ${container_name}"
    archive_log "$container_name"
    
    # Create the log file and set ownership before redirecting output to it.
    touch "$log_file"
    chown "${PUID}:${PGID}" "$log_file"

    /usr/bin/docker logs -f "$container_name" >> "$log_file" 2>&1 &
    
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

log_message "--- Docker Log Daemon Started (running as root) ---"
log_message "File ownership will be set to PUID=${PUID} and PGID=${PGID}."

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
    # Read the exclusion list.
    declare -A excluded_containers
    if [ -f "$EXCLUDE_FILE" ]; then
        while read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]] && continue
            excluded_containers["$line"]=1
        done < "$EXCLUDE_FILE"
    fi

    # Check for new, un-excluded containers to start logging.
    while read -r container_id container_name; do
        if [[ "$container_id" == "$MY_CONTAINER_ID"* ]] || \
           [[ -n "${excluded_containers[$container_name]}" ]] || \
           [[ -n "${logging_pids[$container_name]}" ]]; then
            continue
        fi
        start_logging_for "$container_name"
    done < <(docker ps --format "{{.ID}} {{.Names}}")

    # Check currently logged containers for state changes.
    for name in "${!logging_pids[@]}"; do
        if ! docker ps -q --filter "name=^${name}$" --filter "status=running" | grep -q .; then
            stop_logging_for "$name"; continue
        fi
        if [[ -n "${excluded_containers[$name]}" ]]; then
            log_message "Container '${name}' is now excluded. Stopping log watch."
            stop_logging_for "$name"; continue
        fi
        current_start_time=$(docker inspect -f '{{.State.StartedAt}}' "$name")
        if [[ "${container_start_times[$name]}" != "$current_start_time" ]]; then
            log_message "Restart detected for container: ${name}. Rotating logs."
            kill "${logging_pids[$name]}"
            wait "${logging_pids[$name]}" 2>/dev/null
            archive_log "$name"
            unset logging_pids[$name]; unset container_start_times[$name]
        fi
    done

    sleep 10
done
