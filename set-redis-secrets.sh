#!/bin/bash
# set-redis-secrets.sh — one-shot setup for the rate limiter's Upstash Redis
# secrets (2026-07-21, written with Claude).
#
# Usage:
#   1. On the Upstash database page → REST API section → ".env" tab → Copy.
#   2. In Terminal:  pbpaste > ~/my-running-app/upstash.env
#   3. In Terminal:  bash ~/my-running-app/set-redis-secrets.sh
#
# The script verifies the URL+token pair against Upstash BEFORE saving, maps
# Upstash's names (UPSTASH_REDIS_REST_URL/_TOKEN) to the names the edge
# functions read (UPSTASH_REDIS_URL/_TOKEN), sets them on the Supabase
# project, and deletes upstash.env so no secret is left on disk.

set -e
cd "$(dirname "$0")"

if [ ! -f upstash.env ]; then
  echo "✗ upstash.env not found."
  echo "  On the Upstash page, click the .env tab's Copy button, then run:"
  echo "  pbpaste > ~/my-running-app/upstash.env"
  exit 1
fi

# shellcheck disable=SC1091
source ./upstash.env

if [ -z "$UPSTASH_REDIS_REST_URL" ] || [ -z "$UPSTASH_REDIS_REST_TOKEN" ]; then
  echo "✗ The file didn't contain UPSTASH_REDIS_REST_URL / UPSTASH_REDIS_REST_TOKEN."
  echo "  Make sure you copied from the .env tab (it has exactly those two lines),"
  echo "  then redo:  pbpaste > ~/my-running-app/upstash.env"
  exit 1
fi

echo "Checking the URL + token pair against Upstash..."
CHECK=$(curl -s "$UPSTASH_REDIS_REST_URL/get/secrets-script-probe" \
  -H "Authorization: Bearer $UPSTASH_REDIS_REST_TOKEN")

case "$CHECK" in
  *'"result"'*)
    echo "✓ Upstash accepted the pair."
    ;;
  *)
    echo "✗ Upstash rejected this URL + token pair."
    echo "  Response: $CHECK"
    echo "  Re-copy the .env block (both lines come from the SAME database page),"
    echo "  redo the pbpaste step, and run this script again."
    exit 1
    ;;
esac

echo "Saving secrets to the Supabase project..."
supabase secrets set \
  UPSTASH_REDIS_URL="$UPSTASH_REDIS_REST_URL" \
  UPSTASH_REDIS_TOKEN="$UPSTASH_REDIS_REST_TOKEN"

rm -f upstash.env
echo "✓ Done. Secrets set and upstash.env deleted."
