#!/usr/bin/env bash
set -euo pipefail
RARA_DIR="${RARA_DIR:-/opt/rara-agent}"
cd "$RARA_DIR"
: "${KROUTER_INTERNAL_TOKEN:?KROUTER_INTERNAL_TOKEN must be set}"
: "${KROUTER_ADMIN_USERNAME:-admin}"
: "${KROUTER_ADMIN_PASSWORD:?KROUTER_ADMIN_PASSWORD must be set}"
export NODE_ENV=production HOST=127.0.0.1 PORT="${ZROUTER_PORT:-3001}"
export KROUTER_DATA_DIR="${KROUTER_DATA_DIR:-/data/apps/rara-agent/mini-services/zrouter/data}"
exec bun run mini-services/zrouter/src/index.ts
