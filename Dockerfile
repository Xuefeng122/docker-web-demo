# Render free Web Service — single container: nginx ($PORT) -> xray (127.0.0.1:10001)
# TLS is terminated by Render on *.onrender.com; inside the container everything is plain HTTP/WS.

# ---------- Stage 1: download official xray-core and verify checksum ----------
FROM alpine:3.21 AS fetcher
ARG XRAY_VERSION=v26.11.9
ARG XRAY_ARCH=linux-64
RUN set -eux; \
    apk add --no-cache curl unzip ca-certificates; \
    cd /tmp; \
    curl -fsSL -o xray.zip \
      "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip"; \
    curl -fsSL -o xray.zip.dgst \
      "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip.dgst"; \
    EXPECTED="$(sed -n 's/^SHA2-256= //p' xray.zip.dgst)"; \
    ACTUAL="$(sha256sum xray.zip | awk '{print $1}')"; \
    echo "xray.zip expected SHA2-256: $EXPECTED"; \
    echo "xray.zip actual   SHA2-256: $ACTUAL"; \
    [ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ]; \
    mkdir -p /out; \
    unzip -o xray.zip -d /out; \
    chmod +x /out/xray; \
    /out/xray version

# ---------- Stage 2: runtime (Alpine with shell + nginx + xray) ----------
FROM alpine:3.21
RUN apk add --no-cache nginx ca-certificates \
 && mkdir -p /app/templates /run/nginx
COPY --from=fetcher /out/xray      /usr/local/bin/xray
COPY --from=fetcher /out/geoip.dat /usr/local/bin/geoip.dat
COPY --from=fetcher /out/geosite.dat /usr/local/bin/geosite.dat
COPY nginx.conf.tmpl /app/templates/nginx.conf.tmpl
COPY config.json.tmpl /app/templates/config.json.tmpl
COPY index.html /usr/share/nginx/html/index.html
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh /usr/local/bin/xray
ENV PORT=10000
EXPOSE 10000
ENTRYPOINT ["/app/entrypoint.sh"]
