# TLS Configuration

This project uses a local Team 07 Certificate Authority.

## Certificates

The server certificate is for:

- `app.team07.test`
- `api.team07.test`

The certificate is signed by the Team 07 local CA.

## Private Keys

Private TLS keys must never be committed to GitHub.

Examples:

```text
team07-ca.key
app.team07.test.keycat > tls/README.md <<'EOF'
# TLS Configuration

This project uses a local Team 07 Certificate Authority.

## Certificates

The server certificate is for:

- `app.team07.test`
- `api.team07.test`

The certificate is signed by the Team 07 local CA.

## Private Keys

Private TLS keys must never be committed to GitHub.

Examples:

```text
team07-ca.key
app.team07.test.key
