#!/bin/bash
# This script is the entrypoint for the Delve Docker container.
# It starts the necessary background services and then the main web application.

# Enable Job Control, which allows us to run processes in the background.
set -m

echo "--- Starting Delve Services ---"

# Start the logging daemon script in the background.
# Its output will go to the container's stdout/stderr, which can be viewed with 'docker logs'.
echo "[INFO] Starting logging daemon..."
/usr/local/bin/docker-log-daemon.sh &

# Start the Gunicorn web server in the foreground.
# 'exec' replaces the current shell process with the gunicorn process. This is crucial
# because it makes gunicorn the main process (PID 1) of the container, allowing Docker
# to correctly manage the container's lifecycle and handle signals like SIGTERM.
#
# --bind: Binds Gunicorn to all network interfaces on port 5001.
# --chdir: Changes the working directory to /app so Gunicorn can find the 'app' module.
# app:app: Tells Gunicorn to run the 'app' object from the 'app' module (app.py).
echo "[INFO] Starting web server..."
exec gunicorn --bind 0.0.0.0:5001 --chdir /app app:app
