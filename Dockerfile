FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# SSH internal port.
# Di Railway TCP Proxy, isi internal port = 22.
ENV SSH_PORT=22

# Storage permanen. Mount Railway Volume ke /data.
ENV DATA_DIR=/data
ENV HOME=/root
ENV PM2_HOME=/data/root/.pm2
ENV NPM_CONFIG_CACHE=/data/root/.npm
ENV GOPATH=/data/root/go
ENV PATH="/usr/local/go/bin:/data/root/go/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    openssh-server \
    sudo \
    tini \
    fastfetch \
    nano \
    vim \
    htop \
    procps \
    net-tools \
    iproute2 \
    iputils-ping \
    dnsutils \
    build-essential \
    python3 \
    python3-pip \
    golang-go \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js latest/current dari NodeSource.
# Kalau mau LTS, ganti setup_current.x jadi setup_lts.x
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_current.x | bash -; \
    apt-get update; \
    apt-get install -y nodejs; \
    npm install -g npm@latest pm2; \
    node -v; npm -v; pm2 -v; \
    rm -rf /var/lib/apt/lists/*

# Siapkan sshd
RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d /data/root /data/ssh \
  && chmod 700 /data/root /data/ssh

# Root home dibuat persistent via symlink ke /data/root
RUN rm -rf /root \
  && ln -s /data/root /root

# SSH config
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
ClientAliveInterval 60
ClientAliveCountMax 3

UsePAM yes
PrintMotd no
Subsystem sftp /usr/lib/openssh/sftp-server

HostKey /data/ssh/ssh_host_rsa_key
HostKey /data/ssh/ssh_host_ecdsa_key
HostKey /data/ssh/ssh_host_ed25519_key
EOF

# Startup script
RUN cat > /usr/local/bin/start-ssh.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p /data/root /data/ssh /run/sshd
chmod 700 /data/root /data/ssh

# Root password:
# Prioritas: ROOT_PASSWORD, lalu PASSWORD.
ROOT_PASS="${ROOT_PASSWORD:-${PASSWORD:-}}"

if [ -z "$ROOT_PASS" ]; then
  echo "ERROR: set env ROOT_PASSWORD atau PASSWORD dulu."
  echo "Contoh Railway Variables:"
  echo "ROOT_PASSWORD=password-ku-yang-kuat"
  exit 1
fi

echo "root:${ROOT_PASS}" | chpasswd

# Generate persistent SSH host keys di /data/ssh
if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -A
  cp -f /etc/ssh/ssh_host_* /data/ssh/ || true
fi

# Kalau user kasih SSH_PUBLIC_KEY, otomatis pasang authorized_keys
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p /data/root/.ssh
  chmod 700 /data/root/.ssh
  echo "$SSH_PUBLIC_KEY" > /data/root/.ssh/authorized_keys
  chmod 600 /data/root/.ssh/authorized_keys
fi

# Bash welcome
cat > /data/root/.bashrc <<'BASHRC'
fastfetch || true

echo
echo "Persistent storage:"
echo "  /data"
echo "  /root -> /data/root"
echo
echo "Versions:"
node -v 2>/dev/null || true
npm -v 2>/dev/null || true
go version 2>/dev/null || true
pm2 -v 2>/dev/null || true
echo
BASHRC

# Pastikan PM2 folder persistent
mkdir -p /data/root/.pm2 /data/root/.npm /data/root/go
chmod -R 700 /data/root/.ssh 2>/dev/null || true

# Kalau SSH_PORT bukan 22, patch Port config saat runtime
if [ "${SSH_PORT:-22}" != "22" ]; then
  sed -i "s/^Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
fi

echo "Starting SSH server on port ${SSH_PORT:-22}"
exec /usr/sbin/sshd -D -e
EOF

RUN chmod +x /usr/local/bin/start-ssh.sh

VOLUME ["/data"]

EXPOSE 22

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start-ssh.sh"]
