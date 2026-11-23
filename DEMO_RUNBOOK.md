# Demo runbook: from closed laptops to a full demo

Everything we configured is saved on disk (`~/cn/...`). Closing terminal tabs or restarting a
laptop only stops the **running programs**. This runbook starts them again and walks through the
11 demo steps from the project doc.

| Laptop | Person | IP |
|---|---|---|
| Mac 1 | Arya | 10.7.30.40 |
| Mac 2 | Divyansh | 10.7.20.12 |
| Mac 3 | Rishita | 10.7.30.100 |

---

## A. Cold start (5 minutes)

**1. All three:** join the same Wi-Fi, then get the latest scripts:
```bash
cd ~/cn/CN_Project && git pull
```

**2. Start the services in this order: Mac 3 → Mac 1 → Mac 2.** Each command asks for your password once, then runs everything in the background. You can close the tab afterwards.

| Order | Laptop | Command | Starts |
|---|---|---|---|
| 1 | **Mac 3** (Rishita) | `zsh scripts/mac3.sh start` | Backend A, Backend B, backup DNS, firewall off |
| 2 | **Mac 1** (Arya) | `zsh scripts/mac1.sh start` | primary DNS, team DNS settings |
| 3 | **Mac 2** (Divyansh) | `zsh scripts/mac2.sh start` | nginx edge, team DNS settings |

Each one finishes with a status check. **Everything should be ✔ green** after Mac 2 starts:
```
✔ ping 10.7.30.40 / 10.7.20.12 / 10.7.30.100
✔ primary DNS (Mac 1) -> 10.7.20.12
✔ backup DNS (Mac 3) -> 10.7.20.12
✔ nginx edge (10.7.20.12:8443) reachable
✔ backend A / backend B reachable
✔ https://app.team07.test:8443 -> 200, certificate verified
```
You can re-check at any time from any laptop with `zsh scripts/macN.sh status`.

**3. All three:** keep the laptop awake with `caffeinate -dis` (leave that tab open).

### If something is red ✘
| Red line | Fix |
|---|---|
| "this Mac is X but the configs expect Y" | The IP changed. **Stop and tell the team.** The configs need the new IP. |
| ping fails | Not on the same Wi-Fi, or the laptop is asleep |
| primary/backup DNS not answering | Run `start` again on Mac 1 / Mac 3 |
| nginx edge not reachable | Run `zsh scripts/mac2.sh start` on Mac 2 |
| backend A/B not reachable | Run `zsh scripts/mac3.sh start-both` on Mac 3 |
| end to end gives `000` | Check the lines above it; something earlier in the chain is down |
| end to end gives `200 1` or `200 19`… | Certificate not trusted on this Mac; see `tls/README.md` |
| end to end gives `502` / `504` | nginx is fine, but the backends are down or blocked |

---

## B. The 11 demo steps (from the project doc, section 8)

The **client is Mac 1** unless the table says otherwise. Mac 1 commands are run from `~/cn/CN_Project`.

| # | Step | Who | Command | What to point at |
|---|---|---|---|---|
| 1 | Topology + IPs | anyone | open `README.md` on GitHub | the table and diagram; each person says their role |
| 2 | All on the LAN | Mac 1 | `zsh scripts/mac1.sh status` | the three green ping lines + IPs |
| 3 | Resolve the name | Mac 1 | `dig app.team07.test` | `ANSWER: app.team07.test. 30 IN A 10.7.20.12`, `SERVER: 10.7.30.40`, flag `aa` |
| 4 | HTTPS by name | Mac 1 | `zsh scripts/mac1.sh tls` · then Safari → `https://app.team07.test:8443` | `SSL certificate verify ok`, `HTTP/2 200`, padlock, no IP in the URL |
| 5 | Load balancing | Mac 1 | `zsh scripts/mac1.sh lb` | `x-backend: A, B, A, B…`. Mac 2 can show `zsh scripts/mac2.sh access` |
| 6 | Wireshark | Mac 1 | open the saved capture | DNS query/answer, SYN/SYN-ACK/ACK, ClientHello/ServerHello/Certificate |
| 7 | Caching | Mac 1 | `zsh scripts/mac1.sh cache` | `cache-control: max-age=60`, `MISS` → `HIT`, then **`304`** |
| 8 | Fail one backend | Mac 3 → Mac 1 | Mac 3: `zsh scripts/mac3.sh kill-a` · Mac 1: `zsh scripts/mac1.sh lb` · Mac 2: `zsh scripts/mac2.sh errors` · Mac 3: `zsh scripts/mac3.sh start-a` | all `B`, no errors; nginx log `connect() failed`; after about 10 s, A/B again |
| 9 | Phase 2 DNS/resilience | see below | Ext A, B/E, C | |
| 10 | Faculty fault | all | `HOW_IT_WORKS.md` §5 Ext F ladder | say each layer out loud |
| 11 | Viva | each | `HOW_IT_WORKS.md` §7 | |

### Step 9 details

**Ext A: backup DNS**
| Who | Command | Shows |
|---|---|---|
| Mac 3 | `zsh scripts/mac3.sh dnslog` (leave it running) | queries arriving at the backup |
| Mac 1 | `zsh scripts/mac1.sh dns-down` | primary stopped |
| Mac 2 (client) | `dig @10.7.30.40 app.team07.test +time=2 +tries=1` | **timed out** |
| Mac 2 | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; dig app.team07.test` | `SERVER: 10.7.30.100` |
| Mac 2 | `curl -s https://app.team07.test:8443/api/status` | still works; a query appears in Mac 3's dnslog |
| Mac 1 | `zsh scripts/mac1.sh dns-up` | primary back |

**Ext C: firewall**
| Who | Command | Shows |
|---|---|---|
| Mac 3 | `zsh scripts/mac3.sh firewall-on` | the 3 pf rules |
| Mac 1 | `nc -vz -G 3 10.7.30.100 3001` | **Operation timed out** |
| Mac 2 | `zsh scripts/mac2.sh backends` | edge allowed ✔ |
| Mac 1 | `zsh scripts/mac1.sh lb` | site still works |
| Mac 3 | `zsh scripts/mac3.sh firewall-off` | rollback; `nc` from Mac 1 succeeds again |

**Ext B + E: TTL and edge migration**
| Who | Command | Shows |
|---|---|---|
| Mac 3 | `zsh scripts/mac3.sh standby-on` | standby edge up |
| Mac 3 | `zsh scripts/mac3.sh record mac3` | the backup now also points at Mac 3 |
| Mac 1 | `zsh scripts/mac1.sh migrate` | `mac2-primary` for about 30–40 s after the switch, then `mac3-standby`, then back |
| Mac 3 | `zsh scripts/mac3.sh record mac2` then `standby-off` | clean up |

`migrate` switches Mac 1's record itself and switches it back at the end.

---

## C. Shutting down
| Laptop | Command |
|---|---|
| Mac 3 | `zsh scripts/mac3.sh stop` (also run `firewall-off` if you turned it on) |
| Mac 1 | `zsh scripts/mac1.sh stop` |
| Mac 2 | `zsh scripts/mac2.sh stop` |

To give your laptop normal internet DNS back after the project:
```bash
sudo networksetup -setdnsservers Wi-Fi Empty
```

---

## D. What lives where on each laptop

| Laptop | Files (in `~/cn/`) |
|---|---|
| Mac 1 | `dnsmasq.conf` (primary), `tls/team07-ca.crt` (trusted CA), `CN_Project/` (repo) |
| Mac 2 | `nginx-edge.conf`, `tls/` (CA + **CA key**, server cert + key), `CN_Project/` |
| Mac 3 | `dnsmasq.conf` (backup), `nginx-standby.conf`, `pf/` (firewall rules + backup), `tls/` (CA, server cert + key), `CN_Project/` |

The scripts recreate a missing `dnsmasq.conf` / nginx config / pf file from the repo
automatically. Certificates can't be recreated that way: if they're lost, follow `tls/README.md`.
