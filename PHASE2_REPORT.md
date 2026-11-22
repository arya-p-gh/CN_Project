# Phase 2 Report: Harden, Recover, Troubleshoot

**Team 07 (RAD)**: Divyansh Rathore (2401020021), Arya Pandey (2401020012), Rishita Boisnobi (2401010382)
**Date of build/tests:** 22 November 2026
**Setup:** 3 MacBooks on the hostel Wi-Fi (`10.7.0.0/19`)

| Mac | IP | Roles |
|---|---|---|
| Mac 1 | 10.7.30.40 | primary DNS, client |
| Mac 2 | 10.7.20.12 | nginx edge (TLS :8443, LB), client 2 |
| Mac 3 | 10.7.30.100 | backends A :3001 / B :3002, backup DNS, pf firewall, standby edge |

---

## 1. What changed from Phase 1

We didn't start from scratch. The backends, the nginx layout and the domain names are the same
as in Phase 1. Because we rebuilt on new DHCP leases, every IP changed, and we had to regenerate
the CA and server certificate (the keys were never committed, on purpose).

| Area | Phase 1 | Phase 2 |
|---|---|---|
| DNS servers | 1 (Mac 1) | 2: Mac 1 primary + **Mac 3 backup**, same records |
| DNS TTL | 0 (dnsmasq `address=` default) | **30 s** via `host-record=...,30` |
| DNS forwarding | read `/etc/resolv.conf` | `no-resolv` + public upstreams; `local=/team07.test/` so our zone is never forwarded |
| Client resolvers | Mac 1 only | `10.7.30.40, 10.7.30.100` on Mac 1 and Mac 2 |
| nginx upstream | plain round robin | round robin + `max_fails=1 fail_timeout=10s` + `proxy_next_upstream error timeout http_502 http_503` |
| nginx headers | X-Cache-Status | + `X-Edge` (which edge answered) |
| nginx logs | default | custom format `client -> upstream [status] cache=` |
| HTTP version | HTTP/1.1 | HTTP/2 enabled on 8443 |
| Backend exposure | any LAN host could hit :3001/:3002 | **pf**: only Mac 2 + localhost |
| Edge | single nginx | + **standby nginx** on Mac 3 for DNS cutover |
| Backend code | unchanged | only the startup message changed (it printed the old Phase 1 IP) |

All configs are in the repo: `dns/`, `nginx/`, `firewall/`, `tls/README.md`.

---

## 2. Resilience tests and results

### Ext A: Backup DNS resolver

**Setup.** dnsmasq on Mac 3 with the same records as Mac 1. Clients list `10.7.30.40` first and `10.7.30.100` second.

**Test.** On Mac 1: `sudo killall dnsmasq`. On Mac 2:
```
dig @10.7.30.40 app.team07.test +time=2 +tries=1
  -> ;; connection timed out; no servers could be reached
dig app.team07.test
  -> app.team07.test. 30 IN A 10.7.20.12
  -> SERVER: 10.7.30.100#53
curl -s https://app.team07.test:8443/api/status
  -> {"backend": "B", "status": "ok"}
```
The Mac 3 dnsmasq log showed `query[A] app.team07.test from 10.7.20.12`.

**Result: pass.** Name resolution kept working through the backup, and the app was unaffected.
The first lookup after the failure takes a moment, while the macOS resolver gives up on the
primary.

DNS failure vs application failure: when DNS fails, the name can't be turned into an IP, but
the edge is still up and reachable by IP. When an application server fails, DNS still answers
correctly and the TCP/TLS connection to the edge works, but the edge can't get a response from
upstream (502, or a retry on the other backend).

Evidence: `evidence/phase2/extA_*`

### Ext B: DNS TTL and a controlled record change

**Test.**
1. On Mac 2, flush the cache, then `dscacheutil -q host -a name app.team07.test` returns `10.7.20.12` (now cached).
2. On Mac 1, change the record to `10.7.30.100` and restart dnsmasq.
3. On Mac 2, every 5 s, compare the OS cache (`dscacheutil`) with a direct `dig`.

**Observed (23:15:22 to 23:15:48):**

| Time | OS cache | dig (asks the server directly) |
|---|---|---|
| 23:15:22 | 10.7.20.12 | 10.7.30.100 |
| 23:15:27 to 23:15:48 | 10.7.20.12 | 10.7.30.100 |
| 23:15:53 (record restored) | 10.7.20.12 | 10.7.20.12 |

For the whole window the authoritative answer was already the new IP, but the client's cache
kept handing out the old one. That's exactly what the TTL allows. We restored the record before
the OS cache had switched, so this run doesn't show the switch to the new IP itself. In
Extension E, after the cache expired, the clients did move to the new IP.

Then, after changing the record and running `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`,
the next lookup immediately returned the record's current value.

**Result: pass.** `dig` bypasses the OS cache, so it always shows what the server says now.
`dscacheutil`, curl and Safari go through mDNSResponder and its cache.

Evidence: `evidence/phase2/extB_*`

### Ext C: Service isolation (pf on Mac 3)

**Rules** (`firewall/team07.rules`): pass lo0 → 3001/3002, pass 10.7.20.12 → 3001/3002, block drop everything else to 3001/3002.

| From | `nc -vz -G 3 10.7.30.100 3001/3002` |
|---|---|
| Mac 1 (client) | `Operation timed out` (both ports) |
| Mac 2 (edge) | `succeeded` (both ports) |
| Mac 1 → `https://app.team07.test:8443` | still served through the edge |
| Mac 1, after `pfctl -f /etc/pf.conf; pfctl -d` | `succeeded` again (rollback works) |

**Result: pass.** The backends are only reachable through the edge, the way a private subnet
with a security group would work. We use `drop` rather than `return`, so a blocked client gets a
timeout and learns nothing.

Evidence: `evidence/phase2/extC_*`

### Ext D: HA failover

**Config.** `max_fails=1 fail_timeout=10s` on both upstream servers, plus `proxy_next_upstream error timeout http_502 http_503`.

**Test.**
- Before: requests alternated A/B, and the access log showed `-> 10.7.30.100:3001` and `-> 10.7.30.100:3002` in turn.
- We stopped Backend A on Mac 3. Every request then returned **200 with `X-Backend: B`**. The
  request that hit A first failed with connection refused, nginx retried it on B, and the client
  never saw an error.
- We restarted A. After the 10 s `fail_timeout`, nginx tried A again and the A/B alternation came back.

**Result: pass.** These are passive health checks: nginx notices failures on real traffic
rather than probing.

**Remaining single point of failure:** the nginx edge on Mac 2. If Mac 2 goes down, both healthy
backends become unreachable, because DNS points only at Mac 2. Ways to fix it:
- two edges sharing a floating VIP (keepalived/VRRP), or
- two A records with health-checked DNS failover (e.g. Route 53), or
- a managed load balancer that is redundant across zones (e.g. AWS ALB).

Extension E is the manual, DNS-based version of this.

Evidence: `evidence/phase2/extD_nginx_error_and_access_logs.jpg`

### Ext E: Controlled edge migration (DNS cutover)

**Setup.** A second nginx on Mac 3 (`nginx/nginx-standby.conf`). It's the same config, but the
upstreams are 127.0.0.1 and it sends `X-Edge: mac3-standby`. We copied the server cert and key to
Mac 3, and checked the standby directly before switching DNS:
`curl --resolve app.team07.test:8443:10.7.30.100 ...` returned `x-edge: mac3-standby`.

**Cutover.** We changed `app.team07.test` to `10.7.30.100` on **both** DNS servers. If only the
primary changes, a client that fails over to the backup gets sent to the old edge.

**Observed on Mac 1 (23:29:41 to 23:30:28):** every request returned `x-edge: mac3-standby` and `connected-to=10.7.30.100`.
The pf firewall stayed on the whole time, and the standby reached the backends over lo0.

**Migrate back.** We restored the record to `10.7.20.12` on both servers and flushed the
client, which was back on `mac2-primary`.

**Result: pass.** Traffic moved to a different edge machine without touching any client
config. Only the DNS answer changed. The old edge has to keep running for at least one TTL after
the switch, because clients with a cached answer will still use it. In this run the client's cache
had already expired by the time the loop started, so every row shows the standby.

Evidence: `evidence/phase2/extE_*`

### Ext F: Troubleshooting method

For the faculty-injected fault, we work bottom-up and say what each step rules out:

| Step | Command | If it fails, the problem is… |
|---|---|---|
| 1. IP reachability | `ping -c 2 10.7.20.12` | L3 / Wi-Fi |
| 2. DNS | `scutil --dns \| grep nameserver`, `dig app.team07.test`, `dig @10.7.30.40 …`, `dig @10.7.30.100 …` | resolver settings, dnsmasq down, wrong record |
| 3. TCP | `nc -vz -G 3 app.team07.test 8443` | nginx down / wrong port / firewall |
| 4. TLS | `openssl s_client -connect app.team07.test:8443 -servername app.team07.test` | cert path, expired cert, untrusted CA, SNI |
| 5. HTTP | `curl -v https://app.team07.test:8443/api/status` | 502 = edge OK, upstream bad |
| 6. Edge → backend | `tail /tmp/cn-nginx-error.log`, then from Mac 2: `nc -vz 10.7.30.100 3001` | backend down, wrong upstream port, pf |

---

## 3. Troubleshooting findings (real problems we hit while rebuilding)

1. **zsh treated `#` comments as arguments.** A pasted line like `open -e file  # replace ...`
   tried to open files called `#`, `replace`, and so on. macOS zsh has `interactivecomments`
   off by default. Fix: `setopt interactivecomments`.

2. **dnsmasq ignored Ctrl+C.** In the foreground it just printed `^C`, because dnsmasq uses
   SIGINT internally. We stopped it with `sudo killall dnsmasq` from another tab.
   At one point we accidentally killed the backup on Mac 3 too, so the Ext A test briefly had
   no DNS at all. We restarted it before running the test.

3. **TLS: `unknown ca` on Mac 1 (alert 48).** curl on Mac 1 failed with "unable to get local
   issuer certificate". Working through the layers:
   - DNS was fine (dig → 10.7.20.12).
   - TCP was fine (the connection to :8443 opened).
   - The nginx error log on Mac 2 showed `SSL_do_handshake() failed ... tlsv1 alert unknown ca ... client: 10.7.30.40`.

   So the *client* was rejecting our certificate. Comparing SHA-256 fingerprints showed that
   `~/cn/tls/team07-ca.crt` on Mac 1 was the **old Phase 1 CA**. AirDrop had saved the new file
   as `team07-ca 2.crt`, because the old name already existed. Copying and trusting the correct
   file fixed it. Lesson: verify certificates by fingerprint, not by filename.

4. **`dig` vs the OS cache.** `dig` always shows the server's current answer, so it can't
   demonstrate client-side caching. For the TTL demo we used `dscacheutil -q host`, which goes
   through mDNSResponder like curl and Safari do.

5. **Packet capture location.** On Mac 1 the DNS server is the machine itself, so its own
   queries go over loopback and never appear on `en0`. To capture DNS and HTTPS on the wire,
   the client has to be a different machine from the DNS server.

6. **Hostel Wi-Fi.** We expected client isolation, but this network (`10.7.0.0/19`) allows
   laptop-to-laptop traffic, so all pings worked on the first try.

---

## 4. Learning summary

**Ext A (backup DNS).** DNS is a dependency of everything, even when every server is healthy.
Adding a second resolver with the same zone made name resolution survive the loss of Mac 1. We
also saw that "failover" on the client is just the stub resolver timing out and trying the next
server in its list, which is why the first lookup after the failure was slower.

**Ext B (TTL).** A DNS change isn't instant. Each client keeps the old answer until its TTL runs
out, and only that client can flush its own cache. We saw the server and the client disagree for
the whole window. That's why production teams lower the TTL well before a migration and raise
it again afterwards.

**Ext C (service isolation).** Putting the backends behind a firewall that only trusts the edge
means the load balancer is the only way in. The public site keeps working while direct access is
blocked. Keeping a backup of `/etc/pf.conf` and a one-line rollback made it safe to experiment
with.

**Ext D (HA failover).** With passive health checks and `proxy_next_upstream`, losing one
backend was invisible to clients. It also made it obvious that redundancy at one layer doesn't
help if another layer (our single nginx edge) has no redundancy.

**Ext E (edge migration).** You can move a whole service to new hardware by changing one DNS
record, as long as the new edge is verified first, both DNS servers are updated together, and the
old edge stays up for at least one TTL.

**Ext F (troubleshooting).** The most useful habit was working through the layers in order:
IP, DNS, TCP, TLS, HTTP, upstream. Our real `unknown ca` problem looked like "HTTPS is broken",
but two quick checks ruled out DNS and TCP and pointed straight at the client's trust store.
