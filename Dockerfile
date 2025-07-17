# Use an official lightweight Python image.
FROM python:3.9-slim-buster

# Install Docker CLI client, which is required by the logging daemon
RUN apt-get update && \
    apt-get install -y docker.io --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application and script files
COPY app.py index.html ./
COPY docker-log-daemon.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/

# Make the new scripts executable
RUN chmod +x /usr/local/bin/docker-log-daemon.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose the application port
EXPOSE 5001

# Set the entrypoint to our custom script
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
