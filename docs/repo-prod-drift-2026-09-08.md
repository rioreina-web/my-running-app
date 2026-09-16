# Repo ↔ production drift — reconciliation, 2026-09-08

Follow-up to `docs/security-audit-2026-09-03.md`, whose finding #1 was that
**the repository does not describe production**. This is the pass that closed
most of that gap, plus what it turned up on the way.

Every fact below was read from the live Supabase project
(`aqdijapxmjqaetursrde`) on 2026-09-08 via `list_edge_functions` /
`get_edge_function` — the deployed bundles themselves, not the repo's guess at
them.

---

## 1. Why this mattered more than it looked

The `Deploy` workflow's "Deploy all edge functions" input **defaults to true**.
Before this pass, running it would have overwritten production with older code
in at least six functions and deleted nothing — it would simply have rolled
live behaviour backwards, silently, with a green checkmark.

The largest single case: `trends-timeline` was running **1,850 lines** the repo
had never seen, including two whole files (`goalPace.ts`, `goalPaceGrid.ts`).

Drift is also ongoing, not historical. Two functions were deployed to
production *during* this session's working day — `coaching-daily-read` at
16:09 UTC and `trends-timeline` at 17:25 UTC — neither from a committed SHA.

---

## 2. Inventory

**63 functions live in production. 69 directories in the repo. They are not
the same 63.**

### Live in production, source in no branch (4)

| Function | Deployed | Disposition |
|---|---|---|
| `merge-memo-into-run` | 2026-09-05, v1 | **Recovered into the repo.** Real feature — collapses a voice memo into the GPS run it describes. Correct JWT auth, ownership checked on both rows. |
| `session-story` | 2026-07-25, v1 | **Recovered into the repo** (`index.ts` + `story.ts`, 782 lines). Per-session detail behind the iOS Session Story sheet. Dual-mode auth, no writes. |
| `env-probe` | 2026-06-08, v6 | Unauthenticated. Returns one boolean (`allowed_origin_set`). Delete. |
| `redis-probe` | 2026-07-21, v5 | Unauthenticated. Returns booleans only — **no secret values** — but performs an unauthenticated `INCR`/`EXPIRE` against the same Upstash instance that backs the rate limiter, and returns `redis_error` as a string on failure. Delete. |

`merge-memo-into-run` and `session-story` had exactly one copy each, on
Supabase's servers. Losing the project would have lost them.

### In the repo, not deployed (10)

Four are deliberate cuts documented in `CLAUDE.md` (`adaptive-workout`,
`biomechanics-analysis`, `custom-plan-builder`, `form-check-analysis`) and can
be deleted from the tree.

The other six are not accounted for anywhere, and **two of them have live
client call sites that must be failing today**:

| Function | Called from | Consequence |
|---|---|---|
| `delete-account` (124 lines) | `RunningLog/Shared/SettingsView.swift:1130` | **Account deletion is broken in the shipped iOS app.** App Store Guideline 5.1.1(v) requires in-app account deletion; this is also the GDPR erasure path. Highest-priority item in this document. |
| `coach-workout-read` (339 lines) | `web/src/components/coach/dashboard/workout-drawer.tsx:123` | Coach portal workout drawer fails to load. |
| `post-run-reconciliation` (428 lines) | — | Never deployed. PR #13 hardened its auth; that hardening protects nothing until it ships. |
| `ingest-manual-workout` (337 lines) | — | Never deployed, despite `CLAUDE.md` listing it as updated for the 2026-08-10 workout-label taxonomy. |
| `vital-connect` (113 lines) | — | Consistent with the pending Vital removal. |
| `mcp` (871 lines) | — | Unaccounted for. |

Neither failing call site is speculative — both are `functions.invoke` against
a slug with no ACTIVE function behind it.

---

## 3. What was reconciled into the repo

Direction was decided per file by diffing the deployed bundle against the repo
and reading the result, never by timestamp. Where production was a strict
superset it was taken; where the repo was ahead it was kept.

**Taken from production** (prod strictly ahead):

- `trends-timeline/index.ts` (+243 lines) and its two missing files
  `goalPace.ts` (239) + `goalPaceGrid.ts` (314)
- `coaching-daily-read/index.ts` (+361 lines)
- `parse-workout-structure/index.ts` (+133)
- `compute-workout-features/index.ts` (+41)
- `_shared/`: `athlete-state.ts`, `bodyVocabulary.ts`, `coach-context.ts`
  (+90), `context.ts` (+153), `prompt-library.ts`, `niggleWriter.ts` (+61),
  `qualityLoad.ts`, `workoutSegmentation.ts` (+122),
  `fast-segment-trends.ts`, `shared/workBouts.ts` (+321)
- `_shared/` files absent from the repo entirely: `pace-guard.ts`,
  `watch/authored.ts` (244), `watch/metrics.ts` (275)
- `_shared/prompts/process-training-memo.v4.ts`, `.v5.ts`, `.v6.ts`

**Kept from the repo** (repo ahead): `_shared/auth.ts` — the only difference
was PR #13's `export` on `timingSafeEqual`. Also `qualityLoad.ts`,
`shared/workBouts.ts` and `prompt-library.ts` against the *older* bundles that
still carried superseded copies; the newest deployed copy won in each case.

### `coaching-agent` — merged, not overwritten

Production was 122 lines ahead but still carried every issue PR #13 fixed.
Production's version was taken as the base and all five fixes re-applied on
top, each verified present afterwards:

1. pre-auth `debug_coach_log` insert removed (unauthenticated write that also
   stored the first 30 characters of the caller's `Authorization` header)
2. `proactive` quota bypass gated on `auth.isServiceRole`, not on a
   caller-supplied body field
3. `conversationId` bound to the caller before use — the client is
   service-role and bypasses RLS, so another athlete's history would otherwise
   load into this caller's prompt (404, not 403, so the endpoint doesn't
   confirm the row exists)
4. `.eq("user_id", userId)` on the conversation-message read and both
   conversation updates
5. generic 500 body; the exception detail goes to logs and Sentry only

Lint problems went 50 → 49 across the merge: no new ones introduced.

---

## 4. What was deliberately NOT merged

**`process-training-memo` is a genuine two-way fork and needs a human.**

| | prod v92 (2026-09-05) | repo |
|---|---|---|
| `declaredMood` — athlete's tapped mood beats model extraction | yes | no |
| prompt imported | `process-training-memo.v6` | `process-training-memo.v3` |
| `loadCoachContext` / `formatSplitsBlock` | no | yes |
| `getOrBuildAthleteState` | no | yes |
| `siblingParsedStructure` | no | yes |
| body `audio_url` fallback (audit finding) | **still present** | removed |

~196 lines exist only in production, ~263 only in the repo. Neither side is a
superset. Resolving it changes which prompt version processes real athletes'
voice memos, so it is a product decision under hard rule #3 (manual review
against `docs/coaching/principles.md`), not a mechanical merge.

Production's deployed copy is preserved verbatim at
`docs/prod-snapshots/2026-09-08/process-training-memo.index.ts.prod-v92`,
outside `supabase/functions/` so nothing deploys or imports it. The repo's
version — including the audit fix — is untouched.

Whichever way the merge lands, `?? record.audio_url` must not come back.

---

## 5. New findings

**5.1 — Three prompt generations shipped without review.** The repo had
`process-training-memo.v1/v2/v3`. Production runs **v6**. Versions v4, v5 and
v6 were authored, deployed and are processing athlete voice memos today, and
none was ever committed, reviewed against `docs/coaching/principles.md`, or
covered by a cassette. They were never going to be caught: the prompts were
edited outside the repo entirely, and the CI gate that would have flagged them
is switched off anyway (§5.4). The eval harness's one recorded
`process-training-memo` cassette
tests a prompt version that no longer runs anywhere.

All three are now committed, so they are at least reviewable.

**5.2 — Account deletion is broken in the shipped app.** See §2. This is a
store-compliance and privacy-erasure issue, not just a bug.

**5.3 — Two auth idioms in parallel.** `compute-workout-features` hand-rolls
`isServiceRoleJWT` (decode + `role` claim) while the rest of the tree uses
`_shared/auth.ts`. Both are safe here — the gateway verifies signatures at
`verify_jwt = true` — but a security-relevant decision implemented twice will
drift. Consolidate on the shared helper.

**5.4 — The eval-coverage gate is switched off, and `CLAUDE.md` says it
isn't.** `.github/workflows/ci.yml` carries `if: false` on the `eval-gate`
job, disabled 2026-06-16 on the reasoning that the harness "isn't built out
yet." So hard rule #3 — *"Golden prompts don't ship without recorded eval
cassettes … CI blocks otherwise"* — **is not enforced by anything**. The
golden families it names (`daily-read`, `injury-analysis`, `reschedule-plan`,
`coaching-agent-*`) are the athlete-facing, safety-baitable surfaces, and the
gate that is supposed to protect them has been inert for three months. This
PR's own run shows it: three prompt files added, gate skipped.

This is the mechanism behind §5.1. The gate script and the record-evals
workflow are both intact — only the `if:` is off. Either re-enable it (and
accept that the golden families need cassettes recorded first) or amend
`CLAUDE.md` so the rule doesn't describe a control that does not exist.
Documented-but-absent is the worst of the three states.

**5.5 — `_shared/` has no single truth in production.** Each deployment
bundles whatever `_shared/` the deployer had locally, so live functions run
*different versions of the same shared module*. `workBouts.ts` alone was found
at three different revisions across four bundles. Only deploying from a
committed SHA fixes this.

---

## 6. Verification

- 17 of 19 reconciled dependency-free modules typecheck clean standalone
  (`deno check --no-remote`). The other two fail only because they
  transitively import `supabase-js`.
- Full `deno check` and `deno test` could **not** run here: the sandbox
  network policy returns 403 for both `esm.sh` and `deno.land`. CI is the
  gate, as it was for PR #13.
- All five `coaching-agent` fixes verified present by grep after the merge.
- Every import of the replaced `_shared/shared/workBouts.ts` was checked
  against the new export list before the swap; all five importers still
  resolve.

---

## 7. Operator actions

Ordered. Items 1–2 are the ones that affect users today.

1. **Deploy `delete-account`** — restores account deletion in the shipped iOS
   app. Then `coach-workout-read` for the coach portal.
2. **Deploy `get-pace-zones`** — still the only confirmed live cross-user read
   (audit §3.2). Unchanged by this pass and safe to deploy from the repo.
3. **Delete the probes:** `supabase functions delete env-probe redis-probe`.
4. **Resolve the `process-training-memo` fork** (§4), then deploy it and
   delete the snapshot file.
5. **Deploy the reconciled functions** — now safe to do from a committed SHA,
   which it was not before this pass.
6. `supabase db push` for the two pending migrations from PR #13.
7. **Decide what hard rule #3 actually is** (§5.4) — re-enable the `eval-gate`
   job, or amend `CLAUDE.md`. Right now the rule reads as enforced and is not.
8. **Stop deploying from laptops.** Everything in this document is downstream
   of that one habit. The `Deploy` workflow already enforces committed-SHA
   deploys; it needs its six GitHub secrets set, and then it should be the
   only path. Until it is, this document goes stale the day it is written.
