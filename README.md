# Nginx-reverse-proxy-with-Docker-load-balancing
# Nginx Reverse Proxy with Docker Load Balancing

Production-grade Nginx reverse proxy sitting in front of two Dockerized Node.js backends, deployed on AWS EC2 with TLS, load balancing, compression, rate limiting, custom error pages, and response-time observability.

**Live:** [https://devopsdiaries.in](https://devopsdiaries.in)

---

## What this is

A single Nginx instance handles every incoming request: it terminates TLS, enforces per-IP rate limits, compresses responses, and distributes traffic across two identical backend containers. Neither backend is reachable from the internet — they bind to `127.0.0.1` and only Nginx can talk to them.

The interesting part isn't the proxying. It's the logging. The access log format captures `$request_time` and `$upstream_response_time` separately, which means a single log line tells you whether latency came from the proxy or the application.

---

## Stack

| Layer | Technology |
|---|---|
| Reverse proxy | Nginx 1.24 (host-installed) |
| Backends | Node.js 20 (Alpine) × 2 containers |
| Orchestration | Docker Compose |
| TLS | Let's Encrypt via Certbot |
| Infrastructure | AWS EC2 (Ubuntu 24.04 LTS) |
| DNS | Hostinger |

---

## Features

**Load balancing** — `least_conn` strategy across two upstreams, with `max_fails` / `fail_timeout` health tracking and automatic failover via `proxy_next_upstream`.

**TLS** — Let's Encrypt certificate covering both apex and `www`, with automatic renewal through the certbot systemd timer. HTTP redirects to HTTPS; `www` redirects to apex.

**Gzip compression** — Level 5 compression on text, JSON, JS, CSS, SVG and font types. Compression ratio logged per request via `$gzip_ratio`.

**Cache headers** — Static assets get a 30-day `Cache-Control: public, immutable`. API routes get `no-store`.

**Rate limiting** — Three `limit_req_zone` tiers (general 10r/s, API 5r/s, strict 1r/s) plus a per-IP connection cap. Returns `429` instead of the default `503`.

**Custom error pages** — Styled pages for 502, 503/504, and 429, served as `internal` locations so they can't be hit directly.

**Observability** — Custom log format capturing total request time, upstream connect/header/response times, upstream address, upstream status, and gzip ratio.

---

## Request flow

```
Browser
   │  HTTPS :443
   ▼
Nginx ─── TLS termination
       ├─ rate limiting (limit_req)
       ├─ gzip compression
       ├─ cache headers
       └─ access logging (rt / urt / ua)
   │
   ▼
upstream backend_pool  (least_conn)
   │
   ├──────────────┐
   ▼              ▼
backend1       backend2
127.0.0.1:3001 127.0.0.1:3002
```

---

## Repository layout

```
.
├── app/
│   ├── Dockerfile              # Node 20 Alpine, non-root user, healthcheck
│   ├── package.json
│   └── server.js               # Test endpoints: /, /health, /slow, /big, /crash
│
├── nginx/
│   ├── sites-available/
│   │   └── devopsdiaries.in    # Main server block
│   ├── conf.d/
│   │   ├── log-format.conf     # Custom log formats (detailed + JSON)
│   │   ├── rate-limit.conf     # limit_req_zone definitions
│   │   ├── gzip.conf           # Compression settings
│   │   ├── security-headers.conf
│   │   └── websocket-map.conf  # $connection_upgrade map
│   └── errors/
│       ├── 502.html
│       ├── 50x.html
│       └── 429.html
│
├── scripts/
│   ├── setup-ec2.sh            # One-time provisioning
│   ├── deploy.sh               # Copy configs → test → reload
│   ├── test-all.sh             # Verify every feature
│   ├── analyze-logs.sh         # Latency analysis from access logs
│   └── load-test.sh
│
├── docker-compose.yml
└── README.md
```

Configs live in the repo, not in `/etc/nginx`. `deploy.sh` copies them into place, runs `nginx -t`, and only reloads if the test passes — so a bad config never takes the site down.

---

## Setup

### Prerequisites

- Ubuntu 22.04/24.04 server with a public IP (Elastic IP recommended on EC2)
- A domain with an A record pointing at that IP
- Ports 80 and 443 open in the firewall / security group

### Steps

```bash
git clone https://github.com/yashdua22/Nginx-reverse-proxy-with-Docker-load-balancing.git
cd Nginx-reverse-proxy-with-Docker-load-balancing
chmod +x scripts/*.sh

# Install Nginx, Docker, Certbot; start containers
./scripts/setup-ec2.sh

# Verify DNS resolves to this server before continuing
dig +short yourdomain.com

# Deploy the HTTP-only config first
./scripts/deploy.sh

# Obtain the certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Swap in the full HTTPS config and redeploy
./scripts/deploy.sh

# Verify everything
./scripts/test-all.sh
```

The HTTP-first ordering matters: the full config references certificate files that don't exist until certbot has run.

---

## Log format

```
log_format detailed
    '$remote_addr - $remote_user [$time_local] '
    '"$request" $status $body_bytes_sent '
    '"$http_referer" "$http_user_agent" '
    'rt=$request_time urt=$upstream_response_time '
    'uct=$upstream_connect_time uht=$upstream_header_time '
    'us=$upstream_status ua=$upstream_addr gz=$gzip_ratio';
```

Sample line:

```
49.36.1.20 - - [29/Aug/2026:06:53:41 +0000] "GET /api/products HTTP/2.0" 200 1842
"-" "curl/8.5.0" rt=0.055 urt=0.053 uct=0.000 uht=0.052 us=200 ua=127.0.0.1:3001 gz=3.42
```

### Reading it

The gap between `rt` and `urt` is where the diagnosis lives:

| Pattern | Diagnosis | Where to look next |
|---|---|---|
| `rt` high, `urt` high | Backend is slow | Application code, DB queries |
| `rt` high, `urt` low | Proxy or network is slow | Nginx buffers, server CPU, client connection |
| `ua` shows one address only | The other backend is out of rotation | `docker compose ps` |
| `us=502` | Backend dropped the connection | Container logs |
| `uct` high | TCP connect is slow | Upstream keepalive, connection limits |

`./scripts/analyze-logs.sh` aggregates all of this: slowest requests, average latency per backend, status breakdown, rate-limit hits, and Nginx's own overhead.

---

## Test endpoints

The backend exposes routes designed to exercise the proxy:

| Endpoint | Purpose |
|---|---|
| `/` | Returns JSON with the handling instance name — verifies load balancing |
| `/health` | Health check; excluded from logs and rate limits |
| `/slow?ms=3000` | Artificial delay — produces a high `urt` for latency analysis |
| `/big` | Large JSON payload — verifies gzip |
| `/crash` | Kills the process — triggers the custom 502 page |

---

## Verification

```bash
# Load balancing — both instances should appear
for i in {1..10}; do curl -s https://devopsdiaries.in | grep -o '"instance": "[^"]*"'; done

# Gzip
curl -s -H "Accept-Encoding: gzip" -o /dev/null -D - https://devopsdiaries.in/big | grep -i content-encoding

# Rate limiting — expect a mix of 200 and 429
for i in {1..60}; do curl -s -o /dev/null -w "%{http_code} " https://devopsdiaries.in & done; wait

# Custom 502 page
docker compose stop && curl -s https://devopsdiaries.in | head -20 && docker compose start

# Latency comparison
curl -s "https://devopsdiaries.in/slow?ms=3000" > /dev/null
tail -1 /var/log/nginx/devopsdiaries.in.access.log
```

---

## Design decisions

**Backends bind to `127.0.0.1`, not `0.0.0.0`.** Docker's port mapping is `127.0.0.1:3001:3000`, so the containers are unreachable from outside the host regardless of firewall rules. Combined with a security group that only opens 80 and 443, that's two independent layers between the internet and the application.

**Nginx runs on the host, not in a container.** Certbot's `--nginx` plugin edits the config and reloads the service directly, which is significantly simpler than coordinating certificate renewal across a containerized proxy.

**Configs are version-controlled and deployed by script.** Editing `/etc/nginx` directly means no history and no rollback. `deploy.sh` snapshots the current config, copies the new one, tests it, and reloads only on success.

**`least_conn` over round-robin.** Round-robin assumes uniform response times. When one request takes 3 seconds and the next takes 50ms, connection-count balancing distributes real load more evenly.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `"gzip" directive is duplicate` | Ubuntu's `nginx.conf` already sets it | Comment out the default in `/etc/nginx/nginx.conf` |
| `cannot load certificate` | Full config deployed before certbot ran | Deploy the HTTP-only config first |
| `server: hcdn` in response headers | CDN intercepting before the origin | Disable the CDN at the DNS provider |
| `dig` returns two different IPs | Duplicate A records for `@` | Delete the stale record |
| `unknown "connection_upgrade" variable` | `websocket-map.conf` not deployed | Ensure it's in `nginx/conf.d/` |
| Certbot timeout during connect | Port 80 closed | Open HTTP in the security group |

---

## What I took away from this

Configuration ordering is a real dependency graph. The certificate has to exist before the config that references it, DNS has to resolve before certbot can validate, and the CDN has to be off before the A record means anything. Each of those failed once during setup, and each failure was obvious in hindsight and invisible beforehand.

The `rt` vs `urt` distinction is the single most useful thing in this repo. Most latency debugging starts with guessing which layer is slow. One properly formatted log line removes the guessing.

---

## License

MIT
