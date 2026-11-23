#!/bin/zsh
# Ext E: records the moment clients move from the old edge to the new one.
# Run it on Mac 1 (primary DNS + client). The standby nginx must be running on Mac 3.
# Clients ask the primary first, so switching Mac 1's record is enough to show the TTL effect
# (the backup on Mac 3 gets the same change in a real migration).
source "$(dirname "$0")/common.sh"   # URL and today's MAC2 / MAC3
CONF=~/cn/dnsmasq.conf
OUT=${1:-.}
sudo -v || exit 1      # ask for the password once, up front

restart_dns() { sudo killall dnsmasq; sleep 1; sudo /opt/homebrew/sbin/dnsmasq -C $CONF; }
row() { echo -n "$(date +%T)  "; curl -s -o /dev/null -D - -w "connected-to=%{remote_ip}\n" "$URL/" | grep -iE "x-edge|connected-to" | tr -d '\r' | tr '\n' ' '; echo; }

{
echo "# record before: $(grep app.team07 $CONF)"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
echo "# client resolves + caches the old edge (TTL 30 s):"
row
echo "# $(date +%T) switching app.team07.test -> $MAC3 on the DNS server"
sed -i '' "s/app.team07.test,$MAC2,/app.team07.test,$MAC3,/" $CONF && restart_dns
echo "# dig (asks the server directly): $(dig +short app.team07.test)"
for i in $(seq 1 10); do row; sleep 5; done
echo "# $(date +%T) migrating back"
sed -i '' "s/app.team07.test,$MAC3,/app.team07.test,$MAC2,/" $CONF && restart_dns
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
row
} | tee "$OUT/7e_transition.txt"
