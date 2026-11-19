# n8n Production Deployment Guide

## 1. Local Development Setup

### Prerequisites

- Docker and Docker Compose v2+
- Git
- A text editor

### Steps

1. **Clone the repository**

   ```bash
   git clone https://github.com/your-username/n8n-free-hosting.git
   cd n8n-free-hosting
   ```

2. **Configuration**

   Copy the environment example and fill in your values:

   ```bash
   cp .env.example .env
   # Edit .env with your actual values (never commit this file)
   ```

   The `.env` file is git‑ignored and must remain local. All sensitive values (Neon password, encryption key) must be transferred to GitHub Secrets for the CI/CD pipeline (see below).

3. **Start n8n**

   ```bash
   docker compose up -d
   ```

   - The first startup runs database migrations; wait until the log shows "Editor is now accessible".
   - Access the editor at `http://127.0.0.1:5678` or via the Caddy reverse proxy at `http://localhost`.

4. **Create the owner account**

   Open your browser at the n8n URL and complete the owner-account setup. This is the only built‑in authentication in the Community Edition.

5. **Verify health endpoints**

   ```bash
   # Liveness check
   curl -s http://127.0.0.1:5678/healthz

   # Readiness check (confirms DB connected and migrated)
   curl -s http://127.0.0.1:5678/healthz/readiness
   ```

   Both should return a 200 status code with body `{"status":"ok"}`.

### Using the Development Profile

The default `docker compose up -d` starts n8n only (port 5678 bound to `127.0.0.1`). If you want the Caddy reverse proxy with automatic HTTPS:

```bash
docker compose --profile tls up -d
```

This adds the Caddy service, exposes ports 80 and 443, and provisions a TLS certificate via Let's Encrypt for the domain set in `N8N_DOMAIN` (must be configured in `.env` and point to your machine's public IP).

To stop:

```bash
docker compose down
# Or, keeping the data volume:
docker compose down -v  # removes the n8n_data volume
```

## 2. Neon Database Setup

### Creating a Neon Project

1. Sign up at [neon.tech](https://neon.tech) and create a new project.
2. In the Neon Console, go to **Connect** and choose **Connection pooling** ON to get a pooled endpoint, or OFF for a direct connection.
3. Copy the connection string. For n8n, the following environment variables are required:

| Variable | Value (example) | Description |
|----------|-----------------|-------------|
| `DB_TYPE` | `postgresdb` | Use PostgreSQL |
| `DB_POSTGRESDB_HOST` | `ep-super-hill-bde0se4s-pooler.c-8.us-east-2.aws.neon.tech` | The Neon proxy hostname (pooler or direct) |
| `DB_POSTGRESDB_PORT` | `5432` | Standard Postgres port |
| `DB_POSTGRESDB_DATABASE` | `neondb` | The database name |
| `DB_POSTGRESDB_USER` | `neondb_owner` | The Neon database user |
| `DB_POSTGRESDB_PASSWORD` | `<your‑password>` | The Neon password (from the Console) |
| `DB_POSTGRESDB_SCHEMA` | `n8n` | The schema n8n will use |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` | Enable SSL (Neon requires it) |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `true` | Verify the server certificate (ISRG Root X1, trusted by default) |

### Verifying connectivity without running n8n

You can test the Neon connection independently of n8n using `psql` and the credentials from `.env`:

```bash
# Source the .env file (safe — only sets vars in the shell, no export)
set -a; . ./.env; set +a

# Test connection with SSL
docker run --rm -e PGPASSWORD="$DB_POSTGRESDB_PASSWORD" \
  -e PGSSLMODE="${DB_POSTGRESDB_SSL_ENABLED:+require}" \
  postgres:17-alpine \
  psql -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
       -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
       -c "select 'connected', version();"
```

Expected output (truncated):

```
connected|PostgreSQL 18.7 (84da7d8) on aarch64-unknown-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0, 64-bit
```

### Connection pooling vs direct

- **Pooled (default)**: Uses the `-pooler` hostname. Neon's PgBouncer handles up to 10,000 concurrent connections. Transaction mode; suitable for normal n8n operation. May have issues with session‑level `SET` statements during migrations.
- **Direct**: Omit `-pooler` from the hostname, connect directly to port 5432. Recommended if you encounter migration failures or need native PostgreSQL features (e.g., `SET`, temporary tables). n8n runs schema migrations on startup; if you see errors, switch to the direct endpoint by removing `-pooler` from the host.

### Backup and Restore (manual)

**Backup** the Neon database using `pg_dump`:

```bash
# Using the pooled endpoint (recommended for consistency)
pg_dump -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
  -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
  -n "$DB_POSTGRESDB_SCHEMA" -Fc -f n8n-backup.tar

# Or via the connection string (if you set PGPASSWORD)
pg_dump "$DB_POSTGRESDB_CONNECTION_STRING" -Fc -f n8n-backup.tar
```

**Restore**:

```bash
pg_restore -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
  -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
  -n "$DB_POSTGRESDB_SCHEMA" n8n-backup.tar
```

### Important notes

- Neon **requires** SSL/TLS on every connection; the database will reject unencrypted clients.
- The `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=true` setting (default) validates the server certificate against the system CA bundle. The n8n image includes ISRG Root X1 (Let's Encrypt), so this should work out‑of‑the‑box. If you see SSL errors, set `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` only temporarily for debugging, then revert.
- Never commit the real `.env` file to GitHub. The CI/CD pipeline reads secrets from GitHub Secrets (see below).

## 3. GitHub Secrets Configuration

The GitHub Actions workflow uses the following secrets. Add them via **Repository → Settings → Secrets and variables → Actions → New repository secret** (or per‑environment secrets for `development`/`production` environments).

### Required secrets (repo‑level or environment‑level)

| Secret name | Description |
|---|---|
| `SSH_HOST` | IP address or hostname of the production server |
| `SSH_USERNAME` | User account on the server (e.g., `root` or `deploy`) |
| `SSH_PRIVATE_KEY` | SSH private key (unencrypted) for server access |
| `N8N_DOMAIN` | Public domain name (e.g., `n8n.example.com`) — required for Caddy TLS |
| `N8N_PUBLIC_URL` | Public URL of the n8n instance (e.g., `https://n8n.example.com/`) |
| `DB_POSTGRESDB_HOST` | Neon host (same as `DB_POSTGRESDB_HOST` in `.env`) |
| `DB_POSTGRESDB_PORT` | `5432` |
| `DB_POSTGRESDB_DATABASE` | `neondb` |
| `DB_POSTGRESDB_USER` | `neondb_owner` |
| `DB_POSTGRESDB_PASSWORD` | Neon password |
| `DB_POSTGRESDB_SCHEMA` | `n8n` |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` |
| `N8N_ENCRYPTION_KEY` | 64‑character hex string (must match the existing key for credential decryption) |
| `N8N_HOST` | `n8n.example.com` |
| `N8N_PROTOCOL` | `https` |
| `N8N_PORT` | `5678` |
| `N8N_EDITOR_BASE_URL` | `https://n8n.example.com/` |
| `N8N_WEBHOOK_URL` | `https://n8n.example.com/` |
| `N8N_PROXY_HOPS` | `1` |
| `GENERIC_TIMEZONE` | `Asia/Kolkata` |
| `TZ` | `Asia/Kolkata` |

### Optional secrets

- `N8N_IMAGE_TAG` — override the default `2.48.6` for a deliberate upgrade.
- `DEPLOY_DIR` — remote directory path (default `/opt/n8n`).
- `ACME_EMAIL` — email for Let's Encrypt account (if using Caddy TLS).

### Adding secrets via GitHub Environments

For additional isolation, you can add the above secrets to **specific environments** (`development` and `production`). The workflow declares `environment: development` and `environment: production`; GitHub will make the environment‑scoped secrets available to the corresponding jobs. If a secret is defined both at repo level and environment level, the environment value takes precedence.

**Important**: Never hardcode tokens, passwords, or encryption keys in the workflow YAML or any script. The `deploy-from-ci.sh` script reads them via indirect expansion (`${!var}`) and GitHub masks them in logs automatically.

## 4. Production Hosting Setup

### Recommended: Oracle Cloud Always Free

| Feature | Specification |
|---|---|
| VM type | Arm Ampere A1: 2 OCPU / 12 GB RAM (always‑free) |
| Storage | 200 GB block volume (always‑free) |
| Bandwidth | 10 TB/month outbound |
| Load balancer | 1 flexible LB at 10 Mbps |
| Cost | $0/month (subject to capacity eligibility) |

#### Setup steps

1. **Sign up** at [oracle.com/cloud/free](https://oracle.com/cloud/free). A credit card is required for identity verification; you will not be charged as long as you stay within Always Free limits.
2. **Create a VM instance**:
   - Image: **Ubuntu 22.04**
   - Shape: **VM.Standard.A1.Flex** (Ampere ARM)
   - OCPUs: `1‑4` (recommended `2`)
   - RAM: `6‑24 GB` (recommended `12 GB`)
   - Assign a **public IPv4 address**
3. **SSH into the instance** and install Docker + Docker Compose:

   ```bash
   # Ubuntu 22.04
   sudo apt update
   sudo apt install -y docker.io docker-compose
   sudo usermod -aG docker $USER
   newgrp docker
   ```

4. **Clone the repository** and configure `.env`:

   ```bash
   git clone https://github.com/your-username/n8n-free-hosting.git
   cd n8n-free-hosting
   cp .env.example .env
   # Edit .env with your values (Neon host, passwords, encryption key, domain)
   ```

5. **Run the stack**:

   ```bash
   docker compose up -d
   ```

   For HTTPS with Caddy:

   ```bash
   docker compose --profile tls up -d
   ```

   Ensure your domain’s DNS A record points to the server’s public IP.

6. **Configure the domain (DNS)**

   - Create an A record: `n8n.example.com  →  <server‑public‑IP>`
   - The first time Caddy starts, it will attempt to obtain a Let's Encrypt certificate. Make sure the domain is publicly resolvable and that port 80/443 is open on the server firewall.

### Alternative: Hetzner Cloud (paid, ~€5/mo)

1. Create a **CX11** or **CAX11** server running Ubuntu 22.04.
2. Follow the same steps as Oracle Cloud above.
3. Hetzner offers block storage and a flexible load balancer; the setup is identical.

### Why not Vercel?

Vercel Functions are serverless and do not provide a persistent runtime, durable storage, or always‑on background execution. n8n requires all three for reliable workflow execution, database connectivity, and webhook handling. Deploying n8n to Vercel would result in lost state, failed webhooks, and no guarantee of process continuity. Use the architecture documented herein for a production‑ready n8n instance.

## 5. GitHub Actions Deployment

The workflow `.github/workflows/deploy.yml` implements the following stages:

1. **Trigger** — `push` to `main` (auto‑deploys to **development**); `workflow_dispatch` (manual choice of **development** or **production**).
2. **Validate** — Lints `compose.yaml`, validates all required environment variables, runs secret‑scan checks, verifies the image is pinned (not `latest`), and inspects the image digest.
3. **Deploy** — via SSH: writes a temporary `.env` from GitHub secrets, copies `compose.yaml`, `Caddyfile`, and `scripts/` to the server, then runs the remote `remote-deploy.sh` script.
4. **Health check** — curls the public URL against `/healthz`, `/healthz/readiness`, and `/webhook/`. On any failure, it triggers an automatic rollback to the previous image tag and re‑checks.
5. **Report** — outputs success/failure in the GitHub Actions UI.

### Workflow concurrency

The workflow uses GitHub **concurrency** to prevent overlapping production deployments:

```
concurrency:
  group: n8n-deploy-${{ github.ref }}-${{ github.event.inputs.environment || 'development' }}
  cancel-in-progress: false
```

Only one deployment per branch and environment can run at a time; if a new run starts, the previous one is cancelled.

### Manual approval for production

To require manual approval before a production deployment:

1. In GitHub, go to **Settings → Environments → production**.
2. Add **required reviewers** (team or individuals).
3. The `deploy-production` job will block at the `environment` keyword until an approved reviewer clicks **Run** in the UI.

If you do not set required reviewers, the job runs immediately on `workflow_dispatch` with `environment: production`.

### Running the workflow locally (for testing)

You can test the validation steps without deploying:

```bash
# From the repo root
docker compose config --quiet
bash scripts/validate-env.sh .env
bash scripts/check-secrets.sh
```

### Rolling back manually

If you need to roll back without using the automatic recovery:

```bash
# On the production server
cd /opt/n8n
# Record the previous tag (if any)
cat .deployed-version
# Roll back to a specific tag
N8N_IMAGE_TAG=<previous-tag> docker compose up -d --remove-orphans
```

## 6. Health‑Check Verification

The deployment pipeline verifies the following endpoints after every deploy. All checks use the `N8N_PUBLIC_URL` environment variable (set from the `N8N_PUBLIC_URL` GitHub secret).

| Endpoint | Expected | Meaning |
|---|---|---|
| `GET /healthz` | `200` | n8n process is alive and reachable |
| `GET /healthz/readiness` | `200` | Database is connected and migrations are complete; instance is ready to accept traffic |
| `GET /webhook/` | `< 500` | Webhook endpoint is reachable (a 404 is acceptable; it means the path is served) |

### External monitoring (recommended)

For true uptime monitoring, configure an external service (UptimeRobot, Better Stack, etc.) to poll `/healthz/readiness` every minute from outside your server. An internal probe cannot detect a full server outage.

### n8n-specific details

- The `/healthz` endpoint does **not** indicate database status; it only confirms the process is reachable.
- The `/healthz/readiness` endpoint **does** confirm the database is connected and migrated. This is the endpoint your load balancer or orchestrator should gate on.
- In queue‑mode worker setups, the health endpoint on workers is disabled by default; set `QUEUE_HEALTH_CHECK_ACTIVE=true` on each worker if you need to probe them individually.

## 7. Troubleshooting

### Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| n8n starts but `/healthz` returns 502 or refuses connection | Caddy not yet ready; n8n not reachable from host | Wait a few seconds; ensure Caddy is running (`docker compose ps`) |
| `/healthz/readiness` never becomes 200 | Database not reachable; wrong Neon host/password/SSL config | Verify `DB_POSTGRESDB_*` variables in `.env`; test with the `psql` command in §2 |
| Caddy fails to get a TLS certificate | `N8N_DOMAIN` not set or DNS not pointing to server | Set `N8N_DOMAIN` in `.env`; ensure A record resolves to server IP; open port 80 |
| n8n logs “Could not connect to database” | Neon SSL mismatch or pooler vs direct conflict | Set `DB_POSTGRESDB_SSL_ENABLED=true`, `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=true`; try switching between pooled and direct host |
| Deployment fails with “SSH connection refused” | Firewall blocks port 22; wrong SSH host/key | Check cloud firewall (AWS Security Group, Hetzner firewall, Oracle OCS); verify `SSH_HOST`, `SSH_USERNAME`, `SSH_PRIVATE_KEY` |
| Encryption key mismatch after deploy | New key generated; existing credentials become inaccessible | Always use the **same** `N8N_ENCRYPTION_KEY` across deployments. Generate only when starting fresh. |
| Docker compose config error: “undefined network/volume” | Missing top‑level `networks`/`volumes` section in `compose.yaml` | Ensure `compose.yaml` defines `networks: n8n: driver: bridge` and `volumes: n8n_data:` (see current file) |

### Debugging deployment

To see what the CI job does without actually deploying, run the validation steps locally:

```bash
cd n8n-free-hosting
docker compose config --quiet
bash scripts/validate-env.sh .env
bash scripts/check-secrets.sh
```

To test the SSH handshake only (no deployment):

```bash
ssh -T -i $SSH_PRIVATE_KEY SSH_USERNAME@SSH_HOST
```

### Logs

- **Container logs**: `docker compose logs -f n8n`
- **Caddy logs**: `docker compose logs -f caddy` (when `tls` profile is enabled)
- **GitHub Actions logs**: available in the Actions tab; secrets are automatically masked.

## 8. Rollback Procedure

### Automatic rollback (via CI)

If a health check fails after a deployment, the GitHub Actions workflow (`deploy-from-ci.sh`) automatically attempts:

1. Roll back to the previously deployed image tag (recorded in `.deployed-version`).
2. Re‑run health checks.
3. If the rollback also fails, the workflow fails and logs the error.

### Manual rollback

To roll back to a specific prior version:

1. **On the production server**, navigate to the deploy directory:

   ```bash
   cd /opt/n8n
   ```

2. **Check the current tag**:

   ```bash
   cat .deployed-version
   ```

3. **Roll back** to a known good tag (e.g., `2.48.5`):

   ```bash
   N8N_IMAGE_TAG=2.48.5 docker compose up -d --remove-orphans
   ```

4. **Verify** the health checks pass:

   ```bash
   curl -s https://n8n.example.com/healthz/readiness
   ```

5. **Update the recorded tag** (optional — the script updates `.deployed-version` automatically on every `docker compose up`).

### What rollback does NOT do

- **Does not** restore Docker volumes or Neon schemas from backup. It only swaps the n8n Docker image tag.
- **Does not** reverse database migrations. n8n migrations are idempotent; running them again with a prior image version will re‑apply migrations appropriate to that version.
- **Does not** restore deleted workflows or executions. Those are stored in the Neon database (`n8n` schema) and survive image rolls as long as the database is intact.

## 9. Dependency and Container Image Checks

The CI pipeline includes the following checks:

1. **Image pinning** — `compose.yaml` uses `${N8N_IMAGE_TAG:-2.48.6}`; the `validate` job explicitly checks that `:latest` is not present in `compose.yaml`.
2. **Digest verification** — `docker buildx imagetools inspect` confirms the image digest matches the expected version.
3. **Weekly Dependabot** — `.github/dependabot.yml` opens pull requests for n8n image version updates on a weekly cycle.
4. **Vulnerability scan** — the `validate` job can be extended to run Trivy or another scanner; the infrastructure is in place (SARIF upload step commented out to avoid auth issues, but the command is present).

To add a Trivy scan, uncomment the corresponding step in `.github/workflows/deploy.yml` and ensure the GitHub runner has network access to the registry.

## 10. Summary of Commands

### Local development

```bash
# 1. Clone & configure
git clone https://github.com/your-username/n8n-free-hosting.git
cd n8n-free-hosting
cp .env.example .env   # fill values, never commit

# 2. Start n8n (default, no TLS)
docker compose up -d

# 3. Or with Caddy TLS
docker compose --profile tls up -d   # requires N8N_DOMAIN in .env

# 4. Stop
docker compose down

# 5. Health checks
curl -s http://127.0.0.1:5678/healthz
curl -s http://127.0.0.1:5678/healthz/readiness
```

### Neon database verification

```bash
set -a; . ./.env; set +a
docker run --rm -e PGPASSWORD="$DB_POSTGRESDB_PASSWORD" \
  -e PGSSLMODE="${DB_POSTGRESDB_SSL_ENABLED:+require}" \
  postgres:17-alpine \
  psql -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
       -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
       -c "select 'connected', version();"
```

### GitHub Actions (manual dispatch)

```bash
# From the repo UI: Actions → Deploy n8n → Trigger workflow
# Choose: environment (development/production), image tag (optional)
```

### Rolling back

```bash
# On the server
cd /opt/n8n
N8N_IMAGE_TAG=2.48.5 docker compose up -d --remove-orphans
```

### Backup / restore (Neon)

```bash
# Backup
pg_dump -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
  -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
  -n "$DB_POSTGRESDB_SCHEMA" -Fc -f n8n-backup.tar

# Restore
pg_restore -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" \
  -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" \
  -n "$DB_POSTGRESDB_SCHEMA" n8n-backup.tar
```