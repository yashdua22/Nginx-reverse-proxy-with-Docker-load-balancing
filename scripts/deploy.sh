#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Nginx config ko repo se system folders mein
# copy karta hai, test karta hai, phir reload.
# ─────────────────────────────────────────────

DOMAIN="your domain"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }
error() { echo -e "${RED}[!!]${NC} $1"; }

warn "Backing up current config..."
BACKUP="/etc/nginx/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP"
sudo cp -r /etc/nginx/conf.d "$BACKUP/" 2>/dev/null || true
sudo cp -r /etc/nginx/sites-available "$BACKUP/" 2>/dev/null || true
info "Backup saved to $BACKUP"

warn "Copying conf.d files..."
sudo cp "$REPO_DIR"/nginx/conf.d/*.conf /etc/nginx/conf.d/
info "conf.d copied"

warn "Copying site config..."
sudo cp "$REPO_DIR/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-available/$DOMAIN"
info "Site config copied"

warn "Copying error pages..."
sudo mkdir -p /usr/share/nginx/errors
sudo cp "$REPO_DIR"/nginx/errors/*.html /usr/share/nginx/errors/
sudo chmod 644 /usr/share/nginx/errors/*.html
info "Error pages copied"

warn "Enabling site..."
if [ ! -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
  sudo ln -s "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
  info "Symlink created"
else
  info "Already enabled"
fi

if [ -e /etc/nginx/sites-enabled/default ]; then
  sudo rm /etc/nginx/sites-enabled/default
  info "Default site removed"
fi

warn "Testing config..."
if sudo nginx -t; then
  info "Config valid"
else
  error "Config test FAILED — Nginx reload nahi kiya gaya"
  error "Purani config abhi bhi chal rahi hai. Backup: $BACKUP"
  exit 1
fi

warn "Reloading Nginx..."
sudo systemctl reload nginx
info "Nginx reloaded"

echo ""
info "Deploy complete → https://$DOMAIN"
