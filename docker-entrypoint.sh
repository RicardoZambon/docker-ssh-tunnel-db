#!/bin/sh
#
# docker-entrypoint.sh
#
# Establish an SSH tunnel to a remote database and keep it open.
#
# Authentication is auto-detected, in order of precedence:
#   1. SSH_KEY       - private key contents (PEM), written to a runtime file
#   2. SSH_KEY_PATH  - a private key mounted into the container (default
#                      /root/.ssh/id_rsa)
#   3. SSH_PASSWORD  - plain-text password via sshpass (original behavior)
#
# If none is provided, the container exits with an error.

set -eu

# --- Configuration (env vars, with defaults) ---
SSH_HOST="${SSH_HOST:-}"
SSH_USER="${SSH_USER:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
SSH_KEY="${SSH_KEY:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/root/.ssh/id_rsa}"
SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL:-5}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"

# Normalized runtime key: whichever source is used, the key ends up here with
# strict 0600 permissions (ssh refuses to use a world-readable private key,
# and bind-mounted files often inherit the host's permissions).
RUNTIME_KEY="/root/.ssh/tunnel_key"

# --- Validate required configuration ---
if [ -z "${SSH_HOST}" ] || [ -z "${SSH_USER}" ]; then
    echo "ERROR: SSH_HOST and SSH_USER are required." >&2
    exit 1
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

# --- Common ssh options (built up as positional params) ---
# StrictHostKeyChecking=no + UserKnownHostsFile=/dev/null keep this
# non-interactive for a throwaway tunnel. ServerAlive* is the keepalive: after
# roughly (interval * countmax) seconds of silence ssh exits, so a Docker
# --restart policy can revive the tunnel.
set -- \
    -p "${SSH_PORT}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval="${SSH_SERVER_ALIVE_INTERVAL}" \
    -o ServerAliveCountMax=3 \
    -N \
    -L "*:${DB_PORT}:${DB_HOST}:${DB_PORT}"

# --- Auth auto-detection ---
if [ -n "${SSH_KEY}" ]; then
    echo "Auth: SSH key (from SSH_KEY environment variable)."
    printf '%s\n' "${SSH_KEY}" > "${RUNTIME_KEY}"
    chmod 600 "${RUNTIME_KEY}"
    exec ssh -i "${RUNTIME_KEY}" -o IdentitiesOnly=yes "$@" "${SSH_USER}@${SSH_HOST}"
elif [ -f "${SSH_KEY_PATH}" ]; then
    echo "Auth: SSH key (from mounted file ${SSH_KEY_PATH})."
    cp "${SSH_KEY_PATH}" "${RUNTIME_KEY}"
    chmod 600 "${RUNTIME_KEY}"
    exec ssh -i "${RUNTIME_KEY}" -o IdentitiesOnly=yes "$@" "${SSH_USER}@${SSH_HOST}"
elif [ -n "${SSH_PASSWORD}" ]; then
    echo "Auth: password (sshpass)."
    exec sshpass -p "${SSH_PASSWORD}" ssh "$@" "${SSH_USER}@${SSH_HOST}"
else
    echo "ERROR: no authentication method provided." >&2
    echo "Set SSH_KEY, mount a key at SSH_KEY_PATH (${SSH_KEY_PATH}), or set SSH_PASSWORD." >&2
    exit 1
fi
