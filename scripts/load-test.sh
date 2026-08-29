#!/bin/bash
DOMAIN="devopsdiaries.in"

echo "==> Installing hey (load test tool) if missing"
if ! command -v hey &> /dev/null; then
  sudo apt install -y hey 2>/dev/null || {
    echo "hey not available, using ab (apache2-utils)"
    sudo apt install -y apache2-utils
    ab -n 500 -c 20 "https://$DOMAIN/"
    exit 0
  }
fi

echo "==> 500 requests, 20 concurrent"
hey -n 500 -c 20 "https://$DOMAIN/"

echo ""
echo "==> Rate limit trigger test: 200 requests, 50 concurrent"
hey -n 200 -c 50 "https://$DOMAIN/"

echo ""
echo "Ab logs dekho:"
echo "  ./scripts/analyze-logs.sh"