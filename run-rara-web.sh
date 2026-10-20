#!/usr/bin/env bash
set -euo pipefail
cd /opt/rara-agent

# Required secrets (must be set in container env or .env file)
: "${KFAI_AUTH_SECRET:?must be set}"
: "${KROUTER_ADMIN_PASSWORD:?must be set}"

# Optional — admin username + opencode API key
: "${KROUTER_ADMIN_USERNAME:=admin}"
: "${OPENCODE_API_KEY:=}"

# Network — Next.js standalone server on port 3002 (nginx upstream `rara_web`)
export NODE_ENV=production
export HOST=0.0.0.0
export HOSTNAME=0.0.0.0
export PORT="${RARA_PORT:-3002}"

# Prisma SQLite DB — persistent volume mounted at /data
export DATABASE_URL="${DATABASE_URL:-file:/data/apps/rara-agent/db/rara.db}"

# Self-reference (used for vision-tool download URLs etc.)
export RARA_BASE_URL="${RARA_BASE_URL:-http://127.0.0.1:3002}"

# Legacy env vars kept as no-ops for backward-compat with old .env files —
# rara-agent v2 is self-contained (no external zrouter sidecar). These are
# not used to reach any external service.
export KROUTER_BASE=""
export KROUTER_INTERNAL_TOKEN=""
export MCP_ENDPOINT=""

# Bun runtime path (kali-linux image installs bun at /root/.bun)
export PATH="/root/.bun/bin:/data/root/.bun/bin:$PATH"

# Push prisma schema (creates the DB file if missing) — best-effort, non-fatal
/root/.bun/bin/bun run db:push --accept-data-loss 2>/dev/null || true

# Start the Next.js standalone server (no zrouter sidecar)
exec node .next/standalone/server.js
