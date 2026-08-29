#!/bin/bash
set -euo pipefail

DOMAIN="your domain"
EMAIL="your mail"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[..]${NC} $1"; }

warn "Updating packages"
sudo apt update && sudo apt upgrade -y
info "Packages updated"

warn "Installing Nginx"
sudo apt install -y nginx
sudo systemctl enable nginx
info "Nginx installed"

warn "Installing Certbot"
sudo apt install -y certbot python3-certbot-nginx
info "Certbot installed"

warn "Installing utilities"
sudo apt install -y dnsutils curl jq dos2unix apache2-utils
info "Utilities installed"

warn "Installing Docker"
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker ubuntu
  sudo systemctl enable docker
  info "Docker installed"
  echo ""
  echo "!! IMPORTANT: 'exit' karke dobara SSH karo, phir ye script dobara chalao."
  echo "!! Docker group membership naye login pe hi apply hoti hai."
  exit 0
fi
info "Docker already installed"

warn "Adding swap (t2.micro/t3.micro ke 1GB RAM ke liye)"
if [ ! -f /swapfile ]; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
  info "2GB swap added"
else
  info "Swap already exists"
fi

warn "Building and starting containers"
docker compose up -d --build
info "Containers started"

warn "Waiting for backends to be ready"
sleep 8
curl -sf http://127.0.0.1:3001/health > /dev/null && info "backend1 healthy" || echo "backend1 NOT responding"
curl -sf http://127.0.0.1:3002/health > /dev/null && info "backend2 healthy" || echo "backend2 NOT responding"

echo ""
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo ""
echo "Ab ye karo:"
echo "1. Upar wali IP Hostinger ke A record mein daalo (@ aur www dono)"
echo "2. dig +short $DOMAIN  → jab tak ye IP na de, aage mat badho"
echo "3. nginx/sites-available/$DOMAIN mein Version A config paste karo"
echo "4. ./scripts/deploy.sh"
echo "5. sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --no-eff-email"
echo "6. Version B config paste karke ./scripts/deploy.sh dobara"
