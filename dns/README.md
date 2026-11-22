# Team 07 - DNS

## Servers

| | Machine | IP | Config |
|---|---|---|---|
| Primary | Mac 1 | `10.7.30.40` | `dns/dnsmasq-primary.conf` |
| Backup (Phase 2, Ext A) | Mac 3 | `10.7.30.100` | `dns/dnsmasq-backup.conf` |

Both run dnsmasq 2.93 (Homebrew) on port 53 UDP/TCP, interface `en0`, with identical records.
`dnsmasq.conf.example` is the Phase 1 config, kept for comparison.

## Records

| Name | Type | Value | TTL |
|---|---|---|---|
| `app.team07.test` | A | `10.7.20.12` (Mac 2, edge) | 30 s |
| `api.team07.test` | A | `10.7.20.12` (Mac 2, edge) | 30 s |

### Changes from Phase 1
- **`address=` → `host-record=...,30`.** Phase 1 answers came back with TTL 0, which made the
  TTL demo (Ext B) impossible. Now every answer carries an explicit 30 s TTL.
- **`local=/team07.test/`.** Names under our domain are never forwarded to the internet.
- **`no-resolv` + `server=1.1.1.1/8.8.8.8`.** The DNS Macs also use themselves as resolvers, so
  reading `/etc/resolv.conf` would make dnsmasq forward to itself.
- **`log-queries`.** We run dnsmasq in the foreground (`-k`) so you can watch queries arrive live.

## Running

```bash
sudo /opt/homebrew/sbin/dnsmasq --test -C ~/cn/dnsmasq.conf      # syntax check
sudo /opt/homebrew/sbin/dnsmasq -k -C ~/cn/dnsmasq.conf --log-facility=-
```

To stop it, run `sudo killall dnsmasq` from another tab. dnsmasq ignores Ctrl+C, because it
uses SIGINT internally. After changing a `host-record`, you need to restart it; SIGHUP only
re-reads `/etc/hosts`.

## Client configuration (Mac 1 and Mac 2)

```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.30.40 10.7.30.100   # primary, then backup
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
scutil --dns | grep nameserver
```

To undo it: `sudo networksetup -setdnsservers Wi-Fi Empty`

## Tests

```bash
dig @10.7.30.40  app.team07.test     # primary  -> 30 IN A 10.7.20.12, flags: qr aa
dig @10.7.30.100 app.team07.test     # backup   -> same
dig app.team07.test                  # system resolver, SERVER: 10.7.30.40
```

`dig` talks to the server directly and skips the macOS cache. To see what the OS (and
therefore curl and Safari) has cached, use `dscacheutil -q host -a name app.team07.test`.
