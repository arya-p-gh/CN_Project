# CN Project - Private Network Service Platform (Team 07)

## Team

- **Team:** RAD (Team 07)
- **Infrastructure:** Type 2: 3 Macs with combined roles
- **Domain:** `app.team07.test` / `api.team07.test`

### Members

| Name | Enrollment Number |
|---|---|
| Divyansh Rathore | 2401020021 |
| Arya Pandey | 2401020012 |
| Rishita Boisnobi | 2401010382 |

## Machines (Phase 2 network)

All three Macs are on the same Wi-Fi, subnet `10.7.0.0/19` (mask `255.255.224.0`), gateway `10.7.0.1`, interface `en0`.

| Machine | Phase 1 role | Added in Phase 2 | IP |
|---|---|---|---|
| **Mac 1** (Arya) | Primary DNS (dnsmasq) + client | - | `10.7.30.40` |
| **Mac 2** (Divyansh) | Edge: nginx reverse proxy, TLS termination, load balancer | Client 2, passive health checks | `10.7.20.12` |
| **Mac 3** (Rishita) | Backend A `:3001`, Backend B `:3002` | Backup DNS, pf firewall, standby edge nginx | `10.7.30.100` |

The IPs changed from Phase 1 (`10.7.23.53` / `10.7.10.60` / `10.7.10.56`) because we rebuilt on a new day's DHCP leases.

**If the IPs change again** (new DHCP lease on demo day): each Mac runs `ipconfig getifaddr en0` and shares its IP with the others. Then all three run the same line with their own script:

```bash
zsh scripts/mac1.sh ips <mac1-ip> <mac2-ip> <mac3-ip>    # mac2.sh / mac3.sh on the other two
```

This saves the IPs to `~/cn/ips` on that Mac, outside the repo. The next `start` rebuilds `~/cn/` from the repo configs with those IPs swapped in: the DNS listen address and A records, the nginx upstream, and the pf allow rule. The certificate only names `app.team07.test` / `api.team07.test`, not IPs, so TLS keeps working. The configs in the repo keep the 23 Nov IPs, so they match the evidence.

## Service map

| Service | Host | Port | Cloud equivalent |
|---|---|---|---|
| DNS primary (dnsmasq) | Mac 1 | 53 UDP/TCP | Route 53 hosted zone |
| DNS backup (dnsmasq) | Mac 3 | 53 UDP/TCP | second Route 53 name server |
| Edge nginx (HTTPS) | Mac 2 | 8443 | ALB / CDN edge |
| Edge nginx (HTTP) | Mac 2 | 8080 | - |
| Standby edge nginx | Mac 3 | 8443 | second ALB in another region |
| Backend A | Mac 3 | 3001 | EC2 / container A |
| Backend B | Mac 3 | 3002 | EC2 / container B |
| pf firewall | Mac 3 | - | security group |

## Topology

```text
                       Wi-Fi LAN 10.7.0.0/19 (gw 10.7.0.1)
   ┌───────────────────────┬──────────────────────────┬───────────────────────────┐
   │                       │                          │                           │
┌──┴───────────────┐  ┌────┴─────────────────┐  ┌─────┴──────────────────────────┐
│ Mac 1 10.7.30.40 │  │ Mac 2 10.7.20.12     │  │ Mac 3 10.7.30.100              │
│ dnsmasq :53 (P)  │  │ nginx :8443 TLS      │  │ backend A :3001  backend B :3002│
│ client           │  │ round robin + HC     │  │ dnsmasq :53 (backup)           │
│                  │  │ client 2             │  │ pf: 3001/3002 only from Mac 2  │
│                  │  │                      │  │ standby nginx :8443 (Ext E)    │
└──────────────────┘  └──────────────────────┘  └────────────────────────────────┘
```

## Request flow

```text
Client (Mac 1)
  │ 1. DNS  UDP 53   "A app.team07.test?" → Mac 1 (or Mac 3 if Mac 1 is down)
  │                   ← 10.7.20.12, TTL 30
  │ 2. TCP  3-way handshake → 10.7.20.12:8443 (ephemeral source port)
  │ 3. TLS  ClientHello → ServerHello → Certificate (Team07 Local CA) → Finished
  │ 4. HTTP/2 GET /api/status (encrypted)
  ▼
Mac 2 nginx ── TLS terminated here; Host/X-Forwarded-For added
  │ 5. plain HTTP/1.0 to an upstream picked by round robin
  ▼
Mac 3 Backend A :3001  or  Backend B :3002
  │ 6. JSON + X-Backend, Cache-Control: max-age=60, ETag
  ▼
back through nginx (adds X-Edge, X-Cache-Status) → client
```

| Layer (TCP/IP) | Protocol here | OSI |
|---|---|---|
| Application | DNS, HTTP/1.1 + HTTP/2, REST/JSON | 7 |
| (security) | TLS 1.2 / 1.3 | 5/6 |
| Transport | UDP 53, TCP 8443 / 3001 / 3002 | 4 |
| Network | IPv4 10.7.0.0/19 | 3 |
| Link | Wi-Fi 802.11 (en0) | 2/1 |

## Repo layout

| Path | What |
|---|---|
| `backend/` | Python REST backends A and B |
| `dns/` | dnsmasq primary + backup configs (Phase 1 example kept) |
| `nginx/` | edge config, standby config (Phase 1 example kept) |
| `firewall/` | pf rules for service isolation + apply/rollback steps |
| `tls/` | how the CA and server cert were made and trusted (no keys) |
| `evidence/` | Phase 2 screenshots + raw terminal output from the 23 Nov re-run |
| `scripts/` | evidence collection (`mac1_evidence.sh`), Ext E transition run, certificate fingerprint check |
| [`PHASE2_REPORT.md`](PHASE2_REPORT.md) | Phase 2 final report |

## Quick start (demo day order)

1. **Mac 3:** `python3 backend/backend_a.py`, `python3 backend/backend_b.py`, then backup dnsmasq
2. **Mac 1:** primary dnsmasq
3. **Mac 2:** `nginx -c ~/cn/nginx-edge.conf`
4. **Clients:** `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
5. Check from Mac 1:
   ```bash
   dig app.team07.test
   for i in 1 2 3 4; do curl -s -D - -o /dev/null https://app.team07.test:8443/ | grep -i x-backend; done
   ```
