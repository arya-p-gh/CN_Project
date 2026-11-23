# shared bits for mac1.sh / mac2.sh / mac3.sh  (sourced, not run directly)

# IPs written in the repo configs (the 23 Nov network)
REPO_MAC1=10.7.30.40      # Arya     - primary DNS + client
REPO_MAC2=10.7.20.12      # Divyansh - nginx edge
REPO_MAC3=10.7.30.100     # Rishita  - backends, backup DNS, firewall, standby edge
URL=https://app.team07.test:8443
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CN=~/cn
IPFILE=$CN/ips

# today's IPs: ~/cn/ips (written by "<macN.sh> ips ...") wins over the repo ones
MAC1=$REPO_MAC1; MAC2=$REPO_MAC2; MAC3=$REPO_MAC3
[[ -f $IPFILE ]] && source $IPFILE
DNSMASQ=/opt/homebrew/sbin/dnsmasq
DNSLOG=/tmp/cn-dnsmasq.log

ok()   { print -P "%F{green}✔%f $*"; }
bad()  { print -P "%F{red}✘%f $*"; }
info() { print -P "%F{cyan}›%f $*"; }

check_ip() {   # warn if this Mac's IP is not the one the configs expect
  local want=$1 have=$(ipconfig getifaddr en0)
  if [[ "$have" == "$want" ]]; then ok "this Mac is $have"
  else
    bad "this Mac is '$have' but the configs expect $want"
    info "IPs changed? everyone runs:  zsh scripts/macN.sh ips <mac1-ip> <mac2-ip> <mac3-ip>   then start again"
    exit 1
  fi
}

set_ips() {   # ips <mac1> <mac2> <mac3>  - save today's IPs on this Mac
  if [[ $# -ne 3 ]]; then
    info "this Mac's IP now: $(ipconfig getifaddr en0)"
    info "using: Mac 1 $MAC1   Mac 2 $MAC2   Mac 3 $MAC3   $([[ -f $IPFILE ]] && echo "(from $IPFILE)" || echo "(repo defaults)")"
    info "to change:  ips <mac1-ip> <mac2-ip> <mac3-ip>     to go back to the repo IPs:  ips reset"
    [[ $1 == reset ]] && { rm -f $IPFILE; ok "removed $IPFILE - back to repo IPs"; }
    return 0
  fi
  local ip; for ip in "$@"; do [[ $ip =~ '^([0-9]{1,3}\.){3}[0-9]{1,3}$' ]] || { bad "'$ip' is not an IPv4 address"; return 1; }; done
  mkdir -p $CN
  printf 'MAC1=%s\nMAC2=%s\nMAC3=%s\n' "$@" > $IPFILE
  ok "saved to $IPFILE:  Mac 1 $1   Mac 2 $2   Mac 3 $3"
  info "now run start again - it rebuilds the configs in $CN with these IPs"
}

render() {   # render <repo file> <dest> : copy a repo config, swap in today's IPs and $HOME
  mkdir -p "$(dirname $2)"
  [[ -f $2 ]] && cp $2 $2.prev
  sed -e "s/${REPO_MAC1//./\\.}/@MAC1@/g" -e "s/${REPO_MAC2//./\\.}/@MAC2@/g" -e "s/${REPO_MAC3//./\\.}/@MAC3@/g" \
      -e "s/@MAC1@/$MAC1/g" -e "s/@MAC2@/$MAC2/g" -e "s/@MAC3@/$MAC3/g" -e "s|HOME_DIR|$HOME|g" "$1" > $2
  info "built $2 from $(basename $1)"
}

dns_conf_install() { render "$REPO/dns/dnsmasq-$1.conf" $CN/dnsmasq.conf; }   # $1 = primary|backup

dns_start() {
  sudo killall dnsmasq 2>/dev/null; sleep 1
  sudo $DNSMASQ -C $CN/dnsmasq.conf --log-facility=$DNSLOG && ok "dnsmasq running (log: tail -f $DNSLOG)"
}

dns_stop() { sudo killall dnsmasq 2>/dev/null && ok "dnsmasq stopped" || info "dnsmasq was not running"; }

dns_record() {   # point app.team07.test at mac2 (normal) or mac3 (edge migration)
  local ip
  case $1 in mac2) ip=$MAC2;; mac3) ip=$MAC3;; *) bad "use: record mac2 | record mac3"; return 1;; esac
  sed -i '' -E "s/^host-record=app\.team07\.test,[0-9.]+,/host-record=app.team07.test,$ip,/" $CN/dnsmasq.conf
  info "$(grep app.team07 $CN/dnsmasq.conf)"
  dns_start
}

client_dns() {   # make this Mac resolve through the team DNS (primary, then backup)
  sudo networksetup -setdnsservers Wi-Fi $MAC1 $MAC3
  flush
  ok "DNS servers: $(networksetup -getdnsservers Wi-Fi | tr '\n' ' ')"
}

flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; }

port() { nc -z -G 2 $1 $2 2>/dev/null && ok "$3 ($1:$2) reachable" || bad "$3 ($1:$2) NOT reachable"; }

status_all() {
  info "--- network"
  for h in $MAC1 $MAC2 $MAC3; do ping -c1 -t2 $h >/dev/null 2>&1 && ok "ping $h" || bad "ping $h"; done
  info "--- DNS"
  local a=$(dig +short +time=2 +tries=1 @$MAC1 app.team07.test); [[ -n $a ]] && ok "primary DNS (Mac 1) -> $a" || bad "primary DNS (Mac 1) not answering"
  local b=$(dig +short +time=2 +tries=1 @$MAC3 app.team07.test); [[ -n $b ]] && ok "backup DNS (Mac 3) -> $b" || bad "backup DNS (Mac 3) not answering"
  info "--- services"
  port $MAC2 8443 "nginx edge"
  port $MAC3 3001 "backend A"
  port $MAC3 3002 "backend B"
  info "--- end to end"
  local r=$(curl -s -m 8 -o /dev/null -w "%{http_code} %{ssl_verify_result}" $URL/api/status)
  [[ "$r" == "200 0" ]] && ok "https://app.team07.test:8443 -> 200, certificate verified" || bad "end-to-end result: '$r' (want '200 0')"
}

lb() { for i in 1 2 3 4 5 6; do curl -s -m 5 -o /dev/null -D - $URL/ | grep -iE "x-backend" | tr -d '\r'; done; }
