# The repo is about half of production (2026-08-24)

Written while auditing edge-function security. The audit's premise — that
reading this repo tells you what production runs — turned out to be false,
and that finding matters more than anything else the audit produced.

## The numbers

| | repo | production |
|---|---|---|
| migrations | 103 | **194** (97 prod-only) |
| edge functions | 38 | **61** (23 prod-only, 3 repo-only) |

Measured directly against 30 of the 61 deployed functions (pulled via the
Supabase management API, `get_edge_function`):

- **87 files / ~26,800 lines exist in production and not in this repo at all.**
- **34 files / ~9,000 changed lines** exist in both but differ.
- 42 files are identical.

Extrapolating to all 61 functions, the gap is on the order of **50,000 lines**.
That is not drift. Half the production codebase has never been committed:
never reviewed, no history, not covered by CI, and recoverable only from the
deployed bundles.

## Two consequences you can act on

**1. `supabase functions deploy` from this repo is destructive.** For at least
these five, deploying the repo's copy would revert live code:

| file | prod | repo `main` |
|---|---|---|
| `process-training-memo/index.ts` | 1307 | 678 |
| `compute-workout-features/index.ts` | 765 | 474 |
| `coaching-agent/index.ts` | 1764 | 1670 |
| `_shared/rateLimit.ts` | 506 | 346 |
| `_shared/auth.ts` | 237 | 180 |

This is true of `main` today, not of any one branch.

**2. Reading the repo produces wrong conclusions about security.** Production
carries a security review dated **2026-07-15** whose fixes are visible in the
deployed source as `H1 fix (2026-07-15)` and `H3 fix (2026-07-15)` comments.
None of it is in this repo. An audit done from the repo re-finds bugs that
were fixed a month ago, and — worse — proposes "fixes" that would undo them.

Production is also *ahead* on things the repo would silently revert:
`_shared/auth.ts` has a `lacksSubjectClaim` short-circuit added after the
2026-08-07 incident in which 88% of GoTrue traffic was guaranteed-403
round-trips. `_shared/rateLimit.ts` has monthly cost caps and tier resolution
the repo has never seen.

## What still needs fixing (verified against deployed source)

**`get-pace-zones` — live cross-user read.** Prod is byte-identical to the
stale repo copy. `verify_jwt = true` is satisfied by the anon key; the anon
key carries no `sub` claim, so `getAuthenticatedUser` returns null; the
function reads that as "must be the service-role cross-call" and trusts
`body.user_id`. Anyone holding the public anon key can read any athlete's
pace zones. Fixed on the security branch; that one file is safe to deploy
because it matches prod.

**`process-training-memo` — narrower cross-user read, still live.** The
ownership guard is correct (404s a row you don't own), but the audio pointer
falls back to the request body:

```ts
const audioUrlStr = (ownerRow.audio_url as string | null) ?? record.audio_url ?? null;
```

An authenticated athlete who owns a row with `audio_url = NULL` — a typed
manual note, which the queue models as `kind: "note"` — can pass another
athlete's storage path in `record.audio_url`. Ownership passes (they own the
row), the fallback takes the body value, and the service-role client
downloads and transcribes that object into the attacker's own log.

Exploitability depends on knowing a path. `{user_id}/{uuid}.m4a` is not
guessable, but **97 objects in prod are bare filenames predating that
convention**, and legacy public URLs are recorded in `training_logs.audio_url`.
Treat it as real but not trivial.

Fix is one line — drop the `?? record.audio_url` fallback and read the
pointer only from the row. It must be applied to **prod's 1307-line source**,
not to this repo's 678-line copy.

## Why reconciling is harder than it looks

Three obstacles, all hit while attempting it:

1. **The management API can't be scripted cleanly from an agent session.**
   Large functions persist to disk; small ones return inline and are not
   saved, so ~15 of 61 can't be captured mechanically. Hand-transcribing
   them into a 50,000-line import is exactly how silent corruption happens.
2. **`supabase functions download` is the right tool and needs the CLI plus
   `SUPABASE_ACCESS_TOKEN`.** Neither is present in the agent environment.
3. **The eval-coverage gate fires on the import.** Prod carries 16 prompt
   files under `_shared/prompts/` that this repo lacks (`daily-read.v3/v4/v5`,
   `process-training-memo.v2/v3`, …). CLAUDE.md hard rule #3 and
   `.github/scripts/check_eval_coverage.py` require a cassette per touched
   prompt; only 6 cassettes exist. Importing them turns CI red until
   cassettes are recorded.

Even a single-function scoped import is not small: the transitive dependency
closure of `process-training-memo/index.ts` alone is **45 files**, 16 of them
prompts.

## Suggested order

1. **Reconcile first, from a machine with the Supabase CLI.**
   `supabase functions download <slug>` for all 61, commit as one
   "import production source" PR with no behavioural changes. Expect CI to
   need cassettes recorded for the imported prompts, or the gate scoped to
   exclude a one-time import.
2. Only then re-run a security audit — against source that is actually real.
3. Until step 1 lands, treat `supabase functions deploy` from this repo as a
   destructive operation, and deploy only files verified to match prod.
