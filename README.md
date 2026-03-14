# IRCord Infrastructure

Deployable IRCord public-facing infrastructure package:
- **Directory Service**: Public server listing API (Node.js)
- **Landing Page**: Static marketing and server list site
- **Nginx**: Reverse proxy and TLS termination for production

## Quick Start

### Prerequisites

- Docker and Docker Compose
- DNS records for the directory and landing domains
- TLS certificates for production, or let `deploy.sh` obtain them

### Development

```bash
docker-compose up -d
docker-compose logs -f
docker-compose down
```

Services:
- Directory API: `http://localhost:3000`
- Landing Page: `http://localhost:8080`

The published ports are bound to `127.0.0.1`, so they stay available for a host-level nginx reverse proxy without exposing the containers directly.

### Host nginx reverse proxy

If the server already runs nginx for TLS, do not start the Docker `nginx` service. Start only:

```bash
docker compose up -d directory landing
```

Then point the host nginx config at:
- `127.0.0.1:8080` for the landing page
- `127.0.0.1:3000` for the directory API

An example config is available at `nginx/host-proxy.conf.example`.

### Production

```bash
./deploy.sh
```

The installer asks for:
- Directory API domain (e.g., `directory.example.com`)
- Landing page domain (e.g., `chat.example.com`)
- TLS mode and optional Let's Encrypt validation method

`deploy.sh` is for the bundled Docker nginx setup that terminates TLS itself. If you already have nginx on the host and it owns ports `80/443`, use the host nginx flow above instead of the Docker `nginx` service.

## Services

### Directory Service (`ircord-directory/`)

Node.js API for managing public IRCord server listings.

**Endpoints:**
- `POST /api/servers/register` — Register a new server
- `POST /api/servers/ping` — Keep server on the list (5 min interval)
- `POST /api/servers/unregister` — Remove server from list
- `GET /api/servers` — List all public servers
- `GET /api/servers/:id` — Get single server details
- `GET /api/health` — Health check

**Environment variables:**
- `PORT` - server port, default `3000`
- `NODE_ENV` - environment name
- `DATA_DIR` - data directory for persistent storage

**Server timeout:** Servers are removed from the list if they don't ping within 10 minutes.

### Landing Page (`ircord-landing/`)

Static landing site with:
- Public server list fetched from directory API
- Quick connect via `ircord://` protocol
- Manual fallback when the native client is missing
- Download links for clients

`deploy.sh` generates `ircord-landing/config.js` with the correct directory and landing URLs for the target environment.

## Structure

```
ircord-infra/
├── docker-compose.yml
├── deploy.sh
├── nginx/
│   ├── nginx.conf           # Production reverse proxy + SSL
│   └── static-site.conf     # Local development static file serving
├── ircord-directory/
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js            # Directory API with persistent storage
│   └── README.md
└── ircord-landing/
    ├── index.html
    ├── style.css
    ├── servers.js           # Server list fetching
    └── README.md
```

## Deployment

### 1. Clone

```bash
git clone <repo-url> ircord-infra
cd ircord-infra
```

### 2. Run installer

```bash
sudo ./deploy.sh
```

The installer will:
- Prompt for domain names
- Obtain SSL certificates (Let's Encrypt or self-signed)
- Generate runtime configuration
- Start Docker containers

### 3. Verify

```bash
curl https://directory.example.com/api/health
curl https://chat.example.com
```

### 4. DNS

Point both domains to the server IP:
- `directory.example.com` → Server IP
- `chat.example.com` → Server IP

## Maintenance

### Update services

```bash
git pull
docker-compose --profile production up -d --build
```

### View logs

```bash
docker-compose logs -f
docker-compose logs -f directory
docker-compose logs -f landing
docker-compose logs -f nginx
```

### Backup

```bash
# Backup directory data
docker run --rm -v ircord-infra_directory-data:/data -v $(pwd):/backup alpine tar czf /backup/directory-backup.tar.gz -C /data .
```

### Restore

```bash
# Restore directory data
docker run --rm -v ircord-infra_directory-data:/data -v $(pwd):/backup alpine tar xzf /backup/directory-backup.tar.gz -C /data
```

## Local Development Without Docker

### Directory

```bash
cd ircord-directory
npm install
npm run dev
```

### Landing

```bash
cd ircord-landing
python3 -m http.server 8080
```

For local landing development, `servers.js` falls back to `http://localhost:3000` if `config.js` is not present. On non-localhost deployments it falls back to the current site origin, which lets a host nginx config proxy `/api/` on the same domain.

## IRCord Protocol Handler

The landing page uses the `ircord://` protocol to launch the native client:

```
ircord://host:port
```

Example: `ircord://chat.example.com:6697`

If the protocol handler is not installed, the landing page shows manual connection instructions.

## Related Projects

- [ircord-server](../ircord-server) — IRCord server software
- [ircord-client](../ircord-client) — Desktop client
- [ircord-android](../ircord-android) — Android client
