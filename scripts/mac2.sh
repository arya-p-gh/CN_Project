#!/bin/zsh
# Mac 2 (Divyansh) - nginx edge: TLS termination + load balancer.   usage: zsh scripts/mac2.sh <command>
source "$(dirname "$0")/common.sh"
CONF=$CN/nginx-edge.conf

install_conf() {
  [[ -f $CONF ]] && return
  cp "$REPO/nginx/nginx-edge.conf" $CONF
  sed -i '' "s|HOME_DIR|$HOME|g" $CONF
  info "installed $CONF from repo"
}

case $1 in
  start)
    check_ip $MAC2
    install_conf
    [[ -f $CN/tls/app.team07.test.crt && -f $CN/tls/app.team07.test.key ]] || { bad "missing cert/key in $CN/tls"; exit 1; }
    nginx -s quit -c $CONF 2>/dev/null; sleep 1
    nginx -t -c $CONF 2>&1 | tail -1
    nginx -c $CONF && ok "nginx edge running on :8443 (HTTPS) and :8080"
    client_dns
    status_all ;;
  stop)     nginx -s quit -c $CONF && ok "nginx stopped" ;;
  reload)   nginx -s reload -c $CONF && ok "nginx reloaded" ;;
  status)   status_all ;;
  access)   tail -f /tmp/cn-nginx-access.log ;;   # which backend got each request
  errors)   tail -20 /tmp/cn-nginx-error.log ;;   # Ext D: "connect() failed ... upstream"
  backends) port $MAC3 3001 "backend A"; port $MAC3 3002 "backend B" ;;   # Ext C: edge is allowed
  *) cat <<'EOF'
Mac 2 commands:
  start     start nginx edge, use team DNS, check everything
  status    check all 3 Macs end to end
  access    live access log: client -> which backend, cache HIT/MISS
  errors    last nginx errors (failover evidence)
  backends  can the edge reach 3001/3002? (Ext C: should be yes even with the firewall on)
  reload | stop
EOF
esac
