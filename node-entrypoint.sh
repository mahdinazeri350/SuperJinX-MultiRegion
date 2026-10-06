#!/usr/bin/env bash
set -euo pipefail
DATA=/var/lib/jinx-node
mkdir -p "$DATA/certs"

export PORT="${PORT:-8080}"
export NODE_HOST="${NODE_HOST:-0.0.0.0}"
export SERVICE_PORT="${SERVICE_PORT:-62050}"
export SERVICE_PROTOCOL="${SERVICE_PROTOCOL:-grpc}"
export XRAY_EXECUTABLE_PATH="${XRAY_EXECUTABLE_PATH:-/usr/local/bin/xray}"
export XRAY_ASSETS_PATH="${XRAY_ASSETS_PATH:-/usr/local/share/xray}"

if [ -z "${API_KEY:-}" ]; then
  if [ -f "$DATA/api_key" ]; then
    API_KEY=$(cat "$DATA/api_key")
  elif [ -n "${JINX_NODE_SECRET:-}" ]; then
    API_KEY=$(python3 -c 'import os,uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, os.environ.get("JINX_NODE_SECRET","")+"/"+os.environ.get("JINX_NODE_REGION","region")))')
    echo "$API_KEY" > "$DATA/api_key"
  else
    API_KEY=$(python3 -c 'import uuid;print(uuid.uuid4())')
    echo "$API_KEY" > "$DATA/api_key"
  fi
  export API_KEY
  echo "[jinx-node] API_KEY generated; do not publish this value"
fi

if [ ! -f "$DATA/certs/cert.pem" ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
    -keyout "$DATA/certs/key.pem" -out "$DATA/certs/cert.pem" \
    -subj "/CN=${RAILWAY_PRIVATE_DOMAIN:-localhost}" \
    -addext "subjectAltName=DNS:${RAILWAY_PRIVATE_DOMAIN:-localhost},DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
fi
export SSL_CERT_FILE="${SSL_CERT_FILE:-$DATA/certs/cert.pem}"
export SSL_KEY_FILE="${SSL_KEY_FILE:-$DATA/certs/key.pem}"

python3 - <<'PY'
import json, os
base = {
  "JX-VLESS-WS-1": (10001, "/ws/"),
  "JX-VLESS-WS-2": (10002, "/stream/"),
  "JX-TROJAN-WS": (10003, "/live/"),
  "JX-VMESS-WS": (10004, "/gw/"),
  "JX-VLESS-HU": (10005, "/cdn/"),
}
raw = os.getenv("JINX_SHARED_PATHS_JSON", "").strip()
if not raw and os.getenv("JINX_PANEL_DOMAIN", "").strip():
    import urllib.request, ssl
    try:
        ctx=ssl._create_unverified_context()
        with urllib.request.urlopen("https://"+os.environ["JINX_PANEL_DOMAIN"].strip().rstrip("/")+"/jinx-paths.json", context=ctx, timeout=15) as r:
            raw=r.read().decode()
    except Exception as e:
        print("[jinx-node] path fetch failed:", e)
try: paths=json.loads(raw) if raw else {}
except Exception: paths={}
# Accept either base tags or region-prefixed tags.
items=[]
for tag,(port,fallback) in base.items():
    path=paths.get(tag,fallback)
    items.append((path,port))
for tag,(port,fallback) in base.items():
    for key in list(paths):
        if key.endswith("-"+tag) or key == tag:
            items.append((paths[key],port))
# de-duplicate path/port pairs
seen=set(); loc=[]
for path,port in items:
    if (path,port) in seen: continue
    seen.add((path,port)); loc.append((path,port))
with open('/etc/nginx/generated-locations.conf','w') as f:
    for path,port in loc:
        p=path if str(path).startswith('/') else '/'+str(path)
        f.write(f'location = {p} {{ proxy_pass http://127.0.0.1:{port}; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_buffering off; proxy_request_buffering off; proxy_read_timeout 1h; proxy_send_timeout 1h; }}\n')
PY

sed "s/__PORT__/${PORT}/g" /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t

/opt/pg-node/main &
NODE_PID=$!
nginx -g 'daemon off;' &
NGINX_PID=$!
trap 'kill $NODE_PID $NGINX_PID 2>/dev/null || true' EXIT
wait -n $NODE_PID $NGINX_PID
exit 1
