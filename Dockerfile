FROM kalilinux/kali-rolling

# Railway will override PORT; keep a local default
ENV PORT=7681
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates wget curl git python3 python3-pip tini fastfetch

# Ensure the target dir exists
RUN mkdir -p /usr/local/bin

# Install latest ttyd (pick correct binary for the CPU)
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64|amd64) ttyd_asset="ttyd.x86_64" ;; \
      aarch64|arm64) ttyd_asset="ttyd.aarch64" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    wget -qO /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/latest/download/${ttyd_asset}" \
    && chmod +x /usr/local/bin/ttyd

# Show system info on shell start (fastfetch)
RUN echo "fastfetch || true" >> /root/.bashrc

EXPOSE 7681

ENTRYPOINT ["/usr/bin/tini","--"]

CMD ["/bin/bash","-lc", "/usr/local/bin/ttyd --writable -i 0.0.0.0 -p ${PORT} -c ${USERNAME}:${PASSWORD} /bin/bash"]
