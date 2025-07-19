#!/bin/bash
# This script is the entrypoint for the Delve Docker container.
# It handles cleanup, sets user permissions, and then starts the application services.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Cleanup Task (runs as root) ---
# Check if the setup script requested a cleanup of the data directory.
if [ -f "/data/.del_files" ]; then
    echo "[INFO] Cleanup marker found. Removing existing log data..."
    # Remove all contents of the logs directory.
    rm -rf /data/logs/*
    # Remove the marker file itself.
    rm -f /data/.del_files
    echo "[INFO] Cleanup complete."
fi

# --- User and Group ID Setup (runs as root) ---
# Check if the PUID and PGID environment variables are set.
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    # Get the current UID and GID of the 'delve' user.
    CURRENT_UID=$(id -u delve)
    CURRENT_GID=$(id -g delve)

    # If the provided IDs are different from the current ones, update them.
    if [ "$PUID" != "$CURRENT_UID" ] || [ "$PGID" != "$CURRENT_GID" ]; then
        echo "Updating delve user with UID: ${PUID} and GID: ${PGID}"
        # Use -o to allow non-unique (duplicate) IDs.
        groupmod -o -g "$PGID" delve
        usermod -o -u "$PUID" delve
    fi
fi

# --- Permissions Setup (runs as root) ---
# Ensure the /data directory is owned by the delve user and group.
# This is critical for allowing the non-root process to write logs
# and manage the exclusion list in the mounted volume.
echo "Ensuring /data directory permissions..."
chown -R delve:delve /data

echo "--- Starting Delve Services as user 'delve' ---"

# Use gosu to drop root privileges and execute the rest of the startup
# process as the 'delve' user.
exec gosu delve bash -c '
  set -m # Enable Job Control for the sub-shell

  echo "[INFO] Starting logging daemon..."
  /usr/local/bin/docker-log-daemon.sh &

  echo "[INFO] Starting web server..."
  exec gunicorn --bind 0.0.0.0:5001 --chdir /app app:app
'
