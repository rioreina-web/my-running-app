#!/usr/bin/env python3
"""Design-token lint gate (CLAUDE.md design system, enforced in CI).

Post Run Drip's design system is written down (`design-system/README.md`,
`colors_and_type.css`) but historically nothing mechanical defended it, so
drift accumulated faster than it was cleaned (see
`outputs/design-system-audit-2026-05-20.md`). This gate is that mechanism.

It is **diff-aware and ratcheting**, exactly like the eval-coverage gate:
it only fails on violations *introduced by the PR*, never on the existing
debt (723 `dripCaption` callsites, 101 web `tracking-[]`, 291 web
`text-[]`, 3 iOS files with hardcoded hex). That debt is paid down
surface-by-surface per the remediation plan; this gate stops the pile from
growing.

Rules (checked on ADDED lines only):

  iOS (RunningLog/**.swift)
    R1  No `Color.drip.electric` — deprecated alias; use `.coralDeep`.
    R2  No `Color(hex: "…")` outside the token source (DesignSystem.swift)
        — colors live as `Color.drip.*` tokens, not inline hex in views.

  Web (web/src/**.{ts,tsx})
    R3  No arbitrary `tracking-[…]` — use a tracking token utility.
    R4  No arbitrary `text-[Npx]` — use the type scale.

Usage (CI):  check_design_tokens.py <base-ref>
  Diffs HEAD against <base-ref> (e.g. origin/main), inspects added lines.

Local:  check_design_tokens.py            # defaults base to origin/main
        check_design_tokens.py --staged   # check staged changes (pre-commit)
"""

import re
import subprocess
import sys

# --- rule definitions -------------------------------------------------------
# Each rule: (id, message, compiled line-pattern, path-predicate).
# path-predicate returns True if the rule applies to the given file path.

DESIGN_SYSTEM_FILE = "DesignSystem.swift"  # the one place tokens are defined


def _ios(path: str) -> bool:
    return path.startswith("RunningLog/") and path.endswith(".swift")


def _ios_view(path: str) -> bool:
    # iOS, but not the token source itself.
    return _ios(path) and not path.endswith(DESIGN_SYSTEM_FILE)


def _web(path: str) -> bool:
    return path.startswith("web/src/") and path.endswith((".ts", ".tsx"))


RULES = [
    (
        "R1-electric",
        "`Color.drip.electric` is deprecated — use `Color.drip.coralDeep`.",
        re.compile(r"\bdrip\.electric\b"),
        _ios,
    ),
    (
        "R2-hardcoded-hex",
        "Hardcoded hex in a view — add/use a `Color.drip.*` token in DesignSystem.swift.",
        re.compile(r'Color\(hex:\s*"'),
        _ios_view,
    ),
    (
        "R3-arbitrary-tracking",
        "Arbitrary `tracking-[…]` literal — use a tracking token utility (0.10/0.12/0.14em).",
        re.compile(r"tracking-\["),
        _web,
    ),
    (
        "R4-arbitrary-text-size",
        "Arbitrary `text-[Npx]` literal — use the type scale.",
        re.compile(r"text-\[\d+(?:\.\d+)?px\]"),
        _web,
    ),
]


# --- diff parsing -----------------------------------------------------------

def added_lines(diff_args: list[str]) -> list[tuple[str, int, str]]:
    """Return (path, new_line_no, text) for every added line in the diff.

    Uses `-U0` so only changed lines appear, and tracks the new-file line
    number from each hunk header (`@@ -a,b +c,d @@`).
    """
    out = subprocess.run(
        ["git", "diff", "-U0", "--no-color", *diff_args],
        capture_output=True, text=True, check=True,
    ).stdout

    results: list[tuple[str, int, str]] = []
    path = None
    new_lineno = 0
    hunk_re = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")

    for line in out.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            continue
        if line.startswith("+++ ") or line.startswith("--- "):
            continue
        m = hunk_re.match(line)
        if m:
            new_lineno = int(m.group(1))
            continue
        if line.startswith("+"):
            # An added line. Record with its new-file line number.
            if path is not None:
                results.append((path, new_lineno, line[1:]))
            new_lineno += 1
        elif not line.startswith("-"):
            # Context line (rare with -U0) advances the new-file counter.
            new_lineno += 1
        # '-' (removed) lines don't advance the new-file counter.
    return results


def strip_comment(text: str, path: str) -> str:
    """Drop trailing line comments so doc-comments mentioning a token don't
    trip the gate. Conservative: only strips obvious `//` (swift/ts) tails.
    Not language-aware about strings, which is fine — the patterns we match
    (drip.electric, Color(hex:, tracking-[) don't legitimately appear inside
    a string literal in these codebases."""
    idx = text.find("//")
    return text[:idx] if idx != -1 else text


# --- main -------------------------------------------------------------------

def main() -> int:
    if "--staged" in sys.argv:
        diff_args = ["--cached"]
    else:
        base = next((a for a in sys.argv[1:] if not a.startswith("-")), "origin/main")
        diff_args = [f"{base}...HEAD"]

    violations: list[tuple[str, str, int, str]] = []  # (rule_id, path, line, msg)

    for path, lineno, raw in added_lines(diff_args):
        code = strip_comment(raw, path)
        for rule_id, msg, pattern, applies in RULES:
            if applies(path) and pattern.search(code):
                violations.append((rule_id, path, lineno, msg))

    if not violations:
        print("Design-token gate passed: no new token violations in this diff.")
        return 0

    print("DESIGN-TOKEN GATE FAILED — new violations introduced by this change:")
    print()
    for rule_id, path, lineno, msg in violations:
        # GitHub Actions annotation — surfaces inline on the PR diff.
        print(f"::error file={path},line={lineno}::[{rule_id}] {msg}")
        print(f"  {path}:{lineno}  [{rule_id}] {msg}")
    print()
    print(f"{len(violations)} violation(s). See design-system/README.md and")
    print("outputs/design-remediation-plan-2026-06-16.md (Wave 1).")
    print()
    print("These rules ratchet: they only flag lines this PR adds. If you are")
    print("intentionally touching legacy debt, fix the line you added rather")
    print("than reintroducing the pattern.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
