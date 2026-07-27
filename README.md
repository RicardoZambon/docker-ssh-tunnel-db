# Docker DB SSH Tunnel

Create a tunnel to connect to remote databases (MySQL, SQL Server, PostgreSQL)
over SSH, authenticating with **either an SSH private key or a plain-text
password**.

## Authentication

The container auto-detects how to authenticate, in this order of precedence:

1. **SSH key from an environment variable** — `SSH_KEY` holds the private key contents.
2. **SSH key from a mounted file** — a key mounted into the container at `SSH_KEY_PATH` (default `/root/.ssh/id_rsa`).
3. **Password** — `SSH_PASSWORD` (uses `sshpass`).

If none is provided, the container exits with an error.

> **Security note:** password auth uses `sshpass`, which exposes the password in
> plain text (visible through `docker inspect` and the process list). Key-based
> auth is recommended. Keys are supplied **at runtime only** (mount or env var)
> and are never baked into the image layers.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SSH_HOST` | _(required)_ | SSH server host |
| `SSH_USER` | _(required)_ | SSH user |
| `SSH_PORT` | `22` | SSH port |
| `SSH_PASSWORD` | _(none)_ | Password (used only when no key is provided) |
| `SSH_KEY` | _(none)_ | Private key **contents** (PEM) |
| `SSH_KEY_PATH` | `/root/.ssh/id_rsa` | Path to a **mounted** private key file |
| `SSH_SERVER_ALIVE_INTERVAL` | `5` | Keepalive interval, in seconds |
| `DB_HOST` | `localhost` | Database host, as reachable **from the SSH server** |
| `DB_PORT` | `3306` | Database port (`3306` MySQL, `1433` SQL Server, `5432` PostgreSQL) |

`SSH_HOST`, `SSH_USER`, `SSH_PASSWORD`, `SSH_PORT`, `DB_HOST`, and `DB_PORT` may
also be provided as `--build-arg` values at build time. Keys are runtime-only
and cannot be passed as build args.

## Build

```console
docker build -t matriphe/tunnel:mysql1 .
```

You can still bake connection defaults into the image with build args (keys excepted):

```console
docker build -t matriphe/tunnel:mysql1 \
    --build-arg SSH_HOST=10.1.2.10 \
    --build-arg SSH_USER=user \
    --build-arg SSH_PASSWORD=secret \
    --build-arg DB_HOST=10.1.2.3 \
    --build-arg DB_PORT=3306 \
    .
```

## Usage

The tunnel binds `DB_PORT` inside the container; choose whatever local port you
want with `-p <local>:<DB_PORT>`. `--restart=unless-stopped` is recommended so
the tunnel comes back if the connection drops.

### With an SSH key file (recommended)

Mount your private key at the default `SSH_KEY_PATH` (`/root/.ssh/id_rsa`):

```console
docker run -d \
    --name=mysql1 \
    --restart=unless-stopped \
    -p 33066:3306 \
    -v "$(pwd)/.ssh2/id_rsa:/root/.ssh/id_rsa:ro" \
    -e SSH_HOST=169.57.168.198 \
    -e SSH_USER=mysqltunnel \
    -e DB_HOST=169.57.168.198 \
    -e DB_PORT=3306 \
    matriphe/tunnel:mysql1
```

This reproduces the plain SSH command:

```console
ssh -o ServerAliveInterval=5 -N -L 33066:169.57.168.198:3306 -i .ssh2/id_rsa mysqltunnel@169.57.168.198
```

Then connect from your host on the local port you mapped:

```console
mysql -u mysqlusername -p -P 33066 -h 127.0.0.1
```

> Mounting somewhere other than `/root/.ssh/id_rsa`? Point `SSH_KEY_PATH` at it,
> e.g. `-v "$(pwd)/keys/id_rsa:/keys/id_rsa:ro" -e SSH_KEY_PATH=/keys/id_rsa`.

### With an SSH key as an environment variable

Handy for docker-compose / CI where mounting a file is awkward:

```console
docker run -d \
    --name=mysql1 \
    --restart=unless-stopped \
    -p 33066:3306 \
    -e SSH_HOST=169.57.168.198 \
    -e SSH_USER=mysqltunnel \
    -e DB_HOST=169.57.168.198 \
    -e DB_PORT=3306 \
    -e SSH_KEY="$(cat .ssh2/id_rsa)" \
    matriphe/tunnel:mysql1
```

docker-compose:

```yaml
services:
  tunnel:
    image: matriphe/tunnel:mysql1
    restart: unless-stopped
    ports:
      - "33066:3306"
    environment:
      SSH_HOST: 169.57.168.198
      SSH_USER: mysqltunnel
      DB_HOST: 169.57.168.198
      DB_PORT: 3306
      SSH_KEY: |
        -----BEGIN OPENSSH PRIVATE KEY-----
        ...your private key...
        -----END OPENSSH PRIVATE KEY-----
```

### With a password (original behavior)

```console
docker run -d \
    --name=mysql2 \
    --restart=unless-stopped \
    -p 3333:3306 \
    -e SSH_HOST=192.168.1.123 \
    -e SSH_USER=newuser \
    -e SSH_PASSWORD=newsecret \
    -e SSH_PORT=2222 \
    -e DB_HOST=localhost \
    matriphe/tunnel:mysql1
```

## Notes

- **Staying connected:** the tunnel keeps itself alive with
  `ServerAliveInterval`. If the connection drops, `ssh` exits — pair it with
  Docker's `--restart=unless-stopped` (shown above) so the container reconnects
  automatically. Tune the interval with `SSH_SERVER_ALIVE_INTERVAL`.
- **Port mapping:** inside the container the tunnel binds `DB_PORT` on all
  interfaces; pick your host-side port with `-p <local>:<DB_PORT>`.
- **`DB_HOST`** is resolved from the **SSH server's** network. If the database
  runs on the SSH server itself, either `localhost` or the server's IP works.
