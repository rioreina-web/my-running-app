#!/usr/bin/env bash
# Recompute workout_features for all athletes after the ZONE_WEIGHTS change
# in compute-workout-features (mile=10.0, MP=3.0, HMP=3.5, etc.).
#
# Why this script exists:
#   intensity_score on existing workout_features rows was computed under the
#   OLD weights (mile=5.0, MP=2.5, etc.). The intensity-weighted ACWR will be
#   a Frankenstein of old + new scores until existing rows are recomputed.
#   This forces a full recompute by passing { backfill: true }.
#
# Usage:
#   PROJECT_REF=xxxxxxxxxxxxxxxxxxxx \
#   SERVICE_ROLE_KEY=eyJ... \
#   ./scripts/recompute-workout-features.sh
#
#   or scope to one athlete (faster, safer to test first):
#   PROJECT_REF=xxx SERVICE_ROLE_KEY=eyJ... USER_ID=auth0|abc123 \
#   ./scripts/recompute-workout-features.sh
#
# Environment:
#   PROJECT_REF       Supabase project ref (required)
#   SERVICE_ROLE_KEY  service-role JWT for the project (required)
#   USER_ID           if set, only this user's logs are recomputed
#                     (defaults to ALL users in training_logs)
#
# Idempotent: re-running just overwrites with the same numbers.

set -euo pipefail

if [[ -z "${PROJECT_REF:-}" ]]; then
    echo "ERROR: PROJECT_REF env var is required (your Supabase project ref)." >&2
    exit 1
fi
if [[ -z "${SERVICE_ROLE_KEY:-}" ]]; then
    echo "ERROR: SERVICE_ROLE_KEY env var is required (service-role JWT)." >&2
    exit 1
fi

API="https://${PROJECT_REF}.supabase.co"
FN_URL="${API}/functions/v1/compute-workout-features"
HEADERS=(
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}"
    -H "apikey: ${SERVICE_ROLE_KEY}"
    -H "Content-Type: application/json"
)

# ── Resolve user list ──────────────────────────────────────────────
if [[ -n "${USER_ID:-}" ]]; then
    USERS=("${USER_ID}")
    echo "Scoping recompute to user: ${USER_ID}"
else
    echo "Pulling distinct user_ids from training_logs..."
    USERS_JSON=$(curl -s -X GET \
        "${API}/rest/v1/training_logs?select=user_id&workout_distance_miles=gt.0" \
        "${HEADERS[@]}")
    USERS=($(echo "${USERS_JSON}" | python3 -c '
import sys, json
rows = json.load(sys.stdin)
print("\n".join(sorted({r["user_id"] for r in rows if r.get("user_id")})))'))
    echo "Found ${#USERS[@]} distinct users."
fi

# ── Recompute, one user at a time ──────────────────────────────────
TOTAL=0
FAILED=0
for uid in "${USERS[@]}"; do
    echo
    echo "→ Recomputing for ${uid} ..."
    RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${FN_URL}" \
        "${HEADERS[@]}" \
        -d "{\"user_id\": \"${uid}\", \"backfill\": true}")
    STATUS=$(echo "${RESP}" | grep "^HTTP_STATUS:" | cut -d: -f2)
    BODY=$(echo "${RESP}" | sed '/^HTTP_STATUS:/d')
    if [[ "${STATUS}" == "200" ]]; then
        COUNT=$(echo "${BODY}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("computed", "?"))' 2>/dev/null || echo "?")
        echo "   ✓ ${COUNT} workouts recomputed"
        TOTAL=$((TOTAL + ${COUNT//\"/} 2>/dev/null || echo $TOTAL))
    else
        echo "   ✗ HTTP ${STATUS} — ${BODY}" >&2
        FAILED=$((FAILED + 1))
    fi
done

echo
echo "=================================="
echo "Done. Users processed: ${#USERS[@]}"
echo "       Failed:           ${FAILED}"
echo "=================================="

if [[ "${FAILED}" -gt 0 ]]; then
    exit 1
fi
