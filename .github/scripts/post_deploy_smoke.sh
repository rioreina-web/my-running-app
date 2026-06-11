#!/usr/bin/env bash
# Post-deploy smoke tests (Phase 3 of docs/ops-delivery-roadmap-2026-06-10.md;
# automates operator-checklist-2026-06-09.md §5-6 verifications).
#
# Required env:
#   SUPABASE_URL       — https://<ref>.supabase.co
#   SUPABASE_ANON_KEY  — publishable anon key (for the health ping)
#
# Checks:
#   1. Gateway health: a known function answers (any HTTP status < 500).
#   2. CORS hardening: an OPTIONS preflight from an unknown origin must NOT
#      be granted that origin (no Access-Control-Allow-Origin: * and no echo
#      of the evil origin) — verifies ALLOWED_ORIGIN is set in prod.
#
# The confirmed_races data check (checklist §6) needs an authenticated user
# context and stays a manual SQL-editor step for now — see the checklist.

set -euo pipefail

FN="${SMOKE_FUNCTION:-get-pace-zones}"
URL="$SUPABASE_URL/functions/v1/$FN"
EVIL_ORIGIN="https://evil.example.com"

echo "== 1. Gateway health: $FN"
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  "$URL")
echo "   HTTP $status"
if [ "$status" -ge 500 ] || [ "$status" -eq 000 ]; then
  echo "   FAIL: function gateway unhealthy (HTTP $status)"
  exit 1
fi

echo "== 2. CORS preflight from unknown origin must be rejected"
acao=$(curl -s -D - -o /dev/null -X OPTIONS \
  -H "Origin: $EVIL_ORIGIN" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type" \
  "$URL" | tr -d '\r' | grep -i '^access-control-allow-origin:' | awk '{print $2}' || true)
echo "   Access-Control-Allow-Origin: '${acao:-<absent>}'"
if [ "$acao" = "*" ] || [ "$acao" = "$EVIL_ORIGIN" ]; then
  echo "   FAIL: unknown origin granted — ALLOWED_ORIGIN is not enforced in prod"
  exit 1
fi

echo "SMOKE PASSED"
