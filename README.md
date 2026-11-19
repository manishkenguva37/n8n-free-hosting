# n8n-free-hosting

Production-ready, automated deployment of n8n with Neon PostgreSQL and GitHub Actions.

## Architecture

- **n8n**: runs in a persistent Docker container (pinned image version).
- **Neon PostgreSQL**: persistent cloud database with SSL.
- **GitHub**: source control and CI/CD.
- **GitHub Actions**: validation, deployment automation, health checks.
- **Hosting**: Linux VPS via SSH + Docker Compose (Oracle Cloud Always Free recommended, Hetzner as paid alternative).
- **Vercel**: not used for n8n itself (Vercel Functions are not a suitable replacement for a persistent n8n server).

## Quick Start

1. Install Docker and Docker Compose on your local machine or a VPS.
2. Copy `.env.example` to `.env` and fill in actual values (never commit `.env`).
3. Run `docker compose up -d` to start n8n with the Caddy reverse proxy (HTTP on 80, HTTPS on 443 if `N8N_DOMAIN` is set).
4. Access the editor at `https://n8n.your-domain.com/`.
5. Complete the owner account setup on first load.

## Repository Structure

```
compose.yaml    # Production Docker Compose (pinned n8n image, health checks, volumes, optional Caddy TLS profile)
Caddyfile       # Reverse proxy configuration with automatic HTTPS via Let's Encrypt
.env.example    # All required environment variables with placeholders (git-ignored)
scripts/        # Validation, deployment, health check, and rollback scripts
.github/workflows/deploy.yml  # CI/CD pipeline
.github/dependabot.yml  # Docker image version checks
README.md       # This file
DEPLOYMENT.md   # Detailed deployment, secrets, backup, and rollback guide
HOSTING.md      # Provider comparison and recommendations
```

## Docker Compose

See `compose.yaml` for the production configuration. Key features:

- Pinned n8n image: `docker.n8n.io/n8nio/n8n:2.48.6`
- Persistent volume `n8n_data` for runtime data
- Health checks via `/healthz/readiness`
- Optional Caddy TLS profile (`docker compose --profile tls up -d`) for automatic HTTPS
- Restart policy `unless-stopped`
- n8n bound to `127.0.0.1:5678` (Caddy exposes 80/443)

## GitHub Actions Deployment

See `.github/workflows/deploy.yml`. The workflow:

- Triggers on `push` to `main` (deploys to development) and `workflow_dispatch` (manual deployment to development or production).
- Validates Docker Compose configuration and required environment variables.
- Runs secret scanning.
- Deploys via SSH to the target server.
- Runs health checks (`/healthz`, `/healthz/readiness`, webhook reachability).
- On health check failure, attempts automatic rollback to the previous image tag.
- Uses GitHub secrets for all sensitive information.

## Vercel

Vercel Functions are not a suitable replacement for a persistent n8n server. n8n requires a persistent runtime, durable storage, background execution, and reliable database connectivity — features incompatible with Vercel's serverless model. Use the architecture described above for production n8n hosting.

## License

This project is not affiliated with n8n.io. n8n is copyright n8n.io.