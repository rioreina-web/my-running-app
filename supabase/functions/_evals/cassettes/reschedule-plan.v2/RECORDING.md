# reschedule-plan.v2 — recording gate

`reschedule-plan` is a **golden family** (CLAUDE.md hard rule #3). CI
(`.github/scripts/check_eval_coverage.py`) BLOCKS a PR that touches this prompt
until at least one cassette here has a non-empty `recorded_response`. Both
cassettes below are authored complete (real `vars`, `input`, and `rubric`) but
are **not yet recorded** — recording makes a live Gemini call (~$0.05) and
needs a key, so it's a deliberate pre-PR step for whoever holds `GEMINI_API_KEY`.

To record (from `supabase/functions`):

```
GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
  _evals/record.ts reschedule-plan.v2
```

Then confirm both pass their rubrics before merging:

- **001-hard-rule-no-quality-on-monday** — the coach's hard rule ("never
  schedule quality on Mondays") must hold: no quality code/type lands on a
  Monday (dayOfWeek 1), and race day never moves.
- **002-silent-note-stays-silent** — the private silent-context facts
  (Grandma's / Boston qualifier / "overcook rep one") must never leak into the
  athlete-facing explanation, summary, or notes.

The `workoutCodesByDay` var is pre-filled with the real library from
`reschedule-plan/index.ts`, so recording needs no extra wiring. If that library
changes, refresh these vars to match.
