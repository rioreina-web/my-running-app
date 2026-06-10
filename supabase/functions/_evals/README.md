# Eval harness — `supabase/functions/_evals/`

Test the **wedge** under load: "AI advises, never acts; AI never recommends
stopping training, diagnosing injuries, or making medical claims." This
harness makes those rules testable for every prompt the backend ships.

## What this is

A cassette-driven rubric runner for LLM prompts. Each cassette pins a set
of inputs, a recorded model response, and a rubric. The runner replays
the cassette through the rubric and reports pass/fail.

Replay-by-default keeps CI cost at $0 — no live model calls on every PR.
A separate `--live` mode (W2.1 Day 2) re-records cassettes against the
real provider and is run manually or on a schedule.

## Status — what's covered

| Prompt | Cassettes | State | Live re-record |
|---|---|---|---|
| `injury-analysis.v1` | 3 | recorded | ✓ via `record.ts` |
| `process-training-memo.v1` (Niggles classifier) | 3 | **stubs** — rubrics pinned, awaiting `record.ts` to fill `recorded_response` | ✓ |
| `coaching-agent-{simple,moderate,complex,proactive}.v1` | 0 | — | ✓ (cassettes TODO) |
| `reschedule-plan.v1` | 0 | — | ✓ (cassettes TODO) |

Target by end of W2.1: 20 cassettes for `coaching-agent`, 15 for
`injury-analysis`, 10 for `process-training-memo`, 10 for `reschedule-plan`.

## Stub cassettes

A cassette with `recorded_response: ""` is a **stub** — the rubric and
inputs are pinned but no response has been recorded yet. The runner
shows `[STUB]` with the recording command in test output and does NOT
fail the build. This lets you check in the rubric for review, then fill
in the recording later.

The 3 process-training-memo stubs check in today are:
- `001-positive-long-run` — happy path baseline
- `002-injury-mention-no-diagnosis` — wedge-defining test: mood = `injured`, no specific diagnosis language
- `003-cross-training-soreness-not-injury` — over-trigger guard: gym soreness must NOT be classified as `injured`

To fill them in: `GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env _evals/record.ts process-training-memo.v1`

## Live re-record mode

`record.ts` calls the real model against each cassette's `vars` and
writes the fresh response back to the cassette JSON. Use when:

- Building a new cassette: stub the JSON with `vars` + `rubric`, then
  re-record to fill in `recorded_response` from the real model.
- The prompt template changes and the existing recordings are now stale.
- You're investigating a new failure mode and want to see how the
  current prompt actually responds to a new input.

```
GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
  _evals/record.ts injury-analysis.v1

# All prompts:
GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
  _evals/record.ts --all

# One specific cassette:
GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
  _evals/record.ts injury-analysis.v1 --only 001-bone-stress-reaction
```

Exit code is 1 if any rubric fails on the fresh recording. The cassette
JSON is still written so you can inspect the diff — decide whether to
commit the new recording (intentional change) or revert and fix the
prompt.

Cost: ~$0.001/call at Gemini Flash. A full re-record is < $0.05.
**Not wired into CI** — manual / scheduled only. The $50 Cloud Billing
budget is the hard ceiling.

## How to add a cassette

1. Create `cassettes/<prompt-name>/<id>-<short-description>.json` matching
   the schema in `types.ts` (`Cassette`).
2. Fill `vars` so they satisfy every `{{placeholder}}` in the prompt
   template — same rules as `loadPrompt()`. Missing or extra vars fail
   the cassette at load time.
3. Write the rubric:
   - `forbidden_patterns`: list of regexes the recorded response MUST
     NOT match (e.g. diagnosis language, action recommendations).
   - `required_patterns`: regexes that MUST appear (e.g. "not a
     diagnosis" disclaimer).
   - `must_parse_as_json`: response must be valid JSON.
   - `json_required_keys`: top-level keys that must exist on the parsed
     object.
   - `custom_check`: name of a function in `customChecks.ts` for
     anything pattern-matching can't express.
4. Record the model response (`recorded_response`) by running the prompt
   manually for now; Day 2 will add `deno task eval:record`.
5. Set `recorded_at` and `model` so we can detect stale cassettes when
   the prompt template changes.

## How to run

```
# CI uses this — picked up by `deno test --allow-all` in .github/workflows/ci.yml
cd supabase/functions
deno test --allow-read _evals/

# Replay only (no network)
deno test --allow-read _evals/

# Verbose
deno test --allow-read _evals/ -- --verbose
```

## Architecture

```
_evals/
├── README.md              this file
├── types.ts               Cassette / RubricResult / EvalReport
├── rubric.ts              rubric primitives (forbidden_patterns, required_patterns,
│                          must_parse_as_json, json_required_keys)
├── customChecks.ts        named functions for rubric `custom_check`
├── runner.ts              walk cassettes, apply rubric, aggregate report
├── runner.test.ts         Deno.test entry — runs in CI
└── cassettes/
    └── <prompt-name>/
        └── *.json
```

## Why this matters

`CLAUDE.md` mandates: "No LLM prompt change ships without running the
eval harness." The wedge is differentiated only if it actually behaves
that way under load. A single Niggles output that says "could be ITBS,
ice it tonight" reaching a customer torches the wedge. This harness
makes that behavior testable on every PR.

Source: tech-debt audit item #1, TASKS.md W2.1.
