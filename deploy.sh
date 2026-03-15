#!/bin/bash
# =============================================================================
# IRCord Infrastructure Install Script
# Ubuntu 22.04+ / Debian 12+
#
# Usage:
#   sudo ./deploy.sh
#
# Environment variables (optional):
#   IRCORD_DIR_DOMAIN       - Directory API domain
#   IRCORD_LANDING_DOMAIN   - Landing page domain
#   IRCORD_TURN_ENABLED     - "yes" or "no"
#   IRCORD_TURN_DOMAIN      - TURN domain (default: landing domain)
#   IRCORD_TURN_REALM       - TURN realm (default: TURN domain)
#   IRCORD_TURN_USERNAME    - Static TURN username
#   IRCORD_TURN_PASSWORD    - Static TURN password
#   IRCORD_TURN_CERT_PATH   - Optional source certificate path for TURN
#   IRCORD_TURN_KEY_PATH    - Optional source private key path for TURN
#   IRCORD_USE_LETSENCRYPT  - "yes", "selfsigned", or "skip"
#   IRCORD_LE_METHOD        - "standalone" or "dns-cloudflare"
#   IRCORD_CF_TOKEN         - Cloudflare API token for DNS validation
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
TURN_DIR="$INSTALL_DIR/turn"
DC=""
SERVICES=()

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

collect_turn_settings() {
    if [ -z "${IRCORD_TURN_ENABLED:-}" ]; then
        read -rp "  Enable TURN/ICE server for desktop voice? (Y/n) " -n 1 -r
        echo ""
        [[ -z "${REPLY:-}" || $REPLY =~ ^[Yy]$ ]] && IRCORD_TURN_ENABLED="yes" || IRCORD_TURN_ENABLED="no"
    fi

    if [ "${IRCORD_TURN_ENABLED}" != "yes" ]; then
        IRCORD_TURN_ENABLED="no"
        return
    fi

    if [ -z "${IRCORD_TURN_DOMAIN:-}" ]; then
        read -rp "  TURN domain [${IRCORD_LANDING_DOMAIN}]: " IRCORD_TURN_DOMAIN
        echo ""
    fi
    IRCORD_TURN_DOMAIN="${IRCORD_TURN_DOMAIN:-$IRCORD_LANDING_DOMAIN}"
    ensure_value "TURN domain" "$IRCORD_TURN_DOMAIN"
    validate_domain "$IRCORD_TURN_DOMAIN"

    IRCORD_TURN_REALM="${IRCORD_TURN_REALM:-$IRCORD_TURN_DOMAIN}"

    if [ -z "${IRCORD_TURN_USERNAME:-}" ]; then
        read -rp "  TURN username [ircord]: " IRCORD_TURN_USERNAME
        echo ""
    fi
    IRCORD_TURN_USERNAME="${IRCORD_TURN_USERNAME:-ircord}"

    if [ -z "${IRCORD_TURN_PASSWORD:-}" ]; then
        local generated_password
        generated_password="$(openssl rand -hex 16)"
        read -rp "  TURN password [${generated_password}]: " IRCORD_TURN_PASSWORD
        echo ""
        IRCORD_TURN_PASSWORD="${IRCORD_TURN_PASSWORD:-$generated_password}"
    fi

    ensure_value "TURN username" "$IRCORD_TURN_USERNAME"
    ensure_value "TURN password" "$IRCORD_TURN_PASSWORD"
}

install_dependencies() {
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        ca-certificates certbot curl git openssl ufw

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

collect_services() {
    SERVICES=(directory landing)
    if [ -s "$TURN_DIR/turnserver.conf" ]; then
        SERVICES+=(turn)
    fi
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

    mkdir -p "$SSL_DIR" "$TURN_DIR"
    [ -d "$INSTALL_DIR/ircord-landing" ] || error "Expected landing page files in $INSTALL_DIR/ircord-landing"
}

copy_cert_pair() {
    local src_cert="$1"
    local src_key="$2"
    local dst_cert="$3"
    local dst_key="$4"

    [ -f "$src_cert" ] || error "Certificate not found: $src_cert"
    [ -f "$src_key" ] || error "Private key not found: $src_key"

    cp "$src_cert" "$dst_cert"
    cp "$src_key" "$dst_key"
    chmod 644 "$dst_cert"
    chmod 600 "$dst_key"
}

obtain_cert_le() {
    local domain="$1"
    local dst_cert="$2"
    local dst_key="$3"
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

    copy_cert_pair "$cert_src" "$key_src" "$dst_cert" "$dst_key"
    ok "Certificate ready: $dst_cert"
}

generate_selfsigned() {
    local domain="$1"
    local dst_cert="$2"
    local dst_key="$3"

    info "Generating self-signed certificate for $domain"
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$dst_key" \
        -out "$dst_cert" \
        -days 365 \
        -nodes \
        -subj "/CN=$domain" >/dev/null 2>&1

    chmod 644 "$dst_cert"
    chmod 600 "$dst_key"
    ok "Self-signed certificate ready: $dst_cert"
}

prepare_domain_cert() {
    local domain="$1"
    local dst_cert="$2"
    local dst_key="$3"
    local custom_cert="${4:-}"
    local custom_key="${5:-}"

    if [ -f "$dst_cert" ] && [ -f "$dst_key" ]; then
        ok "Certificate already staged: $dst_cert"
        return
    fi

    case "$IRCORD_USE_LETSENCRYPT" in
        yes)
            obtain_cert_le "$domain" "$dst_cert" "$dst_key"
            ;;
        selfsigned)
            generate_selfsigned "$domain" "$dst_cert" "$dst_key"
            ;;
        skip)
            if [ -n "$custom_cert" ] && [ -n "$custom_key" ]; then
                copy_cert_pair "$custom_cert" "$custom_key" "$dst_cert" "$dst_key"
                ok "Copied custom certificate for $domain"
            else
                warn "Skipping certificate generation for $domain"
                warn "Place certificate at: $dst_cert"
                warn "Place private key at: $dst_key"
            fi
            ;;
        *)
            error "Unknown SSL option: $IRCORD_USE_LETSENCRYPT"
            ;;
    esac
}

prepare_certificates() {
    prepare_domain_cert \
        "$IRCORD_DIR_DOMAIN" \
        "$SSL_DIR/${IRCORD_DIR_DOMAIN}.crt" \
        "$SSL_DIR/${IRCORD_DIR_DOMAIN}.key"

    prepare_domain_cert \
        "$IRCORD_LANDING_DOMAIN" \
        "$SSL_DIR/${IRCORD_LANDING_DOMAIN}.crt" \
        "$SSL_DIR/${IRCORD_LANDING_DOMAIN}.key"

    if [ "${IRCORD_TURN_ENABLED}" = "yes" ]; then
        prepare_domain_cert \
            "$IRCORD_TURN_DOMAIN" \
            "$SSL_DIR/${IRCORD_TURN_DOMAIN}.crt" \
            "$SSL_DIR/${IRCORD_TURN_DOMAIN}.key" \
            "${IRCORD_TURN_CERT_PATH:-}" \
            "${IRCORD_TURN_KEY_PATH:-}"
    fi
}

install_certbot_hook() {
    if [ "$IRCORD_USE_LETSENCRYPT" != "yes" ]; then
        return
    fi

    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/ircord-infra.sh <<HOOK
#!/bin/bash
set -euo pipefail
for domain in ${IRCORD_DIR_DOMAIN} ${IRCORD_LANDING_DOMAIN} ${IRCORD_TURN_DOMAIN:-}; do
    [ -n "\$domain" ] || continue
    src="/etc/letsencrypt/live/\$domain"
    dst="${SSL_DIR}"
    [ -f "\$src/fullchain.pem" ] && cp "\$src/fullchain.pem" "\$dst/\${domain}.crt"
    [ -f "\$src/privkey.pem" ] && cp "\$src/privkey.pem" "\$dst/\${domain}.key"
    chmod 644 "\$dst/\${domain}.crt" 2>/dev/null || true
    chmod 600 "\$dst/\${domain}.key" 2>/dev/null || true
done
cd "${INSTALL_DIR}" && ${DC} restart turn >/dev/null 2>&1 || true
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

detect_turn_external_ip() {
    local ip=""
    ip="$(getent ahostsv4 "$IRCORD_TURN_DOMAIN" 2>/dev/null | awk 'NR==1 {print $1; exit}')"
    if [ -z "$ip" ]; then
        ip="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || true)"
    fi
    if [ -z "$ip" ]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    printf '%s' "$ip"
}

generate_turn_config() {
    if [ "${IRCORD_TURN_ENABLED}" != "yes" ]; then
        return
    fi

    local external_ip
    external_ip="$(detect_turn_external_ip)"

    cat > "$TURN_DIR/turnserver.conf" <<EOF
fingerprint
lt-cred-mech
realm=${IRCORD_TURN_REALM}
user=${IRCORD_TURN_USERNAME}:${IRCORD_TURN_PASSWORD}
listening-ip=0.0.0.0
${external_ip:+external-ip=${external_ip}}
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49200
cert=/etc/coturn/certs/${IRCORD_TURN_DOMAIN}.crt
pkey=/etc/coturn/certs/${IRCORD_TURN_DOMAIN}.key
no-cli
no-multicast-peers
no-tlsv1
no-tlsv1_1
EOF

    ok "TURN config generated"
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

    if [ "${IRCORD_TURN_ENABLED}" = "yes" ]; then
        ufw allow 3478/tcp comment "TURN TCP" >/dev/null 2>&1 || true
        ufw allow 3478/udp comment "TURN UDP" >/dev/null 2>&1 || true
        ufw allow 5349/tcp comment "TURNS TCP" >/dev/null 2>&1 || true
        ufw allow 5349/udp comment "TURNS UDP" >/dev/null 2>&1 || true
        ufw allow 49160:49200/udp comment "TURN relay UDP" >/dev/null 2>&1 || true
    fi

    ufw --force enable >/dev/null 2>&1 || true
    ok "UFW configured"
}

install_update_script() {
    install -m 755 "$INSTALL_DIR/update.sh" /usr/local/bin/ircord-infra-update
    ok "Update script: /usr/local/bin/ircord-infra-update"
}

start_services() {
    cd "$INSTALL_DIR"
    collect_services
    $DC down >/dev/null 2>&1 || true
    $DC up -d --build "${SERVICES[@]}"
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

    if [ "${IRCORD_TURN_ENABLED}" = "yes" ]; then
        if ss -tuln | grep -qE ':(3478|5349)\s'; then
            ok "TURN ports are listening"
        else
            warn "TURN ports are not listening yet"
        fi
    fi
}

show_summary() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  IRCord infrastructure installed successfully${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  Directory API:  ${CYAN}https://${IRCORD_DIR_DOMAIN}${NC}"
    echo -e "  Landing Page:   ${CYAN}https://${IRCORD_LANDING_DOMAIN}${NC}"
    if [ "${IRCORD_TURN_ENABLED}" = "yes" ]; then
        echo -e "  TURN:           ${CYAN}${IRCORD_TURN_DOMAIN}${NC} (3478 / 5349)"
        echo -e "  TURN user:      ${CYAN}${IRCORD_TURN_USERNAME}${NC}"
    fi
    echo -e "  Install dir:    ${INSTALL_DIR}"
    echo ""
    echo -e "  Logs:    cd ${INSTALL_DIR} && ${DC} logs -f"
    echo -e "  Stop:    cd ${INSTALL_DIR} && ${DC} down"
    echo -e "  Update:  sudo ircord-infra-update"
    echo ""

    if [ "$IRCORD_USE_LETSENCRYPT" = "skip" ]; then
        echo -e "  ${YELLOW}Action required:${NC}"
        echo -e "    Ensure certificates exist under ${SSL_DIR}"
        echo -e "    Then restart services:"
        echo -e "      cd ${INSTALL_DIR} && ${DC} restart"
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

collect_turn_settings
choose_ssl_mode
choose_le_method
collect_cloudflare_token

echo ""
info "Configuration summary:"
echo "  Directory API:  $IRCORD_DIR_DOMAIN"
echo "  Landing Page:   $IRCORD_LANDING_DOMAIN"
echo "  TURN enabled:   $IRCORD_TURN_ENABLED"
if [ "$IRCORD_TURN_ENABLED" = "yes" ]; then
    echo "  TURN domain:    $IRCORD_TURN_DOMAIN"
    echo "  TURN realm:     $IRCORD_TURN_REALM"
    echo "  TURN username:  $IRCORD_TURN_USERNAME"
fi
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

step "4/5 Generate runtime config"
generate_landing_config
generate_turn_config
generate_nginx_config
configure_firewall
install_update_script

step "5/5 Start services"
start_services
verify_services
show_summary
