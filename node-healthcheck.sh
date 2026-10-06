#!/usr/bin/env bash
curl -fsS -o /dev/null --max-time 4 http://127.0.0.1:8080/healthz || exit 1
kill -0 "$(pgrep -o -f '/opt/pg-node/main' || true)" 2>/dev/null || exit 1
exit 0
