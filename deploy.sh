#!/bin/bash
# =============================================================================
# IRCord Infrastructure Install Script
# Ubuntu 22.04+ / Debian 12+
#
# Usage:
#   sudo ./deploy.sh
#
# Environment variables (optional):
#   IRCORD_DIR_DOMAIN      - Directory API domain
#   IRCORD_LANDING_DOMAIN  - Landing page domain
#   IRCORD_USE_LETSENCRYPT - "yes", "selfsigned", or "skip"
#   IRCORD_LE_METHOD       - "standalone" or "dns-cloudflare"
#   IRCORD_CF_TOKEN        - Cloudflare API token for DNS validation
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

[ "$(id -u)" -eq 0 ] || error "Run with sudo: sudo $0"

REPO_URL="https://github.com/hittoSepi/ircord-infra.git"
INSTALL_DIR="/opt/ircord-infra"
SSL_DIR="$INSTALL_DIR/nginx/ssl"

validate_domain() {
    local domain="$1"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$ ]]; then
        warn "Domain format looks unusual: $domain"
        read -rp "  Continue anyway? (y/N) " -n 1 -r
        echo ""
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}

ensure_value() {
    local name="$1"
    local value="$2"
    [ -n "$value" ] || error "$name cannot be empty"
}

choose_ssl_mode() {
    if [ -n "${IRCORD_USE_LETSENCRYPT:-}" ]; then
        return
    fi

    echo "  SSL certificate options:"
    echo "    1) Let's Encrypt"
    echo "    2) Self-signed certificate"
    echo "    3) I will provide my own certificates"
    read -rp "  Select option [1-3]: " LE_OPTION
    echo ""

    case "$LE_OPTION" in
        1) IRCORD_USE_LETSENCRYPT="yes" ;;
        2) IRCORD_USE_LETSENCRYPT="selfsigned" ;;
        3) IRCORD_USE_LETSENCRYPT="skip" ;;
        *) IRCORD_USE_LETSENCRYPT="yes" ;;
    esac
}

choose_le_method() {
    if [ "${IRCORD_USE_LETSENCRYPT:-}" != "yes" ] || [ -n "${IRCORD_LE_METHOD:-}" ]; then
        return
    fi

    echo "  Let's Encrypt validation method:"
    echo "    1) Standalone"
    echo "    2) DNS (Cloudflare)"
    read -rp "  Select method [1-2]: " LE_METHOD_OPTION
    echo ""

    case "$LE_METHOD_OPTION" in
        2) IRCORD_LE_METHOD="dns-cloudflare" ;;
        *) IRCORD_LE_METHOD="standalone" ;;
    esac
}

collect_cloudflare_token() {
    if [ "${IRCORD_USE_LETSENCRYPT:-}" != "yes" ] || [ "${IRCORD_LE_METHOD:-}" != "dns-cloudflare" ]; then
        return
    fi

    if [ -z "${IRCORD_CF_TOKEN:-}" ]; then
        echo "  Cloudflare API token required for DNS validation."
        echo "  Required permissions: Zone:Read, DNS:Edit"
        read -rsp "  Cloudflare API token: " IRCORD_CF_TOKEN
        echo ""
    fi

    ensure_value "Cloudflare API token" "${IRCORD_CF_TOKEN:-}"
}

install_dependencies() {
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        ca-certificates certbot git openssl ufw

    if [ "${IRCORD_USE_LETSENCRYPT:-}" = "yes" ] && [ "${IRCORD_LE_METHOD:-}" = "dns-cloudflare" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-certbot-dns-cloudflare
    fi

    if ! command -v docker >/dev/null 2>&1; then
        info "Installing Docker from distro packages..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io
        systemctl enable --now docker
        ok "Docker installed"
    else
        ok "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
    fi

    if docker compose version >/dev/null 2>&1; then
        DC="docker compose"
        ok "Docker Compose plugin available"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        DC="docker-compose"
        ok "docker-compose available"
        return
    fi

    info "Installing Docker Compose..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose 2>/dev/null || \
        error "Failed to install Docker Compose"

    if docker compose version >/dev/null 2>&1; then
        DC="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DC="docker-compose"
    else
        error "Docker Compose is not available after installation"
    fi

    ok "Docker Compose ready"
}

clone_or_update_repo() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Updating existing installation..."
        git -C "$INSTALL_DIR" pull --ff-only
        ok "Repository updated"
    else
        info "Cloning $REPO_URL -> $INSTALL_DIR"
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
        ok "Repository cloned"
    fi

    mkdir -p "$SSL_DIR"
    [ -d "$INSTALL_DIR/ircord-landing" ] || error "Expected landing page files in $INSTALL_DIR/ircord-landing"
}

obtain_cert_le() {
    local domain="$1"
    local cert_src="/etc/letsencrypt/live/$domain/fullchain.pem"
    local key_src="/etc/letsencrypt/live/$domain/privkey.pem"

    if [ -f "$cert_src" ] && [ -f "$key_src" ]; then
        ok "Certificate already exists: $domain"
    elif [ "${IRCORD_LE_METHOD:-standalone}" = "dns-cloudflare" ]; then
        local cf_creds="/root/.cloudflare-ircord-infra.ini"
        info "Obtaining Let's Encrypt certificate via Cloudflare DNS: $domain"
        printf 'dns_cloudflare_api_token = %s\n' "$IRCORD_CF_TOKEN" > "$cf_creds"
        chmod 600 "$cf_creds"
        certbot certonly \
            --dns-cloudflare \
            --dns-cloudflare-credentials "$cf_creds" \
            --non-interactive \
            --agree-tos \
            --email "admin@${domain#*.}" \
            -d "$domain"
    else
        info "Obtaining Let's Encrypt certificate (standalone): $domain"
        if ss -tln | grep -q ':80 '; then
            warn "Port 80 is in use. Standalone validation may fail."
            read -rp "  Continue anyway? (y/N) " -n 1 -r
            echo ""
            [[ $REPLY =~ ^[Yy]$ ]] || exit 1
        fi

        certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "admin@${domain#*.}" \
            -d "$domain"
    fi

    [ -f "$cert_src" ] || error "Certificate acquisition failed for $domain"
    [ -f "$key_src" ] || error "Private key acquisition failed for $domain"

    cp "$cert_src" "$SSL_DIR/${domain}.crt"
    cp "$key_src" "$SSL_DIR/${domain}.key"
    chmod 644 "$SSL_DIR/${domain}.crt"
    chmod 600 "$SSL_DIR/${domain}.key"
    ok "Certificate ready: $SSL_DIR/${domain}.crt"
}

generate_selfsigned() {
    local domain="$1"

    info "Generating self-signed certificate for $domain"
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$SSL_DIR/${domain}.key" \
        -out "$SSL_DIR/${domain}.crt" \
        -days 365 \
        -nodes \
        -subj "/CN=$domain" >/dev/null 2>&1

    chmod 644 "$SSL_DIR/${domain}.crt"
    chmod 600 "$SSL_DIR/${domain}.key"
    ok "Self-signed certificate ready: $SSL_DIR/${domain}.crt"
}

prepare_certificates() {
    local dir_cert="$SSL_DIR/${IRCORD_DIR_DOMAIN}.crt"
    local dir_key="$SSL_DIR/${IRCORD_DIR_DOMAIN}.key"
    local landing_cert="$SSL_DIR/${IRCORD_LANDING_DOMAIN}.crt"
    local landing_key="$SSL_DIR/${IRCORD_LANDING_DOMAIN}.key"

    case "$IRCORD_USE_LETSENCRYPT" in
        yes)
            obtain_cert_le "$IRCORD_DIR_DOMAIN"
            obtain_cert_le "$IRCORD_LANDING_DOMAIN"
            ;;
        selfsigned)
            generate_selfsigned "$IRCORD_DIR_DOMAIN"
            generate_selfsigned "$IRCORD_LANDING_DOMAIN"
            ;;
        skip)
            warn "Skipping certificate generation"
            warn "Place certificates at:"
            warn "  $dir_cert"
            warn "  $dir_key"
            warn "  $landing_cert"
            warn "  $landing_key"

            if [ ! -f "$dir_cert" ] || [ ! -f "$dir_key" ] || [ ! -f "$landing_cert" ] || [ ! -f "$landing_key" ]; then
                read -rp "  Required certificate files are missing. Continue anyway? (y/N) " -n 1 -r
                echo ""
                [[ $REPLY =~ ^[Yy]$ ]] || exit 1
            fi
            ;;
        *)
            error "Unknown SSL option: $IRCORD_USE_LETSENCRYPT"
            ;;
    esac
}

install_certbot_hook() {
    if [ "$IRCORD_USE_LETSENCRYPT" != "yes" ]; then
        return
    fi

    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/ircord-infra.sh <<HOOK
#!/bin/bash
set -euo pipefail
for domain in ${IRCORD_DIR_DOMAIN} ${IRCORD_LANDING_DOMAIN}; do
    src="/etc/letsencrypt/live/\$domain"
    dst="${SSL_DIR}"
    [ -f "\$src/fullchain.pem" ] && cp "\$src/fullchain.pem" "\$dst/\${domain}.crt"
    [ -f "\$src/privkey.pem" ] && cp "\$src/privkey.pem" "\$dst/\${domain}.key"
    chmod 644 "\$dst/\${domain}.crt" 2>/dev/null || true
    chmod 600 "\$dst/\${domain}.key" 2>/dev/null || true
done
docker exec ircord-nginx nginx -s reload 2>/dev/null || true
HOOK
    chmod +x /etc/letsencrypt/renewal-hooks/post/ircord-infra.sh
    ok "Certbot renewal hook installed"
}

generate_landing_config() {
    cat > "$INSTALL_DIR/ircord-landing/config.js" <<EOF
window.IRCORD_CONFIG = {
    DIRECTORY_URL: "https://${IRCORD_DIR_DOMAIN}",
    LANDING_URL: "https://${IRCORD_LANDING_DOMAIN}"
};
EOF

    ok "Landing config generated"
}

generate_nginx_config() {
    cat > "$INSTALL_DIR/nginx/nginx.conf" <<EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=30r/m;

    upstream directory {
        server directory:3000;
    }

    server {
        listen 80;
        server_name ${IRCORD_DIR_DOMAIN} ${IRCORD_LANDING_DOMAIN};
        return 301 https://\$server_name\$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name ${IRCORD_DIR_DOMAIN};

        ssl_certificate /etc/nginx/ssl/${IRCORD_DIR_DOMAIN}.crt;
        ssl_certificate_key /etc/nginx/ssl/${IRCORD_DIR_DOMAIN}.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        location /api/ {
            limit_req zone=api burst=20 nodelay;

            proxy_pass http://directory;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;

            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Content-Type" always;

            if (\$request_method = OPTIONS) {
                return 204;
            }
        }

        location = /api/health {
            proxy_pass http://directory/api/health;
            access_log off;
        }
    }

    server {
        listen 443 ssl http2;
        server_name ${IRCORD_LANDING_DOMAIN};

        ssl_certificate /etc/nginx/ssl/${IRCORD_LANDING_DOMAIN}.crt;
        ssl_certificate_key /etc/nginx/ssl/${IRCORD_LANDING_DOMAIN}.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        root /usr/share/nginx/html/landing;
        index index.html;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 6M;
            add_header Cache-Control "public, immutable";
            access_log off;
        }

        location / {
            try_files \$uri \$uri/ /index.html;
            limit_req zone=general burst=50 nodelay;
        }
    }
}
EOF

    ok "nginx.conf generated"
}

configure_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        return
    fi

    ufw allow 22/tcp comment "SSH" >/dev/null 2>&1 || true
    ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1 || true
    ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    ok "UFW configured for ports 22, 80 and 443"
}

start_services() {
    cd "$INSTALL_DIR"
    $DC --profile production down >/dev/null 2>&1 || true
    $DC --profile production up -d --build
    ok "Services started"
}

verify_services() {
    info "Checking directory service health..."
    sleep 3

    if curl -sf "http://localhost:3000/api/health" >/dev/null 2>&1; then
        ok "Directory service is healthy"
    else
        warn "Directory service health check failed (it may still be starting)"
    fi
}

show_summary() {
    local dir_cert="$SSL_DIR/${IRCORD_DIR_DOMAIN}.crt"
    local dir_key="$SSL_DIR/${IRCORD_DIR_DOMAIN}.key"
    local landing_cert="$SSL_DIR/${IRCORD_LANDING_DOMAIN}.crt"
    local landing_key="$SSL_DIR/${IRCORD_LANDING_DOMAIN}.key"

    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  IRCord infrastructure installed successfully${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  Directory API:  ${CYAN}https://${IRCORD_DIR_DOMAIN}${NC}"
    echo -e "  Landing Page:   ${CYAN}https://${IRCORD_LANDING_DOMAIN}${NC}"
    echo -e "  Install dir:    ${INSTALL_DIR}"
    echo ""
    echo -e "  Logs:    cd ${INSTALL_DIR} && ${DC} logs -f"
    echo -e "  Stop:    cd ${INSTALL_DIR} && ${DC} --profile production down"
    echo -e "  Update:  cd ${INSTALL_DIR} && git pull && ${DC} --profile production up -d --build"
    echo ""

    if [ "$IRCORD_USE_LETSENCRYPT" = "skip" ]; then
        echo -e "  ${YELLOW}Action required:${NC}"
        echo -e "    Place certificates at:"
        echo -e "      ${dir_cert}"
        echo -e "      ${dir_key}"
        echo -e "      ${landing_cert}"
        echo -e "      ${landing_key}"
        echo -e "    Then restart nginx:"
        echo -e "      cd ${INSTALL_DIR} && ${DC} --profile production restart nginx"
        echo ""
    fi
}

step "IRCord Infrastructure Installation"

if [ -z "${IRCORD_DIR_DOMAIN:-}" ]; then
    read -rp "  Directory API domain (e.g. directory.example.com): " IRCORD_DIR_DOMAIN
    echo ""
fi
ensure_value "Directory API domain" "$IRCORD_DIR_DOMAIN"
validate_domain "$IRCORD_DIR_DOMAIN"

if [ -z "${IRCORD_LANDING_DOMAIN:-}" ]; then
    read -rp "  Landing page domain (e.g. chat.example.com): " IRCORD_LANDING_DOMAIN
    echo ""
fi
ensure_value "Landing page domain" "$IRCORD_LANDING_DOMAIN"
validate_domain "$IRCORD_LANDING_DOMAIN"

choose_ssl_mode
choose_le_method
collect_cloudflare_token

echo ""
info "Configuration summary:"
echo "  Directory API:  $IRCORD_DIR_DOMAIN"
echo "  Landing Page:   $IRCORD_LANDING_DOMAIN"
echo "  SSL:            $IRCORD_USE_LETSENCRYPT"
[ "${IRCORD_USE_LETSENCRYPT:-}" = "yes" ] && echo "  LE Method:      ${IRCORD_LE_METHOD:-standalone}"
echo "  Install dir:    $INSTALL_DIR"
echo ""
read -rp "  Proceed with installation? (Y/n) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Nn]$ ]] && exit 0

step "1/5 Dependencies"
install_dependencies

step "2/5 Clone repository"
clone_or_update_repo

step "3/5 TLS certificates"
prepare_certificates
install_certbot_hook

step "4/5 Generate site and nginx config"
generate_landing_config
generate_nginx_config
configure_firewall

step "5/5 Start services"
start_services
verify_services
show_summary
