import os
from flask import Flask, jsonify, Response, render_template

# --- Flask App Initialization ---
# When Flask runs, it will look for the 'templates' folder in the same directory
# as this script. Since this script is in 'app/', it will look for 'app/templates/'.
app = Flask(__name__)

# --- Configuration ---
# A list of possible log directories to check, in order of preference.
# The script will use the first valid directory it finds. This allows for
# flexibility whether running on a host system or in the Docker container.
POSSIBLE_LOG_DIRS = [
    "/var/log/docker/", # Standard path on many Linux systems & inside our container
    "/data/logs/"      # A common alternative for mounted volumes
]

# --- Helper Functions ---

def get_active_log_dir():
    """Finds the first valid, existing log directory from the list."""
    for d in POSSIBLE_LOG_DIRS:
        if os.path.exists(d) and os.path.isdir(d):
            return d
    return None

def is_safe_path(base, path):
    """
    Prevents directory traversal attacks by ensuring the requested path
    is a legitimate subdirectory of the base log directory.
    """
    try:
        # Resolve the absolute path of the user-provided path.
        # os.path.join handles combining the base and the potentially malicious path.
        resolved_path = os.path.realpath(os.path.join(base, path))
        # Ensure the resolved path is still inside the base directory.
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
    log_base_dir = get_active_log_dir()
    if not log_base_dir:
        return jsonify({"error": f"No valid log directory found. Checked: {POSSIBLE_LOG_DIRS}"}), 500
        
    try:
        # List all items in the log directory that are themselves directories.
        containers = [d for d in os.listdir(log_base_dir) if os.path.isdir(os.path.join(log_base_dir, d))]
        return jsonify(sorted(containers))
    except OSError as e:
        return jsonify({"error": f"Error reading log directory: {e}"}), 500


@app.route('/api/logs/<string:container_name>')
def list_log_files(container_name):
    """API endpoint to get a list of log files for a specific container."""
    log_base_dir = get_active_log_dir()
    if not log_base_dir:
        return jsonify({"error": "No valid log directory found."}), 500

    # Security check to prevent path traversal (e.g., '..')
    if not is_safe_path(log_base_dir, container_name):
        return jsonify({"error": "Access denied."}), 403

    container_path = os.path.join(log_base_dir, container_name)
    if not os.path.isdir(container_path):
        return jsonify({"error": "Container not found."}), 404

    try:
        # List all items in the container's log directory that are files.
        files = [f for f in os.listdir(container_path) if os.path.isfile(os.path.join(container_path, f))]
        # Sort in reverse to show newest (timestamped) files first.
        return jsonify(sorted(files, reverse=True))
    except OSError as e:
        return jsonify({"error": f"Error reading container directory: {e}"}), 500


@app.route('/api/log/<string:container_name>/<string:log_file_name>')
def get_log_content(container_name, log_file_name):
    """API endpoint to retrieve the content of a specific log file."""
    log_base_dir = get_active_log_dir()
    if not log_base_dir:
        return Response("No valid log directory found.", status=500, mimetype='text/plain')

    # Construct the full path and perform a security check.
    file_path = os.path.join(container_name, log_file_name)
    if not is_safe_path(log_base_dir, file_path):
        return Response("Access denied.", status=403, mimetype='text/plain')

    full_file_path = os.path.join(log_base_dir, file_path)
    try:
        # Open and read the file, ignoring potential encoding errors.
        with open(full_file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        # Return content as plain text, letting the browser handle rendering.
        return Response(content, mimetype='text/plain')
    except FileNotFoundError:
        return Response("Log file not found.", status=404, mimetype='text/plain')
    except Exception as e:
        return Response(f"Error reading file: {e}", status=500, mimetype='text/plain')


# This block is for running the app directly with 'python app.py' for development.
# In production, Gunicorn will be used as defined in the entrypoint.sh script.
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
