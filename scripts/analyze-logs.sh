#!/bin/bash
LOG="/var/log/nginx/yourdomain.com.access.log"
BLUE='\033[0;34m'; NC='\033[0m'
section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

section "Total requests"
sudo wc -l < "$LOG"

section "Top 10 slowest requests (rt)"
sudo grep -oP '"\K[^"]+(?=".*rt=)' "$LOG" > /tmp/reqs.txt 2>/dev/null
sudo awk '{
  match($0, /rt=([0-9.]+)/, rt);
  match($0, /"([A-Z]+ [^"]+)"/, req);
  if (rt[1] != "") printf "%.3f  %s\n", rt[1], req[1]
}' "$LOG" | sort -rn | head -10

section "Average response time"
sudo awk '{ match($0, /rt=([0-9.]+)/, a); if (a[1]!="") { s+=a[1]; n++ } }
  END { if (n>0) printf "%.4f sec over %d requests\n", s/n, n }' "$LOG"

section "Requests per backend"
sudo grep -oP 'ua=\K[0-9.:]+' "$LOG" | sort | uniq -c | sort -rn

section "Average time per backend"
sudo awk '{
  match($0, /ua=([0-9.:]+)/, ua);
  match($0, /urt=([0-9.]+)/, urt);
  if (ua[1]!="" && urt[1]!="") { sum[ua[1]]+=urt[1]; cnt[ua[1]]++ }
} END { for (b in sum) printf "%s → %.4f sec (%d reqs)\n", b, sum[b]/cnt[b], cnt[b] }' "$LOG"

section "Status code breakdown"
sudo awk '{print $9}' "$LOG" | sort | uniq -c | sort -rn

section "Top 10 IPs by request count"
sudo awk '{print $1}' "$LOG" | sort | uniq -c | sort -rn | head -10

section "Rate limited requests (429)"
sudo awk '$9 == 429' "$LOG" | wc -l

section "Nginx overhead (rt minus urt)"
sudo awk '{
  match($0, /rt=([0-9.]+)/, rt);
  match($0, /urt=([0-9.]+)/, urt);
  if (rt[1]!="" && urt[1]!="" && urt[1] != "-") { d = rt[1]-urt[1]; s+=d; n++ }
} END { if (n>0) printf "%.4f sec average\n", s/n }' "$LOG"