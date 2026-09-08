#!/usr/bin/env bash
# Reproduce the 2026-08-11 LLM cost runaway against a throwaway Postgres, then
# prove the migrations stop it. Touches nothing real — no Supabase, no network,
# no Gemini. Takes about 20 seconds.
#
#   ./run.sh
#
# Requires postgresql-16 binaries (macOS: `brew install postgresql@16`).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS="$HERE/../../supabase/migrations"
PGBIN="${PGBIN:-$(dirname "$(command -v initdb || echo /usr/lib/postgresql/16/bin/initdb)")}"
DATA=$(mktemp -d); SOCK=$(mktemp -d)
trap '"$PGBIN/pg_ctl" -D "$DATA" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$DATA" "$SOCK"' EXIT

"$PGBIN/initdb" -D "$DATA" -U postgres --auth=trust >/dev/null
"$PGBIN/pg_ctl" -D "$DATA" -o "-k $SOCK -p 5433 -c listen_addresses=" -l "$DATA/log" start >/dev/null
sleep 3
export PGHOST="$SOCK" PGPORT=5433 PGUSER=postgres
psql -q -d postgres -c "CREATE DATABASE sim;"

echo "── Loading stub schema (pre-fix trigger definitions) ─────────────────"
psql -v ON_ERROR_STOP=1 -q -d sim -f "$HERE/fixture.sql"

echo
echo "── BEFORE the fix: does a completed parse queue another parse? ───────"
psql -q -d sim -f "$HERE/01-reproduce-loop.sql" | grep -A6 "RESULT"

echo
echo "── Applying migrations ───────────────────────────────────────────────"
for f in "$MIGRATIONS"/20260813180000_*.sql \
         "$MIGRATIONS"/20260813180100_*.sql \
         "$MIGRATIONS"/20260813180200_*.sql; do
  printf '   %-68s' "$(basename "$f")"
  psql -v ON_ERROR_STOP=1 -q -d sim -f "$f" >/dev/null && echo "ok"
done

echo
echo "── AFTER the fix: same question ──────────────────────────────────────"
psql -q -d sim -c "DELETE FROM training_logs; DELETE FROM workout_notes; DELETE FROM workout_parse_jobs;" >/dev/null
psql -q -d sim -f "$HERE/01-reproduce-loop.sql" | grep -A6 "RESULT"

echo
echo "── Regressions and ceilings ──────────────────────────────────────────"
fails=0
while IFS='|' read -r name pass; do
  case "$(echo "$pass" | tr -d ' ')" in
    t) printf "   PASS  %s\n" "$name" ;;
    "") ;;
    *) printf "   FAIL  %s\n" "$name"; fails=$((fails+1)) ;;
  esac
done < <(psql -q -t -A -F'|' -d sim -f "$HERE/02-guards.sql" 2>/dev/null | grep -E "^[A-E][0-9]")

echo
if [ "$fails" -eq 0 ]; then echo "All checks passed."; else echo "$fails CHECK(S) FAILED"; exit 1; fi
