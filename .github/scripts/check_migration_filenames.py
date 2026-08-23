#!/usr/bin/env python3
"""Migration filename gate (CLAUDE.md hard rule #5 / #9 support, enforced in CI).

Migrations are append-only and reach prod only via `supabase db push`. Both
rules assume the CLI and the repo agree on what a migration's *version* is.
They stop agreeing when a filename is malformed, and the failure is silent.

## The failure this prevents (it already happened)

`20260128_152000_user_profile.sql` was intended as version 20260128152000.
The CLI reads the version as the digits before the FIRST underscore, so it
parsed as `20260128` — colliding with the already-applied
`20260128_fix_vector_search.sql`. The CLI saw the version in the ledger and
silently skipped the file. From January onward `user_profiles` did not exist
in prod, which produced three layers of defensive workarounds across web,
iOS and the edge functions, two quarantined migrations, and a blocked Daily
Read cron. See docs/migration-ledger-reconciliation-2026-06-11.md.

Nothing in CI caught it, because a skipped migration is not an error — it
looks exactly like an already-applied one.

## The two checks

1. COLLISION (all files, always). Every migration in supabase/migrations/
   must parse to a unique version. This is the check that would have caught
   the original bug on the PR that introduced it. It is not ratcheted:
   a collision is never acceptable, legacy or not.

2. FORMAT (changed files only, ratcheted). New or modified migrations must
   be named <14-digit-timestamp>_<snake_case_name>.sql. 24 legacy files use
   an 8-digit prefix; they are already applied in prod and renaming them
   would re-diverge the ledger, so they are grandfathered — exactly the
   ratchet used by check_eval_coverage.py. Touch one, and it must be fixed.

Usage:
  check_migration_filenames.py                 # collision check only
  check_migration_filenames.py <base-ref>      # + format check vs base ref
"""

import os
import re
import subprocess
import sys

MIGRATIONS_DIR = "supabase/migrations"

# Mirrors the Supabase CLI: the version is the run of leading digits up to
# the first underscore. `20260128_152000_user_profile.sql` -> "20260128".
VERSION_RE = re.compile(r"^(\d+)_")

# The required shape for anything new: 14-digit UTC timestamp, then a
# lowercase snake_case description.
WELL_FORMED_RE = re.compile(r"^\d{14}_[a-z0-9_]+\.sql$")


def migration_files() -> list[str]:
    if not os.path.isdir(MIGRATIONS_DIR):
        return []
    return sorted(f for f in os.listdir(MIGRATIONS_DIR) if f.endswith(".sql"))


def changed_files(base: str) -> list[str]:
    # --diff-filter=d excludes deletions: a removed migration has no filename
    # left to validate. Added/Copied/Modified/Renamed still count, so moving a
    # quarantined file back into supabase/migrations/ is checked like a new one.
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=d", f"{base}...HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [l.strip() for l in out.splitlines() if l.strip()]


def check_collisions(files: list[str]) -> list[str]:
    """Return human-readable collision descriptions (empty == pass)."""
    by_version: dict[str, list[str]] = {}
    unparseable: list[str] = []

    for f in files:
        m = VERSION_RE.match(f)
        if not m:
            unparseable.append(f)
            continue
        by_version.setdefault(m.group(1), []).append(f)

    problems = []
    for version, group in sorted(by_version.items()):
        if len(group) > 1:
            problems.append(
                f"version {version} claimed by {len(group)} files: " + ", ".join(group)
            )
    for f in unparseable:
        problems.append(f"{f} has no leading numeric version — the CLI cannot order it")
    return problems


def check_format(files: list[str]) -> list[str]:
    return [f for f in files if not WELL_FORMED_RE.match(f)]


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else None
    all_files = migration_files()

    if not all_files:
        print(f"No migrations found in {MIGRATIONS_DIR}/ — nothing to check.")
        return 0

    failed = False

    # ── Check 1: collisions across every migration ──
    collisions = check_collisions(all_files)
    if collisions:
        failed = True
        print("MIGRATION FILENAME GATE FAILED — colliding versions:")
        for c in collisions:
            print(f"  {c}")
        print()
        print("Two migrations that parse to the same version make `supabase db push`")
        print("silently skip one of them. Re-stamp the newer file with a unique")
        print("14-digit UTC timestamp before merging.")
        print()
    else:
        print(f"Collision check passed: {len(all_files)} migrations, all versions unique.")

    # ── Check 2: format, ratcheted to changed files ──
    if base is None:
        print("No base ref given — skipping the format check (collision check only).")
        return 1 if failed else 0

    touched = [
        os.path.basename(f)
        for f in changed_files(base)
        if f.startswith(MIGRATIONS_DIR + "/") and f.endswith(".sql")
    ]

    if not touched:
        print("No migrations touched — format check not applicable.")
        return 1 if failed else 0

    malformed = check_format(touched)
    if malformed:
        failed = True
        print("MIGRATION FILENAME GATE FAILED — malformed new/changed migrations:")
        for f in malformed:
            print(f"  {MIGRATIONS_DIR}/{f}")
        print()
        print("Required: <14-digit-UTC-timestamp>_<snake_case_name>.sql")
        print("  good: 20260611140000_backfill_workout_insights_via_outbox.sql")
        print("  bad:  20260128_152000_user_profile.sql   (parses as version 20260128)")
        print("  bad:  20260202_user_memories.sql         (8-digit prefix)")
        print()
        print("Generate a correct stamp with:  date -u +%Y%m%d%H%M%S")
        print("See docs/migration-ledger-reconciliation-2026-06-11.md for why this matters.")
    else:
        print(f"Format check passed: {len(touched)} touched migration(s) well-formed.")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
