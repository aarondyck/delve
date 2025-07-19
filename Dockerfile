# Specifies a more recent, supported base image (Debian Bookworm).
FROM python:3.9-slim-bookworm

# Install dependencies:
# - docker.io: The Docker CLI client for the logging daemon.
# - ca-certificates & wget: Needed for package management and downloads.
# - gnupg: Provides the 'gpg' command needed to verify the gosu download.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    docker.io \
    ca-certificates \
    wget \
    gnupg && \
    rm -rf /var/lib/apt/lists/*

# Install gosu, a lightweight tool for dropping root privileges.
# This is more robust than using 'su' or 'sudo'.
RUN set -eux; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

# Create a non-root user and group for the application to run as.
# The user is created as a system user with no password and no shell.
RUN addgroup --system delve && \
    adduser --system --ingroup delve --no-create-home delve

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
# The container will start as root, and the entrypoint script will
# be responsible for dropping privileges to the 'delve' user.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
