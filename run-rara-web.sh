#!/usr/bin/env bash
set -euo pipefail
cd /opt/rara-agent
: "${KFAI_AUTH_SECRET:?must be set}"
: "${KROUTER_INTERNAL_TOKEN:?must be set}"
: "${KROUTER_ADMIN_PASSWORD:?must be set}"
export NODE_ENV=production HOST=0.0.0.0 HOSTNAME=0.0.0.0
export PORT="${RARA_PORT:-3002}"
export DATABASE_URL="${DATABASE_URL:-file:/data/apps/rara-agent/db/rara.db}"
export KROUTER_BASE="${KROUTER_BASE:-http://127.0.0.1:3001}"
export MCP_ENDPOINT="${MCP_ENDPOINT:-http://127.0.0.1:3001/mcp}"
export RARA_BASE_URL="${RARA_BASE_URL:-http://127.0.0.1:3002}"
export PATH="/root/.bun/bin:/data/root/.bun/bin:$PATH"
/root/.bun/bin/bun run db:push --accept-data-loss 2>/dev/null || true
exec node .next/standalone/server.js
