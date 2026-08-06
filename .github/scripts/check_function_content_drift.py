#!/usr/bin/env python3
"""Drift check 3: deployed edge-function CONTENT vs repo source.

`check_function_drift.py` compares the *set* of functions (dark functions,
zombies). This compares what each deployed function actually RUNS against
what the repo says it should run.

The gap this closes, concretely (2026-08-06): the iOS client switched
`upload-voice-memo` to a raw-bytes body on 2026-08-04 and the repo function
handled both shapes, but prod still ran the 2026-06-16 JSON-only build. Every
voice memo 400'd for two days. Inventory was clean the whole time — the
function existed in both places. Only the bytes differed. An audit that day
found 41 of 55 deployed functions running older code than the repo, the worst
by 112 days.

Deployed source is fetched with `supabase functions download`, which writes
into `<cwd>/supabase/functions/<slug>`. It is therefore run from a scratch
directory — running it in the repo root OVERWRITES your working tree with the
older deployed files.

Usage (CI):
    supabase functions list --project-ref "$REF" --output json > /tmp/remote_functions.json
    python3 .github/scripts/check_function_content_drift.py --project-ref "$REF"

Usage (local, to see what is stale before deploying):
    python3 .github/scripts/check_function_content_drift.py --project-ref <ref> -v
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile

FUNC_DIR = "supabase/functions"
ALLOWLIST = ".github/scripts/drift_allowlist_functions.txt"
REMOTE_JSON = "/tmp/remote_functions.json"


def load_allowlist() -> set[str]:
    """Slugs marked `content-ok` are exempt from the content comparison.

    Same file as the inventory check, third column kind. Use sparingly and
    always with a reason comment — an exemption here means "we accept that
    prod runs something other than this source."
    """
    out: set[str] = set()
    if not os.path.exists(ALLOWLIST):
        return out
    for line in open(ALLOWLIST):
        line = line.split("#")[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "content-ok":
            out.add(parts[0])
    return out


def repo_functions(root: str) -> set[str]:
    d = os.path.join(root, FUNC_DIR)
    return {
        name
        for name in os.listdir(d)
        if not name.startswith("_")
        and os.path.isfile(os.path.join(d, name, "index.ts"))
    }


def remote_functions(path: str) -> set[str]:
    data = json.load(open(path))
    if isinstance(data, dict):
        data = data.get("functions") or []
    return {d.get("slug") or d.get("name") for d in data if d.get("slug") or d.get("name")}


def download(slug: str, scratch: str, project_ref: str, repo_root: str) -> str | None:
    """Fetch the deployed bundle into its own scratch dir. Returns that dir."""
    dest = os.path.join(scratch, slug)
    os.makedirs(os.path.join(dest, "supabase"), exist_ok=True)
    cfg = os.path.join(repo_root, "supabase", "config.toml")
    if os.path.exists(cfg):
        shutil.copy(cfg, os.path.join(dest, "supabase", "config.toml"))
    proc = subprocess.run(
        ["supabase", "functions", "download", slug, "--project-ref", project_ref],
        cwd=dest, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(f"  ! {slug}: download failed: {proc.stderr.strip().splitlines()[-1:]}")
        return None
    return dest


def compare(slug: str, deployed_root: str, repo_root: str) -> list[str]:
    """Return repo-relative paths whose deployed bytes differ from the repo.

    Covers the function's own files AND any _shared files bundled with it, so
    a stale shared util is caught even when the function's own code is current.
    """
    differing: list[str] = []
    base = os.path.join(deployed_root, FUNC_DIR)
    if not os.path.isdir(base):
        return [f"{slug} (nothing downloaded)"]
    for dirpath, _, filenames in os.walk(base):
        for fn in filenames:
            dep = os.path.join(dirpath, fn)
            rel = os.path.relpath(dep, deployed_root)
            local = os.path.join(repo_root, rel)
            if not os.path.exists(local):
                differing.append(f"{rel} (not in repo)")
                continue
            with open(dep, "rb") as a, open(local, "rb") as b:
                if a.read() != b.read():
                    differing.append(rel)
    return differing


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-ref", required=True)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--remote-json", default=REMOTE_JSON,
                    help="output of `supabase functions list --output json`")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="list every differing file, not just a count")
    args = ap.parse_args()

    repo_root = os.path.abspath(args.repo_root)
    slugs = sorted(repo_functions(repo_root) & remote_functions(args.remote_json) - load_allowlist())
    if not slugs:
        print("No functions present in both repo and prod — nothing to compare.")
        return 0

    scratch = tempfile.mkdtemp(prefix="fn-drift-")
    drifted: dict[str, list[str]] = {}
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {
                pool.submit(download, s, scratch, args.project_ref, repo_root): s
                for s in slugs
            }
            for fut in concurrent.futures.as_completed(futures):
                slug = futures[fut]
                dest = fut.result()
                if dest is None:
                    continue
                diff = compare(slug, dest, repo_root)
                if diff:
                    drifted[slug] = diff
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if not drifted:
        print(f"Function content clean: {len(slugs)} deployed builds match repo source.")
        return 0

    print(f"DRIFT: {len(drifted)} of {len(slugs)} deployed functions do NOT match repo source.")
    print("Prod is running code this repo does not contain. Redeploy via the Deploy workflow.\n")
    for slug in sorted(drifted):
        files = drifted[slug]
        print(f"  {slug}  ({len(files)} file(s) differ)")
        if args.verbose:
            for f in sorted(files):
                print(f"      {f}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
