import os
from flask import Flask, jsonify, Response, render_template

# --- Flask App Initialization ---
app = Flask(__name__)

# --- Configuration ---
# The standard log directory inside the container.
LOG_DIR = "/data/logs"
DAEMON_LOG_FILE = os.path.join(LOG_DIR, "daemon.log")

# --- Helper Functions ---

def is_safe_path(base, path):
    """
    Prevents directory traversal attacks by ensuring the requested path
    is a legitimate subdirectory of the base log directory.
    """
    try:
        resolved_path = os.path.realpath(os.path.join(base, path))
        return resolved_path.startswith(os.path.realpath(base))
    except (TypeError, ValueError):
        return False


# --- HTML Route ---

@app.route('/')
def index():
    """Serves the main HTML page from the 'templates' folder."""
    return render_template('index.html')


# --- API Endpoints ---

@app.route('/api/containers')
def list_containers():
    """API endpoint to get a list of container subdirectories."""
    try:
        # List all items in the log directory that are themselves directories.
        containers = [d for d in os.listdir(LOG_DIR) if os.path.isdir(os.path.join(LOG_DIR, d))]
        return jsonify(sorted(containers))
    except FileNotFoundError:
        # Handle the specific case where the log directory itself doesn't exist yet.
        return jsonify({"error": f"Log directory not found: {LOG_DIR}"}), 500
    except OSError as e:
        # Handle other potential OS-level errors like permission issues.
        return jsonify({"error": f"Error reading log directory: {e}"}), 500

@app.route('/api/daemon-log')
def get_daemon_log():
    """API endpoint to retrieve the content of the daemon's own log file."""
    try:
        with open(DAEMON_LOG_FILE, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        return Response(content, mimetype='text/plain')
    except FileNotFoundError:
        return Response(f"Daemon log file not found at {DAEMON_LOG_FILE}", status=404, mimetype='text/plain')
    except Exception as e:
        return Response(f"Error reading daemon log file: {e}", status=500, mimetype='text/plain')


@app.route('/api/logs/<string:container_name>')
def list_log_files(container_name):
    """API endpoint to get a list of log files for a specific container."""
    if not is_safe_path(LOG_DIR, container_name):
        return jsonify({"error": "Access denied."}), 403

    container_path = os.path.join(LOG_DIR, container_name)
    if not os.path.isdir(container_path):
        return jsonify({"error": "Container not found."}), 404

    try:
        files = [f for f in os.listdir(container_path) if os.path.isfile(os.path.join(container_path, f))]
        return jsonify(sorted(files, reverse=True))
    except OSError as e:
        return jsonify({"error": f"Error reading container directory: {e}"}), 500


@app.route('/api/log/<string:container_name>/<string:log_file_name>')
def get_log_content(container_name, log_file_name):
    """API endpoint to retrieve the content of a specific log file."""
    file_path = os.path.join(container_name, log_file_name)
    if not is_safe_path(LOG_DIR, file_path):
        return Response("Access denied.", status=403, mimetype='text/plain')

    full_file_path = os.path.join(LOG_DIR, file_path)
    try:
        with open(full_file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        return Response(content, mimetype='text/plain')
    except FileNotFoundError:
        return Response("Log file not found.", status=404, mimetype='text/plain')
    except Exception as e:
        return Response(f"Error reading file: {e}", status=500, mimetype='text/plain')


# This block is for running the app directly with 'python app.py' for development.
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
