#!/usr/bin/env python3
"""Eval-coverage gate (CLAUDE.md hard rule #3, enforced in CI).

Golden-set policy (2026-07-07, see
outputs/coach-shapeable-ai-architecture-2026-07-07.md §6):

The gate BLOCKS only for the GOLDEN prompt families — the athlete-facing,
safety-baitable surfaces where a silent regression hurts most. For those,
a touched prompt must have a cassette directory containing at least one
RECORDED cassette (non-empty `recorded_response`); stubs alone don't count.

For every other prompt family, missing/stub-only coverage produces a
WARNING but does not fail the build. Those prompts are gated by manual
review against docs/coaching/principles.md, and coverage is expected to
grow from real usage via the promote-to-cassette flow
(outputs/ai-feedback-loop-design-2026-07-07.md) rather than synthetic
authoring.

As before, the gate only looks at prompts TOUCHED by the PR (a ratchet,
not a big bang), and deletions are exempt.

Usage (CI): check_eval_coverage.py <base-ref>
  Diffs HEAD against <base-ref> (e.g. origin/main).
"""

import json
import os
import re
import subprocess
import sys

PROMPTS_DIR = "supabase/functions/_shared/prompts"
CASSETTES_DIR = "supabase/functions/_evals/cassettes"

# Prompt FAMILIES (name without .v<k>) that block the build when touched
# without recorded cassette coverage. Keep this list short and honest —
# it should be the surfaces where an athlete can be baited into medical
# territory or where a proposal mutates training.
GOLDEN_FAMILIES = {
    "daily-read",
    "injury-analysis",
    "reschedule-plan",
    "coaching-agent-simple",
    "coaching-agent-moderate",
    "coaching-agent-complex",
    "coaching-agent-proactive",
    # Phase E assisted block rewrite (2026-07-15): proposes plan mutations
    # and is baitable into medical territory ("athlete's knee hurts, fix
    # the plan"), so it's golden from day one. Cassettes are stubs as of
    # 2026-07-15 — the next PR touching this prompt must record them.
    "draft-block-rewrite",
}


def changed_files(base: str) -> list[str]:
    # --diff-filter=d EXCLUDES deletions: a deleted prompt has no behavior
    # left to validate, so it must not demand a cassette (otherwise cutting
    # a prompt is impossible without recording a cassette for a file that
    # no longer exists). Added/Copied/Modified/Renamed still count.
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=d", f"{base}...HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [l.strip() for l in out.splitlines() if l.strip()]


def family_of(prompt_name: str) -> str:
    """"daily-read.v5" -> "daily-read"."""
    return re.sub(r"\.v\d+$", "", prompt_name)


def coverage_state(prompt_name: str) -> str:
    """Return "recorded", "stubs-only", or "missing" for a prompt's cassettes."""
    cassette_dir = os.path.join(CASSETTES_DIR, prompt_name)
    if not os.path.isdir(cassette_dir):
        return "missing"
    saw_any = False
    for fname in sorted(os.listdir(cassette_dir)):
        if not fname.endswith(".json"):
            continue
        saw_any = True
        try:
            with open(os.path.join(cassette_dir, fname), encoding="utf-8") as fh:
                cassette = json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue  # unreadable cassette can't count as recorded
        if str(cassette.get("recorded_response", "")).strip():
            return "recorded"
    return "stubs-only" if saw_any else "missing"


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

    blocking: list[tuple[str, str]] = []
    warnings: list[tuple[str, str]] = []
    for name in touched_prompts:
        state = coverage_state(name)
        if state == "recorded":
            continue
        if family_of(name) in GOLDEN_FAMILIES:
            blocking.append((name, state))
        else:
            warnings.append((name, state))

    for name, state in warnings:
        print(f"WARNING — {PROMPTS_DIR}/{name}.ts touched with {state} cassette")
        print(f"  coverage ({CASSETTES_DIR}/{name}/). Not blocking — non-golden")
        print("  family; gate is manual review against docs/coaching/principles.md.")

    if blocking:
        print()
        print("EVAL GATE FAILED — golden prompt changed without RECORDED cassettes:")
        for name, state in blocking:
            print(f"  {PROMPTS_DIR}/{name}.ts  ->  {CASSETTES_DIR}/{name}/ is {state}")
        print()
        print("Golden families (daily-read, injury-analysis, reschedule-plan,")
        print("coaching-agent-*) must ship with at least one recorded cassette.")
        print("Record via: GEMINI_API_KEY=... deno run --allow-net --allow-read \\")
        print("  --allow-write --allow-env supabase/functions/_evals/record.ts <prompt>")
        print("See supabase/functions/_evals/README.md and CLAUDE.md hard rule #3.")
        return 1

    ok = len(touched_prompts) - len(warnings)
    print(f"Eval gate passed: {ok} recorded, {len(warnings)} warned (non-golden), "
          f"of {len(touched_prompts)} touched prompt(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
