# TLS Configuration

Team 07 uses its own local Certificate Authority ("Team07 Local CA"). nginx on the edge
terminates TLS on port **8443** with a server certificate signed by that CA.

## Files

| File | Where it lives | In git? |
|---|---|---|
| `team07-ca.crt` | created on Mac 2, copied to every client and trusted | no (regenerate) |
| `team07-ca.key` | **Mac 2 only**, never leaves it | **never** |
| `app.team07.test.crt` | Mac 2 (edge) and Mac 3 (standby edge) | no |
| `app.team07.test.key` | Mac 2 (edge) and Mac 3 (standby edge) | **never** |

Keys are excluded by `.gitignore` (`*.key`, `*.pem`).

## Current certificate

- Subject CN: `app.team07.test`
- SAN: `DNS:app.team07.test`, `DNS:api.team07.test`
- Issuer: `Team07 Local CA`
- Valid: 22 Nov 2026 to 22 Nov 2027
- Server cert SHA-256: `C1:15:26:42:D3:D0:8E:1E:56:6E:4F:1B:15:BF:73:4D:52:A0:ED:D2:23:B6:5E:53:69:1B:A7:A1:1B:71:5E:E1`
- CA cert SHA-256: `8F:0B:2A:09:86:0B:12:C3:84:F3:5D:B5:A4:EB:53:FB:79:89:33:58:72:07:A5:F0:64:E0:70:47:67:93:55:35`

Screenshot: `evidence/phase2/tls_server_certificate_details.png`

## How we generated it (on Mac 2)

We used Homebrew OpenSSL 3 because the LibreSSL that ships with macOS doesn't support `-addext`.

```bash
OSSL=$(brew --prefix openssl@3)/bin/openssl
mkdir -p ~/cn/tls && cd ~/cn/tls

# 1. local CA
$OSSL req -x509 -newkey rsa:4096 -nodes -keyout team07-ca.key -out team07-ca.crt \
  -days 365 -subj "/CN=Team07 Local CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"

# 2. server key + CSR
$OSSL req -newkey rsa:2048 -nodes -keyout app.team07.test.key -out app.team07.test.csr \
  -subj "/CN=app.team07.test"

# 3. sign it with SANs (browsers only look at SAN, not CN)
cat > san.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.team07.test,DNS:api.team07.test
EOF
$OSSL x509 -req -in app.team07.test.csr -CA team07-ca.crt -CAkey team07-ca.key \
  -CAcreateserial -out app.team07.test.crt -days 365 -sha256 -extfile san.ext
```

## Trusting the CA on clients

Run this on every Mac that will open the site:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/cn/tls/team07-ca.crt
```

Check the fingerprint before trusting it. If a file with the same name is already in
Downloads, AirDrop saves the new one as `team07-ca 2.crt`. That's exactly how Mac 1 ended
up trusting our old Phase 1 CA (see the troubleshooting section in `PHASE2_REPORT.md`).

```bash
openssl x509 -in ~/cn/tls/team07-ca.crt -noout -fingerprint -sha256
```

## Verification

```bash
curl -v https://app.team07.test:8443/api/status     # "SSL certificate verify ok"
openssl s_client -connect app.team07.test:8443 -servername app.team07.test </dev/null
```

The demo never uses `curl -k`.
