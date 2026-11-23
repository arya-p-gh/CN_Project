#!/bin/zsh
# Collects the client-side evidence on Mac 1 in one go.
# It pauses whenever someone has to do something on Mac 2 or Mac 3.
# Output goes to evidence/rerun/<timestamp>/ - take a screenshot of the terminal at each step too.
#
# usage:  zsh scripts/mac1_evidence.sh

source "$(dirname "$0")/common.sh"   # URL and today's MAC2 / MAC3
OUT="$(cd "$(dirname "$0")/.." && pwd)/evidence/rerun/$(date +%Y%m%d_%H%M)"
mkdir -p "$OUT"

step()  { echo; echo "==================== $1 ===================="; }
pause() { echo; echo ">>> $1"; read "?    press Enter when done... "; }
lb()    { for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w "HTTP %{http_code}  " -D - "$URL/" | grep -i x-backend | tr -d '\r'; done; }

step "0. pre-check: is the new CA trusted?"
if ! curl -s -o /dev/null "$URL/api/status"; then
  echo "HTTPS to the edge fails. Mac 1 probably still trusts the OLD CA."
  echo "fingerprint of ~/cn/tls/team07-ca.crt (must end 67:93:55:35):"
  openssl x509 -in ~/cn/tls/team07-ca.crt -noout -fingerprint -sha256
  echo "fix: copy the new team07-ca.crt from Mac 2, then"
  echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/cn/tls/team07-ca.crt"
  exit 1
fi
echo "ok"

step "1. LAN + DNS"
{ ipconfig getifaddr en0; ping -c 3 $MAC2; ping -c 3 $MAC3; } | tee "$OUT/1_lan.txt"
{ dig app.team07.test; dig api.team07.test; scutil --dns | grep nameserver | head -2; } | tee "$OUT/1_dns.txt"

step "2. HTTPS / TLS"
curl -v "$URL/api/status" 2>&1 | tee "$OUT/2_curl_verbose.txt" | grep -E "verify|HTTP/|SSL connection|x-backend|x-edge"
openssl s_client -connect app.team07.test:8443 -servername app.team07.test </dev/null 2>/dev/null \
  | grep -E "subject=|issuer=|Verify return|Protocol|Cipher" | tee "$OUT/2_s_client.txt"

step "3. load balancing"
lb | tee "$OUT/3_loadbalance.txt"

step "4. caching (MISS -> HIT -> 304)"
sleep 61   # let the 60 s nginx cache entry expire so the first request is a MISS
curl -sI "$URL/api/status" | tee "$OUT/4a_first.txt"  | grep -iE "HTTP/|cache-control|etag|x-cache"
curl -sI "$URL/api/status" | tee "$OUT/4b_second.txt" | grep -iE "HTTP/|x-cache"
ETAG=$(grep -i '^etag' "$OUT/4b_second.txt" | cut -d' ' -f2 | tr -d '\r')
curl -sI -H "If-None-Match: $ETAG" "$URL/api/status" | tee "$OUT/4c_conditional.txt" | grep -iE "HTTP/|etag|x-cache"

step "5. Ext C - firewall"
pause "Mac 3: load + enable pf (firewall/README.md 'Apply'), then run: sudo pfctl -sr | grep -E '3001|3002'  (screenshot it)"
{ nc -vz -G 3 $MAC3 3001; nc -vz -G 3 $MAC3 3002; } 2>&1 | tee "$OUT/5a_client_blocked.txt"
echo "site through the edge:"; lb | tee "$OUT/5b_site_still_works.txt"

step "6. Ext D - HA failover"
pause "Mac 3: press Ctrl+C in the Backend A tab"
lb | tee "$OUT/6a_backend_a_down.txt"
pause "Mac 2: screenshot 'tail -5 /tmp/cn-nginx-error.log'. Then Mac 3: restart backend_a.py"
echo "waiting 12 s for fail_timeout..."; sleep 12
lb | tee "$OUT/6b_recovered.txt"

step "7. Ext E - edge migration"
pause "Mac 3: make sure standby nginx is running (nginx -c ~/cn/nginx-standby.conf)"
curl -s -D - -o /dev/null --resolve app.team07.test:8443:$MAC3 "$URL/" | grep -iE "HTTP/|x-edge" | tee "$OUT/7a_standby_direct.txt"
echo "warming the cache with the current edge:"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
curl -s -D - -o /dev/null "$URL/" | grep -i x-edge | tee "$OUT/7b_before.txt"
pause "QUICKLY: change app.team07.test to $MAC3 on BOTH DNS servers (Mac 1 + Mac 3) and restart both dnsmasq"
for i in $(seq 1 12); do echo -n "$(date +%T)  "; curl -s -o /dev/null -D - -w "connected-to=%{remote_ip}\n" "$URL/" | grep -iE "x-edge|connected-to" | tr -d '\r' | tr '\n' ' '; echo; sleep 5; done | tee "$OUT/7c_cutover.txt"
pause "change the record back to $MAC2 on BOTH DNS servers and restart both dnsmasq"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
curl -s -D - -o /dev/null "$URL/" | grep -i x-edge | tee "$OUT/7d_back.txt"

step "8. cleanup reminder"
echo "Mac 3: nginx -s stop -c ~/cn/nginx-standby.conf ; sudo pfctl -f /etc/pf.conf ; sudo pfctl -d"
pause "after the rollback"
nc -vz -G 3 $MAC3 3001 2>&1 | tee "$OUT/8_after_rollback.txt"

echo; echo "done -> $OUT"
