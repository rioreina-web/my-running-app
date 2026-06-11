#!/usr/bin/env python3
"""Eval-coverage gate (CLAUDE.md hard rule #3, enforced in CI).

"No LLM prompt change ships without running the eval harness."

Rule, made mechanical: if a PR modifies a prompt file
(supabase/functions/_shared/prompts/<name>.v<k>.ts), then a cassette
directory supabase/functions/_evals/cassettes/<name>.v<k>/ must exist.
If it didn't exist before the PR, the PR must add it.

This intentionally does NOT fail on legacy prompts that lack cassettes
but are untouched by the PR — coverage is ratcheted up as prompts get
edited, per the roadmap (Phase 2), not all at once.

Usage (CI): check_eval_coverage.py <base-ref>
  Diffs HEAD against <base-ref> (e.g. origin/main).
"""

import os
import re
import subprocess
import sys

PROMPTS_DIR = "supabase/functions/_shared/prompts"
CASSETTES_DIR = "supabase/functions/_evals/cassettes"


def changed_files(base: str) -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [l.strip() for l in out.splitlines() if l.strip()]


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    changed = changed_files(base)

    touched_prompts = []
    for f in changed:
        m = re.match(rf"{re.escape(PROMPTS_DIR)}/(.+)\.ts$", f)
        if m:
            touched_prompts.append(m.group(1))  # e.g. "daily-read.v2"

    if not touched_prompts:
        print("No prompt files touched — eval gate not applicable.")
        return 0

    missing = []
    for name in touched_prompts:
        cassette_dir = os.path.join(CASSETTES_DIR, name)
        if not os.path.isdir(cassette_dir) or not os.listdir(cassette_dir):
            missing.append(name)

    if missing:
        print("EVAL GATE FAILED — prompt changed without cassette coverage:")
        for name in missing:
            print(f"  {PROMPTS_DIR}/{name}.ts  ->  needs {CASSETTES_DIR}/{name}/")
        print()
        print("Record a cassette via supabase/functions/_evals/record.ts")
        print("(needs GEMINI_API_KEY) and commit it with the prompt change.")
        print("See supabase/functions/_evals/README.md and CLAUDE.md hard rule #3.")
        return 1

    print(f"Eval gate passed: {len(touched_prompts)} touched prompt(s) all have cassettes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
