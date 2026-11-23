# How our project works (read this before the viva)

This is a plain-language walk-through of what we built and why. Every one of us should be able
to explain **every** section, not just the part on our own laptop.

---

## 1. The big idea in one paragraph

We built a tiny version of how a real website works, using 3 laptops on the same Wi-Fi. When
someone types `https://app.team07.test:8443` on a client:

1. A **DNS server** turns the name into an IP address.
2. The client opens a **TCP** connection to that IP.
3. **TLS** encrypts the connection and proves the server is genuine.
4. An **nginx reverse proxy** receives the encrypted request, decrypts it, and forwards it to one of two **backend servers**, taking turns.
5. The backend answers with JSON.

Phase 1 built this. Phase 2 made it survive failures: a second DNS server, a firewall, automatic
failover, and moving the whole site to another laptop.

---

## 2. Who runs what

| Laptop | Person | IP | Runs | Real-world equivalent |
|---|---|---|---|---|
| **Mac 1** | Arya | 10.7.30.40 | **dnsmasq** (primary DNS server); also used as the **client** (curl / Safari) | Route 53 / a DNS provider; the user's computer |
| **Mac 2** | Divyansh | 10.7.20.12 | **nginx**: HTTPS on port 8443, load balancer | AWS Load Balancer / CDN edge |
| **Mac 3** | Rishita | 10.7.30.100 | **Backend A** (port 3001), **Backend B** (port 3002), **backup DNS**, **pf firewall**, **standby nginx** | app servers (EC2), second DNS server, security group, second load balancer |

All three are on the same subnet `10.7.0.0/19` (mask 255.255.224.0, gateway 10.7.0.1), so they
reach each other directly without going through a router to another network.

---

## 3. One request, step by step

```
 Mac 1 (client)                Mac 1 (DNS)        Mac 2 (nginx)            Mac 3 (backends)
      |  "what is app.team07.test?"  |                  |                         |
      |----- UDP port 53 ----------->|                  |                         |
      |<---- "10.7.20.12, TTL 30" ---|                  |                         |
      |                                                 |                         |
      |---- TCP SYN / SYN-ACK / ACK  to :8443 --------->|                         |
      |---- TLS ClientHello ... Finished -------------->|  (cert: app.team07.test,|
      |                                                 |   signed by Team07 CA)  |
      |==== encrypted HTTP/2  GET /api/status =========>|                         |
      |                                                 |-- plain HTTP to :3001 ->|  (or :3002)
      |                                                 |<- JSON + X-Backend: A --|
      |<=== encrypted response (+ X-Edge, X-Cache) =====|                         |
```

| Step | Protocol | Port | Layer | What to say in the viva |
|---|---|---|---|---|
| Name lookup | DNS | 53/UDP | Application (uses UDP at transport) | "DNS is like a phone book. It only gives the address; it doesn't connect you." |
| Connect | TCP 3-way handshake | 8443 | Transport | "SYN, SYN-ACK, ACK, before any data. The client uses a random *ephemeral* port (like 54321); the server uses the fixed port 8443." |
| Secure | TLS 1.2/1.3 | 8443 | between transport and application | "The server sends its certificate. The client checks it's signed by a CA it trusts (our Team07 Local CA) and that the name matches. Then they agree on keys, and everything after that is encrypted." |
| Request | HTTP/2 over TLS | 8443 | Application | "In Wireshark you can't read this part; it shows as Application Data." |
| Proxy | HTTP/1.0 | 3001/3002 | Application | "nginx *terminates* TLS: it decrypts, then talks plain HTTP to the backend on the private side." |
| Wire | IPv4 | – | Network | "IP addresses get the packets to the right machine." |
| Wire | Wi-Fi 802.11 | – | Link | "MAC addresses deliver frames on the local Wi-Fi." |

---

## 4. Each component explained

### DNS: dnsmasq (Mac 1, backup on Mac 3)
- The config is `~/cn/dnsmasq.conf` (repo copies: `dns/dnsmasq-primary.conf` and `dns/dnsmasq-backup.conf`).
- `host-record=app.team07.test,10.7.20.12,30`: the name points to Mac 2, and the answer may be cached for **30 seconds (the TTL)**.
- `local=/team07.test/`: we own this domain, so we never ask the internet about it. The answer comes back with the `aa` (authoritative) flag.
- `server=1.1.1.1`: any other name (google.com and so on) is forwarded to the internet, so the clients still have internet access.
- **Why `.test`?** It's reserved for testing and never exists on the real internet. `.local` would clash with Apple's Bonjour/mDNS.
- **Client side:** Mac 1 and Mac 2 have their DNS set to `10.7.30.40, 10.7.30.100`, which means "ask Mac 1 first, then Mac 3".

### Backends: Python (Mac 3)
- `backend/backend_a.py` (port 3001) and `backend_b.py` (port 3002), each about 50 lines.
- They answer `GET /` and `GET /api/status` with JSON, plus these headers:
  - `X-Backend: A` or `B`, so we can see which one answered
  - `Cache-Control: max-age=60`: you may reuse this response for 60 seconds
  - `ETag: "backend-a-v1"`: a version tag for this response. If the client sends it back in `If-None-Match`, the server replies **304 Not Modified** without a body.
- They listen on `0.0.0.0`, meaning all network interfaces, so other laptops can reach them. `127.0.0.1` would only accept connections from Mac 3 itself.

### nginx edge (Mac 2)
- The config is `~/cn/nginx-edge.conf` (repo: `nginx/nginx-edge.conf`).
- `upstream backends { server 10.7.30.100:3001; server 10.7.30.100:3002; }`: **round robin**, so requests alternate A, B, A, B.
- `listen 8443 ssl` + `ssl_certificate`: **TLS termination**. The client's encryption ends here.
- `proxy_cache` on `/api/status`: nginx keeps a copy for 60 seconds. The header `X-Cache-Status` shows `MISS` (had to ask a backend) or `HIT` (answered from the copy).
- `max_fails=1 fail_timeout=10s` + `proxy_next_upstream error timeout ...`: **failover**. If a backend fails, nginx retries the request on the other one and skips the dead backend for 10 seconds.
- `X-Edge: mac2-primary`: tells us which edge answered (used in the migration demo).
- **Why do clients never need the backend IPs?** They only know `app.team07.test` → Mac 2, and nginx knows the backends. We could add, remove or move backends without touching any client.

### TLS certificates
- We made our own **certificate authority** ("Team07 Local CA") on Mac 2 with OpenSSL, and used it to sign a **server certificate** for `app.team07.test` and `api.team07.test`.
- Every client Mac **trusts the CA** (`security add-trusted-cert`). That's why there's no browser warning and no `curl -k`.
- **Fingerprints:**
  - CA ends in `67:93:55:35`
  - server cert ends in `71:5E:E1`
  - the old Phase 1 CA ended in `8C:9D:E4:9B`
- The private keys never leave Mac 2 (and Mac 3 for the standby), and they're never on GitHub.

---

## 5. Phase 2: what each extension proves

### Ext A: Backup DNS
- **What we did:** a second dnsmasq on Mac 3 with the same records. We stopped Mac 1's dnsmasq. The client's `dig` showed `SERVER: 10.7.30.100`, and the site kept working.
- **Key point:** "If DNS dies, the servers are still up. You just can't find them by name. If a backend dies, DNS still works but you get an error from the edge."

### Ext B: TTL
- **What we did:** we changed the record from 10.7.20.12 to 10.7.30.100. `dig` showed the new IP straight away, but the client kept using the old one for about 40 seconds, then switched. Flushing the cache made it switch immediately.
- **Key point:** "TTL is how long a client may remember an answer. Before a migration, companies lower the TTL, so the change spreads quickly."
- **Why `dig` showed the new IP right away:** dig asks the DNS server directly and skips the Mac's cache. `dscacheutil`, curl and Safari use the cache.

### Ext C: Firewall (pf on Mac 3)
- **What we did:** rules allowing only Mac 2 (and localhost) to reach ports 3001/3002. From Mac 1, `nc` to 3001 **timed out**. The website still worked through nginx. Rolling back restored access.
- **Key point:** "Backends should only be reachable through the load balancer, like a security group in AWS. We used `drop`, so the attacker sees a timeout instead of 'refused' and learns nothing."

### Ext D: HA failover
- **What we did:** we stopped Backend A. Six requests in a row came back **200 from B, with no errors**. We restarted A, and after 10 seconds the A/B alternation came back.
- **Key point:** "nginx noticed the failure on a real request (a passive health check), retried it on B, and stopped sending to A for 10 seconds."
- **Single point of failure:** nginx on Mac 2. If Mac 2 dies, the site is down even though both backends are fine. Fixes: two edges with a floating IP (keepalived), DNS failover, or a cloud load balancer.

### Ext E: Edge migration
- **What we did:** started a second nginx on Mac 3 (standby, `X-Edge: mac3-standby`), then pointed `app.team07.test` at 10.7.30.100 **on both DNS servers**. Clients stayed on Mac 2 for about 40 seconds (TTL), then moved to Mac 3. We moved back afterwards.
- **Key point:** "We moved the whole site to another machine without touching any client, just by changing DNS. The old edge has to stay up for at least one TTL."

### Ext F: Troubleshooting (done live by the faculty)
Always go bottom-up, and say each step out loud:

| # | Check | Command (on a client) | Fails → problem is |
|---|---|---|---|
| 1 | Can I reach the machine? | `ping 10.7.20.12` | network / Wi-Fi |
| 2 | Does the name resolve? | `dig app.team07.test` | DNS (server down, wrong record, wrong client setting) |
| 3 | Is the port open? | `nc -vz app.team07.test 8443` | nginx down / wrong port / firewall |
| 4 | Is TLS OK? | `curl -v https://app.team07.test:8443` (look for `verify ok`) | certificate / CA trust |
| 5 | Does HTTP work? | look at the status code | 502 = backend refused, 504 = backend timed out |
| 6 | Edge → backend? | on Mac 2: `zsh scripts/mac2.sh errors` / `backends` | backend down / firewall |

---

## 6. Real problems we hit (good viva stories)

1. **"unable to get local issuer certificate" on Mac 1.**
   - DNS and TCP were fine, but the TLS check failed.
   - nginx logged `alert unknown ca`, meaning the client didn't trust our certificate.
   - Mac 1 was trusting the **old** Phase 1 CA. AirDrop had saved the new one under a different name.
   - Fixed by comparing **fingerprints**, not filenames.
2. **504 Gateway Timeout in the morning.** TLS to nginx worked, so the problem was upstream. It turned out Mac 3 was switched off.
3. **dnsmasq ignores Ctrl+C.** You have to stop it with `sudo killall dnsmasq`.
4. **College Wi-Fi.** We worried it would block laptop-to-laptop traffic, but this network allows it.

---

## 7. Likely viva questions (short answers)

| Question | Answer |
|---|---|
| Difference between DNS resolution and the TCP connection? | DNS finds the IP (UDP 53). TCP then connects to that IP and port (8443). They're separate steps, and either can fail on its own. |
| Why does the client never see the backend IPs? | It only talks to nginx. nginx proxies to the backends. |
| What is TLS termination? | nginx decrypts HTTPS, then talks plain HTTP to the backends on the private side. |
| Why no certificate warning? | The cert is signed by our CA, the CA is trusted on every client, and the name matches the SAN. |
| What's in the TLS handshake? | ClientHello → ServerHello → Certificate → key exchange → ChangeCipherSpec/Finished. In TLS 1.3 the certificate is encrypted. |
| What is an ephemeral port? | The random high port the client's OS picks for its side of the connection. |
| 200 vs 304? | 200 sends the full body. 304 means "your copy is still valid", so there's no body. |
| Fresh cache hit vs conditional request? | Fresh hit: reused without asking anyone. Conditional: asks "changed?" with `If-None-Match`, and gets back 304. |
| 502 vs 504? | 502: the backend refused or returned garbage. 504: the backend didn't answer in time. |
| What does TTL 30 mean? | Clients may reuse the DNS answer for 30 seconds before asking again. |
| How does round robin work? | Each new request goes to the next backend in the list. |
| What's the single point of failure? | nginx on Mac 2. |
| Why port 8443 and not 443? | Ports below 1024 need root on macOS. The project doc allows 8443. |
| How would this look in AWS? | Route 53 (DNS) → ALB with an ACM certificate (edge) → EC2 instances in a target group, with security groups. |
