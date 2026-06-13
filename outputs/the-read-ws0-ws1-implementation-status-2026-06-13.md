# The Read — WS0 + WS1 implementation status

**Date:** 2026-06-13
**Scope this session:** WS0 (403 drain pipeline), WS1 (segment-aware workout
detection & intensity), WS2 (heat-adjustment unit bug), WS3 (retire ACWR
surfacing / promote weighted load), and WS4 (fitness range + confidence).
WS5–WS6 not started.
**Author:** coding agent, against `outputs/the-read-implementation-spec.md`.

---

## TL;DR

- **WS0** — the three drain crons are ported off the brittle exact-key auth
  onto `rebuild-athlete-state`'s robust `role`-claim check. Code-complete;
  **needs deploy** to recover the pipeline (14 jobs queued since 2026-06-11).
- **WS1** — a new shared segmentation module classifies workouts from
  rep-level laps by actual pace. `compute-workout-features` and
  `athlete-state`'s execution block both consume it. Validated offline
  against the real golden-athlete data: **May 20 → `intervals 9×1K @ 5:07
  (5K)`**, 90-day quality count **5 → 12**. Needs migration + deploy +
  backfill.

---

## WS0 — drain-cron 403 fix

**Changed**
- `supabase/functions/drain-voice-processing-jobs/index.ts`
- `supabase/functions/drain-coach-insight-jobs/index.ts`
- `supabase/functions/drain-coachable-moment-jobs/index.ts`
  — replaced `constantTimeEq(token, SUPABASE_SERVICE_ROLE_KEY)` with
  `isServiceRoleJWT(token)` (decodes + validates the `role` claim; the
  gateway verifies the signature). Identical to `rebuild-athlete-state`.
- `supabase/config.toml` — added explicit `[functions.drain-*]` blocks with
  `verify_jwt = true` so the gateway validates the JWT signature.

**Why** the Vault `service_role_key` is a legacy `eyJ…` JWT while the
functions' env key rotated to `sb_secret_*`; exact-match → 403. The role-claim
check accepts any valid service-role token and survives rotation.

**Baseline (live, 2026-06-13):** `coach_insight_jobs` = 14 `queued`, oldest
`2026-06-11 23:09`. (voice/coachable queues empty.)

**Deploy & verify**
```
supabase functions deploy drain-voice-processing-jobs drain-coach-insight-jobs drain-coachable-moment-jobs
# acceptance — within a few minutes:
select status, count(*) from coach_insight_jobs group by status;   -- queued → ~0
# edge logs show the three drains returning 200, not 403
```
**Instant-recovery alternative (no deploy):** set Vault `service_role_key` to
the functions' current `SUPABASE_SERVICE_ROLE_KEY` (Dashboard → Settings →
API). The robust code fix should still ship so this can't recur.

### WS0 follow-up (found during deploy verification) — claim-RPC `search_path` bug

After deploy the auth fix **worked** (403s gone; `drain-voice-processing-jobs`
→ 200). But `drain-coach-insight-jobs` and `drain-coachable-moment-jobs` then
returned **500**, with Postgres logging `relation "coach_insight_jobs" does not
exist`. Root cause: `claim_coach_insight_jobs` / `claim_coachable_moment_jobs`
run with a hardened `search_path = pg_catalog, pg_temp` but reference their
tables **unqualified**, so the table is invisible. `claim_voice_processing_jobs`
was already `public.`-qualified — the hardening pass missed these two. This was
latent: the drains used to 403 before ever calling the RPC.

**Fix:** migration `20260613210000_fix_claim_rpc_schema_qualify.sql` re-creates
both functions with `public.`-qualified table refs (logic otherwise identical).
**Action: one more `supabase db push`** — no function redeploy needed; the next
cron tick (every minute) drains the backlog.

(Separate observation: Postgres logs also show an unrelated `syntax error at or
near "#"` from some other cron job — not in the drain path. Worth a look later.)

---

## WS1 — segment-aware classifier

**New**
- `supabase/functions/_shared/workoutSegmentation.ts` — the single source of
  truth. Reads rep-level laps, separates work/recovery (trusts `is_rest` but
  **pace is the source of truth** — a non-rest float at 9:54/mi is not a rep),
  classifies each bout by actual pace vs the athlete's zones (midpoint
  cutoffs), scores load on the canonical 1–5 weight scale, and derives a
  session type + structure string via the spec's decision tree.
- `supabase/functions/_shared/workoutSegmentation.test.ts` — Deno tests
  including the May 20 golden fixture (real laps). 18 assertions pass.
- `supabase/migrations/20260613200000_workout_features_type_structure.sql` —
  adds `workout_type` + `workout_structure` to `workout_features`
  (append-only, idempotent, no RLS change).

**Changed**
- `compute-workout-features/index.ts` — rewritten to fetch pace zones +
  laps and source intensity from the module. Persists `workout_type` /
  `workout_structure`, and backfills `training_logs.workout_type` where null
  (the 98 untyped imports). ACWR retained but commented as internal-only.
  Upsert degrades gracefully if it runs before the migration.
- `_shared/athlete-state.ts` — execution block now classifies via the shared
  module (no duplicate rep-detection). Added optional `structure` to the
  execution shape; `type` falls back to the detected kind. The laps select now
  includes `moving_time_seconds` / `elapsed_time_seconds`.

**Classifier (athlete-relative, validated):** pace→zone by midpoint cutoffs
between the athlete's anchors. Decision tree priority: race (continuous race
effort) → progression (uniform reps, monotonic faster) → threshold-cruise
(long reps, tight CV, LT/10K) → intervals VO2/5K → intervals 10K → threshold
reps (HMP + rest) → tempo (one block, MP–HMP, no rest) → fallbacks. Tempo vs
threshold splits on pace zone (MP/steady = tempo, HMP/LT = threshold), per the
spec's intentionally-fuzzy boundary.

**Acceptance (offline, real golden data — `user 03857bf3…`)**
- ✅ May 20 → `intervals 9×1K @ 5:07 (5K)` (exact).
- ✅ 90-day quality count **12** (baseline 5; target ~11+). All 12 carry
  threshold+hard seconds > 0 → the `workout_features` quality count goes 5 → 12.
- ✅ 9/10 spec example dates match on kind. The one divergence (4/28: spec
  "Tempo" vs detected "threshold") is the spec's acknowledged fuzzy boundary
  — 7×900m at HMP pace with rest is threshold by the spec's own rule.

**Deploy & verify (order matters — migration first)**
```
supabase db push                                   # applies 20260613200000_*
supabase functions deploy compute-workout-features rebuild-athlete-state
# backfill the golden athlete (then any user), then rebuild state:
curl -X POST .../functions/v1/compute-workout-features \
  -H "Authorization: Bearer <service_role>" -H 'Content-Type: application/json' \
  -d '{"user_id":"03857bf3-6276-4634-b3cc-15cc6d0bc653","backfill":true}'
curl -X POST .../functions/v1/rebuild-athlete-state \
  -H "Authorization: Bearer <service_role>" -d '{"user_id":"03857bf3-6276-4634-b3cc-15cc6d0bc653"}'
# acceptance SQL (was 5, expect ~12):
select count(*) from workout_features wf join training_logs tl on tl.id=wf.training_log_id
 where tl.user_id='03857bf3-6276-4634-b3cc-15cc6d0bc653'
   and tl.workout_date > now()-interval '90 days'
   and (coalesce(wf.threshold_seconds,0)+coalesce(wf.hard_seconds,0))>0;
select workout_date::date, workout_type, workout_structure from workout_features
 where user_id='03857bf3-6276-4634-b3cc-15cc6d0bc653' and workout_date::date='2026-05-20';
```

---

## WS2 — heat-adjustment unit bug

**Root cause (confirmed in data):** `running_workout_laps.heat_adjustment_pct`
is stored as a **fraction** (range 0.0000–0.0434, avg 0.019) — the producer
`_shared/pace-heat.ts` returns a fraction (its own table tops out at 0.120),
the field name `_pct` is just misleading. The only buggy consumer was
`athlete-state.ts`: it averaged the fraction and rounded to 1 decimal
(0.019 → **0.0**) and filtered `heat_adjustment_pct >= 2` (a fraction is always
< 1) → the Read's conditions block was permanently empty.

**Changed**
- `_shared/athlete-state.ts` — environment `heat_adjustment_pct` now ×100 to a
  percent (0.019 → 1.9); the "hot runs" filter threshold is `>= 1.5` (percent);
  the heat-sensitivity pattern (`>= 3`) now fires correctly. Recorded pace is
  never overwritten — `actual_pace` and `heat_adjusted_pace` stay separate.
- **New** `_shared/pace-heat.contract.test.ts` — pins the fraction contract so a
  future "fix" to emit percent breaks the test instead of silently re-zeroing
  the Read.

**Acceptance (verified offline against the real model + data)**
- ✅ May 20 (67°F/67°dew) → 1.9% / **5.9 s/mi**. ✅ May 19 (85°F/71°dew) → 4.5%.
- ✅ The environment block now lists these as hot runs instead of an empty set.
- ✅ Contract test (7 assertions) passes; model reproduces the persisted values.

**Note (defer to WS6):** the spec's "heat-adjusted pace opt-in, default off"
is the iOS workout-detail toggle (WS6 surface). The iOS `heatAdjustmentEnabled`
default (currently true) gates *prescription* forecast adjustment, a separate
feature — left unchanged here. No deploy gate beyond redeploying
`rebuild-athlete-state` (backend-only; no migration).

---

## WS3 — retire ACWR surfacing, promote weighted load

**Changed** (`_shared/athlete-state.ts`, backend-only)
- **ACWR demoted to internal-only.** Removed `ACWR x.xx` from
  `recent_training_summary` (its last surfaced spot). The `acwr` field is still
  computed and stored as an injury-risk input; it just isn't shown.
- **Load story promoted.** `load_distribution` gains `load_trend`
  (building / holding / spiking / backing_off), `load_vs_chronic_pct`,
  `chronic_window_days` (56), and a `recovery_read` (hard-day spacing +
  down-week flag). Computed from a weekly weighted-load series: recent 2 weeks
  vs an 8-week chronic baseline.
- **Windows lengthened.** The `workout_features` fetch widened from 28 → 84
  days so the trend has a chronic baseline; 7d/28d zone aggregates still slice
  their own windows.
- **Prompt** now leads the load section with the plain-language trend, the
  hard/easy split (with the ~80% guide), and the recovery read — not a ratio.

**Acceptance (logic verified on real weekly series)**
- Golden athlete today: chronic (wks 2–7) ≈ 886 wmin, recent (wks 0–1) ≈ 216 →
  **−76% → "backing off" + down week** — the correct read of the post-5/20
  easy stretch (the genuine 3-week quality gap). No NaN on the zero week.
- `volume_x_intensity_7d` is non-zero on weeks with workouts.
- The hard-session count / `avg_days_between_hard` in the recovery read fill in
  fully **after the WS1 backfill** (today's `workout_features.intensity_score`
  is still the old, understated value until then).

**Note:** ACWR's own chronic window (the internal injury input) was left at 4
weeks to avoid shifting injury thresholds; the *surfaced* trend uses the new
8-week baseline. Backend-only, no migration — redeploy `rebuild-athlete-state`.

---

## WS4 — fitness range + confidence (de-collapse)

**Root cause:** `fitness_snapshots.range_*_seconds` are **null** for the test
athlete, so `athlete-state.ts:rangeOf` returned `{low: pred, high: pred,
point: pred}` — a false-precision point disguised as a range (hard rule #7).
`confidence` ("High") and `workout_count` (58) were present and unused for the
band.

**Changed** (`_shared/athlete-state.ts`, backend-only)
- `rangeOf` now synthesizes a confidence-scaled band when the stored band is
  null/0: ±1.0% of the predicted time at HIGH, ±2.0% MEDIUM, ±3.5% LOW. A
  prediction is never a single time.
- The confidence line cites the evidence: workout count **+ a recent race
  anchor** (within 180 days) when one exists — race anchors over goal time.

**Acceptance (computed from the real snapshot)**
- ✅ 10K → **32:10–32:48, HIGH (58 workouts + recent 10K)** — matches the
  spec's `32:1x–32:4x`, never a point. (5K 15:28–15:46; Marathon
  2:28:25–2:31:25.)

**Follow-up (not this session):** the durable fix is to have the snapshot
builder (`assess-fitness`) persist real `range_*_seconds`; that touches the
eval-gated `_shared/prompts/fitness-predictor.v1.ts` (needs cassettes), so it's
deferred. The athlete-state synthesis is the correct low-risk fix now and
becomes a fallback once the builder stores bands. Backend-only, no migration.

---

## ⚠️ Git state — needs your hands (sandbox can't write git)

The repo is mounted read/rename but **deletion is blocked** in my sandbox
(virtiofs), so I could not run `git` writes or make the checkpoint commit you
asked for. What I did instead:

1. **Cleared the stuck cherry-pick** (it was a no-op — `1f8146f` was already
   an ancestor of HEAD) by moving the marker files aside. The repo is no longer
   mid-cherry-pick.
2. **Backed up all in-progress work** to the session outputs folder:
   `wip-backup-2026-06-13/` — `uncommitted-tracked.patch` (full `git diff
   HEAD`), `untracked-files.txt`, and verbatim copies of the WS0/WS1 files.

**On your machine, please run:**
```
cd ~/my-running-app
rm -f .git/*.lock .git/refs/heads/*.lock
rm -rf .git/_stale_locks                 # leftover marker files I moved aside
git status                               # should be clean of cherry-pick state
git add -A && git commit -m "WIP checkpoint before WS0/WS1"   # your restore point
```
The two `migrations_quarantine/` renames (`weekly_coaching_reports`,
`coach_training_plans`) are **undocumented** — not in the quarantine README or
the reconciliation ledger, and both are coach-feature tables (coach work is
deprioritized). I left them unstaged; decide their fate separately.

Then commit WS0/WS1 and push so CI deploys.

---

## Not done (next sessions)

- **WS5** — Daily Read prompt v3→v4 (spine restructure, window-aware claims,
  voice exemplars, widen memo lookback, reconcile the token budget). **Requires
  eval cassettes** under `_evals/cassettes/daily-read.v4/` before it can ship
  (CI gate, hard rule #3) — this is the careful one.
- **WS6** — the "model-of-you" iOS Coach surface (cards, evidence drawers, rep
  view, heat toggle). Large SwiftUI build against the three `outputs/*.html`
  mocks; depends on WS1–WS4 being deployed so the cards are honest.

Both build on the now-correct WS1 data.

## Deploy summary (all of this session)

1. `supabase db push` — migration `20260613200000_*` (WS1 columns).
2. `supabase functions deploy compute-workout-features rebuild-athlete-state
   drain-voice-processing-jobs drain-coach-insight-jobs drain-coachable-moment-jobs`
3. Backfill golden athlete `compute-workout-features {backfill:true}` →
   `rebuild-athlete-state` → run the WS1/WS3/WS4 acceptance queries.
   WS2/WS3/WS4 are all in `athlete-state.ts` (no migration); they take effect
   on the `rebuild-athlete-state` redeploy + next state rebuild.
