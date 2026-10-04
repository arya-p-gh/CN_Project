# Team 07 — DNS Server

## Role

Mac 1 is the DNS server for Team 07.

- Host: Mac 1
- IP address: `10.7.23.53`
- Network interface: `en0`
- DNS software: `dnsmasq`
- DNS port: `53`

## DNS Records

The DNS server resolves the Team 07 test domains to the Edge/Nginx server on Mac 2.

| Domain | IP address | Purpose |
|---|---|---|
| `app.team07.test` | `10.7.10.60` | Application / Edge server |
| `api.team07.test` | `10.7.10.60` | API / Edge server |

## Configuration

The example configuration is stored in:

`dns/dnsmasq.conf.example`

The active dnsmasq configuration uses:

```text
interface=en0
listen-address=127.0.0.1,10.7.23.53
bind-interfaces

address=/app.team07.test/10.7.10.60
address=/api.team07.test/10.7.10.60


## Configuration Validation

The dnsmasq configuration was checked with:

sudo /opt/homebrew/sbin/dnsmasq --test -C /opt/homebrew/etc/dnsmasq.conf

Result:

dnsmasq: syntax check OK.

## DNS Service

The DNS service was verified with:

sudo lsof -nP -iUDP:53 -iTCP:53

The service is listening on:

10.7.23.53:53

for both UDP and TCP.

It also listens locally on:

127.0.0.1:53

## DNS Resolution Tests

The app.team07.test record was tested directly against the Team 07 DNS server:

dig @10.7.23.53 app.team07.test

Expected result:

status: NOERROR

ANSWER SECTION:
app.team07.test. 0 IN A 10.7.10.60

SERVER: 10.7.23.53#53(10.7.23.53)

The api.team07.test record was tested with:

dig @10.7.23.53 api.team07.test

Expected result:

status: NOERROR

ANSWER SECTION:
api.team07.test. 0 IN A 10.7.10.60

SERVER: 10.7.23.53#53(10.7.23.53)

These tests confirm that Mac 1 resolves both Team 07 domains to Mac 2 (10.7.10.60).
