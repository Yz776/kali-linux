FROM kalilinux/kali-rolling

# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════════
# Catatan perubahan (v3 — stabil + cepat):
#   • LANGCHAIN_AUTO_UPGRADE default = false  (sebelumnya true → npm install @latest tiap boot)
#   • NODE_OPTIONS ditambah --max-semi-space-size=64 (GC lebih efisien)
#   • --gc-interval=100 DIHAPUS dari NODE_OPTIONS (tidak diizinkan Node.js di NODE_OPTIONS)
#   • PATH tetap, untuk compat dengan script existing
#   • v3.2 — tambah aplikasi "animest" (https://github.com/Yz776/animest.git)
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
    PRESSURE_AVAIL_THRESHOLD_MB=128

# Repo config
ENV KFAI_REPO=https://github.com/Yz776/kfai-nodejs.git \
    KFAI_BRANCH=master \
    KFAI_MCP_REPO=https://github.com/Yz776/kfai-mcp.git \
    KFAI_MCP_BRANCH=master \
    TTT_REPO=https://github.com/Yz776/ttt.git \
    TTT_BRANCH= \
    NEXCLOUD_REPO=https://github.com/Yz776/nexcloud.git \
    NEXCLOUD_BRANCH= \
    CATUR_REPO=https://github.com/Yz776/catur.git \
    CATUR_BRANCH= \
    ANIMEST_REPO=https://github.com/Yz776/animest.git \
    ANIMEST_BRANCH= \
    KFAI_DIR=/data/apps/kfai-nodejs \
    KFAI_MCP_DIR=/data/apps/kfai-mcp \
    TTT_DIR=/data/apps/ttt \
    NEXCLOUD_DIR=/data/apps/nexcloud \
    CATUR_DIR=/data/apps/catur \
    ANIMEST_DIR=/data/apps/animest \
    LAUNCHER_DIR=/data/launcher

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
      iputils-ping dnsutils bind9-dnsutils unzip \
      build-essential python3 python3-pip \
      earlyoom nscd \
    ; \
    for pkg in \
      nmap masscan whois dnsrecon \
      nikto whatweb wafw00f \
      gobuster ffuf dirb nuclei \
      sslscan sslyze ssh-audit \
      yara lynis \
      enum4linux-ng smbclient chkrootkit rkhunter \
    ; do \
      apt-get install -y --no-install-recommends "$pkg" \
        || echo "WARN: $pkg tidak tersedia."; \
    done; \
    for pkg in \
      exiftool binwalk radare2 checksec patchelf \
      ltrace strace gdb upx-ucl theharvester \
    ; do \
      apt-get install -y --no-install-recommends "$pkg" \
        || echo "WARN: $pkg tidak tersedia."; \
    done; \
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
# LAYER 4 – Direktori + SSH host keys pre-generated
# ═══════════════════════════════════════════════════════════════════════════════
RUN set -eux; \
    mkdir -p /run/sshd /etc/ssh/sshd_config.d \
             /data/root /data/ssh /data/apps /data/bin /data/launcher; \
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
# ADAPTIVE LAUNCHER v3 – index.js
# Perubahan utama dari v2:
#   1. Deteksi RAM via cgroup (v1 + v2), fallback os.totalmem
#   2. Cap total app memory ke APP_MEM_BUDGET_PERCENT (default 75%) RAM container
#   3. Mem MONITOR — TIDAK pernah kill. Hanya pantau RSS + GC nudge.
#   4. Crash-loop protection: max CRASH_LOOP_MAX restart, backoff otomatis
#   5. Memory pressure: graduated response (nudge → pause → kill hanya darurat)
#   6. Dynamic memory rebalancer: limit otomatis naik/turun sesuai kebutuhan nyata
#   7. CPU rebalance: nice adaptif berdasarkan interaksi user
#   8. NODE_OPTIONS per-app: --max-semi-space-size=64 (gc-interval hanya via CLI)
#   9. v3.1 — tambah app "catur" ke daftar APPS, redistribute memory budget
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /data/launcher/index.js <<'LAUNCHEREOF'
// /data/launcher/index.js  (v3.1 — dinamis, minimal restart, +catur)
// Adaptive multi-app launcher – mengelola kfai-nodejs, kfai-mcp, ttt, nexcloud,
// catur, cloudflared dengan dynamic memory allocation, CPU priority adaptif,
// graduated pressure response.
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
//   KFAI_MEMORY_MB / KFAI_MCP_MEMORY_MB / TTT_MEMORY_MB / NEXCLOUD_MEMORY_MB / CATUR_MEMORY_MB / CF_MEMORY_MB
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
const NEXCLOUD_DIR = process.env.NEXCLOUD_DIR || '/data/apps/nexcloud';
const CATUR_DIR    = process.env.CATUR_DIR    || '/data/apps/catur';
const ANIMEST_DIR  = process.env.ANIMEST_DIR  || '/data/apps/animest';

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

// Distribusi v3.2 (6 app): kfai 33%, mcp 23%, ttt 11%, nexcloud 11%, catur 11%, animest 11%
// (cf di luar budget, kecil)
const KFAI_MEM     = Number(process.env.KFAI_MEMORY_MB     || Math.min(1024, Math.floor(APP_BUDGET_MB * 0.33)));
const KFAI_MCP_MEM = Number(process.env.KFAI_MCP_MEMORY_MB || Math.min(1280, Math.floor(APP_BUDGET_MB * 0.23)));
const TTT_MEM      = Number(process.env.TTT_MEMORY_MB       || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.11)));
const NEXCLOUD_MEM = Number(process.env.NEXCLOUD_MEMORY_MB  || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.11)));
const CATUR_MEM    = Number(process.env.CATUR_MEMORY_MB     || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.11)));
const ANIMEST_MEM  = Number(process.env.ANIMEST_MEMORY_MB   || Math.min(384,  Math.floor(APP_BUDGET_MB * 0.11)));
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
    name:     'cloudflared-ssh',
    script:   '/usr/local/bin/run-cloudflared.sh',
    memoryMB: CF_MEM,
    nice:     NORMAL_NICE + 3,
    priority: 8, // penting untuk akses SSH
  },
  {
    name:     'ttt',
    script:   '/usr/local/bin/run-ttt.sh',
    memoryMB: TTT_MEM,
    nice:     NORMAL_NICE,
    priority: 5,
  },
  {
    name:     'nexcloud',
    script:   '/usr/local/bin/run-nexcloud.sh',
    memoryMB: NEXCLOUD_MEM,
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
  {
    name:     'animest',
    script:   '/usr/local/bin/run-animest.sh',
    memoryMB: ANIMEST_MEM,
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
    const now = Date.now();
    if (rss > dynLimit * softRatio && (now - state.lastWarnAt) > 30000) {
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
      if (app.name === 'cloudflared-ssh') continue;
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
      if (app.name === 'cloudflared-ssh' || app.name === INTERACTIVE_APP) continue;
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
      if (app.name === 'cloudflared-ssh' || app.name === INTERACTIVE_APP) continue;
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
  // CATATAN: --gc-interval TIDAK diizinkan di NODE_OPTIONS (V8 flag restricted)
  // Jika perlu gc-interval tuning, pass via CLI di launcher script.
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
    NODE_OPTIONS: nodeOpts,
    NODE_ENV: 'production',
    APP_RESOURCE_MEMORY_MB: String(memMB),
    APP_RESOURCE_MODE: RESOURCE_MODE,
    APP_RESOURCE_ADAPTIVE: RESOURCE_MODE === 'adaptive' ? 'true' : 'false',
  };

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

  log(app.name, `started | mem=${memMB}MB nice=${niceVal}${isInteractive ? ' [interactive]' : ''}`);

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
console.log(`[LAUNCHER] v3.1 — dinamis, minimal restart, +catur`);
console.log(`[LAUNCHER] mem-monitor: soft=${MEM_GUARD_SOFT_RATIO}x (no kill — limit adjusts dynamically)`);
console.log(`[LAUNCHER] pressure: L1=nudge@128MB L2=pause@64MB L3=kill@32MB`);
console.log(`[LAUNCHER] crash-loop: max=${CRASH_LOOP_MAX}/${CRASH_LOOP_WINDOW_MS/1000}s backoff=${CRASH_LOOP_BACKOFF_MS/1000}s`);
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
sc vm.swappiness               5
sc vm.dirty_ratio              20
sc vm.dirty_background_ratio   5
sc vm.vfs_cache_pressure       50
sc vm.overcommit_memory        1
sc vm.min_free_kbytes          "$MIN_FREE"
sc kernel.sched_migration_cost_ns  500000
sc kernel.sched_autogroup_enabled  1
sc net.ipv4.tcp_keepalive_time     30
sc net.ipv4.tcp_keepalive_intvl    10
sc net.ipv4.tcp_keepalive_probes   5
sc net.ipv4.tcp_fastopen           3
sc net.ipv4.tcp_tw_reuse           1
sc net.ipv4.tcp_fin_timeout        30
sc net.core.rmem_max               16777216
sc net.core.wmem_max               16777216
sc net.core.somaxconn              65535
sc net.core.netdev_max_backlog     5000
sc fs.file-max                     1048576
sc fs.inotify.max_user_watches     524288
sc fs.inotify.max_user_instances   1024

ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true
ulimit -u 65535   2>/dev/null || true
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
# Catatan v2: tambah earlyoom protection + cek interval lebih cepat (30s)
# v2.1: tambah proteksi node.*catur
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
  protect "node.*server"          -700
  protect "node.*kfai"            -700
  protect "node.*ttt"             -700
  protect "node.*nexcloud"        -700
  protect "node.*catur"           -700
  protect "node.*animest"         -700
  protect "cloudflared"           -500
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

mkdir -p /data/apps /data/bin /data/root/.pm2 /data/root/.npm

clone_or_pull "kfai-nodejs" "${KFAI_REPO:-}"     "${KFAI_DIR:-/data/apps/kfai-nodejs}"  "${KFAI_BRANCH:-}" &
clone_or_pull "kfai-mcp"    "${KFAI_MCP_REPO:-}" "${KFAI_MCP_DIR:-/data/apps/kfai-mcp}" "${KFAI_MCP_BRANCH:-}" &
clone_or_pull "ttt"         "${TTT_REPO:-}"       "${TTT_DIR:-/data/apps/ttt}"            "${TTT_BRANCH:-}" &
clone_or_pull "nexcloud"    "${NEXCLOUD_REPO:-}"  "${NEXCLOUD_DIR:-/data/apps/nexcloud}"  "${NEXCLOUD_BRANCH:-}" &
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

# ─── run-nexcloud.sh ──────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/run-nexcloud.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/run-node-app.sh \
  "nexcloud" \
  "${NEXCLOUD_DIR:-/data/apps/nexcloud}" \
  "${NEXCLOUD_ENTRY:-server.js}" \
  "${NEXCLOUD_NODE_MODULES_ZIP:-node_modules.zip}" \
  "${NEXCLOUD_USE_NODE_MODULES_ZIP:-true}" \
  "${NEXCLOUD_SKIP_NPM_INSTALL:-false}" \
  "${NEXCLOUD_NODE_OPTIONS:---max-old-space-size=256}"
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
    npm install --legacy-peer-deps --no-audit --no-fund --loglevel=error --prefer-offline \
      || npm install --legacy-peer-deps --no-audit --no-fund --loglevel=error
    npm cache clean --force >/dev/null 2>&1 || true
    echo "[$APP_NAME] deps siap."
  fi
fi

echo "[$APP_NAME] start: npm run start"
exec npm run start
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

# ─── optimize-system.sh ───────────────────────────────────────────────────────
RUN cat > /usr/local/bin/optimize-system.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true
ulimit -u 65535   2>/dev/null || true
mkdir -p /data/root/.cache /data/root/.npm /data/root/.pm2 /data/tmp
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
# Catatan v2: tambah info cgroup memory limit + per-app RSS live
# v2.1: tambah catur ke per-app RSS live
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
  echo "Mode: adaptive launcher (index.js v3.2)"
  pgrep -fa "node.*adaptive-launcher\|node.*launcher/index.js" 2>/dev/null | head -n 5 || echo "  (tidak aktif)"
else
  echo "Mode: PM2"
  pm2 status 2>/dev/null
fi

printf "\n${C}== Top proses (RAM) ==${R}\n"; ps -eo pid,stat,pcpu,pmem,nice,rss,comm --sort=-rss | head -n 18

printf "\n${C}== Per-app RSS live ==${R}\n"
for pat in "kfai-nodejs" "kfai-mcp" "ttt" "nexcloud" "catur" "animest" "cloudflared" "adaptive-launcher"; do
  for pid in $(pgrep -f "$pat" 2>/dev/null | head -1); do
    rss=$(awk '/VmRSS:/{printf "%d", $2/1024}' /proc/$pid/status 2>/dev/null || echo "?")
    nice_val=$(ps -p $pid -o ni= 2>/dev/null | tr -d ' ')
    printf "  %-20s pid=%-6s rss=%-6sMB nice=%s\n" "$pat" "$pid" "$rss" "$nice_val"
  done
done

printf "\n${C}== OOM protection ==${R}\n"
for pat in "adaptive-launcher" earlyoom "node.*server" "node.*kfai" "node.*ttt" "node.*nexcloud" "node.*catur" "node.*animest" sshd cloudflared; do
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
ps -eo pid,nice,comm --sort=nice | grep -E 'node|cloudflared' | head -n 10 || true
SCRIPT

# ─── start-all.sh ─────────────────────────────────────────────────────────────
# Catatan v2:
#   • Mulai earlyoom daemon dengan konfigurasi yang melindungi launcher+sshd
#   • Bersihkan proses orphan dari run sebelumnya
#   • Mulai nscd via service-aware fallback
#   • PM2 ecosystem ditambah min_uptime + max_restarts + exp_backoff_restart_delay
#   v2.1: earlyoom --prefer / --avoid pattern diperluas untuk catur
#          PM2 ecosystem ditambah app catur
RUN cat > /usr/local/bin/start-all.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# ── 0. Direktori ───────────────────────────────────────────────────────────
mkdir -p /data/root /data/ssh /data/apps /data/bin /data/launcher \
         /run/sshd /data/root/.pm2 /data/root/.npm /data/tmp
chmod 700 /data/root /data/ssh
chmod 1777 /data/tmp /tmp || true

# ── 0a. Bersihkan orphan proses Node/PM2 dari run sebelumnya ──────────────
# Hanya kill proses lama, BUKAN yang baru dimulai oleh script ini
pkill -f "node.*adaptive-launcher\|node.*launcher/index.js" 2>/dev/null && echo "[start-all] clean stale launcher" || true
pkill -f "PM2.*God Daemon" 2>/dev/null && echo "[start-all] clean stale PM2" || true
sleep 1

# ── 1. Optimasi sistem (paralel) ───────────────────────────────────────────
/usr/local/bin/optimize-system.sh &
/usr/local/bin/resource-optimizer.sh &

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
fastfetch 2>/dev/null || true
echo
echo "  /data (persistent) | /root → /data/root"
echo "  LAUNCHER_MODE=${LAUNCHER_MODE:-adaptive}  |  kstatus"
echo "  Edit launcher: nano /data/launcher/index.js"
echo
node -v; npm -v; cloudflared --version 2>/dev/null; echo
BASHRC

# ── 7. Tunggu optimasi selesai ─────────────────────────────────────────────
wait

# ── 8. Clone / pull repos PARALEL ─────────────────────────────────────────
/usr/local/bin/bootstrap-apps.sh &
BOOTSTRAP_PID=$!

# ── 9a. Mulai earlyoom (proteksi OOM proaktif) ───────────────────────────
# earlyoom bunuh proses boros RAM sebelum OOM killer kernel, melindungi launcher+sshd
# -r 3600: report interval 1 jam
# -m 10:    trigger saat MemAvailable < 10%
# --avoid "(^node.*adaptive|^node.*launcher|^/usr/sbin/sshd|^earlyoom)": jangan bunuh ini
# --prefer "(^node.*kfai|^node.*ttt|^node.*nexcloud|^node.*catur|^cloudflared)": bunuh ini dulu
if command -v earlyoom >/dev/null 2>&1; then
  echo "[start-all] mulai earlyoom..."
  earlyoom -r 3600 -m 10 -s \
    --avoid '(^node.*adaptive|^node.*launcher/index|^/usr/sbin/sshd|^earlyoom|^node.*PM2)' \
    --prefer '(^node.*kfai|^node.*ttt|^node.*nexcloud|^node.*catur|^node.*animest|^cloudflared)' \
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

# ── 10. Tunggu bootstrap repo selesai ──────────────────────────────────────
wait $BOOTSTRAP_PID || echo "WARN: bootstrap selesai dengan error."

# ── 11. Pilih launcher ─────────────────────────────────────────────────────
LAUNCHER_MODE="${LAUNCHER_MODE:-adaptive}"
echo "[start-all] LAUNCHER_MODE=${LAUNCHER_MODE}"

if [ "$LAUNCHER_MODE" = "pm2" ]; then
  # ── PM2 mode (v2.1: tambah app catur) ────────────────────────────────────
  echo "[start-all] mode PM2"
  cat > /data/ecosystem.config.js <<'PM2EOF'
const fs = require('fs');

// cgroup-aware memory detection (sama dengan launcher v3.1)
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
// Distribusi v3.2: kfai 33%, mcp 23%, ttt 11%, nexcloud 11%, catur 11%, animest 11%
const mem = {
  kfai:     process.env.KFAI_MAX_MEMORY     || Math.min(1024, Math.floor(BUDGET*0.33))+'M',
  mcp:      process.env.KFAI_MCP_MAX_MEMORY || Math.min(1280, Math.floor(BUDGET*0.23))+'M',
  ttt:      process.env.TTT_MAX_MEMORY       || Math.min(384,  Math.floor(BUDGET*0.11))+'M',
  nexcloud: process.env.NEXCLOUD_MAX_MEMORY  || Math.min(384,  Math.floor(BUDGET*0.11))+'M',
  catur:    process.env.CATUR_MAX_MEMORY     || Math.min(384,  Math.floor(BUDGET*0.11))+'M',
  animest:  process.env.ANIMEST_MAX_MEMORY   || Math.min(384,  Math.floor(BUDGET*0.11))+'M',
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
  { name:'ttt', script:'/usr/local/bin/run-ttt.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.ttt, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'nexcloud', script:'/usr/local/bin/run-nexcloud.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.nexcloud, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'catur', script:'/usr/local/bin/run-catur.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.catur, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'animest', script:'/usr/local/bin/run-animest.sh', interpreter:'bash',
    autorestart:true, max_restarts:10, min_uptime:'10s', restart_delay:2000,
    exp_backoff_restart_delay:200, max_memory_restart:mem.animest, kill_timeout:10000,
    listen_timeout:15000, node_args:nodeArgs, env:{NODE_ENV:'production'} },
]};
PM2EOF
  exec pm2-runtime /data/ecosystem.config.js

else
  # ── Adaptive launcher mode (default, v3.2) ───────────────────────────────
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
      /usr/local/bin/run-nexcloud.sh \
      /usr/local/bin/run-catur.sh \
      /usr/local/bin/run-animest.sh \
      /usr/local/bin/run-cloudflared.sh \
      /usr/local/bin/optimize-system.sh \
      /usr/local/bin/kstatus \
      /usr/local/bin/start-all.sh

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-all.sh"]
