# Coach Read — weekly cadence, and the merge question

**Date:** 2026-08-06
**Decision owner:** Rio
**Status:** cadence change authored (migration `20260806160000`), pending
`supabase db push`. Merge NOT started — gated on an IA decision.

---

## 1. What triggered this

A cost question: *what is my AI cost per user?* The honest answer is that
there is one real user, so the per-user number is not yet meaningful. But
chasing it surfaced two things worth fixing.

**Ninety-day Gemini spend: $8.91.** One active athlete. Roughly $0.04 per
AI call. August month-to-date $0.96 across 22 jobs.

### 1a. The daily Read cron fires for everyone, forever

`enqueue_daily_reads()` (from `20260615220000_daily_coaching_reads_cron.sql`)
loops over **every row in `athlete_state`** and dispatches
`coaching-daily-read` for anyone whose local hour is 06. The only filter is
`WHERE st.user_id IS NOT NULL`.

There is no activity check. No "opened the app," no "logged a run," no "is
still active." An athlete who signs up once and never returns draws a
frontier-model call every morning in perpetuity.

At `gemini-3.1-pro-preview` with up to 3 attempts, that is a fixed monthly
cost per signup — the one cost line that grows with *registrations* rather
than with usage. It is the wrong shape for a consumer app.

### 1b. …and it has never once worked

- 104 dispatches logged between 2026-06-16 and 2026-08-06.
- **Zero** rows in `daily_coaching_reads` with `triggered_by = 'cron'`.
- All 47 reads on file are `'manual'` — Rio tapping generate.
- Edge function logs show `POST | 429 | .../coaching-daily-read`.

`enforceFeatureRateLimit(userId, "daily_read")` runs at index.ts:166,
**before** context building and before the Gemini call. So the cron has been
firing into a rate limiter for seven weeks. Probably not costing money —
the 429 short-circuits ahead of the model — but producing nothing either.

The product has been on-demand-only this whole time without anyone deciding
that.

### 1c. The code already argued for weekly

From `coaching-daily-read/index.ts`, justifying the frontier model:

> *"The Read is the flagship synthesis surface and runs on a WEEKLY
> cadence, so per-call cost is small"*

It does not run on a weekly cadence — it is wired to an hourly cron. The
justification was written for a cadence nobody implemented. Moving to weekly
makes the comment true and the model choice defensible.

**Related comment drift, worth a separate cleanup:**
`weekly-coaching-report/index.ts` says *"Use Gemini Pro for deeper coaching
reasoning (worth the cost for a weekly report)"* directly above
`model: "gemini-2.5-flash"`. Neither file's comments can be trusted as
design intent right now.

---

## 2. Decision — weekly, Sunday evening, active athletes only

| | Before | After |
|---|---|---|
| Cadence | Daily, 06:00 local | **Sunday 18:00 local** |
| Eligibility | Every `athlete_state` row | **≥1 `training_log` in trailing 7 days** |
| Manual generation | On demand | Unchanged |
| `workout_trigger` re-render | Active | Unchanged |

**Sunday evening over Monday morning.** The Read becomes reflective — it
reads the week that just closed rather than forecasting the one ahead. That
matches the existing `weekly_coaching_reports` surface and it matches the
Read's actual voice posture (feeling first, soft questions, no directives).
A Monday-morning read would drift toward prescription, which is the thing
the product deliberately does not do.

**The eligibility gate is the real cost lever.** Cadence alone takes a
dormant account from ~30 calls/month to ~4. The activity filter takes it to
zero. Everything else here is rounding.

**No schema change.** `daily_coaching_reads` stays keyed on
`(user_id, read_date)`; a weekly read is just one row landing on a Sunday
date. No iOS change required, no migration to the table itself.

Verified against prod read-only: of two athlete rows, the real account
(15 logs in 7 days) passes the gate and the seed account
`a7e57a71-…-1eed1eed1eed` (0 logs) is correctly filtered out.

Migration `20260806160000_weekly_coaching_read_cadence.sql` is authored and
parses clean. **It has not been applied** — per hard rule #9 it reaches prod
only via `supabase db push` from a committed SHA.

Rollback is re-scheduling `enqueue_daily_reads()`, which the migration
leaves defined and intact.

---

## 3. The merge — scoped, not started

Rio's call: fold the Read and the weekly report into **one weekly surface**.
Right instinct, but it is gated on something else first.

### 3a. Both surfaces are already dark

| Surface | Route |
|---|---|
| `CoachReadView.swift` | Unlinked 2026-07-28 with the Coach tab |
| `WeeklyCoachingReportSheet.swift` | Reachable only via a `↗ HISTORY` button **inside `CoachReadView`** |

The weekly report is two hops behind a door that no longer exists. Nothing
in the shipping 3-tab IA (Log · Trends · Train) reaches either one.

**So the merge has no user-facing payoff until the IA question is answered:
where does the merged weekly surface live?** Merging two dark surfaces
produces one dark surface. The open question from `CLAUDE.md` — three
non-canonical coach surfaces already exist — means a careless merge creates
a fourth rather than collapsing to one.

That IA call should come first. The cadence fix does not wait on it.

### 3b. If and when it proceeds: keep `coaching-daily-read` as the base

It is the stronger machine. Schema-constrained generation, 3-attempt retry,
post-hoc citation validation against real workout/doc/niggle IDs, a
pending/completed/failed row lifecycle, and it is already a CI-gated golden
eval family.

`weekly-coaching-report`'s unique value is **not** its LLM architecture —
that is a single un-retried Flash call with no response schema and a regex
text-mangle as its JSON fallback. Its value is the deterministic analytics
layer: `computeAllMetrics` / `generateAlerts`, ACWR, compliance, mood
trend, the structured `metrics` payload. That is the part worth carrying
over, and notably it is the part that needs *no model at all* — the same
computed-first / narrated-second shape the Ask surface already proved.

### 3c. Blockers to price before starting

1. **Grain mismatch.** `daily_coaching_reads` is day-keyed
   (`user_id, read_date`) with `resolveAthleteLocalDate` and the
   `workout_trigger` bypass all assuming days;
   `weekly_coaching_reports` is week-keyed (`user_id, week_start`). Real
   schema work, not a prompt merge.
2. **Golden-family asymmetry.** `daily-read` is CI-blocking (hard rule #3);
   `weekly-coaching-report` is not. Folding weekly's alerts/adjustments
   into the Read expands the golden-gated surface with zero cassette
   coverage for that content. Cassettes get recorded *before* the merge
   PR, or CI blocks it.
3. **Prescription boundary.** Weekly emits directive `adjustments`
   (`recommended_value`, `priority`). The Read is deliberately
   non-prescriptive for self-coached athletes. Merging them without
   deciding which register wins would quietly walk back "AI advises,
   never acts."
4. **Batch mode.** Weekly has a service-role `batch: true` fan-out
   (chunks of 10, 60s per-user timeout); the Read is strictly single-user.
   Porting that is real work.
5. **Failure-policy mismatch.** Read uses `Promise.allSettled` with
   per-query fallback; weekly uses bare `Promise.all` where one bad query
   fails the whole generation. The merged ~15-table context builder needs
   one policy.
6. **Rate-limit buckets diverge.** `"daily_read"` vs `"weekly_review"`,
   and weekly's batch path skips rate limiting entirely. Pick one.

---

## 4. Cost outlook, restated honestly

The $3/athlete/month figure from the initial pass **overstated the
scheduled component** — it assumed the daily cron was generating reads. It
was not. Current spend is manual generation and workout insight jobs, which
is genuinely usage-driven.

The number to actually watch is not today's bill. It is the shape of the
bill: **anything dispatched per-signup rather than per-use scales with
registrations**, and registrations are the number you are about to try to
grow. This migration removes the only such line item currently in the
system. Worth checking for others before launch.

Two things not yet measured and worth measuring before pricing anything:

- **Signup backfill cost.** The 2-year HealthKit import plus race detection
  is a one-time per-user charge, paid twice ever, so it is invisible in the
  90-day chart. It could easily exceed a month of steady-state usage.
- **Ask, once live.** `analysis_queries` is empty. Chip taps stay free
  (Layer 1 is deterministic, no model) — the architecture is already right.
  Free-text questions add a routing call plus a narration call.

---

## 5. Also spotted

- **`llm_model_pricing` has 0 rows.** The `daily-llm-spend-alert` cron
  (job #4, 13:00 UTC daily) computes cost by joining against it — with an
  empty table the Slack alert is reporting $0 regardless of real spend.
  The cost monitoring you built is silently blind.
- **Three backup tables with RLS disabled** —
  `_dup_cleanup_backup_20260803`, `_heat_backfill_backup_20260805`,
  `_backup_voice_dupe_merge_20260805`. Anyone with the anon key can read
  them. They look like leftovers from the Aug 3/5 cleanups; dropping them
  is the cleanest fix.
