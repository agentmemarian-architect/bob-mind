# Run bob-mind on a free VM (Oracle Cloud Always Free)

This is the replacement path for the Hugging Face Space deploy, which no longer
works on a free account.

## Why this exists

As of roughly **8 July 2026**, Hugging Face requires a **PRO subscription ($9/month)**
to create **Docker or Gradio Spaces**. Free accounts can only create *Static* Spaces,
which cannot run a bot. The old deploy workflow therefore fails with:

```
402 Payment Required
Static Spaces are free for everyone, but hosting Gradio and Docker Spaces
on free cpu-basic requires a PRO subscription.
```

The `space/` folder itself is fine — it is a normal Docker image. It just needs a
Docker host. This guide gives you one, for free.

**Oracle Cloud Always Free** includes an ARM VM with up to **4 CPU cores and 24 GB RAM**,
permanently free, no time limit. That is far more than this stack needs.

---

## What you'll end up with

| Thing | Where |
|---|---|
| Telegram bot | works out of the box once your token is set |
| Router dashboard | `http://<server-ip>:7860/` |
| Agent dashboard | `http://<server-ip>:7860/hermes/` |
| Agent API | `http://<server-ip>:7860/hermes-api/v1` |
| State | a Docker volume, so it survives restarts |

> **The Telegram bot is outbound-only.** It long-polls Telegram, so it works even if
> you never open a single firewall port. The ports are only for the dashboards and
> the HTTP API. If the firewall step is giving you trouble, skip it — your bot will
> still answer.

---

## Step 1 — Create the Oracle Cloud account

1. Go to <https://cloud.oracle.com> and click **Start for free**.
2. Pick **Always Free**. Choose a home region close to you.
3. Oracle asks for a card to verify identity. Always Free resources are **not charged**.
4. Wait for the account to be provisioned (a few minutes).

## Step 2 — Create the VM

In the console: **Compute → Instances → Create instance**.

| Field | Value |
|---|---|
| Name | `bob-mind` |
| Image | **Canonical Ubuntu 24.04** (or 22.04) |
| Shape | **VM.Standard.A1.Flex** — set **4 OCPU / 24 GB** |
| Boot volume | default is fine (50 GB) |
| SSH keys | **Upload** your public key, or let Oracle generate one and **download the private key** |
| Public IPv4 address | **Assign** (tick it) |

> **"Out of host capacity" is common for A1.** It means the free ARM pool is full in
> that Availability Domain. Try a different **Availability Domain** in the same region,
> or just retry in a few hours. This is an Oracle limitation, not a problem with your setup.

> If you cannot get an A1 instance at all, a paid **VM.Standard.E2.1.Micro** or any
> small VPS works identically — the setup below is not Oracle-specific.

## Step 3 — Connect to it

```bash
ssh ubuntu@<your-server-ip>
```

(If you uploaded an SSH key, use `ssh -i /path/to/private.key ubuntu@<ip>`.)

## Step 4 — Open port 7860 (optional, dashboards only)

Skip this entirely if you only care about the Telegram bot.

**a) Oracle's cloud firewall** — Networking → Virtual Cloud Networks → your VCN →
**Security Lists** → *Default Security List* → **Add Ingress Rule**:

- Source CIDR: `0.0.0.0/0`
- IP Protocol: **TCP**
- Destination Port Range: `7860`

**b) The VM's own firewall** — Oracle's Ubuntu images ship with iptables rules that
block everything except SSH:

```bash
sudo iptables -I INPUT -p tcp --dport 7860 -j ACCEPT
sudo netfilter-persistent save
```

If `netfilter-persistent` is missing:

```bash
sudo apt-get update && sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

## Step 5 — Install bob-mind

```bash
git clone https://github.com/agentmemarian-architect/bob-mind.git
cd bob-mind/deploy/vm
cp .env.example .env
nano .env
```

In `.env`, set **two** things and nothing else is required:

```ini
TELEGRAM_BOT_TOKEN=123456789:AAH...        # from @BotFather
TELEGRAM_ALLOWED_USERS=123456789           # YOUR numeric id, from @userinfobot
```

> `TELEGRAM_ALLOWED_USERS` must be a **number**, not your `@username`.
> Message **@userinfobot** on Telegram to get it.
> Leave it blank and Hermes denies everyone — your bot will ignore you silently.

Then:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The first build takes **10–25 minutes** (it downloads the Hermes base image, 9Router,
OmniRouter and Caddy). Later rebuilds are fast.

## Step 6 — Test it

Send `/start` to your bot in Telegram.

If nothing happens:

```bash
docker compose logs -f bob
```

Look for lines starting with `[telegram]`. To see the agent's actual config:

```bash
docker exec bob-mind cat /opt/data/config.yaml
```

You should see `provider: omnirouter` and `default: "auto"`. If you see
`SET-HERMES-MODEL-VARIABLE`, you are on an old copy of the repo — pull the latest.

---

## The model: why it works with no API key

By default this stack uses the built-in **OmniRouter**, which serves free web models
with **no key at all**, and the model name **`auto`**, which picks the healthiest
available provider and fails over automatically. That is why you don't need to sign up
for anything or paste an API key.

Want a specific model? Edit `.env` and re-run `./bootstrap.sh`:

```ini
HERMES_MODEL=gemini/gemini-3.6-flash
```

Available examples: `auto`, `qwen/qwen3.8-max`, `gemini/gemini-3.6-flash`,
`glm/glm-5.3`, `oc/big-pickle`.

---

## Updating

```bash
cd bob-mind
git pull
cd deploy/vm
./bootstrap.sh          # rebuilds and restarts
```

Your data lives in the `bob-data` Docker volume, so it is **not** lost on rebuild.

## Useful commands

```bash
cd bob-mind/deploy/vm

docker compose logs -f bob          # live logs
docker compose ps                   # status + health
docker compose restart              # restart
docker compose down                 # stop
docker compose up -d                # start again

docker exec bob-mind ls /opt/data/logs
docker exec bob-mind tail -n 50 /opt/data/logs/supervisor.log
docker exec bob-mind tail -n 50 /opt/data/logs/omnirouter.log
```

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Bot silent | `TELEGRAM_ALLOWED_USERS` empty or not your numeric id. Check `docker exec bob-mind grep TELEGRAM /opt/data/.env` |
| Bot silent, token looks fine | Another process is polling the same token. Create a fresh bot with @BotFather, or make sure no webhook is set. |
| Bot silent after working | The container restarted before `/opt/data` was populated. Check `docker compose logs bob`. |
| Build fails downloading Caddy/OmniRouter | Transient network error. Just re-run `./bootstrap.sh`. |
| `no space left on device` | `docker system prune -af` |
| Dashboards unreachable | Port 7860 not open — see Step 4. The bot does not need this. |
| `Out of host capacity` on Oracle | Try another Availability Domain, or retry later. |
| Container killed | Hit `MEMORY_LIMIT`. Raise it in `.env` (needs 4 GB+ realistically). |
| Everything was fine, then died | Oracle may reclaim Always Free instances that look idle over a 7-day window. A running bot is normally active enough, but this is the main risk of the free tier. |

## A note on the old Hugging Face workflows

`.github/workflows/deploy-to-hf.yml` and `keepalive.yml` are still in the repo. They are
harmless now (the deploy will fail with the 402 above), but if you are not going to
subscribe to HF PRO you can delete both files to keep your Actions tab quiet.

## Security

- `.env` holds your bot token — it is in `.gitignore`. Never commit it.
- Keep the Space/VM private to you. `TELEGRAM_ALLOWED_USERS` is what locks the bot down.
- If a token ever leaks, revoke it with @BotFather (`/revoke`) and generate a new one.
