# Specifies the base image. Using a specific, slim version is a good practice.
FROM python:3.9-slim-buster

# Install the Docker CLI client, which the logging daemon needs to interact
# with the host's Docker service. Chaining commands and cleaning up reduces image size.
RUN apt-get update && \
    apt-get install -y docker.io --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory for subsequent commands in the container.
WORKDIR /app

# Copy the requirements file first to leverage Docker's layer caching.
# This step will only be re-run if the requirements file changes.
COPY app/requirements.txt .

# Install the Python dependencies.
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire Flask application from the 'app' subdirectory into the container's /app directory.
COPY app/ /app/

# Copy the utility scripts into a standard executable path in the container.
COPY scripts/docker-log-daemon.sh /usr/local/bin/
COPY scripts/entrypoint.sh /usr/local/bin/

# Make the scripts executable so they can be run.
RUN chmod +x /usr/local/bin/docker-log-daemon.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Inform Docker that the container listens on this port at runtime.
EXPOSE 5001

# Set the main command to run when the container starts.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
