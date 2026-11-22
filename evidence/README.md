# Evidence

## Phase 1 (captured at the Phase 1 review)

1. DNS resolution for `app.team07.test`
2. Backend A response
3. Backend B response
4. nginx load balancing
5. HTTPS/TLS connection
6. nginx cache MISS
7. nginx cache HIT
8. Wireshark DNS query and response
9. Wireshark TCP handshake
10. Wireshark TLS handshake
11. Backend failure demonstration

## Phase 2 (`phase2/`)

| Ext | File | Shows |
|---|---|---|
| A | `extA_1_primary_down_backup_answers.jpg` | Mac 2: `dig @10.7.30.40` times out; `dig app.team07.test` answers from `SERVER: 10.7.30.100`; curl still returns backend B |
| A | `extA_2_backup_dnsmasq_query_log.png` | Mac 3 dnsmasq log: `query[A] app.team07.test from 10.7.20.12`, answered from its own config |
| B | `extB_1_ttl_cache_vs_dig.jpg` | Mac 2: dig (direct to server) already says `10.7.30.100`, but the OS cache keeps serving the old `10.7.20.12` |
| B | `extB_2_flush_cache.jpg` | Mac 2: lookup before/after `dscacheutil -flushcache` |
| B | `extB_3_flush_cache_after_restore.jpg` | Mac 2: flush after the record was restored, so the client gets `10.7.20.12` immediately |
| C | `extC_1_client_blocked_from_backends.webp` | Mac 1 → 10.7.30.100:3001/3002: `Operation timed out` |
| C | `extC_2_edge_allowed_to_backends.jpg` | Mac 2 → 10.7.30.100:3001/3002: `succeeded` |
| C | `extC_3_after_rollback_client_reaches_backend.webp` | After the pf rollback, Mac 1 → :3001 succeeds again |
| D | `extD_nginx_error_and_access_logs.jpg` | nginx access log alternating 3001/3002; error log shows TLS `unknown ca` alerts from Mac 1 (troubleshooting finding #3) |
| E | `extE_1_clients_on_standby_edge.webp` | Mac 1 after the DNS cutover: every request goes to `x-edge: mac3-standby`, `connected-to=10.7.30.100` |
| E | `extE_2_dns_restored_and_pf_rolled_back.webp` | Records changed back to 10.7.20.12 on the DNS server, and backend port reachable again |
| TLS | `tls_server_certificate_details.png` | Server cert: CN app.team07.test, issued by Team07 Local CA, validity, SHA-256 |

## Still to capture before the final review

- [ ] Ext D: curl loop showing **only `x-backend: B`** while Backend A is stopped, then A/B again after the restart
- [ ] Ext D: nginx error log line `connect() failed (61: Connection refused) ... 10.7.30.100:3001`
- [ ] Ext C: `sudo pfctl -sr | grep -E '3001|3002'` (rules loaded)
- [ ] Ext E: the **transition** in one run: a few `mac2-primary` rows, then `mac3-standby` (warm the cache first)
- [ ] Ext B: a run long enough to show the OS cache switching to the new IP after the TTL expires
- [ ] Phase 1 re-captures on the new IPs (dig, LB loop, cache HIT/304, Wireshark pcap from Mac 3 as the client)
