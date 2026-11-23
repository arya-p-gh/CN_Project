#!/bin/zsh
# Mac 3 (Rishita) - backends A/B, backup DNS, firewall, standby edge.   usage: zsh scripts/mac3.sh <command>
source "$(dirname "$0")/common.sh"
STANDBY=$CN/nginx-standby.conf
PFDIR=$CN/pf

backend_start() {  # $1 = a | b
  pgrep -f "backend_$1.py" >/dev/null && { info "backend ${(U)1} already running"; return; }
  nohup python3 "$REPO/backend/backend_$1.py" > /tmp/cn-backend-$1.log 2>&1 &
  sleep 1; ok "backend ${(U)1} started (log /tmp/cn-backend-$1.log)"
}
backend_kill() { pkill -f "backend_$1.py" && ok "backend ${(U)1} stopped" || info "backend ${(U)1} was not running"; }

pf_install() {
  mkdir -p $PFDIR
  [[ -f $PFDIR/pf.conf.backup ]] || cp /etc/pf.conf $PFDIR/pf.conf.backup
  render "$REPO/firewall/team07.rules" $PFDIR/team07.rules   # allows today's Mac 2 IP
  cat /etc/pf.conf $PFDIR/team07.rules > $PFDIR/pf.team07.conf
}

standby_install() { render "$REPO/nginx/nginx-standby.conf" $STANDBY; }

case $1 in
  start)
    check_ip $MAC3
    backend_start a; backend_start b
    dns_conf_install backup
    dns_start
    sudo pfctl -d 2>/dev/null; info "firewall off (turn on with: firewall-on)"
    status_all ;;
  stop)        backend_kill a; backend_kill b; dns_stop; nginx -s quit -c $STANDBY 2>/dev/null ;;
  status)      status_all ;;
  ips)         set_ips ${@:2} ;;
  kill-a)      backend_kill a ;;               # Ext D / Phase 1 "one backend down"
  start-a)     backend_start a ;;
  kill-both)   backend_kill a; backend_kill b ;;   # Phase 1 "both down" -> 502
  start-both)  backend_start a; backend_start b ;;
  firewall-on)                                   # Ext C
    pf_install
    sudo pfctl -f $PFDIR/pf.team07.conf 2>/dev/null; sudo pfctl -e 2>/dev/null
    ok "firewall on - only $MAC2 and localhost may reach 3001/3002"
    sudo pfctl -sr 2>/dev/null | grep -E "3001|3002" ;;
  firewall-off) sudo pfctl -f /etc/pf.conf 2>/dev/null; sudo pfctl -d 2>/dev/null; ok "firewall rolled back" ;;
  standby-on)                                    # Ext E
    standby_install
    fp=$(openssl x509 -in $CN/tls/app.team07.test.crt -noout -fingerprint -sha256)
    [[ $fp == *71:5E:E1 ]] || bad "server cert in $CN/tls is not the new one (should end 71:5E:E1) - get it from Mac 2"
    nginx -s quit -c $STANDBY 2>/dev/null; sleep 1
    nginx -c $STANDBY && ok "standby edge running on $MAC3:8443 (X-Edge: mac3-standby)" ;;
  standby-off) nginx -s quit -c $STANDBY && ok "standby edge stopped" ;;
  record)      dns_record $2 ;;                  # Ext E: change the backup's record too
  dnslog)      tail -f $DNSLOG ;;                # Ext A: watch queries arrive at the backup
  *) cat <<'EOF'
Mac 3 commands:
  ips <m1> <m2> <m3>   save today's IPs if they changed (then start again)
  start          start backends A+B and backup DNS, firewall off, check everything
  status         check all 3 Macs end to end
  kill-a | start-a           stop / start backend A   (Ext D)
  kill-both | start-both     stop / start both        (502 demo)
  firewall-on | firewall-off pf isolation             (Ext C)
  standby-on | standby-off   second nginx edge        (Ext E)
  record mac3 | record mac2  switch the backup DNS record (Ext E)
  dnslog         watch DNS queries arriving here (Ext A)
  stop           stop everything on this Mac
EOF
esac
