#!/usr/bin/env python3
"""Drift check 2: repo edge-function directories vs prod function inventory.

Reads /tmp/remote_functions.json (output of `supabase functions list
--output json`) and compares slugs against supabase/functions/<dir>/index.ts.

Directories starting with `_` (e.g. _shared, _evals) are infrastructure,
not deployable functions.
"""

import json
import os
import sys

FUNC_DIR = "supabase/functions"
ALLOWLIST = ".github/scripts/drift_allowlist_functions.txt"


def load_allowlist() -> dict[str, str]:
    """slug -> 'repo-only' | 'prod-only'"""
    out: dict[str, str] = {}
    if not os.path.exists(ALLOWLIST):
        return out
    for line in open(ALLOWLIST):
        line = line.split("#")[0].strip()
        if line:
            parts = line.split()
            if len(parts) >= 2:
                out[parts[0]] = parts[1]
    return out


def repo_functions() -> set[str]:
    out = set()
    for d in os.listdir(FUNC_DIR):
        if d.startswith("_"):
            continue
        if os.path.isfile(os.path.join(FUNC_DIR, d, "index.ts")):
            out.add(d)
    return out


def remote_functions() -> set[str]:
    data = json.load(open("/tmp/remote_functions.json"))
    if isinstance(data, dict):
        data = data.get("functions") or []
    return {d.get("slug") or d.get("name") for d in data}


def main() -> int:
    repo = repo_functions()
    remote = remote_functions()
    allow = load_allowlist()

    allowed_repo_only = {s for s, kind in allow.items() if kind == "repo-only"}
    allowed_prod_only = {s for s, kind in allow.items() if kind == "prod-only"}

    only_repo = repo - remote - allowed_repo_only   # dark: in repo, never deployed
    only_remote = remote - repo - allowed_prod_only  # zombie: live in prod, no source in repo

    ok = True
    if only_repo:
        ok = False
        print("DRIFT: functions in repo but NOT deployed (dark functions):")
        for f in sorted(only_repo):
            print(f"  {f}")
    if only_remote:
        ok = False
        print("DRIFT: functions live in prod with NO repo source (zombies):")
        for f in sorted(only_remote):
            print(f"  {f}  -> supabase functions delete {f}")
    if ok:
        allow_note = f", {len(allow)} allowlisted" if allow else ""
        print(f"Function inventory clean: {len(repo & remote)} in sync{allow_note}.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
