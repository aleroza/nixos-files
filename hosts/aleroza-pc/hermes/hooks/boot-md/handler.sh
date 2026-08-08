#!/usr/bin/env bash
# boot-md hook — runs on every gateway startup.
#
# Probes OpenViking with a real-embedding call (viking_add_resource
# via the public Admin API path), and on degraded state sends a
# Telegram message to the first user in TELEGRAM_ALLOWED_USERS.
#
# No-op on healthy run (silent). Errors are caught and logged
# without affecting the gateway startup.

set -euo pipefail

ENDPOINT="${OPENVIKING_ENDPOINT:-http://127.0.0.1:1933}"
USER_KEY_FILE="${OPENVIKING_USER_KEY_FILE:-/opt/openviking/keys/user_key}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_ALLOWED_USERS="${TELEGRAM_ALLOWED_USERS:-}"

# Read bearer from env (preferred) or file (fallback).
bearer=""
if [[ -n "${OPENVIKING_API_KEY:-}" ]]; then
  bearer="$OPENVIKING_API_KEY"
elif [[ -r "$USER_KEY_FILE" ]]; then
  bearer=$(<"$USER_KEY_FILE") || true
fi

# Track errors. status=ok = silent, anything else = notify.
status="ok"
detail=""

# 1. Health probe — 3 s timeout.
if ! curl -fsS --max-time 3 -H "Authorization: Bearer ${bearer}" \
    "$ENDPOINT/health" >/dev/null 2>&1; then
  status="degraded"
  detail="health probe failed"
fi

# 2. Ready probe — 10 s timeout. Skipped if health already failed.
if [[ "$status" == "ok" ]]; then
  if ! curl -fsS --max-time 10 -H "Authorization: Bearer ${bearer}" \
      "$ENDPOINT/ready" >/dev/null 2>&1; then
    status="degraded"
    detail="ready probe failed"
  fi
fi

# 3. Real-embedding call. The OpenViking API exposes a resource
#    ingest endpoint that triggers a fresh embedding call against
#    the configured provider (Gemini). The exact path may differ
#    between versions; the upstream server's /openapi.json is the
#    source of truth. We try a few known paths in order.
if [[ "$status" == "ok" ]]; then
  body='{"resource":"https://example.com/openviking-bootmd-probe","reason":"boot-md probe"}'
  ingest_ok=0
  for path in \
      "/api/v1/resources" \
      "/api/v1/viking/resources" \
      "/api/v1/fs/add"; do
    if curl -fsS --max-time 15 \
        -X POST \
        -H "Authorization: Bearer ${bearer}" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$ENDPOINT$path" >/dev/null 2>&1; then
      ingest_ok=1
      break
    fi
  done
  if [[ "$ingest_ok" -ne 1 ]]; then
    status="degraded"
    detail="real-embedding probe failed"
  fi
fi

# Log outcome. journald captures stderr.
if [[ "$status" == "ok" ]]; then
  echo "[boot-md] openviking probe ok" >&2
  exit 0
fi

# Notify on degraded.
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_ALLOWED_USERS" ]]; then
  chat_id="${TELEGRAM_ALLOWED_USERS%%,*}"
  if [[ -n "$chat_id" ]]; then
    msg="⚠ OpenViking probe at gateway startup: ${status} — ${detail}"
    curl -fsS --max-time 5 \
      -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${chat_id}" \
      --data-urlencode "text=${msg}" \
      --data-urlencode "disable_notification=true" \
      >/dev/null 2>&1 || true
  fi
fi

echo "[boot-md] openviking probe ${status}: ${detail}" >&2
exit 0
