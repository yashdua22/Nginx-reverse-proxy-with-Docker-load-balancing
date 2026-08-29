#!/bin/bash
DOMAIN="devopsdiaries.in"

GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
pass()    { echo -e "${GREEN}PASS${NC} — $1"; }
fail()    { echo -e "${RED}FAIL${NC} — $1"; }

section "1. HTTPS working"
code=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN")
[ "$code" = "200" ] && pass "HTTPS returns 200" || fail "Got $code"

section "2. HTTP redirects to HTTPS"
redirect=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN")
[ "$redirect" = "301" ] && pass "301 redirect working" || fail "Got $redirect"

section "3. Load balancing (10 requests)"
for i in $(seq 1 10); do
  curl -s "https://$DOMAIN" | grep -o '"instance": "[^"]*"' | cut -d'"' -f4
done | sort | uniq -c

section "4. Gzip compression"
enc=$(curl -s -H "Accept-Encoding: gzip" -o /dev/null -D - "https://$DOMAIN/big" | grep -i "content-encoding")
[ -n "$enc" ] && pass "Gzip active → $enc" || fail "No gzip header"

section "5. Cache headers on static"
cache=$(curl -s -o /dev/null -D - "https://$DOMAIN/style.css" | grep -i "cache-control")
[ -n "$cache" ] && pass "$cache" || fail "No cache-control header"

section "6. Rate limiting (60 rapid requests)"
codes=$(for i in $(seq 1 60); do
  curl -s -o /dev/null -w "%{http_code}\n" "https://$DOMAIN" &
done; wait)
echo "$codes" | sort | uniq -c

section "7. Security headers"
curl -s -o /dev/null -D - "https://$DOMAIN" | grep -iE "x-frame|x-content-type|strict-transport"

section "8. Response times from log (last 10)"
sudo tail -10 /var/log/nginx/$DOMAIN.access.log | grep -o 'rt=[0-9.]*'

echo -e "\n${BLUE}=== 502 page test ===${NC}"
echo "Manually chalao:"
echo "  docker compose stop && curl https://$DOMAIN && docker compose start"