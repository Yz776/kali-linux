# syntax=docker/dockerfile:1.6

# ═══════════════════════════════════════════════════════════════════════════════
# v6 — Puppeteer-at-scale: shared Chromium daemon + tab pool
#   • v5 base tetap: debian:bookworm-slim (lebih ringan dari Ubuntu)
#   • TAMBAH: 1 Chromium daemon persisten (1 proses ~200-400MB) untuk SEMUA app
#     - App pakai puppeteer.connect() ke ws://127.0.0.1:9222, BUKAN puppeteer.launch()
#     - Helper /usr/local/lib/chromium-pool.js: withPage(fn) bounded pool (default 64 tab)
#     - 'Miliaran proses' = jutaan panggilan withPage() di-antri di pool, RAM tetap kecil
#   • Chromium low-mem flags: --no-zygote, --disable-site-isolation, --js-flags heap cap,
#     --disk-cache-dir (cache di disk bukan RAM), --disable-gpu, dll
#   • zram swap (zstd, 50% RAM) untuk kompresi in-memory saat tab banyak
#   • Tuning network: ip_local_port_range, tcp_max_tw_buckets untuk koneksi masif
#   • Bump fs.file-max 4M, ulimit -n 4M (jutaan FD untuk jutaan tab)
#   • oom-watchdog: protect chromium main, prefer kill renderer (auto-respawn)
#   • Redistribusi memori 6-app -> 7-app: chromium-daemon 12%, app lain turun proporsional
# ═══════════════════════════════════════════════════════════════════════════════
FROM debian:bookworm-slim

# SHELL dengan pipefail agar pipeline gagal ketika ada step yang gagal
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Metadata image (OCI standard labels)
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="kfai-multi-app" \
      org.opencontainers.image.description="Lightweight multi-app container (Debian Bookworm-slim, no cloud storage)" \
      org.opencontainers.image.source="https://github.com/Yz776/kali-linux" \
      org.opencontainers.image.base.name="debian:bookworm-slim" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="6.0"

# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════════
# Catatan perubahan (v6 — Puppeteer-at-scale + Debian Bookworm-slim):
#   • v5 base tetap: debian:bookworm-slim (lebih ringan & stabil dari Ubuntu 24.04)
#   • v6 — TAMBAH shared Chromium daemon + chromium-pool.js untuk concurrency tinggi
#   • v6 — zram swap, network tuning, bump FD limit untuk jutaan koneksi
#   • v5 — HAPUS nexcloud (cloud storage), redistribusi memori
#   • v5 — HEALTHCHECK, SHELL pipefail, LABEL metadata, STOPSIGNAL, retry Ollama
#   • v4 — tambah Ollama service, pm2 start "ollama serve" --name animest
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    # Node
    NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=384 --max-semi-space-size=64 --expose-gc" \
    # NPM – matikan semua yang lambat
    NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_PROGRESS=false \
    NPM_CONFIG_LOGLEVEL=error \
    NPM_CONFIG_PREFER_OFFLINE=true \
    NPM_CONFIG_FETCH_RETRIES=3 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=5000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=30000 \
    # LangChain – default NONAKTIF (override ke true via docker run -e kalau perlu)
    LANGCHAIN_AUTO_UPGRADE=false \
    # Paths
    SSH_PORT=22 \
    DATA_DIR=/data \
    HOME=/root \
    PM2_HOME=/data/root/.pm2 \
    NPM_CONFIG_CACHE=/data/root/.npm \
    PATH="/data/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    # Git
    GIT_TERMINAL_PROMPT=0 \
    GIT_HTTP_LOW_SPEED_LIMIT=1000 \
    GIT_HTTP_LOW_SPEED_TIME=60 \
    # Launcher mode: "pm2" (default) | "adaptive" (pakai index.js adaptive launcher)
    LAUNCHER_MODE=adaptive \
    # Adaptive launcher tuning (bisa di-override via env saat docker run)
    INTERACTIVE_APP=kfai-nodejs \
    RESOURCE_MODE=adaptive \
    ADAPTIVE_INTERVAL_MS=3000 \
    FOCUS_HOLD_MS=12000 \
    HIGH_CPU_PERCENT=18 \
    NORMAL_NICE=5 \
    FOCUS_NICE=1 \
    STARVE_SAFE_NICE=6 \
    # Memory budget cap (persen RAM container yang dipakai untuk semua app)
    APP_MEM_BUDGET_PERCENT=75 \
    # Mem guard v2 — 3-level (warn → soft → hard) + rolling window
    MEM_GUARD_SOFT_RATIO=1.15 \
    MEM_GUARD_HARD_RATIO=1.45 \
    MEM_GUARD_MAX_STRIKES=3 \
    MEM_GUARD_WINDOW_MS=60000 \
    MEM_GUARD_INTERVAL_MS=8000 \
    # Crash-loop protection
    CRASH_LOOP_WINDOW_MS=300000 \
    CRASH_LOOP_MAX=8 \
    CRASH_LOOP_MIN_UPTIME_MS=10000 \
    CRASH_LOOP_BACKOFF_MS=60000 \
    # Memory pressure detector
    PRESSURE_CHECK_INTERVAL_MS=15000 \
    PRESSURE_AVAIL_THRESHOLD_MB=128 \
    # Ollama
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_MODELS=/data/ollama/models \
    OLLAMA_DIR=/data/ollama

# Repo config
ENV KFAI_REPO=https://github.com/Yz776/kfai-nodejs.git \
    KFAI_BRANCH=master \
    KFAI_MCP_REPO=https://github.com/Yz776/kfai-mcp.git \
    KFAI_MCP_BRANCH=master \
    TTT_REPO=https://github.com/Yz776/ttt.git \
    TTT_BRANCH= \
    CATUR_REPO=https://github.com/Yz776/catur.git \
    CATUR_BRANCH= \
    ANIMEST_REPO=https://github.com/Yz776/animest.git \
    ANIMEST_BRANCH= \
    KFAI_DIR=/data/apps/kfai-nodejs \
    KFAI_MCP_DIR=/data/apps/kfai-mcp \
    TTT_DIR=/data/apps/ttt \
    CATUR_DIR=/data/apps/catur \
    ANIMEST_DIR=/data/apps/animest \
    LAUNCHER_DIR=/data/launcher \
    # ── Puppeteer-at-scale (single shared Chromium daemon + tab pool) ──
    # Semua app Node yang pakai puppeteer.connect() ke daemon ini,
    # BUKAN puppeteer.launch() — 1 browser shared, jutaan tab hemat RAM.
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_SKIP_DOWNLOAD=true \
    CHROMIUM_REMOTE_DEBUGGING_HOST=127.0.0.1 \
    CHROMIUM_REMOTE_DEBUGGING_PORT=9222 \
    PUPPETEER_WS_ENDPOINT=ws://127.0.0.1:9222 \
    # Bound concurrency pool — antri 'miliaran proses' tanpa meledak RAM
    PUPPETEER_MAX_CONCURRENT_TABS=64 \
    PUPPETEER_TAB_IDLE_TTL_MS=60000 \
    PUPPETEER_TAB_HARD_TTL_MS=300000 \
    PUPPETEER_NAV_TIMEOUT_MS=30000 \
    # Disk-backed cache agar RAM tidak membengkak karena cache web
    CHROMIUM_DISK_CACHE_DIR=/data/chromium-cache \
    CHROMIUM_USER_DATA_DIR=/data/chromium-profile \
    # Cap V8 heap per renderer (MB) — tab tidak bisa boros RAM
    CHROMIUM_RENDERER_MAX_OLD_SPACE_MB=96 \
    # v6.1: args tambahan untuk puppeteer.launch() di app animest (gofile, nhentai, westmanga, downloader)
    #   App yang pakai puppeteer-extra-plugin-stealth WAJIB puppeteer.launch() — tidak bisa connect ke daemon.
    #   Flag ini di-merge ke args[] launch via env hint (app baca process.env.CHROMIUM_LAUNCH_ARGS_EXTRA).
    CHROMIUM_LAUNCH_ARGS_EXTRA="--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --disable-gpu --mute-audio --disable-blink-features=AutomationControlled --disable-features=IsolateOrigins,site-per-process --disable-site-isolation-trials --disable-extensions --disable-default-apps --disable-translate --disable-sync --disable-background-networking --disable-component-update --disable-popup-blocking --disable-metrics --disable-breakpad --disable-software-rasterizer --memory-pressure-off --disable-background-timer-throttling --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-ipc-flooding-protection --no-first-run --no-default-browser-check"

# v6.1: puppeteer config — paksa pakai chromium sistem, JANGAN download chromium sendiri
# File ini dibaca oleh puppeteer v13+ saat require('puppeteer').
RUN printf '\
const fs = require("fs");\n\
const chromePath = process.env.PUPPETEER_EXECUTABLE_PATH || "/usr/bin/chromium";\n\
module.exports = {\n\
  executablePath: fs.existsSync(chromePath) ? chromePath : undefined,\n\
  skipDownload: true,\n\
  cache: process.env.PUPPETEER_CACHE_DIR || "/data/puppeteer-cache",\n\
};\n' > /usr/local/lib/puppeteer.config.cjs

ENV PUPPETEER_CONFIG_FILE=/usr/local/lib/puppeteer.config.cjs \
    PUPPETEER_CACHE_DIR=/data/puppeteer-cache

# ═══════════════════════════════════════════════════════════════════════════════
# APT – tuning agar download & install secepat mungkin
# ═══════════════════════════════════════════════════════════════════════════════
RUN printf '\
APT::Install-Recommends "false";\n\
APT::Install-Suggests "false";\n\
APT::Acquire::Retries "3";\n\
APT::Acquire::http::Timeout "30";\n\
APT::Acquire::https::Timeout "30";\n\
Acquire::ForceIPv4 "true";\n\
' > /etc/apt/apt.conf.d/99fast-apt

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 1 – Base + semua tool dalam SATU apt-get update + install
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
      bash ca-certificates curl wget git gnupg lsb-release \
      openssh-server openssl sudo tini \
      nano vim htop procps net-tools iproute2 \
      iputils-ping dnsutils bind9-dnsutils unzip zstd \
      build-essential python3 python3-pip \
      earlyoom nscd \
      # v6.1: dbus + dbus-x11 — Chromium butuh system bus socket
      #   Fix: 'Failed to connect to socket /run/dbus/system_bus_socket'
      dbus dbus-x11 \
      # Chromium untuk Puppeteer shared-daemon (1 binary sistem, bukan per-app)
      chromium chromium-sandbox \
      fonts-noto-cjk fonts-noto-color-emoji \
    ; \
    # Security tools (beberapa mungkin tidak ada di Ubuntu, fallback gracefully)
    for pkg in \
      nmap whois dnsrecon \
      nikto whatweb wafw00f \
      gobuster ffuf dirb \
      sslscan ssh-audit \
      yara lynis \
      chkrootkit rkhunter \
    ; do \
      apt-get install -y --no-install-recommends "$pkg" \
        || echo "WARN: $pkg tidak tersedia di Ubuntu 24.04."; \
    done; \
    for pkg in \
      binwalk radare2 checksec patchelf \
      ltrace strace gdb upx-ucl theharvester \
    ; do \
      apt-get install -y --no-install-recommends "$pkg" \
        || echo "WARN: $pkg tidak tersedia di Ubuntu 24.04."; \
    done; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 1B – Browser/Chromium runtime deps (Playwright/Puppeteer prerequisites)
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends \
      libglib2.0-0 \
      libasound2 \
      libnss3 \
      libnspr4 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libcups2 \
      libdbus-1-3 \
      libdrm2 \
      libgbm1 \
      libx11-6 \
      libx11-xcb1 \
      libxcb1 \
      libxcomposite1 \
      libxdamage1 \
      libxext6 \
      libxfixes3 \
      libxkbcommon0 \
      libxrandr2 \
      libxrender1 \
      libxshmfence1 \
      libxss1 \
      libgtk-3-0 \
      libpango-1.0-0 \
      libpangocairo-1.0-0 \
      libcairo2 \
      fonts-liberation \
    ; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 2 – Cloudflared
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    mkdir -p --mode=0755 /usr/share/keyrings; \
    curl -fsSL --retry 3 https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
      | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null; \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' \
      > /etc/apt/sources.list.d/cloudflared.list; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends cloudflared; \
    cloudflared --version; \
    apt-get autoremove -y; apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 3 – Node.js 20 + PM2
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    curl -fsSL --retry 3 https://deb.nodesource.com/setup_20.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    npm install -g npm@latest pm2 --no-audit --no-fund --loglevel=error; \
    npm config set audit false --global; \
    npm config set fund false --global; \
    npm config set update-notifier false --global; \
    npm config set progress false --global; \
    npm config set prefer-offline true --global; \
    npm cache clean --force || true; \
    node -v; npm -v; pm2 -v; \
    apt-get autoremove -y; apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 3B – Ollama (LLM lokal — https://ollama.com)
# Models disimpan di /data/ollama/models (persistent via volume)
# ═══════════════════════════════════════════════════════════════════════════════
# v5: retry 3x download installer Ollama agar build tidak gagal karena network blip
RUN set -eux; \
    for i in 1 2 3; do \
      curl -fsSL --retry 3 --retry-delay 5 https://ollama.com/install.sh -o /tmp/ollama-install.sh && break; \
      echo "[ollama] retry download installer ($i/3)..."; sleep 5; \
    done; \
    if [ -f /tmp/ollama-install.sh ] && [ -s /tmp/ollama-install.sh ]; then \
      sh /tmp/ollama-install.sh; \
      rm -f /tmp/ollama-install.sh; \
    else \
      echo "WARN: ollama install gagal download — service akan skip di runtime"; \
    fi; \
    ollama --version || echo "WARN: ollama version check gagal"; \
    mkdir -p /data/ollama/models

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER 4 – Direktori + SSH host keys pre-generated
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    mkdir -p /run/sshd /etc/ssh/sshd_config.d \
             /data/root /data/ssh /data/apps /data/bin /data/launcher \
             /data/ollama/models \
             /data/chromium-cache /data/chromium-profile \
             /data/puppeteer-cache /run/dbus; \
    chmod 1777 /data/chromium-cache /data/chromium-profile /data/puppeteer-cache; \
    chmod 755 /run/dbus; \
    chmod 700 /data/root /data/ssh; \
    rm -rf /root; \
    ln -s /data/root /root; \
    mkdir -p /etc/ssh/pregenerated; \
    ssh-keygen -t rsa     -b 4096 -f /etc/ssh/pregenerated/ssh_host_rsa_key     -N "" -q; \
    ssh-keygen -t ecdsa           -f /etc/ssh/pregenerated/ssh_host_ecdsa_key   -N "" -q; \
    ssh-keygen -t ed25519         -f /etc/ssh/pregenerated/ssh_host_ed25519_key -N "" -q

# ═══════════════════════════════════════════════════════════════════════════════
# SSH CONFIG
# Catatan: MaxStartups diturunkan jadi 10:30:60 agar SSH flood tidak boros RAM.
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /etc/ssh/sshd_config <<'EOF'
Port 22
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding yes
GatewayPorts yes
ClientAliveInterval 30
ClientAliveCountMax 6
UseDNS no
UsePAM yes
PrintMotd no
PrintLastLog no
Compression yes
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
MaxAuthTries 4
MaxSessions 20
MaxStartups 10:30:60
LoginGraceTime 30
StrictModes yes
Subsystem sftp /usr/lib/openssh/sftp-server
HostKey /data/ssh/ssh_host_rsa_key
HostKey /data/ssh/ssh_host_ecdsa_key
HostKey /data/ssh/ssh_host_ed25519_key
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# NSCD CONFIG — turunkan threads agar hemat RAM di container kecil
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /etc/nscd.conf <<'EOF'
logfile                /dev/null
threads                2
max-threads            8
paranoia               no
enable-cache           hosts     yes
positive-time-to-live  hosts     600
negative-time-to-live  hosts     20
suggested-size         hosts     211
check-files            hosts     yes
persistent             hosts     yes
shared                 hosts     yes
max-db-size            hosts     8388608
enable-cache           passwd    no
enable-cache           group     no
enable-cache           netgroup  no
enable-cache           services  no
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# ADAPTIVE LAUNCHER v4 – index.js
# Perubahan utama dari v3.2:
#   • Ditambah app "ollama" (animest) ke daftar APPS
#   • Memory distribution di-redistribute untuk 7 app
#   • Ollama punya memory budget sendiri (OLLAMA_MEMORY_MB)
#   • PM2 start "ollama serve" --name animest
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /data/launcher/index.js <<'LAUNCHEREOF'
// /data/launcher/index.js  (v4 — Ubuntu 24.04 + Ollama/animest)
// Adaptive multi-app launcher – mengelola kfai-nodejs, kfai-mcp, ttt,
// catur, ollama (animest), cloudflared dengan dynamic memory allocation,
// CPU priority adaptif, graduated pressure response.
// TIDAK pernah restart app karena alasan memory — limitnya yang berubah.
//
// ENV override (semua opsional):
//   LAUNCHER_MODE=adaptive|pm2
//   INTERACTIVE_APP=kfai-nodejs
//   RESOURCE_MODE=adaptive|fair|custom
//   FOCUS_APP=kfai-nodejs
//   ADAPTIVE_INTERVAL_MS=3000
//   FOCUS_HOLD_MS=12000
//   HIGH_CPU_PERCENT=18
//   NORMAL_NICE=5  FOCUS_NICE=1  STARVE_SAFE_NICE=6
//   APP_MEM_BUDGET_PERCENT=75    -> cap total app memory
//   KFAI_MEMORY_MB / KFAI_MCP_MEMORY_MB / TTT_MEMORY_MB / CATUR_MEMORY_MB / OLLAMA_MEMORY_MB / CF_MEMORY_MB
//   MEM_GUARD_SOFT_RATIO=1.15  MEM_GUARD_HARD_RATIO=1.45
//   MEM_GUARD_MAX_STRIKES=3    MEM_GUARD_WINDOW_MS=60000  MEM_GUARD_INTERVAL_MS=8000
//   CRASH_LOOP_WINDOW_MS=300000  CRASH_LOOP_MAX=8
//   CRASH_LOOP_MIN_UPTIME_MS=10000  CRASH_LOOP_BACKOFF_MS=60000
//   PRESSURE_CHECK_INTERVAL_MS=15000  PRESSURE_AVAIL_THRESHOLD_MB=128

'use strict';
const { spawn, spawnSync } = require('child_process');
const fs   = require('fs');
const os   = require('os');
const path = require('path');

// ── Konstanta & ENV ──────────────────────────────────────────────────────────
const KFAI_DIR     = process.env.KFAI_DIR     || '/data/apps/kfai-nodejs';
const KFAI_MCP_DIR = process.env.KFAI_MCP_DIR || '/data/apps/kfai-mcp';
const TTT_DIR      = process.env.TTT_DIR      || '/data/apps/ttt';
const CATUR_DIR    = process.env.CATUR_DIR    || '/data/apps/catur';
const ANIMEST_DIR  = process.env.ANIMEST_DIR  || '/data/apps/animest';
const OLLAMA_DIR   = process.env.OLLAMA_DIR   || '/data/ollama';
// Chromium daemon dir (shared browser untuk semua app Puppeteer)
const CHROMIUM_PROFILE_DIR = process.env.CHROMIUM_USER_DATA_DIR || '/data/chromium-profile';

const INTERACTIVE_APP   = (process.env.INTERACTIVE_APP || 'kfai-nodejs').trim();
const RESOURCE_MODE     = (process.env.RESOURCE_MODE   || 'adaptive').trim().toLowerCase();
const MANUAL_FOCUS      = (process.env.FOCUS_APP       || '').trim();

const CPU_COUNT          = Math.max(1, os.cpus()?.length || 1);

// ── Deteksi RAM container via cgroup (v2 → v1 → os.totalmem) ─────────────────
function detectContainerMemMB() {
  // cgroup v2
  try {
    const v = fs.readFileSync('/sys/fs/cgroup/memory.max', 'utf8').trim();
    if (v !== 'max' && /^\d+$/.test(v)) {
      const mb = Math.floor(Number(v) / 1024 / 1024);
      if (mb > 0) return mb;
    }
  } catch {}
  // cgroup v1
  try {
    const v = fs.readFileSync('/sys/fs/cgroup/memory/memory.limit_in_bytes', 'utf8').trim();
    if (/^\d+$/.test(v)) {
      const n = Number(v);
      // cgroup v1 mengembalikan VERY_LARGE_NUMBER jika tidak di-set; tolak jika > 1 TB
      if (n > 0 && n < 1024 * 1024 * 1024 * 1024) return Math.floor(n / 1024 / 1024);
    }
  } catch {}
  // Fallback: os.totalmem (mungkin salah baca di container tanpa cgroup limit)
  return Math.floor(os.totalmem() / 1024 / 1024);
}

const TOTAL_MEM_MB  = detectContainerMemMB();
const BUDGET_PERCENT = Math.min(95, Math.max(50, Number(process.env.APP_MEM_BUDGET_PERCENT || 75)));
const APP_BUDGET_MB  = Math.floor(TOTAL_MEM_MB * BUDGET_PERCENT / 100);

// Distribusi v6 (7 app — +chromium-daemon shared browser):
//   kfai 28%, mcp 20%, ollama 18%, chromium 12%, ttt 8%, catur 8%, cf 6%
const KFAI_MEM     = Number(process.env.KFAI_MEMORY_MB     || Math.min(1024, Math.floor(APP_BUDGET_MB * 0.28)));
const KFAI_MCP_MEM = Number(process.env.KFAI_MCP_MEMORY_MB || Math.min(1280, Math.floor(APP_BUDGET_MB * 0.20)));
const OLLAMA_MEM   = Number(process.env.OLLAMA_MEMORY_MB   || Math.min(768,  Math.floor(APP_BUDGET_MB * 0.18)));
// Chromium daemon: 1 browser process shared untuk SEMUA tab Puppeteer
// 12% budget cukup untuk ~200-400 tab aktif di RAM kecil (10-30MB/tab)
const CHROMIUM_MEM = Number(process.env.CHROMIUM_MEMORY_MB || Math.min(512,  Math.floor(APP_BUDGET_MB * 0.12)));
const TTT_MEM      = Number(process.env.TTT_MEMORY_MB       || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.08)));
const CATUR_MEM    = Number(process.env.CATUR_MEMORY_MB     || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.08)));
const ANIMEST_MEM  = Number(process.env.ANIMEST_MEMORY_MB   || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.09)));
const CF_MEM       = Number(process.env.CF_MEMORY_MB        || 96);

const ADAPTIVE_INTERVAL  = Number(process.env.ADAPTIVE_INTERVAL_MS || 3000);
const FOCUS_HOLD_MS      = Number(process.env.FOCUS_HOLD_MS        || 12000);
const HIGH_CPU_PERCENT   = Number(process.env.HIGH_CPU_PERCENT      || 18);
const NORMAL_NICE        = Number(process.env.NORMAL_NICE            || 5);
const FOCUS_NICE         = Number(process.env.FOCUS_NICE             || 1);
const STARVE_SAFE_NICE   = Number(process.env.STARVE_SAFE_NICE       || 6);

// Mem guard v2
const MEM_GUARD_SOFT_RATIO   = Number(process.env.MEM_GUARD_SOFT_RATIO    || 1.15);
const MEM_GUARD_HARD_RATIO   = Number(process.env.MEM_GUARD_HARD_RATIO    || 1.45);
const MEM_GUARD_MAX_STRIKES  = Number(process.env.MEM_GUARD_MAX_STRIKES   || 3);
const MEM_GUARD_WINDOW_MS    = Number(process.env.MEM_GUARD_WINDOW_MS     || 60000);
const MEM_GUARD_INTERVAL_MS  = Number(process.env.MEM_GUARD_INTERVAL_MS   || 8000);

// Crash-loop protection
const CRASH_LOOP_WINDOW_MS    = Number(process.env.CRASH_LOOP_WINDOW_MS    || 300000);
const CRASH_LOOP_MAX          = Number(process.env.CRASH_LOOP_MAX          || 8);
const CRASH_LOOP_MIN_UPTIME_MS= Number(process.env.CRASH_LOOP_MIN_UPTIME_MS|| 10000);
const CRASH_LOOP_BACKOFF_MS   = Number(process.env.CRASH_LOOP_BACKOFF_MS   || 60000);

// Memory pressure detector
const PRESSURE_CHECK_INTERVAL_MS = Number(process.env.PRESSURE_CHECK_INTERVAL_MS || 15000);
const PRESSURE_AVAIL_THRESHOLD_MB= Number(process.env.PRESSURE_AVAIL_THRESHOLD_MB|| 128);

// ── Definisi app ─────────────────────────────────────────────────────────────
const APPS = [
  {
    name:     'kfai-nodejs',
    script:   '/usr/local/bin/run-kfai-nodejs.sh',
    memoryMB: KFAI_MEM,
    nice:     NORMAL_NICE,
    priority: 10, // prioritas restart relatif (lebih tinggi = lebih penting)
  },
  {
    name:     'kfai-mcp',
    script:   '/usr/local/bin/run-kfai-mcp.sh',
    memoryMB: KFAI_MCP_MEM,
    nice:     NORMAL_NICE,
    priority: 9,
  },
  {
    // Chromium shared daemon — SEMUA app Puppeteer connect ke sini via
    // puppeteer.connect({browserWSEndpoint: process.env.PUPPETEER_WS_ENDPOINT})
    // Bukan puppeteer.launch()! Prioritas tinggi karena jika mati, semua tab mati.
    name:     'chromium-daemon',
    script:   '/usr/local/bin/run-chromium-daemon.sh',
    memoryMB: CHROMIUM_MEM,
    nice:     NORMAL_NICE - 2,  // sedikit lebih prioritas dari app biasa
    priority: 9,                // sama penting dengan mcp
  },
  {
    name:     'cloudflared-ssh',
    script:   '/usr/local/bin/run-cloudflared.sh',
    memoryMB: CF_MEM,
    nice:     NORMAL_NICE + 3,
    priority: 8, // penting untuk akses SSH
  },
  {
    name:     'ollama',
    script:   '/usr/local/bin/run-ollama.sh',
    memoryMB: OLLAMA_MEM,
    nice:     NORMAL_NICE,
    priority: 7, // Ollama (animest) — LLM lokal
  },
  {
    name:     'ttt',
    script:   '/usr/local/bin/run-ttt.sh',
    memoryMB: TTT_MEM,
    nice:     NORMAL_NICE,
    priority: 5,
  },
  {
    name:     'catur',
    script:   '/usr/local/bin/run-catur.sh',
    memoryMB: CATUR_MEM,
    nice:     NORMAL_NICE,
    priority: 5,
  },
];

// ── Helpers ──────────────────────────────────────────────────────────────────
const log  = (name, msg) => console.log(`[${name}] ${msg}`);
const warn = (name, msg) => console.warn(`[${name}] WARN: ${msg}`);
const err  = (name, msg, e) => console.error(`[${name}] ERROR: ${msg}`, e || '');

function clampNice(n) {
  const x = Math.round(Number(n));
  return Number.isFinite(x) ? Math.max(0, Math.min(19, x)) : NORMAL_NICE;
}

function safeNum(v, fallback) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

const isLinux  = process.platform === 'linux';
const hasNice   = isLinux && spawnSync('sh', ['-c', 'command -v nice'],   { stdio: 'ignore' }).status === 0;
const hasRenice = isLinux && spawnSync('sh', ['-c', 'command -v renice'], { stdio: 'ignore' }).status === 0;

// ── State ────────────────────────────────────────────────────────────────────
const children    = new Map(); // name → ChildProcess
const restarting  = new Map(); // name → boolean (false = graceful stop)
const lastRestart = new Map(); // name → timestamp
const procStats   = new Map(); // name → { cpuTicks, sysTicks, at }
const curNice     = new Map(); // name → current nice value
const startedAt   = new Map(); // name → timestamp (untuk uptime)
const memGuardSt  = new Map(); // name → { strikes, lastWarnAt, lastRss }
const restartHist = new Map(); // name → number[] (timestamps)
const backoffUntil= new Map(); // name → timestamp (jangan restart sebelum ini)
const lastRebalanceSig = new Map(); // name → signature CPU terakhir (untuk throttle)

// ── Dynamic memory state ───────────────────────────────────────────────────
const dynamicLimit = new Map();  // name → current dynamic mem limit (MB)
const rssPeak      = new Map();  // name → peak RSS observed (MB)
const rssSamples   = new Map();  // name → number[] (rolling RSS, max 30)

let focusedApp  = MANUAL_FOCUS || null;
let focusUntil  = MANUAL_FOCUS ? Number.MAX_SAFE_INTEGER : 0;

// ── /proc helpers ─────────────────────────────────────────────────────────────
function readProcStat(pid) {
  try {
    const raw = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
    const after = raw.slice(raw.lastIndexOf(')') + 2).split(' ');
    return { cpuTicks: Number(after[11]) + Number(after[12]) };
  } catch { return null; }
}

function readSysTicks() {
  try {
    const parts = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0]
      .trim().split(/\s+/).slice(1).map(Number);
    return parts.reduce((a, b) => a + (Number.isFinite(b) ? b : 0), 0);
  } catch { return null; }
}

function readRssMB(pid) {
  try {
    const m = fs.readFileSync(`/proc/${pid}/status`, 'utf8').match(/^VmRSS:\s+(\d+)/im);
    return m ? Math.round(Number(m[1]) / 1024) : null;
  } catch { return null; }
}

function readMemAvailMB() {
  try {
    const m = fs.readFileSync('/proc/meminfo', 'utf8').match(/^MemAvailable:\s+(\d+)/im);
    return m ? Math.round(Number(m[1]) / 1024) : null;
  } catch { return null; }
}

// ── Nice / renice ─────────────────────────────────────────────────────────────
function applyNice(name, pid, value) {
  if (!hasRenice || !pid) return;
  const next = clampNice(value);
  if (curNice.get(name) === next) return;
  const res = spawnSync('renice', ['-n', String(next), '-p', String(pid)], { stdio: 'ignore' });
  if (res.status === 0) {
    curNice.set(name, next);
    log('NICE', `${name} → nice=${next}`);
  }
}

// ── Adaptive focus ────────────────────────────────────────────────────────────
function chooseAdaptiveFocus() {
  if (RESOURCE_MODE !== 'adaptive' || MANUAL_FOCUS || !isLinux) return;
  const now = Date.now();
  if (focusedApp && now < focusUntil) return;

  const sysNow = readSysTicks();
  if (sysNow == null) return;

  let best = null;
  for (const app of APPS) {
    const child = children.get(app.name);
    if (!child?.pid) continue;
    const stat = readProcStat(child.pid);
    if (!stat) continue;

    const prev = procStats.get(app.name);
    procStats.set(app.name, { cpuTicks: stat.cpuTicks, sysTicks: sysNow, at: now });
    if (!prev) continue;

    const procDelta = stat.cpuTicks - prev.cpuTicks;
    const sysDelta  = sysNow - prev.sysTicks;
    if (procDelta < 0 || sysDelta <= 0) continue;

    const cpuPct = (procDelta / sysDelta) * CPU_COUNT * 100;
    const rssMB  = readRssMB(child.pid) || 0;
    const score  = cpuPct + Math.min(20, rssMB / 256);

    if (!best || score > best.score)
      best = { name: app.name, cpuPct, rssMB, score };
  }

  if (best && best.cpuPct >= HIGH_CPU_PERCENT) {
    focusedApp = best.name;
    focusUntil = now + FOCUS_HOLD_MS;
    log('ADAPTIVE', `focus → ${focusedApp} (${best.cpuPct.toFixed(1)}% CPU, RSS ${best.rssMB}MB)`);
  } else {
    focusedApp = null;
    focusUntil = 0;
  }
}

function rebalanceNice() {
  if (RESOURCE_MODE === 'fair' || RESOURCE_MODE === 'custom' || !isLinux) return;
  chooseAdaptiveFocus();

  // Throttle: hanya apply renice jika ada perubahan target
  for (const app of APPS) {
    const child = children.get(app.name);
    if (!child?.pid) continue;
    let target = NORMAL_NICE;
    if (focusedApp && app.name === focusedApp) target = FOCUS_NICE;
    else if (focusedApp)                       target = STARVE_SAFE_NICE;
    applyNice(app.name, child.pid, target);
  }
}

// ── Mem monitor — pantau RSS, kirim GC nudge, TIDAK PERNAH kill ────────────────
// Restart HANYA dilakukan oleh crash recovery (child.on close).
// Limit mem tidak fix — di-adjust oleh rebalanceMemory() secara dinamis.
function startMemMonitor(app, child) {
  if (!isLinux) return;
  const nominal    = safeNum(app.memoryMB, 512);
  const softRatio  = Number(process.env.MEM_GUARD_SOFT_RATIO || 1.20);
  const softLimit  = Math.ceil(nominal * softRatio);
  const intervalMs = Number(process.env.MEM_GUARD_INTERVAL_MS || 8000);
  memGuardSt.set(app.name, { lastWarnAt: 0, lastRss: 0 });

  const t = setInterval(() => {
    if (!child.pid || child.killed) { clearInterval(t); return; }
    const rss = readRssMB(child.pid);
    if (rss == null) return;
    const state = memGuardSt.get(app.name) || { lastWarnAt: 0, lastRss: 0 };
    state.lastRss = rss;

    // Track peak & rolling samples untuk dynamic allocator
    const peak = rssPeak.get(app.name) || 0;
    if (rss > peak) rssPeak.set(app.name, rss);
    const samples = (rssSamples.get(app.name) || []);
    samples.push(rss);
    if (samples.length > 30) samples.shift();
    rssSamples.set(app.name, samples);

    // Update dynamic limit: pakai current limit kalau sudah di-adjust, else nominal
    if (!dynamicLimit.has(app.name)) dynamicLimit.set(app.name, nominal);
    const dynLimit = dynamicLimit.get(app.name);

    // GC nudge kalau RSS melewati dynamic limit * softRatio
    // NOTE: Ollama bukan Node.js, SIGUSR2 tidak trigger GC — skip untuk ollama
    const now = Date.now();
    if (app.name !== 'ollama' && rss > dynLimit * softRatio && (now - state.lastWarnAt) > 30000) {
      state.lastWarnAt = now;
      warn(app.name, `RSS ${rss}MB > limit ${dynLimit}MB — GC nudge (limit akan di-adjust)`);
      try { child.kill('SIGUSR2'); } catch {}
    }
    memGuardSt.set(app.name, state);
  }, intervalMs);
  t.unref();
}

// ── Crash-loop protection ─────────────────────────────────────────────────────
function recordCrash(name) {
  const now = Date.now();
  const hist = (restartHist.get(name) || []).filter(t => (now - t) < CRASH_LOOP_WINDOW_MS);
  hist.push(now);
  restartHist.set(name, hist);
  return hist.length;
}

function shouldRestart(name, uptimeMs) {
  const now = Date.now();
  // Cek backoff
  const bo = backoffUntil.get(name) || 0;
  if (now < bo) {
    const wait = Math.ceil((bo - now) / 1000);
    warn(name, `backoff aktif, restart ditunda ${wait}s`);
    return false;
  }
  // Jika uptime terlalu singkat = crash, hitung
  if (uptimeMs < CRASH_LOOP_MIN_UPTIME_MS) {
    const count = recordCrash(name);
    if (count >= CRASH_LOOP_MAX) {
      err(name, `crash-loop: ${count} restart dlm ${CRASH_LOOP_WINDOW_MS/1000}s — backoff ${CRASH_LOOP_BACKOFF_MS/1000}s`);
      backoffUntil.set(name, now + CRASH_LOOP_BACKOFF_MS);
      // Reset history setelah backoff agar bisa coba lagi
      restartHist.set(name, []);
      return false;
    }
  }
  return true;
}

// ── Memory pressure — graduated response, TIDAK langsung kill ──────────────────
// Level 1: MemAvail < 128MB → GC nudge semua non-kritis yang boros
// Level 2: MemAvail < 64MB  → pause app prioritas terendah 5 detik (SIGSTOP/SIGCONT)
// Level 3: MemAvail < 32MB  → kill app prioritas terendah (DARURAT ABSOLUT saja)
let pressureLevel = 0;
function checkMemoryPressure() {
  if (!isLinux) return;
  const avail = readMemAvailMB();
  if (avail == null) return;
  const threshold = Number(process.env.PRESSURE_AVAIL_THRESHOLD_MB || 128);
  if (avail >= threshold) { pressureLevel = 0; return; }

  // Level 1: GC nudge semua app yang boros (>64MB)
  if (avail < 128) {
    if (pressureLevel < 1) {
      warn('PRESSURE', `MemAvail ${avail}MB < 128MB → GC nudge semua app`);
      pressureLevel = 1;
    }
    for (const app of APPS) {
      if (app.name === 'cloudflared-ssh' || app.name === 'ollama' || app.name === 'chromium-daemon') continue;
      const child = children.get(app.name);
      if (!child?.pid) continue;
      const rss = readRssMB(child.pid) || 0;
      if (rss > 64) try { child.kill('SIGUSR2'); } catch {}
    }
  }

  // Level 2: pause app prioritas terendah 5 detik (bukan kill!)
  if (avail < 64) {
    if (pressureLevel < 2) {
      warn('PRESSURE', `MemAvail ${avail}MB < 64MB → pause app prioritas terendah 5s`);
      pressureLevel = 2;
    }
    let lowest = null; let lowestPri = Infinity;
    for (const app of APPS) {
      if (app.name === 'cloudflared-ssh' || app.name === 'ollama' || app.name === 'chromium-daemon' || app.name === INTERACTIVE_APP) continue;
      if (!children.has(app.name)) continue;
      if (app.priority < lowestPri) { lowestPri = app.priority; lowest = app; }
    }
    if (lowest) {
      const child = children.get(lowest.name);
      try {
        child.kill('SIGSTOP');
        setTimeout(() => { try { child.kill('SIGCONT'); } catch {} }, 5000).unref();
      } catch {}
    }
  }

  // Level 3: DARURAT — kill HANYA jika MemAvailable kritis (<32MB)
  if (avail < 32) {
    err('PRESSURE', `MemAvail ${avail}MB < 32MB — DARURAT, kill app prioritas terendah`);
    pressureLevel = 3;
    let victim = null; let lowestPri = Infinity;
    for (const app of APPS) {
      if (app.name === 'cloudflared-ssh' || app.name === 'ollama' || app.name === 'chromium-daemon' || app.name === INTERACTIVE_APP) continue;
      if (!children.has(app.name)) continue;
      if (app.priority < lowestPri) { lowestPri = app.priority; victim = app; }
    }
    if (victim) {
      const child = children.get(victim.name);
      restarting.set(victim.name, true);
      try {
        child.kill('SIGTERM');
        setTimeout(() => { try { if (!child.killed) child.kill('SIGKILL'); } catch {} }, 3000).unref();
      } catch {}
    }
  }
}

// ── Dynamic memory rebalancer — limit otomatis naik/turun sesuai kebutuhan ──────
// TIDAK restart app. Hanya track & adjust limit untuk:
//   (a) monitoring real-time
//   (b) dipakai saat app restart berikutnya (NODE_OPTIONS --max-old-space-size)
function rebalanceMemory() {
  if (!isLinux) return;
  const avail = readMemAvailMB();
  if (avail == null) return;

  // Collect usage info semua app yang berjalan
  const usages = [];
  let totalRss = 0;
  for (const app of APPS) {
    const child = children.get(app.name);
    if (!child?.pid) continue;
    const rss  = readRssMB(child.pid) || 0;
    const peak = rssPeak.get(app.name) || rss;
    totalRss += rss;
    usages.push({ name: app.name, rss, peak, app });
  }
  if (usages.length === 0) return;

  // Hitung total allocated vs total used
  let totalAllocated = 0;
  for (const u of usages) totalAllocated += dynamicLimit.get(u.name) || 0;
  const slack = Math.max(0, totalAllocated - totalRss);

  // Redistribute: app yang peak-nya melewati limit dapat tambahan dari slack,
  // app yang pakai jauh di bawah limit dikurangi (dengan headroom 30%)
  for (const { name, rss, peak } of usages) {
    const curLimit = dynamicLimit.get(name) || app.memoryMB;
    // Minimum limit: actual RSS + 30% headroom, atau 64MB (mana lebih besar)
    const minLimit = Math.max(64, Math.ceil(rss * 1.3));
    let newLimit = curLimit;

    if (peak > curLimit * 1.1 && slack > 32) {
      // App butuh lebih: grow ambil dari slack, max 50% kebutuhan ekstra
      const growBy = Math.min(slack * 0.5, Math.ceil((peak * 1.3 - curLimit) * 0.5));
      if (growBy > 16) newLimit = curLimit + Math.floor(growBy);
    } else if (rss < curLimit * 0.5 && curLimit > minLimit * 1.2) {
      // App pakai jauh di bawah limit: shrink pelan-pelan ke minLimit
      newLimit = Math.max(minLimit, Math.ceil(curLimit * 0.85));
    }

    // Clamp: max 50% budget per app, min minLimit
    newLimit = Math.max(minLimit, Math.min(Math.floor(APP_BUDGET_MB * 0.5), newLimit));

    if (Math.abs(newLimit - curLimit) > 16) {
      dynamicLimit.set(name, newLimit);
      log('MEMBALANCE', `${name}: ${curLimit}MB → ${newLimit}MB (rss=${rss}MB peak=${peak}MB slack=${Math.round(slack)}MB)`);
    }
  }
}

// ── stdout/stderr prefix pipe ─────────────────────────────────────────────────
function prefixPipe(stream, name, isErr) {
  let buf = '';
  stream.on('data', chunk => {
    buf += chunk.toString();
    const lines = buf.split(/\r?\n/);
    buf = lines.pop() || '';
    for (const l of lines) {
      if (!l.trim()) continue;
      isErr ? console.error(`[${name}] ${l}`) : console.log(`[${name}] ${l}`);
    }
  });
  stream.on('end', () => {
    if (buf.trim()) isErr ? console.error(`[${name}] ${buf}`) : console.log(`[${name}] ${buf}`);
  });
}

// ── Start app ─────────────────────────────────────────────────────────────────
function startApp(app) {
  if (children.has(app.name)) { warn(app.name, 'sudah berjalan, skip.'); return; }

  const isInteractive = app.name === INTERACTIVE_APP;
  // Pakai dynamic limit kalau sudah ada, else initial allocation
  const memMB = safeNum(dynamicLimit.get(app.name) || app.memoryMB, 512);
  const niceVal = clampNice(RESOURCE_MODE === 'custom' ? app.nice : NORMAL_NICE);

  // Bangun NODE_OPTIONS dengan max-old-space-size yang benar
  // CATATAN: Ollama bukan Node.js, jadi NODE_OPTIONS tidak di-apply
  const isOllama = app.name === 'ollama';
  const nodeOpts = (process.env.NODE_OPTIONS || '')
    .split(/\s+/)
    .filter(x => x && !x.startsWith('--max-old-space-size=') && !x.startsWith('--max-semi-space-size=') && !x.startsWith('--gc-interval='))
    .concat([
      `--max-old-space-size=${memMB}`,
      `--max-semi-space-size=64`,
      '--expose-gc',
    ])
    .join(' ');

  const env = {
    ...process.env,
    NODE_OPTIONS: isOllama ? (process.env.NODE_OPTIONS || '') : nodeOpts,
    NODE_ENV: isOllama ? undefined : 'production',
    APP_RESOURCE_MEMORY_MB: String(memMB),
    APP_RESOURCE_MODE: RESOURCE_MODE,
    APP_RESOURCE_ADAPTIVE: RESOURCE_MODE === 'adaptive' ? 'true' : 'false',
  };
  // Ollama-specific env
  if (isOllama) {
    env.OLLAMA_HOST = process.env.OLLAMA_HOST || '0.0.0.0:11434';
    env.OLLAMA_MODELS = process.env.OLLAMA_MODELS || '/data/ollama/models';
    delete env.NODE_OPTIONS;
    delete env.NODE_ENV;
  }

  // Jalankan script via bash, opsional wrap dengan nice
  let command, args;
  if (hasNice) {
    command = 'nice';
    args    = ['-n', String(niceVal), 'bash', app.script];
  } else {
    command = 'bash';
    args    = [app.script];
  }

  const child = spawn(command, args, {
    shell:  false,
    env,
    stdio: isInteractive
      ? ['inherit', 'inherit', 'inherit']
      : ['ignore', 'pipe', 'pipe'],
  });

  children.set(app.name, child);
  restarting.set(app.name, true);
  curNice.set(app.name, niceVal);
  startedAt.set(app.name, Date.now());
  startMemMonitor(app, child);

  log(app.name, `started | mem=${memMB}MB nice=${niceVal}${isInteractive ? ' [interactive]' : ''}${isOllama ? ' [ollama]' : ''}`);

  if (!isInteractive) {
    prefixPipe(child.stdout, app.name, false);
    prefixPipe(child.stderr, app.name, true);
  }

  child.on('close', (code, signal) => {
    const startedAtMs = startedAt.get(app.name) || Date.now();
    const uptimeMs = Date.now() - startedAtMs;
    children.delete(app.name);
    procStats.delete(app.name);
    curNice.delete(app.name);
    startedAt.delete(app.name);
    log(app.name, `stopped code=${code} signal=${signal || '-'} uptime=${(uptimeMs/1000).toFixed(1)}s`);

    if (focusedApp === app.name && !MANUAL_FOCUS) { focusedApp = null; focusUntil = 0; }
    if (restarting.get(app.name) === false) return;

    // Crash-loop check
    if (!shouldRestart(app.name, uptimeMs)) {
      // Coba lagi setelah backoff
      const bo = backoffUntil.get(app.name) || (Date.now() + CRASH_LOOP_BACKOFF_MS);
      const delay = Math.max(1000, bo - Date.now());
      warn(app.name, `akan coba restart lagi dalam ${(delay/1000).toFixed(0)}s`);
      setTimeout(() => {
        if (restarting.get(app.name) === false) return;
        log(app.name, 'restarting (post-backoff)...');
        startApp(app);
      }, delay).unref();
      return;
    }

    const now  = Date.now();
    const last = lastRestart.get(app.name) || 0;
    // Exponential backoff untuk restart cepat: 3s → 8s → 15s → 30s
    const sinceLast = now - last;
    let delay = 3000;
    if (sinceLast < 30000) delay = 8000;
    if (sinceLast < 10000) delay = 15000;
    lastRestart.set(app.name, now);
    setTimeout(() => { log(app.name, 'restarting...'); startApp(app); }, delay).unref();
  });

  child.on('error', e => { children.delete(app.name); err(app.name, 'spawn error:', e); });
}

// ── Graceful shutdown ─────────────────────────────────────────────────────────
function stopAll() {
  console.log('\n[LAUNCHER] shutdown semua proses...');
  for (const app of APPS) restarting.set(app.name, false);
  for (const [name, child] of children) {
    try { log(name, 'SIGTERM'); child.kill('SIGTERM'); }
    catch (e) { err(name, 'kill gagal:', e); }
  }
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on('SIGINT',  stopAll);
process.on('SIGTERM', stopAll);
process.on('uncaughtException', e => { console.error('[LAUNCHER] uncaughtException:', e); });
process.on('unhandledRejection', e => { console.error('[LAUNCHER] unhandledRejection:', e); });

// ── Info startup ──────────────────────────────────────────────────────────────
console.log(`\n[LAUNCHER] ══════════════════════════════════════════`);
console.log(`[LAUNCHER] CPU=${CPU_COUNT} core | RAM(container)=${TOTAL_MEM_MB}MB | budget=${APP_BUDGET_MB}MB (${BUDGET_PERCENT}%)`);
console.log(`[LAUNCHER] RESOURCE_MODE=${RESOURCE_MODE} | INTERACTIVE=${INTERACTIVE_APP}`);
console.log(`[LAUNCHER] nice: focus=${FOCUS_NICE} normal=${NORMAL_NICE} other=${STARVE_SAFE_NICE}`);
console.log(`[LAUNCHER] v6 — Debian + Ollama + shared Chromium daemon (Puppeteer-at-scale)`);
console.log(`[LAUNCHER] puppeteer WS: ${process.env.PUPPETEER_WS_ENDPOINT || 'ws://127.0.0.1:9222'}`);
console.log(`[LAUNCHER] max concurrent tabs: ${process.env.PUPPETEER_MAX_CONCURRENT_TABS || 64}`);
console.log(`[LAUNCHER] mem-monitor: soft=${MEM_GUARD_SOFT_RATIO}x (no kill — limit adjusts dynamically)`);
console.log(`[LAUNCHER] pressure: L1=nudge@128MB L2=pause@64MB L3=kill@32MB`);
console.log(`[LAUNCHER] crash-loop: max=${CRASH_LOOP_MAX}/${CRASH_LOOP_WINDOW_MS/1000}s backoff=${CRASH_LOOP_BACKOFF_MS/1000}s`);
console.log(`[LAUNCHER] ollama: host=${process.env.OLLAMA_HOST || '0.0.0.0:11434'} models=${process.env.OLLAMA_MODELS || '/data/ollama/models'}`);
for (const app of APPS)
  console.log(`[LAUNCHER]   ${app.name.padEnd(16)} init=${safeNum(app.memoryMB,512)}MB  priority=${app.priority}`);
console.log(`[LAUNCHER] ══════════════════════════════════════════\n`);

// ── Rebalance loop (CPU nice) ──────────────────────────────────────────────────
setInterval(rebalanceNice, ADAPTIVE_INTERVAL).unref();

// ── Memory rebalancer loop — redistribute budget tiap 10 detik ──────────────────
setInterval(rebalanceMemory, 10000).unref();

// ── Memory pressure detector loop ─────────────────────────────────────────────
setInterval(checkMemoryPressure, PRESSURE_CHECK_INTERVAL_MS).unref();

// ── Start semua app satu per satu (900ms jeda agar stdin tidak tabrakan) ──────
(async () => {
  for (const app of APPS) {
    startApp(app);
    await new Promise(r => setTimeout(r, 900));
  }
})();
LAUNCHEREOF

# Pastikan launcher persisten di /data (sudah di layer 4, tapi buat symlink
# ke lokasi tetap agar mudah diedit via SSH)
RUN ln -sf /data/launcher/index.js /usr/local/bin/adaptive-launcher.js

# ═══════════════════════════════════════════════════════════════════════════════
# SCRIPTS
# ═══════════════════════════════════════════════════════════════════════════════

# ─── resource-optimizer.sh ────────────────────────────────────────────────────
# Catatan v2:
#   • vm.min_free_kbytes dinamis berdasarkan RAM (5% RAM, min 16MB, max 64MB)
#   • drop_caches hanya jika MemAvailable < 256MB
#   • Semua sysctl gagal (unprivileged container) ditelan tanpa noise
RUN cat > /usr/local/bin/resource-optimizer.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
log() { echo "[resource-optimizer] $*"; }

# Stop service tidak diperlukan (di container biasanya tidak ada, tapi just in case)
UNNEEDED=(
  cron atd anacron rsyslog syslog
  avahi-daemon bluetooth ModemManager
  cups cups-browsed snapd snapd.socket
  multipathd thermald iscsid
  apt-daily apt-daily-upgrade unattended-upgrades
  packagekit polkit colord geoclue whoopsie apport kerneloops
  accounts-daemon rtkit-daemon speech-dispatcher
  pipewire wireplumber pulseaudio
  udisks2 upower wpa_supplicant
  NetworkManager NetworkManager-wait-online
  firewalld ufw
)
for svc in "${UNNEEDED[@]}"; do
  command -v systemctl >/dev/null 2>&1 || continue
  systemctl is-active --quiet "$svc" 2>/dev/null || continue
  log "stop: $svc"
  systemctl stop "$svc"    2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done
for proc in freshclam clamd updatedb mlocate; do
  pkill -f "$proc" 2>/dev/null && log "killed: $proc" || true
done

# Hitung min_free_kbytes dinamis berdasarkan RAM tersedia (cgroup-aware)
read_mem_kb() {
  # cgroup v2
  if [ -f /sys/fs/cgroup/memory.max ]; then
    local v; v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    if [ "$v" != "max" ] && [ -n "$v" ]; then
      echo $(( v / 1024 ))
      return
    fi
  fi
  # cgroup v1
  if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    local v; v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)
    if [ -n "$v" ] && [ "$v" -lt 1099511627776 ]; then
      echo $(( v / 1024 ))
      return
    fi
  fi
  # fallback /proc/meminfo
  awk '/MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 1048576
}
MEM_KB=$(read_mem_kb)
# 5% RAM, min 16384 (16MB), max 65536 (64MB)
MIN_FREE=$(( MEM_KB / 20 ))
[ "$MIN_FREE" -lt 16384 ] && MIN_FREE=16384
[ "$MIN_FREE" -gt 65536 ] && MIN_FREE=65536

sc() { sysctl -w "$1=$2" >/dev/null 2>&1 && log "sysctl $1=$2" || true; }
# v6: zram swap (RAM kompresi in-memory) — dramatis untuk banyak tab Chromium
# Container biasanya tidak bisa modprobe, jadi wrap dengan cek
if command -v modprobe >/dev/null 2>&1 && [ ! -e /dev/zram0 ]; then
  modprobe zram num_devices=1 2>/dev/null && log "zram: module loaded" || true
fi
if [ -e /dev/zram0 ] && ! swapon -s 2>/dev/null | grep -q zram0; then
  echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  # zram size = 50% RAM (cap 2GB), kompresi zstd biasanya 3-4x
  ZRAM_SIZE=$(( MEM_KB / 2 ))
  [ "$ZRAM_SIZE" -gt 2097152 ] && ZRAM_SIZE=2097152
  echo "$ZRAM_SIZE"K > /sys/block/zram0/disksize 2>/dev/null || true
  mkswap /dev/zram0 2>/dev/null && swapon -p 100 /dev/zram0 2>/dev/null \
    && log "zram: enabled ($(( ZRAM_SIZE / 1024 ))MB, zstd, priority 100)" || true
fi
# Swappiness: tinggi (60) kalau zram aktif (kompresi cepat), rendah (5) kalau tidak
if swapon -s 2>/dev/null | grep -q zram0; then
  sc vm.swappiness               60
else
  sc vm.swappiness               5
fi
sc vm.dirty_ratio              20
sc vm.dirty_background_ratio   5
sc vm.vfs_cache_pressure       50
sc vm.overcommit_memory        1
sc vm.min_free_kbytes          "$MIN_FREE"
sc kernel.sched_migration_cost_ns  500000
sc kernel.sched_autogroup_enabled  1
# Network tuning untuk many concurrent Puppeteer connections
sc net.ipv4.tcp_keepalive_time     30
sc net.ipv4.tcp_keepalive_intvl    10
sc net.ipv4.tcp_keepalive_probes   5
sc net.ipv4.tcp_fastopen           3
sc net.ipv4.tcp_tw_reuse           1
sc net.ipv4.tcp_fin_timeout        30
sc net.ipv4.ip_local_port_range    "1024 65535"
sc net.ipv4.tcp_max_tw_buckets     2000000
sc net.ipv4.tcp_max_syn_backlog    65535
sc net.core.rmem_max               16777216
sc net.core.wmem_max               16777216
sc net.core.somaxconn              65535
sc net.core.netdev_max_backlog     5000
# File descriptors — jutaan tab butuh jutaan FD
sc fs.file-max                     4194304
sc fs.nr_open                      4194304
sc fs.inotify.max_user_watches     1048576
sc fs.inotify.max_user_instances   4096

# v6: bump FD limit untuk many concurrent Puppeteer tabs
ulimit -n 4194304 2>/dev/null || ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true
ulimit -u 262144  2>/dev/null || ulimit -u 65535   2>/dev/null || true
ulimit -s unlimited 2>/dev/null || true
ulimit -c 0       2>/dev/null || true

for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -f "$g" ] && echo performance > "$g" 2>/dev/null && log "cpu governor: performance" && break
done
for dev in /sys/block/*/queue/scheduler; do
  [ -f "$dev" ] && { echo none > "$dev" 2>/dev/null || echo mq-deadline > "$dev" 2>/dev/null || true; }
done

# Drop cache hanya jika MemAvailable < 256MB
AVAIL_MB=$(awk '/MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 9999)
if [ "${AVAIL_MB:-9999}" -lt 256 ]; then
  log "MemAvailable=${AVAIL_MB}MB < 256MB → drop caches"
  sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
else
  log "MemAvailable=${AVAIL_MB}MB OK, skip drop_caches"
fi

rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
log "selesai."
SCRIPT

# ─── oom-watchdog.sh ──────────────────────────────────────────────────────────
# v3: tambah proteksi ollama/animest
RUN cat > /usr/local/bin/oom-watchdog.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
protect() {
  local pat="$1" score="$2"
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    echo "$score" > /proc/$pid/oom_score_adj 2>/dev/null || true
  done
}
while true; do
  # Paling dilindungi: launcher, earlyoom, sshd
  protect "node.*adaptive-launcher|node.*launcher/index.js" -1000
  protect "earlyoom"              -950
  protect "/usr/sbin/sshd"        -900
  protect "PM2|pm2"               -800
  protect "ollama"                -750
  protect "node.*server"          -700
  protect "node.*kfai"            -700
  protect "node.*ttt"             -700
  protect "node.*catur"           -700
  protect "cloudflared"           -500
  # Chromium daemon: lindungi main process (parent browser)
  protect "/usr/bin/chromium.*--remote-debugging-port" -900
  # Tapi render child (tab) boleh dibunuh — auto-respawn dari daemon
  protect "/usr/bin/chromium.*--type=renderer"     500
  protect "/usr/bin/chromium.*--type=gpu-process"  300
  protect "/usr/bin/chromium.*--type=zygote"      -500
  sleep 30
done
SCRIPT

# ─── bootstrap-apps.sh – clone PARALEL ───────────────────────────────────────
# v2.1: tambah catur ke daftar clone paralel
RUN cat > /usr/local/bin/bootstrap-apps.sh <<'SCRIPT'
#!/usr/bin/env bash
set -u
export GIT_TERMINAL_PROMPT=0

get_token() { printf '%s' "${GH_TOKEN:-${GITHUB_TOKEN:-${GIT_TOKEN:-}}}"; }
git_auth() {
  local token basic
  token="$(get_token)"
  if [ -n "$token" ]; then
    basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
    git -c http.https://github.com/.extraHeader="Authorization: Basic ${basic}" \
        -c http.postBuffer=524288000 -c core.compression=9 "$@"
  else
    git -c http.postBuffer=524288000 -c core.compression=9 "$@"
  fi
}

clone_or_pull() {
  local name="$1" repo="$2" dir="$3" branch="${4:-}"
  [ -z "$repo" ] && echo "[$name] skip (repo kosong)." && return 0

  if [ -d "$dir/.git" ]; then
    echo "[$name] pull → $dir"
    [ -n "$branch" ] && {
      git_auth -C "$dir" fetch origin "$branch" --depth=1 2>&1 | sed "s/^/[$name] /" || true
      git -C "$dir" checkout "$branch" 2>&1 | sed "s/^/[$name] /" || true
    }
    git_auth -C "$dir" pull --ff-only 2>&1 | sed "s/^/[$name] /" \
      || echo "[$name] WARN: pull gagal, pakai versi lama."
    return 0
  fi

  echo "[$name] clone → $dir"
  rm -rf "$dir"
  if [ -z "$(get_token)" ]; then
    echo "[$name] ERROR: token GitHub kosong." && return 0
  fi
  local args=("clone" "--depth=1" "--single-branch" "--no-tags")
  [ -n "$branch" ] && args+=("--branch" "$branch")
  git_auth "${args[@]}" "$repo" "$dir" 2>&1 | sed "s/^/[$name] /" \
    || echo "[$name] WARN: clone gagal."
}

mkdir -p /data/apps /data/bin /data/root/.pm2 /data/root/.npm /data/ollama/models

clone_or_pull "kfai-nodejs" "${KFAI_REPO:-}"     "${KFAI_DIR:-/data/apps/kfai-nodejs}"  "${KFAI_BRANCH:-}" &
clone_or_pull "kfai-mcp"    "${KFAI_MCP_REPO:-}" "${KFAI_MCP_DIR:-/data/apps/kfai-mcp}" "${KFAI_MCP_BRANCH:-}" &
clone_or_pull "ttt"         "${TTT_REPO:-}"       "${TTT_DIR:-/data/apps/ttt}"            "${TTT_BRANCH:-}" &
clone_or_pull "catur"       "${CATUR_REPO:-}"     "${CATUR_DIR:-/data/apps/catur}"        "${CATUR_BRANCH:-}" &
clone_or_pull "animest"    "${ANIMEST_REPO:-}"   "${ANIMEST_DIR:-/data/apps/animest}"    "${ANIMEST_BRANCH:-}" &

FAIL=0
for job in $(jobs -p); do
  wait "$job" || { echo "WARN: clone/pull gagal (pid $job)"; FAIL=$((FAIL+1)); }
done
[ "$FAIL" -gt 0 ] && echo "bootstrap-apps: $FAIL repo gagal." || echo "bootstrap-apps: semua repo siap."
SCRIPT

# ─── clear-app-port-env.sh ────────────────────────────────────────────────────
RUN cat > /usr/local/bin/clear-app-port-env.sh <<'SCRIPT'
#!/usr/bin/env bash
[ "${KEEP_APP_PORT_ENV:-false}" != "true" ] && unset PORT
exec "$@"
SCRIPT

# ─── upgrade-langchain-packages.sh ────────────────────────────────────────────
# Catatan v2: default NONAKTIF kecuali LANGCHAIN_AUTO_UPGRADE=true
RUN cat > /usr/local/bin/upgrade-langchain-packages.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
APP_NAME="${1:-node-app}"
# Default false (sebelumnya true) — hanya aktif jika explicit di-set ke true
[ "${LANGCHAIN_AUTO_UPGRADE:-false}" != "true" ] && exit 0
[ ! -f package.json ] && exit 0
grep -q '"@langchain/' package.json 2>/dev/null || exit 0
PKGS="@langchain/core@latest @langchain/openai@latest @langchain/mcp-adapters@latest"
grep -q '"@langchain/anthropic"' package.json 2>/dev/null && PKGS="$PKGS @langchain/anthropic@latest"
grep -q '"@langchain/google'     package.json 2>/dev/null && PKGS="$PKGS @langchain/google-genai@latest"
echo "[$APP_NAME] upgrade LangChain..."
# Sanitize NODE_OPTIONS: hapus V8 flag yang tidak diizinkan di NODE_OPTIONS
export NODE_OPTIONS="$(echo "${NODE_OPTIONS:-}" | sed 's/--gc-interval=[0-9]*//g;s/  */ /g;s/^ *//;s/ *$//')"
npm install $PKGS --save --omit=dev --include=optional \
  --no-audit --no-fund --loglevel=error --prefer-offline \
  || echo "[$APP_NAME] WARN: upgrade gagal"
npm cache clean --force >/dev/null 2>&1 || true
SCRIPT

# ─── ensure-node-app-deps.sh ──────────────────────────────────────────────────
RUN cat > /usr/local/bin/ensure-node-app-deps.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="$1"; APP_DIR="$2"
ZIP_FILE="${3:-node_modules.zip}"; USE_ZIP="${4:-true}"; SKIP_NPM="${5:-false}"
cd "$APP_DIR"
[ ! -f package.json ] && echo "[$APP_NAME] package.json tidak ada." && exit 1

extract_zip() {
  [ ! -f "$1" ] && return 1
  echo "[$APP_NAME] ekstrak zip: $1"
  rm -rf node_modules node_modules.tmp && mkdir -p node_modules.tmp
  unzip -q "$1" -d node_modules.tmp || { rm -rf node_modules.tmp; return 1; }
  [ -d node_modules.tmp/node_modules ] \
    && mv node_modules.tmp/node_modules ./node_modules \
    || mv node_modules.tmp ./node_modules
  rm -rf node_modules.tmp
  find node_modules -mindepth 1 -maxdepth 1 2>/dev/null | head -n1 | grep -q . \
    && { /usr/local/bin/upgrade-langchain-packages.sh "$APP_NAME" || true; return 0; }
  rm -rf node_modules; return 1
}

if [ "$USE_ZIP" = "true" ] && extract_zip "$ZIP_FILE"; then
  echo "[$APP_NAME] pakai node_modules dari zip."
  exit 0
fi
[ "$SKIP_NPM" = "true" ] && { /usr/local/bin/upgrade-langchain-packages.sh "$APP_NAME" || true; exit 0; }

echo "[$APP_NAME] npm install..."
# Sanitize NODE_OPTIONS: hapus V8 flag yang tidak diizinkan di NODE_OPTIONS
export NODE_OPTIONS="$(echo "${NODE_OPTIONS:-}" | sed 's/--gc-interval=[0-9]*//g;s/  */ /g;s/^ *//;s/ *$//')"
FLAGS="--omit=dev --include=optional --no-audit --no-fund --loglevel=error --prefer-offline"
[ -f package-lock.json ] \
  && npm ci $FLAGS || npm install $FLAGS
npm rebuild --loglevel=error || true
node -e "require.resolve('dotenv')" >/dev/null 2>&1 \
  || npm install dotenv --save --omit=dev --no-audit --no-fund --prefer-offline
/usr/local/bin/upgrade-langchain-packages.sh "$APP_NAME" || true
npm cache clean --force || true
echo "[$APP_NAME] deps siap."
SCRIPT

# ─── run-node-app.sh ──────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-node-app.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="$1"; APP_DIR="$2"; ENTRY_DEFAULT="${3:-server.js}"
ZIP_FILE="${4:-node_modules.zip}"; USE_ZIP="${5:-true}"; SKIP_NPM="${6:-false}"
NODE_EXTRA="${7:-}"

[ ! -d "$APP_DIR" ] && echo "[$APP_NAME] folder tidak ada: $APP_DIR" >&2 && sleep 10 && exit 1
cd "$APP_DIR"
[ ! -f package.json ] && echo "[$APP_NAME] package.json tidak ada." >&2 && sleep 10 && exit 1

/usr/local/bin/ensure-node-app-deps.sh "$APP_NAME" "$APP_DIR" "$ZIP_FILE" "$USE_ZIP" "$SKIP_NPM"

ENTRY="$ENTRY_DEFAULT"
if [ ! -f "$ENTRY" ]; then
  for f in server.js server-langchain.js index.js; do
    [ -f "$f" ] && ENTRY="$f" && break
  done
fi
if [ ! -f "$ENTRY" ]; then
  npm run 2>/dev/null | grep -qE '^\s+start\b' \
    && exec /usr/local/bin/clear-app-port-env.sh npm start \
    || { echo "[$APP_NAME] entry point tidak ditemukan." >&2; sleep 10; exit 1; }
fi

echo "[$APP_NAME] start: node $NODE_EXTRA $ENTRY"
exec /usr/local/bin/clear-app-port-env.sh node $NODE_EXTRA "$ENTRY"
SCRIPT

# ─── run-kfai-nodejs.sh ───────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-kfai-nodejs.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/run-node-app.sh \
  "kfai-nodejs" \
  "${KFAI_DIR:-/data/apps/kfai-nodejs}" \
  "${KFAI_ENTRY:-server-langchain.js}" \
  "${KFAI_NODE_MODULES_ZIP:-node_modules.zip}" \
  "${KFAI_USE_NODE_MODULES_ZIP:-true}" \
  "${KFAI_SKIP_NPM_INSTALL:-false}" \
  "${KFAI_NODE_OPTIONS:---max-old-space-size=512}"
SCRIPT

# ─── run-kfai-mcp.sh ──────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-kfai-mcp.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/run-node-app.sh \
  "kfai-mcp" \
  "${KFAI_MCP_DIR:-/data/apps/kfai-mcp}" \
  "${KFAI_MCP_ENTRY:-server.js}" \
  "${KFAI_MCP_NODE_MODULES_ZIP:-node_modules.zip}" \
  "${KFAI_MCP_USE_NODE_MODULES_ZIP:-true}" \
  "${KFAI_MCP_SKIP_NPM_INSTALL:-false}" \
  "${KFAI_MCP_NODE_OPTIONS:---max-old-space-size=768}"
SCRIPT

# ─── run-ttt.sh ───────────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-ttt.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/run-node-app.sh \
  "ttt" \
  "${TTT_DIR:-/data/apps/ttt}" \
  "${TTT_ENTRY:-server.js}" \
  "${TTT_NODE_MODULES_ZIP:-node_modules.zip}" \
  "${TTT_USE_NODE_MODULES_ZIP:-true}" \
  "${TTT_SKIP_NPM_INSTALL:-false}" \
  "${TTT_NODE_OPTIONS:---max-old-space-size=256}"
SCRIPT

# ─── run-catur.sh ─────────────────────────────────────────────────────────────
# v3.1 — launcher script untuk aplikasi catur (https://github.com/Yz776/catur.git)
# Default memory 256MB (override via CATUR_NODE_OPTIONS / CATUR_MEMORY_MB di launcher)
RUN cat > /usr/local/bin/run-catur.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/run-node-app.sh \
  "catur" \
  "${CATUR_DIR:-/data/apps/catur}" \
  "${CATUR_ENTRY:-server.js}" \
  "${CATUR_NODE_MODULES_ZIP:-node_modules.zip}" \
  "${CATUR_USE_NODE_MODULES_ZIP:-true}" \
  "${CATUR_SKIP_NPM_INSTALL:-false}" \
  "${CATUR_NODE_OPTIONS:---max-old-space-size=256}"
SCRIPT

# ─── run-animest.sh ───────────────────────────────────────────────────────────
# v3.2 — launcher script untuk aplikasi animest (https://github.com/Yz776/animest.git)
# Pakai node_modules dari ZIP (--legacy-peer-deps sebagai fallback install)
# Jalankan dengan: npm run start
# Default memory 256MB (override via ANIMEST_NODE_OPTIONS / ANIMEST_MEMORY_MB di launcher)
RUN cat > /usr/local/bin/run-animest.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="animest"
APP_DIR="${ANIMEST_DIR:-/data/apps/animest}"
ZIP_FILE="${ANIMEST_NODE_MODULES_ZIP:-node_modules.zip}"
USE_ZIP="${ANIMEST_USE_NODE_MODULES_ZIP:-true}"

[ ! -d "$APP_DIR" ] && echo "[$APP_NAME] folder tidak ada: $APP_DIR" >&2 && sleep 10 && exit 1
cd "$APP_DIR"
[ ! -f package.json ] && echo "[$APP_NAME] package.json tidak ada." >&2 && sleep 10 && exit 1

# ── Coba ekstrak dari zip dulu ──────────────────────────────────────────────
extract_zip() {
  [ ! -f "$1" ] && return 1
  echo "[$APP_NAME] ekstrak zip: $1"
  rm -rf node_modules node_modules.tmp && mkdir -p node_modules.tmp
  unzip -q "$1" -d node_modules.tmp || { rm -rf node_modules.tmp; return 1; }
  [ -d node_modules.tmp/node_modules ] \
    && mv node_modules.tmp/node_modules ./node_modules \
    || mv node_modules.tmp ./node_modules
  rm -rf node_modules.tmp
  find node_modules -mindepth 1 -maxdepth 1 2>/dev/null | head -n1 | grep -q . && return 0
  rm -rf node_modules; return 1
}

NEED_INSTALL=true
if [ "$USE_ZIP" = "true" ] && extract_zip "$ZIP_FILE"; then
  echo "[$APP_NAME] pakai node_modules dari zip."
  NEED_INSTALL=false
fi

# ── Fallback: npm install --legacy-peer-deps ─────────────────────────────────
if [ "$NEED_INSTALL" = "true" ]; then
  if [ ! -d node_modules ] || [ ! "$(ls -A node_modules 2>/dev/null)" ]; then
    echo "[$APP_NAME] npm install --legacy-peer-deps..."
    export NODE_OPTIONS="$(echo "${NODE_OPTIONS:-}" | sed 's/--gc-interval=[0-9]*//g;s/  */ /g;s/^ *//;s/ *$//')"
    npm install --legacy-peer-deps --include=dev --no-audit --no-fund --loglevel=error --prefer-offline \
      || npm install --legacy-peer-deps --include=dev --no-audit --no-fund --loglevel=error
    npm cache clean --force >/dev/null 2>&1 || true
    echo "[$APP_NAME] deps siap."
  fi
fi

echo "[$APP_NAME] build frontend: npm run build"
export NODE_OPTIONS="$(echo "${NODE_OPTIONS:-}" | sed 's/--gc-interval=[0-9]*//g;s/  */ /g;s/^ *//;s/ *$//')"
npm run build

echo "[$APP_NAME] start backend: npm run start"
exec npm run start
SCRIPT

# ─── run-ollama.sh ────────────────────────────────────────────────────────────
# v4 — Ollama LLM service (dijalankan sebagai "animest" di PM2)
# pm2 start "ollama serve" --name animest
# Models disimpan di /data/ollama/models (persistent via volume)
# Ollama API: http://0.0.0.0:11434
RUN cat > /usr/local/bin/run-ollama.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Pastikan direktori models ada
mkdir -p "${OLLAMA_MODELS:-/data/ollama/models}"

echo "[ollama] starting ollama serve..."
echo "[ollama] OLLAMA_HOST=${OLLAMA_HOST:-0.0.0.0:11434}"
echo "[ollama] OLLAMA_MODELS=${OLLAMA_MODELS:-/data/ollama/models}"

# Jalankan ollama serve
exec ollama serve
SCRIPT

# ─── run-cloudflared.sh ───────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-cloudflared.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${CLOUDFLARED_TOKEN:-}" ]; then
  exec cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARED_TOKEN"
fi
exec cloudflared tunnel --no-autoupdate --url "${CLOUDFLARED_URL:-ssh://127.0.0.1:${SSH_PORT:-22}}"
SCRIPT

# ═══════════════════════════════════════════════════════════════════════════════
# LAYER PUPPETEER-AT-SCALE — shared Chromium daemon + tab pool helper
# ═══════════════════════════════════════════════════════════════════════════════
# Arsitektur: 1 browser daemon Chromium (1 proses, ~200-400MB) melayani
# semua tab via --remote-debugging-port. Setiap tab hanya ~10-30MB.
# App Node connect via puppeteer.connect({browserWSEndpoint: PUPPETEER_WS_ENDPOINT})
# Helper /usr/local/lib/chromium-pool.js menyediakan withPage(fn) bounded pool.
#
# MEMORI: dibanding N browser independen (N x ~250MB), shared daemon + N tabs
#         pakai ~250MB + N x 20MB — hemat ~10x untuk N besar.
#
# KEAMANAN: --remote-debugging-port HANYA listen 127.0.0.1 (tidak exposed).
#           Jangan set CHROMIUM_REMOTE_DEBUGGING_HOST=0.0.0.0 kecuali paham risiko.
# ═══════════════════════════════════════════════════════════════════════════════

# ─── run-chromium-daemon.sh ──────────────────────────────────────────────────
# Launch Chromium headless sebagai daemon dengan remote debugging.
# Memory-saving flags (komentar penjelas di tiap baris):
#   --headless=new              : headless mode baru (lebih efisien)
#   --no-sandbox                : container tidak butuh sandbox (butuh CAP_SYS_ADMIN)
#   --disable-dev-shm-usage     : pakai /tmp bukan /dev/shm (container kecil)
#   --no-zygote                 : skip zygote process (-50MB per fork)
#   --disable-gpu               : tanpa GPU (headless tidak butuh)
#   --disable-software-rasterizer
#   --disable-extensions        : no extensions
#   --disable-default-apps      : no default apps
#   --disable-translate         : no translate popup
#   --disable-sync              : no account sync
#   --disable-background-networking
#   --disable-component-update
#   --disable-popup-blocking    : popup tidak numpuk RAM
#   --disable-prompt-on-repost
#   --disable-metrics           : no UMA
#   --disable-breakpad          : no crash reporter
#   --disable-features=...      : matikan fitur berat
#   --disable-site-isolation    : BIG memory saver — matikan per-origin process model
#   --disable-features=IsolateOrigins,site-per-process
#   --memory-pressure-off       : jangan throttle karena memory pressure
#   --disable-background-timer-throttling : timer jangan ditrottle
#   --disable-backgrounding-occluded-windows
#   --disable-renderer-backgrounding
#   --disable-ipc-flooding-protection
#   --js-flags=--max-old-space-size=96 : cap V8 heap per renderer (MB)
#   --disk-cache-dir=...        : cache web di disk, bukan RAM
#   --user-data-dir=...         : profile persistent (cookies, localStorage)
#   --remote-debugging-port=9222 : WebSocket untuk puppeteer.connect()
#   --remote-debugging-address=127.0.0.1 : HANYA localhost
RUN cat > /usr/local/bin/run-chromium-daemon.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CHROMIUM_BIN="${PUPPETEER_EXECUTABLE_PATH:-/usr/bin/chromium}"
RDEBUG_HOST="${CHROMIUM_REMOTE_DEBUGGING_HOST:-127.0.0.1}"
RDEBUG_PORT="${CHROMIUM_REMOTE_DEBUGGING_PORT:-9222}"
DISK_CACHE="${CHROMIUM_DISK_CACHE_DIR:-/data/chromium-cache}"
USER_DATA="${CHROMIUM_USER_DATA_DIR:-/data/chromium-profile}"
RENDERER_HEAP="${CHROMIUM_RENDERER_MAX_OLD_SPACE_MB:-96}"

mkdir -p "$DISK_CACHE" "$USER_DATA"
chmod 1777 "$DISK_CACHE" "$USER_DATA" 2>/dev/null || true

echo "[chromium-daemon] starting: $CHROMIUM_BIN"
echo "[chromium-daemon] remote-debugging: ws://${RDEBUG_HOST}:${RDEBUG_PORT}"
echo "[chromium-daemon] disk-cache: $DISK_CACHE"
echo "[chromium-daemon] user-data: $USER_DATA"
echo "[chromium-daemon] renderer V8 heap cap: ${RENDERER_HEAP}MB"

# Test binary ada
[ -x "$CHROMIUM_BIN" ] || { echo "[chromium-daemon] FATAL: $CHROMIUM_BIN tidak ada/executable" >&2; sleep 5; exit 1; }

exec "$CHROMIUM_BIN" \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --no-zygote \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-extensions \
  --disable-default-apps \
  --disable-translate \
  --disable-sync \
  --disable-background-networking \
  --disable-component-update \
  --disable-popup-blocking \
  --disable-prompt-on-repost \
  --disable-metrics \
  --disable-breakpad \
  --disable-features=TranslateUI,BlinkGenPropertyTrees,site-per-process,IsolateOrigins,SharedArrayBuffer,MediaRouter \
  --disable-site-isolation \
  --memory-pressure-off \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --disable-ipc-flooding-protection \
  --no-first-run \
  --no-default-browser-check \
  --enable-features=NetworkService,NetworkServiceInProcess \
  --js-flags="--max-old-space-size=${RENDERER_HEAP} --max-semi-space-size=16" \
  --disk-cache-dir="$DISK_CACHE" \
  --user-data-dir="$USER_DATA" \
  --remote-debugging-port="$RDEBUG_PORT" \
  --remote-debugging-address="$RDEBUG_HOST" \
  about:blank
SCRIPT

# ─── chromium-pool.js — Node helper untuk bounded tab pool ────────────────────
# Usage di app Node:
#   const pool = require('/usr/local/lib/chromium-pool');
#   const html = await pool.withPage(async page => await page.content());
#   // pool auto-akquire tab, jalankan fn, release tab ke pool
#
# Pool ini membatasi concurrency ke PUPPETEER_MAX_CONCURRENT_TABS (default 64).
# Request ke-65 di-antri (queue). Tab idle > TTL di-close otomatis.
# 'Miliaran proses' = jutaan panggilan withPage() di-antri di pool ini.
RUN mkdir -p /usr/local/lib && cat > /usr/local/lib/chromium-pool.js <<'POOLEOF'
// /usr/local/lib/chromium-pool.js — bounded tab pool untuk shared Chromium daemon
// Semua app Node require modul ini; jangan puppeteer.launch() langsung.
'use strict';
const puppeteer = require('puppeteer');

const WS = process.env.PUPPETEER_WS_ENDPOINT || 'ws://127.0.0.1:9222';
const MAX_TABS = parseInt(process.env.PUPPETEER_MAX_CONCURRENT_TABS || '64', 10);
const TAB_IDLE_TTL_MS = parseInt(process.env.PUPPETEER_TAB_IDLE_TTL_MS || '60000', 10);
const TAB_HARD_TTL_MS = parseInt(process.env.PUPPETEER_TAB_HARD_TTL_MS || '300000', 10);
const NAV_TIMEOUT_MS = parseInt(process.env.PUPPETEER_NAV_TIMEOUT_MS || '30000', 10);
const RECONNECT_DELAY_MS = 2000;

let _browser = null;
let _connecting = null;
const _idle = [];          // pool of free tabs
const _waiters = [];       // queue of {resolve, reject}
let _activeCount = 0;
const _tabBirth = new WeakMap();
const _tabLastUsed = new WeakMap();

function log(...a)  { console.log('[chromium-pool]', ...a); }
function warn(...a) { console.warn('[chromium-pool] WARN', ...a); }

async function getBrowser() {
  if (_browser && _browser.isConnected()) return _browser;
  if (_connecting) return _connecting;
  _connecting = (async () => {
    for (let attempt = 1; ; attempt++) {
      try {
        _browser = await puppeteer.connect({ browserWSEndpoint: WS });
        log('connected to', WS);
        _browser.on('disconnected', () => {
          warn('browser disconnected, will reconnect on next request');
          _browser = null;
          _idle.length = 0;  // tab references invalid
        });
        return _browser;
      } catch (e) {
        warn(`connect attempt ${attempt} failed: ${e.message}`);
        await new Promise(r => setTimeout(r, RECONNECT_DELAY_MS));
      }
    }
  })();
  try { return await _connecting; } finally { _connecting = null; }
}

async function newTab() {
  const browser = await getBrowser();
  const [page] = await Promise.all([browser.newPage()]);
  await page.setDefaultNavigationTimeout(NAV_TIMEOUT_MS);
  await page.setDefaultTimeout(NAV_TIMEOUT_MS);
  // Block resource heavy types by default (override per-call jika perlu)
  await page.setRequestInterception(true).catch(() => {});
  page.on('request', req => {
    const type = req.resourceType();
    if (type === 'image' || type === 'media' || type === 'font') {
      req.abort().catch(() => {});
    } else {
      req.continue().catch(() => {});
    }
  });
  _tabBirth.set(page, Date.now());
  _tabLastUsed.set(page, Date.now());
  return page;
}

function recycleTab(page) {
  // Tutup tab jika sudah hard TTL atau error
  const birth = _tabBirth.get(page) || 0;
  if (Date.now() - birth > TAB_HARD_TTL_MS) {
    page.close().catch(() => {});
    return false;
  }
  // Reset state: clear cookies, clear cache, go to about:blank
  page.deleteCookie({}).catch(() => {});
  page.goto('about:blank', { waitUntil: 'domcontentloaded' }).catch(() => {});
  _tabLastUsed.set(page, Date.now());
  _idle.push(page);
  return true;
}

function dispatchWaiter() {
  if (_waiters.length === 0) return;
  if (_idle.length > 0) {
    const page = _idle.shift();
    _activeCount++;
    _waiters.shift().resolve(page);
  } else if (_activeCount < MAX_TABS) {
    _activeCount++;
    newTab().then(page => _waiters.shift().resolve(page))
            .catch(e => { _activeCount--; _waiters.shift().reject(e); });
  }
}

async function acquire() {
  // Coba idle dulu
  if (_idle.length > 0) {
    const page = _idle.shift();
    _activeCount++;
    _tabLastUsed.set(page, Date.now());
    return page;
  }
  if (_activeCount < MAX_TABS) {
    _activeCount++;
    try { return await newTab(); }
    catch (e) { _activeCount--; throw e; }
  }
  // Antri
  return new Promise((resolve, reject) => {
    _waiters.push({ resolve, reject });
  });
}

function release(page) {
  _activeCount = Math.max(0, _activeCount - 1);
  if (page && !page.isClosed?.()) {
    if (!recycleTab(page)) {
      // tab ditutup oleh recycle karena hard TTL — biarkan
    }
  }
  dispatchWaiter();
}

/**
 * withPage(fn): acquire tab, jalankan fn(page), release ke pool.
 * fn boleh return value; akan diteruskan ke caller.
 * Error di fn tetap me-release tab (dengan recycle).
 */
async function withPage(fn) {
  const page = await acquire();
  try {
    return await fn(page);
  } finally {
    release(page);
  }
}

// Reaper: tutup tab idle yang sudah tidak dipakai lama
setInterval(() => {
  const now = Date.now();
  for (let i = _idle.length - 1; i >= 0; i--) {
    const page = _idle[i];
    const last = _tabLastUsed.get(page) || 0;
    const birth = _tabBirth.get(page) || 0;
    if (now - last > TAB_IDLE_TTL_MS || now - birth > TAB_HARD_TTL_MS) {
      _idle.splice(i, 1);
      page.close().catch(() => {});
    }
  }
}, 15000).unref();

function stats() {
  return { active: _activeCount, idle: _idle.length, queued: _waiters.length, max: MAX_TABS, ws: WS };
}

module.exports = { withPage, acquire, release, stats, getBrowser };
POOLEOF

# ─── init-dbus.sh — start dbus-daemon untuk Chromium ──────────────────────────
# v6.1: Fix 'Failed to connect to socket /run/dbus/system_bus_socket'
# Chromium butuh system bus untuk beberapa fitur (notification, portal, dll).
# Tanpa ini, launch Chromium keluarkan 6 baris ERROR dbus di log per launch.
RUN cat > /usr/local/bin/init-dbus.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
mkdir -p /run/dbus /var/run/dbus
# Generate config default kalau belum ada (idempotent)
if [ ! -f /etc/dbus-1/system.conf ] && command -v dbus-daemon >/dev/null 2>&1; then
  # Pakai config minimal yang listen di unix:/run/dbus/system_bus_socket
  cat > /tmp/dbus-system.conf <<'CONF'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path=/run/dbus/system_bus_socket</listen>
  <auth>EXTERNAL</auth>
  <auth>ANONYMOUS</auth>
  <allow_anonymous/>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
  cp /tmp/dbus-system.conf /etc/dbus-1/system.conf
  rm -f /tmp/dbus-system.conf
fi
# Start dbus-daemon kalau belum running
if command -v dbus-daemon >/dev/null 2>&1; then
  if [ ! -S /run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork --nopidfile 2>/dev/null \
      && echo "[init-dbus] dbus-daemon started" \
      || echo "[init-dbus] WARN: dbus-daemon start gagal (non-fatal)"
  else
    echo "[init-dbus] socket sudah ada, skip"
  fi
else
  echo "[init-dbus] dbus-daemon tidak tersedia, skip"
fi
# Set DBUS_SESSION_BUS_ADDRESS & DBUS_SYSTEM_BUS_ADDRESS untuk semua child process
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
SCRIPT

# ─── optimize-system.sh ───────────────────────────────────────────────────────
RUN cat > /usr/local/bin/optimize-system.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true
ulimit -u 65535   2>/dev/null || true
mkdir -p /data/root/.cache /data/root/.npm /data/root/.pm2 /data/tmp /data/ollama/models
chmod 700 /data/root /data/root/.pm2 /data/root/.npm 2>/dev/null || true
chmod 1777 /data/tmp /tmp 2>/dev/null || true
npm config set prefer-offline true --global >/dev/null 2>&1 || true
npm config set audit false --global         >/dev/null 2>&1 || true
npm config set fund false --global          >/dev/null 2>&1 || true
# Bersihkan tmp lama, tapi JANGAN hapus /tmp yang baru ditulis oleh proses lain
find /tmp -mindepth 1 -maxdepth 1 -mmin +60 -delete 2>/dev/null || true
echo "[optimize-system] selesai."
SCRIPT

# ─── kstatus ──────────────────────────────────────────────────────────────────
# v3: tambah info ollama + per-app RSS live
RUN cat > /usr/local/bin/kstatus <<'SCRIPT'
#!/usr/bin/env bash
set +e
C='\033[1;36m'; R='\033[0m'
printf "\n${C}== System ==${R}\n"; uptime; free -h; df -h / /data 2>/dev/null || df -h

# Cgroup memory info
printf "\n${C}== Container Memory Limit ==${R}\n"
if [ -f /sys/fs/cgroup/memory.max ]; then
  V=$(cat /sys/fs/cgroup/memory.max)
  if [ "$V" = "max" ]; then
    echo "  cgroup v2: no limit"
  else
    echo "  cgroup v2: $(( V / 1024 / 1024 )) MB"
  fi
elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
  V=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
  if [ "$V" -ge 1099511627776 ]; then
    echo "  cgroup v1: no limit"
  else
    echo "  cgroup v1: $(( V / 1024 / 1024 )) MB"
  fi
else
  echo "  cgroup: not available (using host RAM)"
fi

printf "\n${C}== Network ==${R}\n"; ip -br addr 2>/dev/null; ss -lntup 2>/dev/null | head -n 30
printf "\n${C}== Launcher proses ==${R}\n"
LAUNCHER_MODE="${LAUNCHER_MODE:-adaptive}"
if [ "$LAUNCHER_MODE" = "adaptive" ]; then
  echo "Mode: adaptive launcher (index.js v6 — Debian + Ollama + Chromium daemon)"
  pgrep -fa "node.*adaptive-launcher\|node.*launcher/index.js" 2>/dev/null | head -n 5 || echo "  (tidak aktif)"
else
  echo "Mode: PM2"
  pm2 status 2>/dev/null
fi

printf "\n${C}== Top proses (RAM) ==${R}\n"; ps -eo pid,stat,pcpu,pmem,nice,rss,comm --sort=-rss | head -n 18

printf "\n${C}== Per-app RSS live ==${R}\n"
for pat in "kfai-nodejs" "kfai-mcp" "ttt" "catur" "ollama" "cloudflared" "chromium-daemon" "adaptive-launcher"; do
  for pid in $(pgrep -f "$pat" 2>/dev/null | head -1); do
    rss=$(awk '/VmRSS:/{printf "%d", $2/1024}' /proc/$pid/status 2>/dev/null || echo "?")
    nice_val=$(ps -p $pid -o ni= 2>/dev/null | tr -d ' ')
    printf "  %-20s pid=%-6s rss=%-6sMB nice=%s\n" "$pat" "$pid" "$rss" "$nice_val"
  done
done

printf "\n${C}== Ollama ==${R}\n"
if command -v ollama >/dev/null 2>&1; then
  ollama --version 2>/dev/null || echo "  version: N/A"
  echo "  host: ${OLLAMA_HOST:-0.0.0.0:11434}"
  echo "  models dir: ${OLLAMA_MODELS:-/data/ollama/models}"
  ollama list 2>/dev/null || echo "  (models: belum ada / ollama tidak berjalan)"
  # Test API
  curl -sf http://${OLLAMA_HOST:-0.0.0.0:11434}/api/tags 2>/dev/null | head -c 200 || echo "  API: belum responsif"
else
  echo "  (ollama tidak terinstall)"
fi

printf "\n${C}== Chromium daemon (Puppeteer-at-scale) ==${R}\n"
if pgrep -f "/usr/bin/chromium.*--remote-debugging-port" >/dev/null 2>&1; then
  echo "  status: RUNNING"
  echo "  WS endpoint: ${PUPPETEER_WS_ENDPOINT:-ws://127.0.0.1:9222}"
  echo "  max concurrent tabs: ${PUPPETEER_MAX_CONCURRENT_TABS:-64}"
  # Hitung tab aktif via /json (Chromium DevTools Protocol)
  TAB_COUNT=$(curl -sf http://${CHROMIUM_REMOTE_DEBUGGING_HOST:-127.0.0.1}:${CHROMIUM_REMOTE_DEBUGGING_PORT:-9222}/json 2>/dev/null | grep -c '"type": "page"' || echo 0)
  echo "  active tabs: ${TAB_COUNT}"
  # Renderer process count (bisa kasih estimasi RAM: ~ tabs x 20MB)
  REND_COUNT=$(pgrep -c -f 'chromium.*--type=renderer' 2>/dev/null || echo 0)
  echo "  renderer processes: ${REND_COUNT} (est RAM: $(( REND_COUNT * 20 ))MB)"
  # Total Chromium RSS
  CHROM_RSS=$(ps -eo rss,comm | awk '/chromium/{s+=$1} END{printf "%d", s/1024}')
  echo "  total Chromium RSS: ${CHROM_RSS:-0}MB"
else
  echo "  status: NOT RUNNING (jalankan kstatus lagi setelah startup)"
fi
echo "  pool helper: node -e \"console.log(require('/usr/local/lib/chromium-pool').stats())\""

printf "\n${C}== OOM protection ==${R}\n"
for pat in "adaptive-launcher" earlyoom "node.*server" "node.*kfai" "node.*ttt" "node.*catur" ollama sshd cloudflared chromium; do
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    score=$(cat /proc/$pid/oom_score_adj 2>/dev/null || echo "?")
    comm=$(ps -p $pid -o comm= 2>/dev/null || echo "?")
    printf "  pid %-6s  oom=%-6s  %s\n" "$pid" "$score" "$comm"
  done
done

printf "\n${C}== earlyoom ==${R}\n"
pgrep -fa earlyoom 2>/dev/null || echo "  (tidak aktif)"

printf "\n${C}== DNS cache (nscd) ==${R}\n"
nscd -g 2>/dev/null | grep -E 'cache hit|request' | head -n 10 || echo "  nscd tidak aktif"

printf "\n${C}== Nice values ==${R}\n"
ps -eo pid,nice,comm --sort=nice | grep -E 'node|cloudflared|ollama' | head -n 10 || true
SCRIPT

# ─── start-all.sh ─────────────────────────────────────────────────────────────
# v4: tambah Ollama service (animest) + Ubuntu 24.04 base
RUN cat > /usr/local/bin/start-all.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# ── 0. Direktori ───────────────────────────────────────────────────────────
mkdir -p /data/root /data/ssh /data/apps /data/bin /data/launcher \
         /data/ollama/models /run/sshd /data/root/.pm2 /data/root/.npm /data/tmp
chmod 700 /data/root /data/ssh
chmod 1777 /data/tmp /tmp || true

# ── 0a. Bersihkan orphan proses Node/PM2 dari run sebelumnya ──────────────
# Hanya kill proses lama, BUKAN yang baru dimulai oleh script ini
pkill -f "node.*adaptive-launcher\|node.*launcher/index.js" 2>/dev/null && echo "[start-all] clean stale launcher" || true
pkill -f "PM2.*God Daemon" 2>/dev/null && echo "[start-all] clean stale PM2" || true
pkill -f "ollama serve" 2>/dev/null && echo "[start-all] clean stale ollama" || true
# v6: bersihkan chromium lama (daemon + renderer + gpu-process)
pkill -f "/usr/bin/chromium" 2>/dev/null && echo "[start-all] clean stale chromium" || true
sleep 1

# ── 1. Optimasi sistem (paralel) ───────────────────────────────────────────
/usr/local/bin/optimize-system.sh &
/usr/local/bin/resource-optimizer.sh &

# ── 1b. v6.1: Start dbus untuk Chromium (fix 'Failed to connect to bus') ────
/usr/local/bin/init-dbus.sh

# ── 2. SSH host keys ───────────────────────────────────────────────────────
if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
  echo "SSH: copy pre-generated host keys..."
  cp /etc/ssh/pregenerated/ssh_host_rsa_key*     /data/ssh/
  cp /etc/ssh/pregenerated/ssh_host_ecdsa_key*   /data/ssh/
  cp /etc/ssh/pregenerated/ssh_host_ed25519_key* /data/ssh/
  chmod 600 /data/ssh/ssh_host_*_key
  chmod 644 /data/ssh/ssh_host_*_key.pub
fi

# ── 3. Password root ───────────────────────────────────────────────────────
ROOT_PASS="${ROOT_PASSWORD:-${PASSWORD:-}}"
if [ -z "$ROOT_PASS" ]; then
  if [ -f /data/root/.generated-root-password ]; then
    ROOT_PASS="$(cat /data/root/.generated-root-password)"
  else
    ROOT_PASS="$(openssl rand -base64 18)"
    printf '%s' "$ROOT_PASS" > /data/root/.generated-root-password
    chmod 600 /data/root/.generated-root-password
  fi
  echo "⚠  WARNING: ROOT_PASSWORD belum diset. Password SSH sementara: $ROOT_PASS"
fi
echo "root:${ROOT_PASS}" | chpasswd

# ── 4. SSH authorized_keys ─────────────────────────────────────────────────
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p /data/root/.ssh && chmod 700 /data/root/.ssh
  echo "$SSH_PUBLIC_KEY" > /data/root/.ssh/authorized_keys
  chmod 600 /data/root/.ssh/authorized_keys
fi

# ── 5. SSH port ────────────────────────────────────────────────────────────
[ "${SSH_PORT:-22}" != "22" ] && sed -i "s/^Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config

# ── 6. .bashrc ────────────────────────────────────────────────────────────
cat > /data/root/.bashrc <<'BASHRC'
export NODE_ENV=production
export HISTSIZE=5000
export HISTFILESIZE=10000
export EDITOR=nano
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias pms='pm2 status'
alias pml='pm2 logs --lines 80'
alias pmr='pm2 restart all'
alias psa='ps aux --sort=-%mem | head -n 20'
alias ports='ss -lntup'
alias cls='clear'
alias lmode='echo $LAUNCHER_MODE'
alias ostatus='ollama list 2>/dev/null || echo "ollama not running"'
fastfetch 2>/dev/null || true
echo
echo "  /data (persistent) | /root → /data/root"
echo "  LAUNCHER_MODE=${LAUNCHER_MODE:-adaptive}  |  kstatus"
echo "  Edit launcher: nano /data/launcher/index.js"
echo "  Ollama API: http://${OLLAMA_HOST:-0.0.0.0:11434}"
echo "  Models: ${OLLAMA_MODELS:-/data/ollama/models}"
echo "  Puppeteer WS: ${PUPPETEER_WS_ENDPOINT:-ws://127.0.0.1:9222} (max tabs: ${PUPPETEER_MAX_CONCURRENT_TABS:-64})"
echo
node -v; npm -v; cloudflared --version 2>/dev/null; ollama --version 2>/dev/null; echo
BASHRC

# ── 7. Tunggu optimasi selesai ─────────────────────────────────────────────
wait

# ── 8. Clone / pull repos PARALEL ─────────────────────────────────────────
/usr/local/bin/bootstrap-apps.sh &
BOOTSTRAP_PID=$!

# ── 9a. Mulai earlyoom (proteksi OOM proaktif) ───────────────────────────
# earlyoom bunuh proses boros RAM sebelum OOM killer kernel, melindungi launcher+sshd+ollama
# -r 3600: report interval 1 jam
# -m 10:    trigger saat MemAvailable < 10%
# --avoid "(^node.*adaptive|^node.*launcher|^/usr/sbin/sshd|^earlyoom|^ollama)": jangan bunuh ini
# --prefer "(^node.*kfai|^node.*ttt|^node.*catur|^cloudflared)": bunuh ini dulu
if command -v earlyoom >/dev/null 2>&1; then
  echo "[start-all] mulai earlyoom..."
  earlyoom -r 3600 -m 10 -s \
    --avoid '(^node.*adaptive|^node.*launcher/index|^/usr/sbin/sshd|^earlyoom|^node.*PM2|^ollama|chromium.*--remote-debugging-port)' \
    --prefer '(^node.*kfai|^node.*ttt|^node.*catur|^cloudflared|chromium.*--type=renderer|chromium.*--type=gpu-process)' \
    >/var/log/earlyoom.log 2>&1 &
else
  echo "[start-all] earlyoom tidak tersedia, andalkan oom-watchdog."
fi

# ── 9b. Layanan pendukung ───────────────────────────────────────────────────
# nscd: coba service dulu, fallback ke binary langsung
if command -v service >/dev/null 2>&1; then
  service nscd start 2>/dev/null || nscd 2>/dev/null || true
else
  nscd 2>/dev/null || true
fi

/usr/sbin/sshd -D -e &
/usr/local/bin/oom-watchdog.sh &

# ── 9c. v6.1: Pastikan /dev/shm cukup besar untuk Chromium ─────────────────
# Chromium pakai /dev/shm untuk shared memory antar proses. Default container
# sering cuma 64MB — bikin crash tab banyak. Mount tmpfs kalau belum besar.
SHM_SIZE_MB=$(df -m /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
if [ -n "${SHM_SIZE_MB:-}" ] && [ "${SHM_SIZE_MB}" -lt 256 ] 2>/dev/null; then
  echo "[start-all] /dev/shm hanya ${SHM_SIZE_MB}MB, mount tmpfs 512MB"
  mount -t tmpfs -o size=512m,mode=1777 tmpfs /dev/shm 2>/dev/null || true
fi
# Set TMPDIR ke /data/tmp (lebih besar dari default /tmp di container kecil)
export TMPDIR=/data/tmp
mkdir -p "$TMPDIR" 2>/dev/null || true

# ── 10. Tunggu bootstrap repo selesai ──────────────────────────────────────
wait $BOOTSTRAP_PID || echo "WARN: bootstrap selesai dengan error."

# ── 11. Pilih launcher ─────────────────────────────────────────────────────
LAUNCHER_MODE="${LAUNCHER_MODE:-adaptive}"
echo "[start-all] LAUNCHER_MODE=${LAUNCHER_MODE}"

if [ "$LAUNCHER_MODE" = "pm2" ]; then
  # ── PM2 mode (v4: tambah ollama/animest) ────────────────────────────────────
  echo "[start-all] mode PM2"
  cat > /data/ecosystem.config.js <<'PM2EOF'
const fs = require('fs');

// cgroup-aware memory detection
function detectContainerMemMB() {
  try {
    const v = fs.readFileSync('/sys/fs/cgroup/memory.max', 'utf8').trim();
    if (v !== 'max' && /^\d+$/.test(v)) return Math.floor(Number(v) / 1024 / 1024);
  } catch {}
  try {
    const v = fs.readFileSync('/sys/fs/cgroup/memory/memory.limit_in_bytes', 'utf8').trim();
    const n = Number(v);
    if (/^\d+$/.test(v) && n > 0 && n < 1024 * 1024 * 1024 * 1024) return Math.floor(n / 1024 / 1024);
  } catch {}
  try {
    const m = fs.readFileSync('/proc/meminfo','utf8').match(/MemTotal:\s+(\d+)/);
    return m ? Math.floor(parseInt(m[1])/1024) : 2048;
  } catch { return 2048; }
}

const memTotal = detectContainerMemMB();
const BUDGET = Math.floor(memTotal * 0.75);
// Distribusi v6 (7 app — +chromium-daemon): kfai 28%, mcp 20%, ollama 18%, chromium 12%, ttt 8%, catur 8%, cf 6%
const mem = {
  kfai:     process.env.KFAI_MAX_MEMORY     || Math.min(1024, Math.floor(BUDGET*0.28))+'M',
  mcp:      process.env.KFAI_MCP_MAX_MEMORY || Math.min(1280, Math.floor(BUDGET*0.20))+'M',
  ollama:   process.env.OLLAMA_MAX_MEMORY   || Math.min(768,  Math.floor(BUDGET*0.18))+'M',
  chromium: process.env.CHROMIUM_MAX_MEMORY || Math.min(512,  Math.floor(BUDGET*0.12))+'M',
  ttt:      process.env.TTT_MAX_MEMORY       || Math.min(384,  Math.floor(BUDGET*0.08))+'M',
  catur:    process.env.CATUR_MAX_MEMORY     || Math.min(384,  Math.floor(BUDGET*0.08))+'M',
  cf:       process.env.CF_MAX_MEMORY         || '96M',
};
const nodeArgs = '--expose-gc --max-semi-space-size=64 --max-http-header-size=16384';
module.exports = { apps: [
  { name:'cloudflared-ssh', script:'/usr/local/bin/run-cloudflared.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:5000,
    exp_backoff_restart_delay:300, max_memory_restart:mem.cf, kill_timeout:5000 },
  { name:'kfai-nodejs', script:'/usr/local/bin/run-kfai-nodejs.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.kfai, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'kfai-mcp', script:'/usr/local/bin/run-kfai-mcp.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.mcp, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'chromium-daemon', script:'/usr/local/bin/run-chromium-daemon.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:3000,
    exp_backoff_restart_delay:300, max_memory_restart:mem.chromium, kill_timeout:8000 },
  { name:'animest', script:'/usr/local/bin/run-ollama.sh', interpreter:'bash',
    autorestart:true, max_restarts:8, min_uptime:'15s', restart_delay:5000,
    exp_backoff_restart_delay:500, max_memory_restart:mem.ollama, kill_timeout:15000,
    env:{
      OLLAMA_HOST: process.env.OLLAMA_HOST || '0.0.0.0:11434',
      OLLAMA_MODELS: process.env.OLLAMA_MODELS || '/data/ollama/models',
    } },
  { name:'ttt', script:'/usr/local/bin/run-ttt.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.ttt, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'catur', script:'/usr/local/bin/run-catur.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.catur, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
]};
PM2EOF
  exec pm2-runtime /data/ecosystem.config.js

else
  # ── Adaptive launcher mode (default, v4 — Ubuntu + Ollama) ────────────────
  echo "[start-all] mode adaptive launcher"
  # Pastikan launcher ada di /data (persistent – bisa di-edit via SSH)
  [ ! -f /data/launcher/index.js ] && cp /usr/local/bin/adaptive-launcher.js /data/launcher/index.js
  exec node /data/launcher/index.js
fi
SCRIPT

# ─── chmod semua ──────────────────────────────────────────────────────────────
RUN chmod +x \
      /usr/local/bin/resource-optimizer.sh \
      /usr/local/bin/oom-watchdog.sh \
      /usr/local/bin/bootstrap-apps.sh \
      /usr/local/bin/clear-app-port-env.sh \
      /usr/local/bin/upgrade-langchain-packages.sh \
      /usr/local/bin/ensure-node-app-deps.sh \
      /usr/local/bin/run-node-app.sh \
      /usr/local/bin/run-kfai-nodejs.sh \
      /usr/local/bin/run-kfai-mcp.sh \
      /usr/local/bin/run-ttt.sh \
      /usr/local/bin/run-catur.sh \
      /usr/local/bin/run-animest.sh \
      /usr/local/bin/run-ollama.sh \
      /usr/local/bin/run-chromium-daemon.sh \
      /usr/local/bin/init-dbus.sh \
      /usr/local/bin/run-cloudflared.sh \
      /usr/local/bin/optimize-system.sh \
      /usr/local/bin/kstatus \
      /usr/local/bin/start-all.sh

# ─── Stabilisasi: Healthcheck + stop signal ─────────────────────────────────
# Cek SSH port setiap 60s; start-period 60s agar container stabil dulu sebelum dicek
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
  CMD ss -lnt | grep -q ":${SSH_PORT:-22}\b" || exit 1

# Pastikan SIGTERM diterima dengan baik oleh tini/sshd/launcher saat docker stop
STOPSIGNAL SIGTERM

EXPOSE 22 11434

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-all.sh"]
