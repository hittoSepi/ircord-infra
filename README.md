# IRCord Infrastructure

This repository contains the infrastructure components for IRCord:
- **Directory Service**: Public server listing API (Node.js)
- **Web Client**: Browser-based fallback for connecting to IRCord servers

## Quick Start

### Prerequisites
- Docker & Docker Compose
- (Optional) SSL certificates for production

### Development

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

Services will be available at:
- Directory API: http://localhost:3000
- Web Client: http://localhost:8080

### Production

```bash
# Start with nginx reverse proxy and SSL
docker-compose --profile production up -d
```

## Services

### Directory Service (`ircord-directory/`)

Node.js API for managing public IRCord server listings.

**Endpoints:**
- `POST /api/servers/register` - Register a new server
- `POST /api/servers/ping` - Keep server alive
- `GET /api/servers` - List all servers
- `GET /api/health` - Health check

**Environment Variables:**
- `PORT` - Server port (default: 3000)
- `NODE_ENV` - Environment (development/production)

### Web Client (`ircord-webclient/`)

Static HTML/JS client for connecting to IRCord servers via browser.

**Features:**
- Quick connect to any server
- Browse public server list
- Fallback when native client isn't installed

**Query Parameters:**
- `?server=host&port=6697` - Pre-fill server address
- `&connect=true` - Auto-connect on load

## Directory Structure

```
ircord-infra/
├── docker-compose.yml      # Orchestration
├── nginx/
│   ├── nginx.conf          # Production reverse proxy
│   └── webclient.conf      # Simple static serving
├── ircord-directory/       # Directory service
│   ├── Dockerfile
│   ├── package.json
│   ├── server.js
│   └── README.md
└── ircord-webclient/       # Web client
    ├── index.html
    ├── style.css
    ├── app.js
    └── README.md
```

## Deployment Guide

### 1. Clone and Configure

```bash
git clone <repo-url> ircord-infra
cd ircord-infra
```

### 2. SSL Certificates (Production)

Place certificates in `nginx/ssl/`:
```
nginx/ssl/
├── directory.ircord.dev.crt
├── directory.ircord.dev.key
├── web.ircord.dev.crt
└── web.ircord.dev.key
```

Or use Let's Encrypt with Certbot.

### 3. Deploy

```bash
# Start services
docker-compose --profile production up -d

# Verify
curl https://directory.ircord.dev/api/health
curl https://web.ircord.dev
```

### 4. Update DNS

Point your domains to the server:
- `directory.ircord.dev` → Server IP
- `web.ircord.dev` → Server IP

## Maintenance

### Update Services

```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose down
docker-compose --profile production up -d --build
```

### Backup

```bash
# Backup directory data
docker run --rm -v ircord-infra_directory-data:/data -v $(pwd):/backup alpine tar czf /backup/directory-backup.tar.gz -C /data .
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f directory
```

## Configuration

### Directory Service

Edit `ircord-directory/server.js`:
- `SERVER_TIMEOUT_MS` - Server timeout (default: 10 min)
- `CLEANUP_INTERVAL_MS` - Cleanup interval (default: 1 min)

### Web Client

Edit `ircord-webclient/app.js`:
- `DIRECTORY_URL` - Directory API endpoint
- `WEB_CLIENT_URL` - Web client URL

### Nginx

Edit `nginx/nginx.conf`:
- Rate limiting settings
- SSL configuration
- CORS headers

## Troubleshooting

### Directory service not responding
```bash
docker-compose ps
docker-compose logs directory
```

### Web client not loading
```bash
docker-compose logs webclient
docker-compose logs nginx
```

### CORS errors
Check `Access-Control-Allow-Origin` headers in nginx.conf.

## Development

### Local Development Without Docker

**Directory:**
```bash
cd ircord-directory
npm install
npm run dev
```

**Web Client:**
```bash
cd ircord-webclient
python3 -m http.server 8080
# or use any static file server
```

## License

MIT
