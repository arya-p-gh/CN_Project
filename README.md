# CN Phase 1 — Build & Observe

## Team

- **Team:** RAD
- **Infrastructure:** Type 2 — 2–3 Macs with combined roles

### Members

| Name | Enrollment Number |
|---|---|
| Divyansh Rathore | 2401020021 |
| Arya Pandey | 2401020012 |
| Rishita Boisnobi | 2401010382 |

## Architecture

| Machine | Role | IP Address |
|---|---|---|
| Mac 1 | DNS Server | 10.7.23.53 |
| Mac 2 | Edge Server / Nginx / TLS | 10.7.10.60 |
| Mac 3 | Backend Server | 10.7.10.56 |

## Request Flow

```text
Client
  |
  | DNS query
  v
Mac 1 — DNS (10.7.23.53)
  |
  | app.team07.test -> 10.7.10.60
  v
Mac 2 — Nginx Edge
  |
  | HTTPS :8443
  v
Backend A (:3001) / Backend B (:3002)
  |
  v
/api/status
