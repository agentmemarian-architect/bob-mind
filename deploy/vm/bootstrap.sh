#!/usr/bin/env bash
# ============================================================
#  bob-mind — one-shot bootstrap for a fresh Ubuntu VM
#  Built for Oracle Cloud Always Free (Ubuntu 22.04/24.04, arm64)
#  but works on any Debian/Ubuntu Docker host.
#
#  On the VM:
#      git clone https://github.com/agentmemarian-architect/bob-mind.git
#      cd bob-mind/deploy/vm
#      cp .env.example .env
#      nano .env            # set TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS
#      chmod +x bootstrap.sh
#      ./bootstrap.sh
#
#  Safe to re-run: it rebuilds and restarts with whatever is in .env.
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------- architecture
case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac
say "architecture: ${ARCH}"

# ---------------------------------------------------------- sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    die "need root or sudo to install packages"
fi

# ---------------------------------------------------------- docker
if ! command -v docker >/dev/null 2>&1; then
    say "Docker not found — installing from get.docker.com"
    curl -fsSL https://get.docker.com | $SUDO sh
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
    $SUDO usermod -aG docker "${USER:-ubuntu}" >/dev/null 2>&1 || true
    say "Docker installed. (You may need to log out/in for group changes.)"
else
    say "Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
    say "Installing the Docker Compose plugin"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq docker-compose-plugin \
        || die "could not install docker-compose-plugin"
fi

# The docker group may not be active in this shell yet.
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
    if $SUDO docker info >/dev/null 2>&1; then
        DOCKER="$SUDO docker"
    else
        die "cannot talk to the Docker daemon"
    fi
fi

# ---------------------------------------------------------- configuration
[ -f .env ] || die ".env is missing. Run:  cp .env.example .env   then edit it."

set -a
# shellcheck disable=SC1091
. ./.env
set +a

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    die "TELEGRAM_BOT_TOKEN is empty in .env — the bot cannot work without it."
fi

if [ -z "${TELEGRAM_ALLOWED_USERS:-}" ]; then
    say "WARNING: TELEGRAM_ALLOWED_USERS is empty."
    say "Hermes denies ALL users by default, so the bot will ignore you."
    say "Set it to your numeric id from @userinfobot (e.g. 123456789)."
elif printf '%s' "$TELEGRAM_ALLOWED_USERS" | grep -q '[^0-9,]'; then
    say "WARNING: TELEGRAM_ALLOWED_USERS should be digits and commas only."
    say "It is currently: $TELEGRAM_ALLOWED_USERS"
fi

PORT="${PUBLIC_PORT:-7860}"

# ---------------------------------------------------------- build & run
say "Building the image (first build pulls a large base — 10-25 min)"
$DOCKER compose build

say "Starting the stack"
$DOCKER compose up -d

say "Waiting for /healthz on port ${PORT} ..."
UP=0
for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/healthz" 2>/dev/null; then
        UP=1
        break
    fi
    printf '.'
    sleep 5
done
echo

if [ "$UP" = "1" ]; then
    say "Stack is UP and answering on port ${PORT}."
else
    say "Not answering yet. It may still be starting — check the logs below."
fi

say "Container status"
$DOCKER compose ps

cat <<EOF

================================================================
 Next steps
================================================================
 1. Open Telegram and send /start to your bot.
    If it stays silent:
        $DOCKER compose logs -f bob
    and look for lines starting with [telegram].

 2. Inspect the generated agent config:
        $DOCKER exec bob-mind cat /opt/data/config.yaml

 3. Service logs live inside the container:
        $DOCKER exec bob-mind ls /opt/data/logs
        $DOCKER exec bob-mind tail -n 50 /opt/data/logs/supervisor.log

 4. Dashboards (only reachable if you opened port ${PORT}):
        http://<server-ip>:${PORT}/          router dashboard
        http://<server-ip>:${PORT}/hermes/   agent dashboard

 To change any setting later: edit .env, then re-run ./bootstrap.sh
================================================================
EOF
