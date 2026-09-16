# Recording status — suggest-workout-progression.v1

Both cassettes are **stubs**: `vars` + rubric are authored, `recorded_response`
is empty. This is NOT a golden prompt family (CLAUDE.md hard rule #3), so CI
only warns — the ship gate is manual review against
`docs/coaching/principles.md`. Recording is still encouraged before the next
prompt revision:

```sh
cd supabase/functions/_evals
GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
  record.ts suggest-workout-progression.v1
```

What the rubrics pin:

- Output is JSON with a `ranking` array containing EXACTLY the provided
  candidate ids (the `"id": "(?!...)"` negative-lookahead pattern rejects any
  invented id).
- No workout structures (`"steps"`, `"paceZone"`) in the output — the model
  annotates, it never authors.
- No athlete-directed prescriptions ("you should ...") and no intensity /
  pace-zone escalation language — progression here is structural by design.
