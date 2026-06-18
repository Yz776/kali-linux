FROM kalilinux/kali-rolling

# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT
# ═══════════════════════════════════════════════════════════════════════════════
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    # Node
    NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=512" \
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
    # LangChain
    LANGCHAIN_AUTO_UPGRADE=true \
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
    ADAPTIVE_INTERVAL_MS=2500 \
    FOCUS_HOLD_MS=12000 \
    HIGH_CPU_PERCENT=18 \
    NORMAL_NICE=5 \
    FOCUS_NICE=1 \
    STARVE_SAFE_NICE=6

# Repo config
ENV KFAI_REPO=https://github.com/Yz776/kfai-nodejs.git \
    KFAI_BRANCH=master \
    KFAI_MCP_REPO=https://github.com/Yz776/kfai-mcp.git \
    KFAI_MCP_BRANCH=master \
    TTT_REPO=https://github.com/Yz776/ttt.git \
    TTT_BRANCH= \
    KFAI_DIR=/data/apps/kfai-nodejs \
    KFAI_MCP_DIR=/data/apps/kfai-mcp \
    TTT_DIR=/data/apps/ttt \
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
MaxAuthTries 6
MaxSessions 20
LoginGraceTime 30
StrictModes yes
Subsystem sftp /usr/lib/openssh/sftp-server
HostKey /data/ssh/ssh_host_rsa_key
HostKey /data/ssh/ssh_host_ecdsa_key
HostKey /data/ssh/ssh_host_ed25519_key
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# NSCD CONFIG
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /etc/nscd.conf <<'EOF'
logfile                /dev/null
threads                4
max-threads            32
paranoia               no
enable-cache           hosts     yes
positive-time-to-live  hosts     600
negative-time-to-live  hosts     20
suggested-size         hosts     211
check-files            hosts     yes
persistent             hosts     yes
shared                 hosts     yes
max-db-size            hosts     33554432
enable-cache           passwd    no
enable-cache           group     no
enable-cache           netgroup  no
enable-cache           services  no
EOF

# ═══════════════════════════════════════════════════════════════════════════════
# ADAPTIVE LAUNCHER – index.js
# Launcher Node.js dengan adaptive CPU priority (nice/renice) + memory monitor.
# Dipasang di /data/launcher/index.js, persisten di /data sehingga bisa di-edit
# tanpa rebuild image.
# ═══════════════════════════════════════════════════════════════════════════════
RUN cat > /data/launcher/index.js <<'LAUNCHEREOF'
// /data/launcher/index.js
// Adaptive multi-app launcher – mengelola kfai-nodejs, kfai-mcp, ttt, cloudflared
// sebagai proses child dengan adaptive CPU priority dan memory guard.
//
// ENV override (semua opsional):
//   LAUNCHER_MODE=adaptive|pm2        -> pilih launcher (default: adaptive)
//   INTERACTIVE_APP=kfai-nodejs       -> app yang menerima stdin/readline
//   RESOURCE_MODE=adaptive|fair|custom
//   FOCUS_APP=kfai-nodejs             -> paksa fokus ke app tertentu
//   ADAPTIVE_INTERVAL_MS=2500
//   FOCUS_HOLD_MS=12000
//   HIGH_CPU_PERCENT=18
//   NORMAL_NICE=5  FOCUS_NICE=1  STARVE_SAFE_NICE=6
//   KFAI_MEMORY_MB=1024  KFAI_MCP_MEMORY_MB=1536  TTT_MEMORY_MB=512
//   CF_MEMORY_MB=128

'use strict';
const { spawn, spawnSync } = require('child_process');
const fs   = require('fs');
const os   = require('os');
const path = require('path');

// ── Konstanta & ENV ──────────────────────────────────────────────────────────
const KFAI_DIR     = process.env.KFAI_DIR     || '/data/apps/kfai-nodejs';
const KFAI_MCP_DIR = process.env.KFAI_MCP_DIR || '/data/apps/kfai-mcp';
const TTT_DIR      = process.env.TTT_DIR      || '/data/apps/ttt';

const INTERACTIVE_APP   = (process.env.INTERACTIVE_APP || 'kfai-nodejs').trim();
const RESOURCE_MODE     = (process.env.RESOURCE_MODE   || 'adaptive').trim().toLowerCase();
const MANUAL_FOCUS      = (process.env.FOCUS_APP       || '').trim();

const CPU_COUNT          = Math.max(1, os.cpus()?.length || 1);
const TOTAL_MEM_MB       = Math.floor(os.totalmem() / 1024 / 1024);
const ADAPTIVE_INTERVAL  = Number(process.env.ADAPTIVE_INTERVAL_MS || 2500);
const FOCUS_HOLD_MS      = Number(process.env.FOCUS_HOLD_MS        || 12000);
const HIGH_CPU_PERCENT   = Number(process.env.HIGH_CPU_PERCENT      || 18);
const NORMAL_NICE        = Number(process.env.NORMAL_NICE            || 5);
const FOCUS_NICE         = Number(process.env.FOCUS_NICE             || 1);
const STARVE_SAFE_NICE   = Number(process.env.STARVE_SAFE_NICE       || 6);

// Alokasi memori dinamis berdasarkan total RAM tersedia
const KFAI_MEM     = Number(process.env.KFAI_MEMORY_MB     || Math.floor(TOTAL_MEM_MB * 0.35));
const KFAI_MCP_MEM = Number(process.env.KFAI_MCP_MEMORY_MB || Math.floor(TOTAL_MEM_MB * 0.40));
const TTT_MEM      = Number(process.env.TTT_MEMORY_MB       || Math.floor(TOTAL_MEM_MB * 0.20));
const CF_MEM       = Number(process.env.CF_MEMORY_MB        || 128);

// ── Definisi app ─────────────────────────────────────────────────────────────
// Setiap app dijalankan via shell script runner yang sudah ada di image.
// Ini agar deps install, entry detection, dll tetap dihandle script yang sama.
const APPS = [
  {
    name:     'kfai-nodejs',
    script:   '/usr/local/bin/run-kfai-nodejs.sh',
    memoryMB: KFAI_MEM,
    nice:     NORMAL_NICE,
  },
  {
    name:     'kfai-mcp',
    script:   '/usr/local/bin/run-kfai-mcp.sh',
    memoryMB: KFAI_MCP_MEM,
    nice:     NORMAL_NICE,
  },
  {
    name:     'ttt',
    script:   '/usr/local/bin/run-ttt.sh',
    memoryMB: TTT_MEM,
    nice:     NORMAL_NICE,
  },
  {
    name:     'cloudflared-ssh',
    script:   '/usr/local/bin/run-cloudflared.sh',
    memoryMB: CF_MEM,
    nice:     NORMAL_NICE + 3, // cloudflared tidak perlu prioritas tinggi
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
  for (const app of APPS) {
    const child = children.get(app.name);
    if (!child?.pid) continue;
    let target = NORMAL_NICE;
    if (focusedApp && app.name === focusedApp) target = FOCUS_NICE;
    else if (focusedApp)                       target = STARVE_SAFE_NICE;
    applyNice(app.name, child.pid, target);
  }
}

// ── Memory guard ──────────────────────────────────────────────────────────────
function startMemGuard(app, child) {
  if (!isLinux) return;
  const limitMB = Math.ceil(safeNum(app.memoryMB, 512) * 1.35 + 96);
  const t = setInterval(() => {
    if (!child.pid || child.killed) { clearInterval(t); return; }
    const rss = readRssMB(child.pid);
    if (rss != null && rss > limitMB) {
      warn(app.name, `RSS ${rss}MB > limit ${limitMB}MB → SIGTERM`);
      restarting.set(app.name, true);
      try {
        child.kill('SIGTERM');
        setTimeout(() => { if (!child.killed) child.kill('SIGKILL'); }, 5000).unref();
      } catch (e) { err(app.name, 'kill gagal:', e); }
    }
  }, 10000);
  t.unref();
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
  const memMB = safeNum(app.memoryMB, 512);
  const niceVal = clampNice(RESOURCE_MODE === 'custom' ? app.nice : NORMAL_NICE);

  // Bangun NODE_OPTIONS dengan max-old-space-size yang benar
  const nodeOpts = (process.env.NODE_OPTIONS || '')
    .split(/\s+/)
    .filter(x => x && !x.startsWith('--max-old-space-size='))
    .concat([`--max-old-space-size=${memMB}`, '--expose-gc'])
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
  startMemGuard(app, child);

  log(app.name, `started | mem=${memMB}MB nice=${niceVal}${isInteractive ? ' [interactive]' : ''}`);

  if (!isInteractive) {
    prefixPipe(child.stdout, app.name, false);
    prefixPipe(child.stderr, app.name, true);
  }

  child.on('close', (code, signal) => {
    children.delete(app.name);
    procStats.delete(app.name);
    curNice.delete(app.name);
    log(app.name, `stopped code=${code} signal=${signal || '-'}`);

    if (focusedApp === app.name && !MANUAL_FOCUS) { focusedApp = null; focusUntil = 0; }
    if (restarting.get(app.name) === false) return;

    const now  = Date.now();
    const last = lastRestart.get(app.name) || 0;
    const delay = (now - last < 5000) ? 8000 : 3000;
    lastRestart.set(app.name, now);
    setTimeout(() => { log(app.name, 'restarting...'); startApp(app); }, delay);
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
console.log(`[LAUNCHER] CPU=${CPU_COUNT} core | RAM=${TOTAL_MEM_MB}MB`);
console.log(`[LAUNCHER] RESOURCE_MODE=${RESOURCE_MODE} | INTERACTIVE=${INTERACTIVE_APP}`);
console.log(`[LAUNCHER] nice: focus=${FOCUS_NICE} normal=${NORMAL_NICE} other=${STARVE_SAFE_NICE}`);
for (const app of APPS)
  console.log(`[LAUNCHER]   ${app.name.padEnd(16)} mem=${safeNum(app.memoryMB,512)}MB`);
console.log(`[LAUNCHER] ══════════════════════════════════════════\n`);

// ── Rebalance loop ────────────────────────────────────────────────────────────
setInterval(rebalanceNice, ADAPTIVE_INTERVAL).unref();

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
RUN cat > /usr/local/bin/resource-optimizer.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
log() { echo "[resource-optimizer] $*"; }

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
  systemctl is-active --quiet "$svc" 2>/dev/null || continue
  log "stop: $svc"
  systemctl stop "$svc"    2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
done
for proc in freshclam clamd updatedb mlocate; do
  pkill -f "$proc" 2>/dev/null && log "killed: $proc" || true
done

sc() { sysctl -w "$1=$2" >/dev/null 2>&1 && log "sysctl $1=$2" || log "WARN skip: $1"; }
sc vm.swappiness               5
sc vm.dirty_ratio              20
sc vm.dirty_background_ratio   5
sc vm.vfs_cache_pressure       50
sc vm.overcommit_memory        1
sc vm.min_free_kbytes          32768
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

sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
log "selesai."
SCRIPT

# ─── oom-watchdog.sh ──────────────────────────────────────────────────────────
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
  protect "node.*adaptive-launcher|node.*index.js" -900
  protect "PM2|pm2"             -800
  protect "node.*server"        -700
  protect "node.*kfai"          -700
  protect "node.*ttt"           -700
  protect "/usr/sbin/sshd"      -600
  protect "cloudflared"         -500
  sleep 60
done
SCRIPT

# ─── bootstrap-apps.sh – clone PARALEL ───────────────────────────────────────
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
RUN cat > /usr/local/bin/upgrade-langchain-packages.sh <<'SCRIPT'
#!/usr/bin/env bash
set +e
APP_NAME="${1:-node-app}"
[ "${LANGCHAIN_AUTO_UPGRADE:-true}" != "true" ] && exit 0
[ ! -f package.json ] && exit 0
grep -q '"@langchain/' package.json 2>/dev/null || exit 0
PKGS="@langchain/core@latest @langchain/openai@latest @langchain/mcp-adapters@latest"
grep -q '"@langchain/anthropic"' package.json 2>/dev/null && PKGS="$PKGS @langchain/anthropic@latest"
grep -q '"@langchain/google'     package.json 2>/dev/null && PKGS="$PKGS @langchain/google-genai@latest"
echo "[$APP_NAME] upgrade LangChain..."
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
chmod 1777 /tmp /data/tmp 2>/dev/null || true
npm config set prefer-offline true --global >/dev/null 2>&1 || true
npm config set audit false --global         >/dev/null 2>&1 || true
npm config set fund false --global          >/dev/null 2>&1 || true
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
echo "[optimize-system] selesai."
SCRIPT

# ─── kstatus ──────────────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/kstatus <<'SCRIPT'
#!/usr/bin/env bash
set +e
C='\033[1;36m'; R='\033[0m'
printf "\n${C}== System ==${R}\n"; uptime; free -h; df -h / /data 2>/dev/null || df -h
printf "\n${C}== Network ==${R}\n"; ip -br addr 2>/dev/null; ss -lntup 2>/dev/null | head -n 30
printf "\n${C}== Launcher proses ==${R}\n"
LAUNCHER_MODE="${LAUNCHER_MODE:-adaptive}"
if [ "$LAUNCHER_MODE" = "adaptive" ]; then
  echo "Mode: adaptive launcher (index.js)"
  pgrep -fa "node.*adaptive-launcher\|node.*index.js" 2>/dev/null | head -n 5 || echo "  (tidak aktif)"
else
  echo "Mode: PM2"
  pm2 status 2>/dev/null
fi
printf "\n${C}== Top proses (RAM) ==${R}\n"; ps -eo pid,stat,pcpu,pmem,nice,comm --sort=-%mem | head -n 18
printf "\n${C}== OOM protection ==${R}\n"
for pat in "adaptive-launcher" pm2 "node.*server" "node.*kfai" "node.*ttt" sshd cloudflared; do
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    score=$(cat /proc/$pid/oom_score_adj 2>/dev/null || echo "?")
    comm=$(ps -p $pid -o comm= 2>/dev/null || echo "?")
    printf "  pid %-6s  oom=%-6s  %s\n" "$pid" "$score" "$comm"
  done
done
printf "\n${C}== DNS cache (nscd) ==${R}\n"
nscd -g 2>/dev/null | grep -E 'cache hit|request' | head -n 10 || echo "  nscd tidak aktif"
printf "\n${C}== Nice values ==${R}\n"
ps -eo pid,nice,comm --sort=nice | grep -E 'node|cloudflared' | head -n 10 || true
SCRIPT

# ─── start-all.sh ─────────────────────────────────────────────────────────────
RUN cat > /usr/local/bin/start-all.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# ── 0. Direktori ───────────────────────────────────────────────────────────
mkdir -p /data/root /data/ssh /data/apps /data/bin /data/launcher \
         /run/sshd /data/root/.pm2 /data/root/.npm /data/tmp
chmod 700 /data/root /data/ssh
chmod 1777 /data/tmp /tmp || true

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

# ── 9. Layanan pendukung ───────────────────────────────────────────────────
nscd 2>/dev/null || true
/usr/sbin/sshd -D -e &
/usr/local/bin/oom-watchdog.sh &

# ── 10. Tunggu bootstrap repo selesai ──────────────────────────────────────
wait $BOOTSTRAP_PID || echo "WARN: bootstrap selesai dengan error."

# ── 11. Pilih launcher ─────────────────────────────────────────────────────
LAUNCHER_MODE="${LAUNCHER_MODE:-adaptive}"
echo "[start-all] LAUNCHER_MODE=${LAUNCHER_MODE}"

if [ "$LAUNCHER_MODE" = "pm2" ]; then
  # ── PM2 mode ──────────────────────────────────────────────────────────────
  echo "[start-all] mode PM2"
  cat > /data/ecosystem.config.js <<'PM2EOF'
const fs = require('fs');
const memTotal = (() => {
  try {
    const m = fs.readFileSync('/proc/meminfo','utf8').match(/MemTotal:\s+(\d+)/);
    return m ? Math.floor(parseInt(m[1])/1024) : 2048;
  } catch { return 2048; }
})();
const mem = {
  kfai: process.env.KFAI_MAX_MEMORY     || Math.floor(memTotal*0.35)+'M',
  mcp:  process.env.KFAI_MCP_MAX_MEMORY || Math.floor(memTotal*0.40)+'M',
  ttt:  process.env.TTT_MAX_MEMORY       || Math.floor(memTotal*0.20)+'M',
  cf:   '96M',
};
const nodeArgs = '--expose-gc --max-http-header-size=16384';
module.exports = { apps: [
  { name:'cloudflared-ssh', script:'/usr/local/bin/run-cloudflared.sh', interpreter:'bash',
    autorestart:true, max_restarts:50, restart_delay:5000, exp_backoff_restart_delay:200,
    max_memory_restart:mem.cf, kill_timeout:5000 },
  { name:'kfai-nodejs', script:'/usr/local/bin/run-kfai-nodejs.sh', interpreter:'bash',
    autorestart:true, max_restarts:30, restart_delay:2000, exp_backoff_restart_delay:100,
    max_memory_restart:mem.kfai, kill_timeout:10000, listen_timeout:15000,
    node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'kfai-mcp', script:'/usr/local/bin/run-kfai-mcp.sh', interpreter:'bash',
    autorestart:true, max_restarts:30, restart_delay:2000, exp_backoff_restart_delay:100,
    max_memory_restart:mem.mcp, kill_timeout:10000, listen_timeout:15000,
    node_args:nodeArgs, env:{NODE_ENV:'production'} },
  { name:'ttt', script:'/usr/local/bin/run-ttt.sh', interpreter:'bash',
    autorestart:true, max_restarts:30, restart_delay:2000, exp_backoff_restart_delay:100,
    max_memory_restart:mem.ttt, kill_timeout:10000, listen_timeout:15000,
    node_args:nodeArgs, env:{NODE_ENV:'production'} },
]};
PM2EOF
  exec pm2-runtime /data/ecosystem.config.js

else
  # ── Adaptive launcher mode (default) ──────────────────────────────────────
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
      /usr/local/bin/run-cloudflared.sh \
      /usr/local/bin/optimize-system.sh \
      /usr/local/bin/kstatus \
      /usr/local/bin/start-all.sh

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-all.sh"]
