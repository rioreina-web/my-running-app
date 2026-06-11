#!/usr/bin/env python3
"""Drift check 1: repo migration files vs prod migration ledger.

Reads the output of `supabase migration list --linked` (JSON if available,
table-text fallback) and compares against supabase/migrations/*.sql.

Known, documented exceptions live in .github/scripts/drift_allowlist.txt —
one migration version per line. These are the consciously-unapplied
migrations from docs/migration-ledger-reconciliation-2026-06-11.md Step 3.
"""

import json
import os
import re
import sys

REPO_DIR = "supabase/migrations"
ALLOWLIST = ".github/scripts/drift_allowlist.txt"


def load_allowlist() -> set[str]:
    if not os.path.exists(ALLOWLIST):
        return set()
    out = set()
    for line in open(ALLOWLIST):
        line = line.split("#")[0].strip()
        if line:
            out.add(line)
    return out


def repo_versions() -> set[str]:
    out = set()
    for f in os.listdir(REPO_DIR):
        m = re.match(r"(\d{8,14})_.+\.sql$", f)
        if m:
            out.add(m.group(1))
    return out


def remote_versions() -> set[str]:
    if os.path.exists("/tmp/remote_migrations.json"):
        data = json.load(open("/tmp/remote_migrations.json"))
        # CLI json shape: list of {"version": ..., ...} or {"remote": [...]}
        if isinstance(data, dict):
            data = data.get("remote") or data.get("migrations") or []
        return {str(d["version"]) for d in data if d.get("version")}
    # Table-text fallback: lines like "  20260125 | 20260125 | ..."
    out = set()
    for line in open("/tmp/remote_migrations.txt"):
        for tok in re.findall(r"\b\d{8,14}\b", line):
            out.add(tok)
    return out


def main() -> int:
    allow = load_allowlist()
    repo = repo_versions()
    remote = remote_versions()

    only_repo = repo - remote - allow
    only_remote = remote - repo

    ok = True
    if only_repo:
        ok = False
        print("DRIFT: migrations in repo but NOT applied in prod (and not allowlisted):")
        for v in sorted(only_repo):
            print(f"  {v}")
    if only_remote:
        ok = False
        print("DRIFT: migrations applied in prod with NO repo file:")
        for v in sorted(only_remote):
            print(f"  {v}")
    if ok:
        print(f"Migration ledger clean: {len(repo & remote)} in sync, {len(allow & repo)} allowlisted pending.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
