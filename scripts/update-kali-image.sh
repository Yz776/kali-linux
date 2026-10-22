#!/usr/bin/env bash
# /usr/local/bin/update-kali-image.sh
#
# Boot-time image updater for the kali container on rara.ai.id server.
# Pulls the latest ghcr.io/yz776/kali-linux:main and recreates the
# running 'kali' container ONLY if the image ID actually changed.
# Safe to run on every boot - no-op if image is already current.
#
# Wired to: /etc/systemd/system/update-kali-image.service
# Trigger: After docker.service on boot (oneshot).
#
# Why this exists:
#   Docker's 'unless-stopped' restart policy will restart the kali
#   container on reboot, but using the SAME image that was used to
#   create the container originally. New images pushed to GHCR don't
#   auto-pull unless we explicitly do so. This script closes that gap.
#
# Failure modes:
#   - If docker pull fails (network, registry), exit non-zero - systemd
#     marks the service as failed, but boot continues (not a hard dep).
#   - If container recreation fails, leave the old container running
#     (don't destroy state without a working replacement).

set -euo pipefail

IMAGE="ghcr.io/yz776/kali-linux:main"
CONTAINER="kali"

echo "[$(date -Is)] update-kali-image.sh start"
echo "Image:    $IMAGE"
echo "Container: $CONTAINER"

# Sanity: docker must be reachable
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker daemon not reachable" >&2
    exit 1
fi

# Step 1: pull latest image
echo "--- docker pull $IMAGE ---"
if ! docker pull "$IMAGE"; then
    echo "ERROR: docker pull failed - leaving existing container untouched" >&2
    exit 1
fi

LATEST_ID=$(docker image inspect "$IMAGE" --format '{{.Id}}')
echo "Latest image ID: $LATEST_ID"

# Step 2: get the running container's image ID
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container $CONTAINER does not exist - creating fresh from $IMAGE"
    docker run -d \
        --name "$CONTAINER" \
        --restart=unless-stopped \
        --privileged \
        --network host \
        -v /data:/data \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "$IMAGE"
    echo "Container $CONTAINER created"
    exit 0
fi

CURRENT_ID=$(docker inspect "$CONTAINER" --format '{{.Image}}')
echo "Current container image ID: $CURRENT_ID"

# Step 3: compare and recreate if different
if [ "$LATEST_ID" = "$CURRENT_ID" ]; then
    echo "Image is already up-to-date. No action needed."
    exit 0
fi

echo "Image changed: $CURRENT_ID -> $LATEST_ID"
echo "Recreating container $CONTAINER (preserving config)..."

NAME="$CONTAINER"
BINDS=$(docker inspect "$CONTAINER" --format '{{range .HostConfig.Binds}}{{println .}}{{end}}' | tr '\n' ' ')
RESTART=$(docker inspect "$CONTAINER" --format '{{.HostConfig.RestartPolicy.Name}}')
PRIVILEGED=$(docker inspect "$CONTAINER" --format '{{.HostConfig.Privileged}}')
NETWORK=$(docker inspect "$CONTAINER" --format '{{.HostConfig.NetworkMode}}')

echo "Original binds:    $BINDS"
echo "Original restart:  $RESTART"
echo "Original privileged: $PRIVILEGED"
echo "Original network:  $NETWORK"

RUN_ARGS=()
RUN_ARGS+=(-d)
RUN_ARGS+=(--name "$NAME")
[ "$RESTART" = "unless-stopped" ] && RUN_ARGS+=(--restart=unless-stopped)
[ "$PRIVILEGED" = "true" ] && RUN_ARGS+=(--privileged)
[ -n "$NETWORK" ] && [ "$NETWORK" != "default" ] && RUN_ARGS+=(--network "$NETWORK")
for bind in $BINDS; do
    RUN_ARGS+=(-v "$bind")
done
RUN_ARGS+=("$IMAGE")

echo "Recreate command: docker run ${RUN_ARGS[@]}"

docker stop "$CONTAINER" || true
docker rm "$CONTAINER" || true
docker run "${RUN_ARGS[@]}"

echo "Container $CONTAINER recreated with new image."

# Post-recreate recovery:
# 1. Restore /opt/rara-agent/.env from persistent backup in /data
#    (the new container's /opt/rara-agent has source code from git
#     but no .env, since .env is in .gitignore).
# 2. PM2 resurrect (load saved dump from /data/root/.pm2/dump.pm2).
#    If dump is missing apps, manually start the rara-web stack via
#    ecosystem.config.cjs (after sourcing .env).
echo "--- post-recreate: restore .env + pm2 resurrect ---"
docker exec "$CONTAINER" bash -c '
    # Restore .env if missing
    if [ ! -f /opt/rara-agent/.env ] && [ -f /data/root/.rara-agent.env ]; then
        cp /data/root/.rara-agent.env /opt/rara-agent/.env
        chmod 600 /opt/rara-agent/.env
        echo "Restored /opt/rara-agent/.env from /data/root/.rara-agent.env"
    fi

    # PM2 resurrect from dump
    pm2 resurrect 2>&1 | tail -5

    # If rara-web not in PM2 list, start it via ecosystem
    if ! pm2 list 2>/dev/null | grep -q "rara-web"; then
        cd /opt/rara-agent && \
        set -a && . ./.env && set +a && \
        pm2 start ecosystem.config.cjs 2>&1 | tail -3
        pm2 save 2>&1 | tail -2
    fi

    # If nginx not in PM2 list, start it
    if ! pm2 list 2>/dev/null | grep -q "nginx"; then
        pm2 start /usr/sbin/nginx --name nginx -- -g "daemon off;" 2>&1 | tail -3
        pm2 save 2>&1 | tail -2
    fi
'

echo "[$(date -Is)] update-kali-image.sh done"
