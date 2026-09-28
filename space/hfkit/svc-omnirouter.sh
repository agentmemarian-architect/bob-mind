#!/usr/bin/env bash
# OmniRouter (Godde3s) — keyless web models. NOT exposed publicly;
# used by Hermes as the "omnirouter" provider and can be chained
# inside 9Router as a custom provider (http://127.0.0.1:8080/v1).
set -e

D=/opt/data/omnirouter
mkdir -p "$D"
cd "$D"

# ---- architecture -------------------------------------------
# Caddy/OmniRouter ship arch-specific binaries and Oracle Cloud
# Always Free (Ampere A1) is arm64, so never hardcode amd64 here.
case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) echo "[omnirouter] unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# ---- stable router key --------------------------------------
# config.yaml authenticates with key_env OMNI_ROUTER_KEY, so the router
# and the agent must agree on the same value. If the operator did not set
# one, generate it once and persist it in /opt/data — it then survives
# restarts and rides along in the hourly backup. (cont-init 02 normally
# creates this file first; the fallback below covers direct invocations.)
KEY_FILE=/opt/data/.omni_key
if [ -z "${OMNI_ROUTER_KEY:-}" ]; then
    if [ ! -s "$KEY_FILE" ]; then
        mkdir -p "$(dirname "$KEY_FILE")"
        printf 'sk-omni-%s' "$(tr -dc 'a-f0-9' < /dev/urandom | head -c 32)" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
    fi
    OMNI_ROUTER_KEY="$(cat "$KEY_FILE")"
fi

# write .env exactly like upstream start.sh does
{
    echo "PORT=8080"
    echo "ADMIN_PASSWORD=${OMNI_ADMIN_PASSWORD:-admin}"
    echo "AGENT_MODE=1"
    echo "ROUTER_KEY=${OMNI_ROUTER_KEY}"
    if [ -n "${OMNI_AUTO_CHAIN:-}" ]; then
        echo "AUTO_CHAIN=${OMNI_AUTO_CHAIN}"
    fi
} > .env

export QWEN_BX_FILE=qwen-bx.json

# Qwen guest mode needs Baxia headers on datacenter IPs (cloud VMs are
# datacenter IPs too). Do it once per data dir; retry next boot if it failed.
if [ ! -f qwen-bx.json ]; then
    timeout 90 "/opt/omnirouter/qwen-bx-linux-${ARCH}" >/dev/null 2>&1 || true
fi

exec "/opt/omnirouter/omnirouter-linux-${ARCH}"
