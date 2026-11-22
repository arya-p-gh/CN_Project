# Backend firewall (Extension C)

Runs on **Mac 3** (backends, `10.7.30.100`) and uses macOS `pf`.

| Source | Ports 3001 / 3002 |
|---|---|
| Mac 2, the edge (`10.7.20.12`) | allowed |
| localhost (standby nginx on Mac 3) | allowed |
| anyone else (e.g. Mac 1, `10.7.30.40`) | silently dropped |

Rules: [`team07.rules`](team07.rules)

## Apply

```bash
mkdir -p ~/cn/pf && cd ~/cn/pf
cp /etc/pf.conf pf.conf.backup                      # rollback copy
cp <repo>/firewall/team07.rules .
cat /etc/pf.conf team07.rules > pf.team07.conf      # stock rules + ours
sudo pfctl -nf pf.team07.conf                       # syntax check only
sudo pfctl -f  pf.team07.conf                       # load
sudo pfctl -e                                       # enable
sudo pfctl -sr | grep -E '3001|3002'                # show active rules
```

## Test

```bash
# from Mac 1 (client): times out
nc -vz -G 3 10.7.30.100 3001
# from Mac 2 (edge): succeeded
nc -vz -G 3 10.7.30.100 3001
# from Mac 1: the site still works through the edge
curl -s https://app.team07.test:8443/api/status
```

## Rollback

```bash
sudo pfctl -f /etc/pf.conf
sudo pfctl -d
```

Afterwards, `nc -vz -G 3 10.7.30.100 3001` from Mac 1 succeeds again.

## Why `drop` and not `return`
`block drop` discards packets silently, so the client sees a **timeout**, which reveals nothing
about the host. `block return` would send a TCP RST, and the client would get "connection
refused" immediately. That's faster to debug, but it tells an attacker the host exists.
