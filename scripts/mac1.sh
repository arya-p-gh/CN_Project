#!/bin/zsh
# Mac 1 (Arya) - primary DNS + client.   usage: zsh scripts/mac1.sh <command>
source "$(dirname "$0")/common.sh"

case $1 in
  start)       # everything Mac 1 needs, from a cold start
    check_ip $MAC1
    dns_conf_install primary
    dns_start
    client_dns
    status_all ;;
  stop)        dns_stop ;;
  status)      status_all ;;
  dns-down)    dns_stop; info "primary DNS is down - clients should now use the backup on Mac 3" ;;   # Ext A
  dns-up)      dns_start ;;
  record)      dns_record $2 ;;          # Ext B / E: record mac3  |  record mac2
  flush)       flush; ok "DNS cache flushed" ;;
  dnslog)      tail -f $DNSLOG ;;
  lb)          lb ;;                       # 6 requests, shows x-backend each time
  cache)       # Task F: MISS -> HIT -> 304
    curl -sI $URL/api/status | grep -iE "HTTP/|cache-control|etag|x-cache"
    curl -sI $URL/api/status | grep -iE "HTTP/|x-cache"
    etag=$(curl -sI $URL/api/status | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
    curl -sI -H "If-None-Match: $etag" $URL/api/status | grep -iE "HTTP/|etag|x-cache" ;;
  tls)         curl -sv $URL/api/status 2>&1 | grep -E "SSL connection|verify|HTTP/2 |x-backend|x-edge" ;;
  migrate)     zsh "$REPO/scripts/extE_transition.sh" /tmp ;;   # Ext E live: old edge -> TTL -> new edge -> back
  *) cat <<'EOF'
Mac 1 commands:
  start      start primary DNS, use team DNS, check everything
  status     check all 3 Macs end to end
  lb         load balancing (A/B alternating)
  cache      caching demo: MISS -> HIT -> 304
  tls        TLS verify + HTTP/2
  dns-down   stop primary DNS (Ext A)      dns-up   start it again
  record mac3 | record mac2                switch app.team07.test (Ext B/E)
  migrate    full Ext E switch-over run (needs standby on Mac 3)
  flush      flush this Mac's DNS cache    dnslog   watch DNS queries live
  stop       stop primary DNS
EOF
esac
