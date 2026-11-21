#!/bin/sh
# Render entrypoint: render configs from env, generate subscription, start xray + nginx.
# Required-ish env: UUID, PUBLIC_HOST. Optional: PORT (Render injects), WS_PATH, SUB_PATH, NODE_NAME.
set -eu

PORT="${PORT:-10000}"
XRAY_LOCAL_PORT="10001"
APP_DIR="/app"
SUB_FILE="$APP_DIR/subscription.txt"

rand_hex() {
    # $1 = bytes; prints 2*$1 hex chars
    od -An -tx1 -N "$1" /dev/urandom | tr -d ' \n'
}

strip_slashes() {
    printf '%s' "$1" | sed 's:^/*::; s:/*$::'
}

# --- UUID: no fake default. Random per boot if unset, with a loud warning. ---
if [ -z "${UUID:-}" ]; then
    UUID="$(cat /proc/sys/kernel/random/uuid)"
    echo "[entrypoint] WARNING: UUID env var is NOT set." >&2
    echo "[entrypoint] WARNING: generated a random UUID for this boot only: $UUID" >&2
    echo "[entrypoint] WARNING: set UUID in Render -> Environment, or the node changes on every restart." >&2
fi

# --- WS_PATH / SUB_PATH: random if unset, printed once to the log. ---
if [ -z "${WS_PATH:-}" ]; then
    WS_PATH="$(rand_hex 8)"
    echo "[entrypoint] WS_PATH not set; generated random WS path: /$WS_PATH"
fi
WS_PATH="$(strip_slashes "$WS_PATH")"

if [ -z "${SUB_PATH:-}" ]; then
    SUB_PATH="$(rand_hex 8)"
    echo "[entrypoint] SUB_PATH not set; generated random subscription path: /$SUB_PATH"
fi
SUB_PATH="$(strip_slashes "$SUB_PATH")"

# --- Public host for the subscription link (Render service hostname). ---
if [ -z "${PUBLIC_HOST:-}" ]; then
    PUBLIC_HOST="REPLACE-ME.onrender.com"
    echo "[entrypoint] WARNING: PUBLIC_HOST not set; subscription link uses placeholder host: $PUBLIC_HOST" >&2
fi
NODE_NAME="${NODE_NAME:-Render-Node}"

# --- Render xray config ---
sed -e "s|__UUID__|$UUID|g" \
    -e "s|__WS_PATH__|$WS_PATH|g" \
    "$APP_DIR/templates/config.json.tmpl" > "$APP_DIR/config.json"

# --- Render nginx config ---
sed -e "s|__PORT__|$PORT|g" \
    -e "s|__WS_PATH__|$WS_PATH|g" \
    -e "s|__SUB_PATH__|$SUB_PATH|g" \
    "$APP_DIR/templates/nginx.conf.tmpl" > "$APP_DIR/nginx.conf"

# --- Subscription file: base64 of a single vless:// link ---
# Client view: host=PUBLIC_HOST, port 443, TLS terminated by Render, WS path /$WS_PATH.
VLESS_LINK="vless://${UUID}@${PUBLIC_HOST}:443?encryption=none&security=tls&type=ws&host=${PUBLIC_HOST}&path=%2F${WS_PATH}#${NODE_NAME}"
printf '%s' "$VLESS_LINK" | base64 | tr -d '\n' > "$SUB_FILE"
chmod 644 "$SUB_FILE"

# --- Validate both configs before starting anything ---
/usr/local/bin/xray run -test -config "$APP_DIR/config.json"
nginx -t -c "$APP_DIR/nginx.conf"

# --- Start xray (background), nginx (foreground) ---
/usr/local/bin/xray run -config "$APP_DIR/config.json" &

echo "[entrypoint] xray listening on 127.0.0.1:$XRAY_LOCAL_PORT (VLESS+WS, path /$WS_PATH)"
echo "[entrypoint] subscription URL: https://${PUBLIC_HOST}/${SUB_PATH}"
echo "[entrypoint] nginx listening on 0.0.0.0:$PORT"

# nginx becomes PID 1; when it exits / the container stops, the runtime tears down xray with it.
exec nginx -c "$APP_DIR/nginx.conf" -g 'daemon off;'
