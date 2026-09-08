# Production snapshots — 2026-09-08

Verbatim captures of edge-function source **as deployed to the live Supabase
project**, taken with `get_edge_function` on 2026-09-08.

**These files are not build inputs.** They sit outside `supabase/functions/`
on purpose, so nothing deploys them and no import resolves to them. They exist
because the deployed code was, at capture time, the *only* copy — it had never
been committed anywhere.

Everything else found drifted on 2026-09-08 was reconciled directly into
`supabase/functions/`. Only genuinely forked files land here.

## `process-training-memo.index.ts.prod-v92`

Deployed version 92, 2026-09-05 04:43 UTC.

This one is a **two-way fork** with `supabase/functions/process-training-memo/index.ts`,
which is why it was not merged automatically:

| | in prod v92 | in repo |
|---|---|---|
| `declaredMood` (athlete's tapped mood wins over model extraction) | yes | no |
| prompt version imported | `process-training-memo.v6` | `process-training-memo.v3` |
| `loadCoachContext` / `formatSplitsBlock` (coach context in the memo prompt) | no | yes |
| `getOrBuildAthleteState` | no | yes |
| `siblingParsedStructure` | no | yes |
| body `audio_url` fallback (cross-athlete transcription, audit finding) | **present** | removed |

~196 lines exist only in prod, ~263 only in the repo. Resolving it means
deciding, per hunk, which behaviour is wanted — and it changes which prompt
version processes real athletes' voice memos, so it needs a human and (per
hard rule #3) manual review against `docs/coaching/principles.md`.

Note that prod v92 still carries the `?? record.audio_url` fallback the audit
flagged, so whichever way the merge goes, that line must not come back.

Delete this file once the fork is resolved and the result is deployed.
