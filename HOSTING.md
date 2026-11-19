# Hosting Provider Comparison and Recommendation

## Evaluated Providers (2026)

| Provider | Free Model | Persistent VM? | Docker Compose | Persistent Disk | SSL / HTTPS | Notes |
|---|---|---|---|---|---|---|
| **Oracle Cloud Always Free** | $0, permanent | Yes (Arm A1: 2 OCPU / 12 GB) | Yes (run your own) | Yes (200 GB) | Via Let's Encrypt (Caddy/Traefik) | Strongest free always‑on VM. Capacity varies by region; may need to wait for Ampere shape availability. |
| **Hetzner Cloud** | from €5.49/mo | Yes (CX11/CAX11) | Yes (built‑in) | Yes (block storage) | Via Let's Encrypt (Caddy/Traefik) | Cheap paid option. Very reliable, wide availability. |
| **Render** | $0 (free tier) | No (services sleep after 15 min idle) | Yes (per service) | Ephemeral (no persistent disk) | None by default | Free tier spins down; data does not survive restart. Demo only. |
| **Fly.io** | No free tier for new orgs | No (trial only: 2h/7d) | Yes (via fly.toml) | Yes (disks available) | Via Flycerts or external TLS | No free tier; trial expires. Good DX but not free. |
| **Render (free web service)** | $0 | No (sleep after idle) | Yes | Ephemeral | None | Not suitable for persistent n8n. |
| **Google Cloud free tier** | $0 (e2‑micro: 1 GB RAM) | Yes | No (single containers, no Compose) | 30 GB disk | Via Let's Encrypt (certs manual) | Tiny VM; works but limited RAM for n8n with many workflows. |
| **n8n Cloud trial** | 14 days, then expires | No | No | No | n8n‑managed | Evaluation only; workspace deleted after trial. |
| **Vercel** | $0 (hobby) | No (serverless) | No (functions only) | N/A | Built‑in HTTPS | Not suitable for n8n core server; see detailed explanation below. |

## Vercel — Why n8n Does Not Run There

n8n requires:

1. **A persistent runtime** — a long‑lived process that stays up between executions.
2. **Durable storage** — credentials, workflows, and execution state must survive restarts.
3. **Background execution** — scheduled triggers and webhooks must be reliably handled.
4. **Reliable database connectivity** — persistent TCP connections to PostgreSQL.

Vercel Functions are ephemeral: they start on demand, run for a maximum of 60 seconds, and then terminate. State is lost between invocations. There is no always‑on container, no persistent filesystem, and no guarantee of in‑order webhook delivery. While n8n can be configured to use Vercel for *compatible* components (e.g., a serverless front‑end or API proxy), the n8n engine itself must run on a persistent host.

Therefore, **Vercel is not used for the n8n server** in this architecture. It could theoretically host a static dashboard or a lightweight proxy, but the core automation engine requires the setup described in this repository.

## Recommended Architecture

### Oracle Cloud Always Free + SSH + Docker Compose

- **Cost**: $0/month (subject to capacity eligibility; Arm Ampere shape may need region selection).
- **Spec**: 2 OCPU / 12 GB RAM, 200 GB storage, 10 TB bandwidth.
- **Software**: Ubuntu 22.04, Docker Engine + Docker Compose, Caddy for automatic HTTPS.
- **Network**: Inbound ports 80/443 open; SSH (port 22) restricted to your IP if desired.
- **Deployment**: GitHub Actions SSH job (as described in `.github/workflows/deploy.yml`) pushes the latest n8n image and restarts the container.
- **Backup**: Manual `pg_dump`/`pg_restore` of the Neon database; the `n8n_data` Docker volume is backed up separately if custom nodes or binary data are used.

### Alternative: Hetzner Cloud (paid)

- **Cost**: from €5.49/mo (excluding VAT).
- **Spec**: CX11 (1 vCPU, 2 GB) is minimal; CAX11 (2 vCPU, 4 GB) or CAX21 (4 vCPU, 8 GB) recommended for n8n with assistants.
- **Software**: Same as Oracle.
- **Advantages**: Wider availability, easier UI, excellent support.
- **Trade‑off**: Monthly cost; still very affordable for a production‑grade automation platform.

### Quick setup checklist (Oracle Cloud)

1. Sign up at oracle.com/cloud/free.
2. Create Arm A1 VM (Ubuntu 22.04, 2 OCPU, 12 GB, public IP).
3. `sudo apt update && sudo apt install -y docker.io docker-compose`
4. `newgrp docker` to add yourself to the docker group.
5. `git clone https://github.com/your-username/n8n-free-hosting.git`
6. `cp .env.example .env`; edit with your Neon credentials, domain, encryption key.
7. `docker compose up -d` (or `docker compose --profile tls up -d` for HTTPS).
8. Add DNS A record: `n8n.example.com → <server‑public‑IP>`.
9. First Caddy startup will provision a Let's Encrypt certificate (ensure port 80 is open).
10. Access the editor at `https://n8n.example.com/`.

### Capacity notes

- Oracle's Always Free Ampere allocation may be exhausted in popular regions (us‑east‑1, eu‑west‑1). If you see “out of host capacity” errors, try a different region (e.g., us‑south‑1, eu‑central‑1) or fall back to Hetzner.
- The ARM shape is essential; x86 micro shapes burn through a limited free‑hour pool and start billing after 30 days.
- Idle instances (CPU < 20% over 7 days) may be reclaimed by Oracle; keep a lightweight workflow running or set a scheduled no‑op webhook to stay above the threshold.

## Conclusion

For a **free, always‑on** n8n host, **Oracle Cloud Always Free** is the only viable option. For users who prefer a managed VPS with guaranteed capacity and paid‑support, **Hetzner Cloud** is the recommended alternative at a minimal monthly cost. Vercel is unsuitable for the n8n core server but can be used for compatible front‑end components if desired.

## Next Steps

1. Choose your hosting provider and provision the VM.
2. Follow the "Quick setup checklist" for your chosen host.
3. Configure GitHub Secrets as described in §3.
4. Push to `main` to trigger the first development deployment.
5. Promote to production via the `workflow_dispatch` manual flow (with required reviewers).