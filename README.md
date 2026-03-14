# IRCord Infrastructure

This repository contains the deployable IRCord public-facing package:
- **Directory Service**: public server listing API (Node.js)
- **Landing Page**: static marketing and server list site
- **Nginx**: reverse proxy and TLS termination for production

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

### Production

```bash
./deploy.sh
```

The installer asks for:
- Directory API domain, for example `directory.example.com`
- Landing page domain, for example `chat.example.com`
- TLS mode and optional Let's Encrypt validation method

## Services

### Directory Service (`ircord-directory/`)

Node.js API for managing public IRCord server listings.

Endpoints:
- `POST /api/servers/register`
- `POST /api/servers/ping`
- `POST /api/servers/unregister`
- `GET /api/servers`
- `GET /api/servers/:id`
- `GET /api/health`

Environment variables:
- `PORT` - server port, default `3000`
- `NODE_ENV` - environment name

### Landing Page (`ircord-landing/`)

Static landing site with:
- public server list
- quick connect via `ircord://`
- manual fallback when the native client is missing

`deploy.sh` generates `ircord-landing/config.js` with the correct directory and landing URLs for the target environment.

## Structure

```text
ircord-infra/
|-- docker-compose.yml
|-- deploy.sh
|-- nginx/
|   |-- nginx.conf
|   `-- static-site.conf
|-- ircord-directory/
`-- ircord-landing/
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

### 3. Verify

```bash
curl https://directory.example.com/api/health
curl https://chat.example.com
```

### 4. DNS

Point both domains to the server:
- `directory.example.com`
- `chat.example.com`

## Maintenance

### Update services

```bash
git pull
docker-compose --profile production up -d --build
```

### Logs

```bash
docker-compose logs -f
docker-compose logs -f directory
docker-compose logs -f landing
docker-compose logs -f nginx
```

### Backup

```bash
docker run --rm -v ircord-infra_directory-data:/data -v $(pwd):/backup alpine tar czf /backup/directory-backup.tar.gz -C /data .
```

## Local development without Docker

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

For local landing development, `servers.js` falls back to `http://localhost:3000` if `config.js` is not present.
