# Love Alpine
FROM alpine:latest

# Narcissism is not a sin
LABEL maintainer="halo@matriphe.com"

# Ask for SSH info on build
ARG SSH_HOST
ARG SSH_USER
ARG SSH_PASSWORD
ARG SSH_PORT=22

# Ask for DB Info on build
ARG DB_HOST=localhost
ARG DB_PORT=3306

# Set environments
ENV SSH_HOST=${SSH_HOST}
ENV SSH_USER=${SSH_USER}
ENV SSH_PASSWORD=${SSH_PASSWORD}
ENV SSH_PORT=${SSH_PORT}
ENV DB_HOST=${DB_HOST}
ENV DB_PORT=${DB_PORT}

# SSH key auth (provided at runtime only; keys are never baked into the image)
ENV SSH_KEY_PATH=/root/.ssh/id_rsa
ENV SSH_SERVER_ALIVE_INTERVAL=5

# Set timezone
ENV TIMEZONE="Asia/Jakarta"

# Set workdir
WORKDIR /root

# Install the tools
RUN apk add --no-cache \
    tzdata \
    ca-certificates \
    openssh \
    openssh-client \
    sshpass && \
    echo "${TIMEZONE}" >  /etc/timezone

# Copy the entrypoint that auto-detects SSH key vs password auth
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose port for MySQL, MS SQL, and PostgreSQL
EXPOSE 3306 1433 5432

# Establish the tunnel; auth (SSH key or password) is auto-detected at runtime
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
