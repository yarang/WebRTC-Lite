#!/bin/bash
###############################################################################
# Coturn TURN/STUN Server Setup Script for Oracle Cloud Free Tier
#
# This script automates the installation and configuration of Coturn
# on Ubuntu 22.04 (Oracle Cloud Free Tier).
#
# Requirements: REQ-U001, REQ-U003, REQ-S001, REQ-S003
#
# Usage:
#   sudo ./setup.sh
#
# Prerequisites:
#   - Oracle Cloud Free Tier VM (Ubuntu 22.04)
#   - Public IP assigned
#   - Security group/inbound rules configured (ports 3478, 5349)
###############################################################################

set -euo pipefail

###############################################################################
# COLOR OUTPUT
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

###############################################################################
# CONFIGURATION VARIABLES
###############################################################################

# Domain name for TURN server (must resolve to this server's public IP)
DOMAIN="${DOMAIN:-turn.example.com}"
EMAIL="${EMAIL:-admin@example.com}"

# Public IP (auto-detect if not set)
PUBLIC_IP="${PUBLIC_IP:-}"

# TURN secret for HMAC authentication
TURN_SECRET="${TURN_SECRET:-$(openssl rand -hex 32)}"

# Ports
STUN_PORT=3478
TLS_PORT=5349
ALT_STUN_PORT=3479
ALT_TLS_PORT=5350

###############################################################################
# PREREQUISITE CHECKS
###############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_public_ip() {
    if [[ -z "$PUBLIC_IP" ]]; then
        log_step "Auto-detecting public IP..."
        PUBLIC_IP=$(curl -s https://ifconfig.me || curl -s https://icanhazip.com)
        log_info "Detected public IP: $PUBLIC_IP"
    fi
}

check_ubuntu_version() {
    log_step "Checking Ubuntu version..."
    local version
    version=$(lsb_release -rs)
    if [[ $(echo "$version >= 22.04" | bc -l) -eq 0 ]]; then
        log_error "Ubuntu 22.04 or higher required. Current: $version"
        exit 1
    fi
    log_info "Ubuntu version: $version ✓"
}

###############################################################################
# FIREWALL CONFIGURATION
###############################################################################

configure_firewall() {
    log_step "Configuring firewall (ufw)..."

    # Allow SSH
    ufw allow 22/tcp

    # Allow STUN/TURN ports
    ufw allow $STUN_PORT/udp comment "Coturn STUN"
    ufw allow $STUN_PORT/tcp comment "Coturn STUN TCP"
    ufw allow $ALT_STUN_PORT/udp comment "Coturn STUN Alt"
    ufw allow $TLS_PORT/tcp comment "Coturn TLS"
    ufw allow $ALT_TLS_PORT/tcp comment "Coturn TLS Alt"

    # Allow HTTP for Let's Encrypt
    ufw allow 80/tcp comment "Let's Encrypt HTTP"
    ufw allow 443/tcp comment "HTTPS"

    # Enable firewall
    ufw --force enable

    log_info "Firewall configured ✓"
}

###############################################################################
# INSTALL COTURN
###############################################################################

install_coturn() {
    log_step "Installing Coturn..."

    apt-get update
    apt-get install -y coturn

    log_info "Coturn installed ✓"
}

###############################################################################
# OBTAIN TLS CERTIFICATE
###############################################################################

obtain_certificate() {
    log_step "Obtaining TLS certificate from Let's Encrypt..."

    # Install certbot
    apt-get install -y certbot

    # Obtain certificate (standalone mode)
    certbot certonly --standalone \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --keep-until-expiring

    # Set up auto-renewal
    (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 0 * * * certbot renew --quiet") | crontab -

    log_info "TLS certificate obtained ✓"
}

###############################################################################
# CONFIGURE COTURN
###############################################################################

configure_coturn() {
    log_step "Configuring Coturn..."

    local config_file="/etc/turnserver.conf"
    local secret_file="/etc/turn_secret.txt"

    # Backup original config
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"

    # Save TURN secret for API use
    echo "$TURN_SECRET" > "$secret_file"
    chmod 600 "$secret_file"

    # Write configuration
    cat > "$config_file" << EOF
# Coturn TURN Server Configuration for WebRTC-Lite
# Auto-generated by setup.sh on $(date)

# Network
listening-port=$STUN_PORT
tls-listening-port=$TLS_PORT
alt-listening-port=$ALT_STUN_PORT
alt-tls-listening-port=$ALT_TLS_PORT
listening-ip=0.0.0.0
relay-ip=10.0.0.2
external-ip=$PUBLIC_IP

# Authentication
lt-cred-mech
realm=$DOMAIN
stale-nonce

# Security
fingerprint
no-loopback-peers
no-multicast-peers
keep-address-family
no-udp-loop

# TLS Certificates
cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
pkey=/etc/letsencrypt/live/$DOMAIN/privkey.pem
cipher-list="ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384"

# Oracle Cloud Optimization
max-bps=3000000
total-quota=300000
min-port=49152
max-port=65535
max-allocate-lifetime=3600

# Logging
log-file=/var/log/turnserver.log
verbose

# Performance
io-thread-count=2
relay-thread-count=2
no-cli

# Rate Limiting
max-allocate-per-user=10
max-permission-per-user=10
user-quota=100
total-quota=1000

# Channel Data
channel-lifetime=600
permission-lifetime=300

# Private IP for OCI
allowed-peer-ip=10.0.0.0-10.0.0.255
EOF

    log_info "Coturn configured ✓"
}

###############################################################################
# ENABLE AND START COTURN SERVICE
###############################################################################

enable_coturn_service() {
    log_step "Enabling Coturn service..."

    # Enable service in systemd
    sed -i 's/TURNSERVER_ENABLED=0/TURNSERVER_ENABLED=1/' /etc/default/coturn

    # Reload systemd
    systemctl daemon-reload

    # Restart service
    systemctl restart coturn

    # Enable on boot
    systemctl enable coturn

    # Wait for service to start
    sleep 3

    # Check status
    if systemctl is-active --quiet coturn; then
        log_info "Coturn service started ✓"
    else
        log_error "Coturn service failed to start"
        journalctl -u coturn -n 20 --no-pager
        exit 1
    fi
}

###############################################################################
# CREATE HEALTH CHECK SCRIPT
###############################################################################

create_health_check() {
    log_step "Creating health check script..."

    cat > /usr/local/bin/turn-health-check.sh << 'HEALTH_EOF'
#!/bin/bash
# Coturn Health Check Script for Oracle Cloud

# Check if coturn process is running
if ! systemctl is-active --quiet coturn; then
    echo "ERROR: Coturn service is not running"
    systemctl restart coturn
    exit 1
fi

# Check if listening ports are open
if ! netstat -ulnp | grep -q ":3478"; then
    echo "ERROR: Coturn not listening on port 3478"
    systemctl restart coturn
    exit 1
fi

echo "OK: Coturn is healthy"
exit 0
HEALTH_EOF

    chmod +x /usr/local/bin/turn-health-check.sh

    # Add to crontab (every 5 minutes)
    (crontab -l 2>/dev/null | grep -v "turn-health-check"; echo "*/5 * * * * /usr/local/bin/turn-health-check.sh >> /var/log/turn-health.log 2>&1") | crontab -

    log_info "Health check script created ✓"
}

###############################################################################
# CREATE CREDENTIALS API (Python FastAPI)
###############################################################################

create_credentials_api() {
    log_step "Creating TURN credentials API..."

    # Install Python dependencies
    apt-get install -y python3-pip python3-venv

    # Create virtual environment
    python3 -m venv /opt/turn-api
    source /opt/turn-api/bin/activate
    pip install --upgrade pip
    pip install fastapi uvicorn gunicorn

    # Create API application
    cat > /opt/turn-api/main.py << API_EOF
from fastapi import FastAPI, HTTPException
from datetime import datetime, timedelta
import hmac
import hashlib
import base64
import os
import secrets

app = FastAPI(title="TURN Credentials API")

# Load TURN secret
TURN_SECRET = os.environ.get('TURN_SECRET', open('/etc/turn_secret.txt').read().strip())
TURN_SERVER = os.environ.get('TURN_SERVER', f"{os.environ.get('DOMAIN', 'turn.example.com')}:5349")

def generate_turn_credentials(username: str, ttl: int = 86400) -> dict:
    """Generate time-limited TURN credentials using HMAC-SHA1"""
    timestamp = int(datetime.now().timestamp()) + ttl
    turn_username = f"{timestamp}:{username}"

    # HMAC-SHA1 signature
    hmac_obj = hmac.new(
        TURN_SECRET.encode(),
        turn_username.encode(),
        hashlib.sha1
    )
    password = base64.b64encode(hmac_obj.digest()).decode()

    return {
        "username": turn_username,
        "password": password,
        "ttl": ttl,
        "uris": [
            f"turn:{TURN_SERVER}?transport=udp",
            f"turn:{TURN_SERVER}?transport=tcp",
            f"turns:{TURN_SERVER}?transport=tcp"
        ]
    }

@app.get("/")
def read_root():
    return {"service": "TURN Credentials API", "version": "1.0.0"}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/turn-credentials")
def get_turn_credentials(username: str, ttl: int = 86400):
    """Get TURN credentials for WebRTC client"""
    if not username or len(username) > 128:
        raise HTTPException(status_code=400, detail="Invalid username")

    if ttl < 60 or ttl > 86400:
        raise HTTPException(status_code=400, detail="TTL must be between 60 and 86400 seconds")

    return generate_turn_credentials(username, ttl)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
API_EOF

    # Create systemd service
    cat > /etc/systemd/system/turn-api.service << SERVICE_EOF
[Unit]
Description=TURN Credentials API
After=network.target

[Service]
Type=notify
User=www-data
WorkingDirectory=/opt/turn-api
Environment="DOMAIN=$DOMAIN"
Environment="TURN_SECRET=$TURN_SECRET"
ExecStart=/opt/turn-api/bin/gunicorn -w 2 -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable turn-api
    systemctl start turn-api

    log_info "TURN credentials API created and started ✓"
}

###############################################################################
# CONFIGURE ORACLE CLOUD SECURITY (IPTABLES)
###############################################################################

configure_security() {
    log_step "Configuring additional security rules..."

    # Install fail2ban for brute force protection
    apt-get install -y fail2ban

    cat > /etc/fail2ban/jail.local << JAIL_EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[coturn]
enabled = true
port = 3478,5349
protocol = udp
logpath = /var/log/turnserver.log
maxretry = 10
JAIL_EOF

    systemctl enable fail2ban
    systemctl start fail2ban

    log_info "Security rules configured ✓"
}

###############################################################################
# DISPLAY CONFIGURATION SUMMARY
###############################################################################

display_summary() {
    log_step "Installation Summary"
    cat << SUMMARY

╔════════════════════════════════════════════════════════════════════════════╗
║                   Coturn TURN Server Installation Complete                  ║
╚════════════════════════════════════════════════════════════════════════════╝

Server Configuration:
  Domain:         $DOMAIN
  Public IP:      $PUBLIC_IP
  STUN Port:      $STUN_PORT (UDP/TCP)
  TLS Port:       $TLS_PORT (TCP)
  API Endpoint:   http://$PUBLIC_IP:8080/turn-credentials

TURN Credentials API:
  URL:            http://$PUBLIC_IP:8080/turn-credentials?username=USER
  Documentation:  http://$PUBLIC_IP:8080/docs
  Health Check:   http://$PUBLIC_IP:8080/health

Testing Commands:
  # Test STUN
  stun-client --mode basic $PUBLIC_IP:3478

  # Test TURN (use Trickle ICE)
  # URL: turn:$USERNAME:$PASSWORD@$PUBLIC_IP:5349

  # Test API
  curl "http://$PUBLIC_IP:8080/turn-credentials?username=testuser"

Logs:
  Coturn:         /var/log/turnserver.log
  Health Check:   /var/log/turn-health.log
  API:            journalctl -u turn-api -f

TURN Secret:      $TURN_SECRET
  Location:       /etc/turn_secret.txt

Next Steps:
  1. Update DNS A record: $DOMAIN -> $PUBLIC_IP
  2. Test STUN/TURN connectivity
  3. Configure Firebase Firestore
  4. Deploy client SDKs

SUMMARY
}

###############################################################################
# MAIN INSTALLATION FLOW
###############################################################################

main() {
    log_step "Starting Coturn TURN Server Installation..."

    check_root
    detect_public_ip
    check_ubuntu_version
    configure_firewall
    install_coturn
    obtain_certificate
    configure_coturn
    enable_coturn_service
    create_health_check
    create_credentials_api
    configure_security
    display_summary

    log_info "Installation completed successfully! ✓"
}

# Run main function
main "$@"
