#!/usr/bin/env python3
"""
CI gate: LLM cost guardrails.

Born from the 2026-08-11 cost runaway (1,269 unmetered Gemini calls from a
trigger loop — see supabase/migrations/20260813180000_* for the post-mortem)
and the $7-day audit (COST-AUDIT-2026-08-13.md). Two rules:

RULE 1 — every edge function that calls an LLM must consult the budget guard.
  A file under supabase/functions/ that talks to Gemini/Groq must reference
  llm_budget_allows (via _shared/llm-budget.ts or RPC). Files that predate the
  guard are grandfathered in BASELINE_UNGUARDED below and only WARN — the
  list is a ratchet: wire a file up, remove it from the list, and it can
  never regress. NEW call sites fail the build immediately.
  Escape hatch for deliberate exceptions: a comment containing
  `llm-guard-exempt: <reason>` in the file.

RULE 2 — no new no-op-write trigger loops.
  Any NEW migration (timestamp > CUTOFF) that creates an `AFTER UPDATE OF`
  trigger, or a trigger function that enqueues work / calls net.http_post,
  must contain a value-change guard (`IS DISTINCT FROM`). Postgres fires
  `UPDATE OF col` on ASSIGNMENT, not on change — writing the same value
  counts. That single fact is how completion manufactured its own next
  assignment on Aug 11. Escape hatch: `no-op-guard-exempt: <reason>`.

Run: python3 .github/scripts/check_llm_guardrails.py
Exit 0 = clean (warnings allowed), 1 = violations.
"""

import os
import re
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
FUNCTIONS_DIR = os.path.join(REPO, "supabase", "functions")
MIGRATIONS_DIR = os.path.join(REPO, "supabase", "migrations")

# Migrations at or before this version predate the guard and are history
# (append-only, never edited) — only newer files are checked by RULE 2.
MIGRATION_CUTOFF = "20260813180200"

# Signals that a TS file makes provider LLM calls.
LLM_CALL_PATTERNS = [
    "generativelanguage.googleapis.com",
    "GoogleGenerativeAI(",
    "api.groq.com/openai/v1/chat",
]

# Grandfathered pre-guard call sites. RATCHET: wiring one up means deleting
# its line here in the same PR. Never add to this list.
BASELINE_UNGUARDED = {
    "ask/index.ts",
    "biomechanics-analysis/index.ts",
    "block-review/index.ts",
    "coach-workout-read/index.ts",
    "coaching-agent/index.ts",
    "compare-workouts/index.ts",
    "correct-workout-structure/index.ts",
    "custom-plan-builder/index.ts",
    "draft-block-rewrite/index.ts",
    "extract-rpe/index.ts",           # covered upstream by SQL dispatcher guard
    "form-check-analysis/index.ts",
    "generate-training-plan/index.ts",
    "ingest-documents/index.ts",
    "ingest-manual-workout/index.ts",
    "injury-early-warning/index.ts",
    "interpret-goal/index.ts",
    "parse-training-plan/index.ts",
    "parse-training-week/index.ts",
    "parse-workout-structure/index.ts",  # covered upstream by SQL dispatcher guard
    "post-run-analysis/index.ts",
    "process-check-in/index.ts",
    "race-intel/index.ts",
    "race-readiness/index.ts",
    "reschedule-plan/index.ts",
    "suggest-workout-progression/index.ts",
    "weekly-coaching-report/index.ts",
}


def check_functions():
    errors, warnings = [], []
    for root, _dirs, files in os.walk(FUNCTIONS_DIR):
        rel_root = os.path.relpath(root, FUNCTIONS_DIR)
        # _evals is the offline eval harness (developer-run, cassette-gated);
        # _shared is library code with no entry points of its own.
        if rel_root.split(os.sep)[0] in ("_evals", "_shared"):
            continue
        for fname in files:
            if not fname.endswith(".ts") or fname.endswith(".test.ts"):
                continue
            rel = os.path.join(rel_root, fname).replace(os.sep, "/")
            path = os.path.join(root, fname)
            try:
                src = open(path, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            if not any(p in src for p in LLM_CALL_PATTERNS):
                continue
            if "llm_budget_allows" in src or "llm-budget.ts" in src:
                continue
            if "llm-guard-exempt:" in src:
                continue
            if rel in BASELINE_UNGUARDED:
                warnings.append(
                    f"  WARN  {rel} calls an LLM without the budget guard "
                    f"(grandfathered — wire it up and remove from BASELINE_UNGUARDED)"
                )
            else:
                errors.append(
                    f"  FAIL  {rel} calls an LLM but never consults llm_budget_allows.\n"
                    f"        Import _shared/llm-budget.ts and gate the call, or add\n"
                    f"        `// llm-guard-exempt: <reason>` if this is deliberate."
                )
    return errors, warnings


def check_migrations():
    errors = []
    ts_re = re.compile(r"^(\d{8,14})_")
    for fname in sorted(os.listdir(MIGRATIONS_DIR)):
        if not fname.endswith(".sql"):
            continue
        m = ts_re.match(fname)
        if not m:
            continue
        version = m.group(1).ljust(14, "0")
        if version <= MIGRATION_CUTOFF:
            continue
        path = os.path.join(MIGRATIONS_DIR, fname)
        try:
            src = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        upper = src.upper()
        if "no-op-guard-exempt:" in src:
            continue
        creates_update_of_trigger = "AFTER UPDATE OF" in upper or (
            "AFTER INSERT OR UPDATE" in upper and "TRIGGER" in upper
        )
        enqueues = "NET.HTTP_POST" in upper or re.search(
            r"INSERT\s+INTO\s+\S*_JOBS", upper
        )
        if creates_update_of_trigger and enqueues and "IS DISTINCT FROM" not in upper:
            errors.append(
                f"  FAIL  supabase/migrations/{fname} adds an UPDATE trigger that "
                f"enqueues work\n"
                f"        without a value-change guard. Postgres fires `UPDATE OF col` "
                f"on ASSIGNMENT,\n"
                f"        not on change — this is the exact shape of the 2026-08-11 "
                f"runaway loop.\n"
                f"        Compare OLD vs NEW with `IS DISTINCT FROM` and return early, "
                f"or add\n"
                f"        `-- no-op-guard-exempt: <reason>`."
            )
    return errors


def main():
    fn_errors, fn_warnings = check_functions()
    mig_errors = check_migrations()

    for w in fn_warnings:
        print(w)
    all_errors = fn_errors + mig_errors
    for e in all_errors:
        print(e)

    if all_errors:
        print(f"\nLLM guardrail check FAILED ({len(all_errors)} violation(s)).")
        return 1
    print(
        f"\nLLM guardrail check passed "
        f"({len(fn_warnings)} grandfathered warning(s) remaining)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
