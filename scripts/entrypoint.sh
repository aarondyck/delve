#!/bin/bash
# This script is the entrypoint for the Delve Docker container.
# It starts the background daemon and the main web application as root.

# Enable Job Control, which allows us to run processes in the background.
set -m

echo "--- Starting Delve Services ---"

# Start the logging daemon script in the background.
echo "[INFO] Starting logging daemon..."
/usr/local/bin/docker-log-daemon.sh &

# Start the Gunicorn web server in the foreground.
# 'exec' replaces the current shell process with the gunicorn process, making it
# the main process (PID 1) for proper signal handling by Docker.
echo "[INFO] Starting web server..."
exec gunicorn --bind 0.0.0.0:5001 --chdir /app app:app
