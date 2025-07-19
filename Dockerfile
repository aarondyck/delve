# Specifies a more recent, supported base image (Debian Bookworm).
FROM python:3.9-slim-bookworm

# Install dependencies:
# - docker.io: The Docker CLI client for the logging daemon.
# - ca-certificates & wget: Needed for package management and downloads.
# - gnupg: Provides the 'gpg' command.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    docker.io \
    ca-certificates \
    wget \
    gnupg && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory for subsequent commands in the container.
WORKDIR /app

# Copy the requirements file first to leverage Docker's layer caching.
COPY app/requirements.txt .

# Install the Python dependencies.
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire Flask application from the 'app' subdirectory.
COPY app/ /app/

# Copy the utility scripts into a standard executable path.
COPY scripts/docker-log-daemon.sh /usr/local/bin/
COPY scripts/entrypoint.sh /usr/local/bin/
COPY scripts/manage-logs.sh /usr/local/bin/

# Make the scripts executable.
RUN chmod +x /usr/local/bin/docker-log-daemon.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/manage-logs.sh

# Inform Docker that the container listens on this port at runtime.
EXPOSE 5001

# Set the main command to run when the container starts.
# The container will now start and run as root.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
