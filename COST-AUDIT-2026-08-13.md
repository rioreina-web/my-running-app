# COST AUDIT — 2026-08-13 · The $7 day, and the architecture that prevents the next one

A single-user beta spent ~$7 of Gemini API credits in one day. This audit
traces where the money went, records the fixes shipped today, and sets the
cost architecture and operating process going forward. Companion docs:
`docs/deploy/llm-cost-controls.md` (billing-cap runbook, still the source of
truth for Step 1 below) and `PERF-AUDIT-2026-08-10.md`.

**Status right now: the Gemini key's prepaid credits are DEPLETED.** Edge
function logs show `"Your prepayment credits are depleted"` on embedding
calls, and widespread `generateContent` failures across parse-workout-
structure, process-training-memo, ask narration, and the daily read. Every
AI feature in the app is currently degrading or failing. Topping up credits
without shipping the fixes below would just re-run the same burn.

---

## 1 · Where the money went

The bill was not one bug. It was one *expensive default* multiplied by one
*client-side loop*, sitting on top of a tracking layer that couldn't see
either of them.

### 1a. The Daily Read ran a frontier model on a surface nobody can see

`coaching-daily-read` calls `gemini-3.1-pro-preview` — the most expensive
model in the codebase at roughly $2 per million input tokens and $12 per
million output tokens (thinking tokens bill as output). The in-file comment
justified this with "runs on a WEEKLY cadence, so per-call cost is small."
That cadence was designed (migration `20260806160000`) but the calls that
actually happen are not weekly: the iOS app calls `DailyReadService.refresh()`
on **every app launch and every foreground transition**
(`RunningLogApp.swift` lines ~246 and ~294), and on any day where today's
row isn't `completed`, each of those calls POSTs to the edge function and
burns up to **3 full model attempts** (the retry loop re-rolled on *any*
error, including Google-side 429s where retrying is pure waste).

The compounding detail: the Read's display surface, `CoachReadView`, was
unmounted with the Coach tab on 2026-07-28. The app has been generating
frontier-model editorial content for a screen that cannot be opened.

Evidence from production: Upstash rate-limit logs show the `daily_read`
counter reaching **46/5 in a single day** for the one beta user (the limiter
blocked calls 6–46, but 5 generations × up to 3 attempts each still ran);
the edge-function log shows 36 invocations of `coaching-daily-read` in one
24-hour window, clustered exactly like a developer foregrounding the app
through an afternoon (5–8 invocations per hour, 19:00–22:00 UTC on 8/12).

Cost math for one generated read: the context bundle (athlete state block +
60 training logs + memos + weekly report) plus an 8,000-token output budget
with thinking. A day of 5 rate-limit-permitted generations × 3 attempts can
plausibly reach **$2–4 on this model alone**, and more before the limiter
was in place.

### 1b. Every synced workout paid for a Pro model

`generate-workout-insight` pinned `INSIGHT_MODEL = "gemini-2.5-pro"`
($1.25/$10 per 1M) with the comment "button-triggered, low-volume." It is
neither: the `coach_insight_jobs` outbox auto-enqueues an insight for
workouts as they're ingested, and the drain cron runs every minute. Each
insight call also loads the full athlete-state context block. Logs show
`gemini-2.5-pro` failures still firing in the last 24 h.

### 1c. Retry loops multiplied failures instead of containing them

Three patterns, same shape. The daily read retried API-level failures 3×.
`process-training-memo` burst to 33 invocations in a single hour (dispatch
crons run every minute; a stuck or failing item gets re-dispatched until the
stale-cleanup sweeps it). `parse-workout-structure` logged 23 Gemini
failures in 24 h. When Google returns a 429, every retry re-sends the full
prompt — you pay input-token prices to be told no.

### 1d. The spend tracker was structurally blind

This is the process failure that let 1a–1c go unnoticed. The daily Slack
spend alert reads `usage_tracking`, but:

`usage_tracking`'s CHECK constraint only allows feature values
`('coaching','transcription','insight')`. Inserts with any other label —
including `coaching_proactive` from coaching-agent — failed the constraint,
and because supabase-js returns errors in the result object (no throw) and
no call site checked it, those rows were dropped **silently**. Meanwhile the
two most expensive functions (`coaching-daily-read`,
`generate-workout-insight`) never wrote to `usage_tracking` at all, and
`llm_model_pricing` had no row for `gemini-3.1-pro-preview`, so even a
correctly-tracked call would have priced at $0. Result: on the $7 day,
`usage_tracking` recorded three flash calls worth about two cents.

The alert's own design doc says "the Cloud billing dashboard is ground
truth" — correct, but the trend signal it was supposed to provide never
existed for the calls that mattered.

---

## 2 · What shipped today (2026-08-13)

**`supabase/functions/coaching-daily-read/index.ts`** — model downgraded
`gemini-3.1-pro-preview` → `gemini-2.5-flash` (~20× cheaper per read).
Retries now apply to JSON-parse failures only; an API-level failure (429,
network, 5xx) aborts immediately instead of re-billing the full prompt.
Every invocation now writes real token counts to `usage_tracking` under
feature `daily_read`. The comment gate for re-upgrading to a Pro model:
only after (a) the client no longer auto-generates and (b) weekly cadence
is verified in `daily_read_dispatch_log`.

**`supabase/functions/generate-workout-insight/index.ts`** — `INSIGHT_MODEL`
downgraded to `gemini-2.5-flash`. Side benefit: the spend alert's
`coach_insight_proxy` row already assumed flash pricing, so its estimate is
now accurate rather than a 4× undercount.

**`RunningLog/.../Services/DailyReadService.swift`** — `refresh()` grew a
`generateIfMissing` parameter that **defaults to false**. Launch and
foreground calls are now SELECT-only and can never trigger a paid
generation. The old "SELECT failed → generate anyway" fallback is gone for
the same reason. `CoachReadView` (the mounted surface, when it returns)
passes `generateIfMissing: true` from its explicit GENERATE button and
pull-to-refresh — user intent is the only thing that spends money.

**`supabase/migrations/20260813120000_fix_usage_tracking_and_pricing.sql`**
— widens the `usage_tracking` feature CHECK so labels stop being silently
dropped, and adds `gemini-3.1-pro-preview` pricing rows so historical and
future spend attribution prices correctly.

### Deploy checklist (in order)

1. Review the diffs, commit.
2. `supabase db push` from the committed SHA (hard rule #9) — applies the
   usage-tracking migration.
3. `supabase functions deploy coaching-daily-read generate-workout-insight`.
4. Rebuild the iOS app so the SELECT-only client ships.
5. In Google AI Studio / Cloud Console: top up credits **after** steps 2–3,
   and complete Step 1 of `docs/deploy/llm-cost-controls.md` — the monthly
   budget with the 110% disable-billing action. That runbook has existed
   since June and is marked "manual setup required." It is the only layer
   that can actually stop a runaway bill. Set it to **$25/month** for the
   current beta (raise deliberately, never reactively).
6. Verify: `SELECT * FROM yesterday_llm_spend ORDER BY est_cost_usd DESC;`
   the morning after a day of normal use. You should now see `daily_read`
   rows with real token counts.

---

## 3 · The cost architecture (rules going forward)

**Rule 1 — model tier is set by trigger, not by surface prestige.**
Anything a machine can invoke (cron, trigger, outbox drain, app lifecycle)
runs flash-tier or cheaper, always. Pro-tier models are reserved for
explicit, rate-limited, user-initiated actions — and even then only where
flash demonstrably fails eval. Today nothing in the app meets that bar.
`generate-training-plan` still calls `gemini-2.5-pro` twice per generation;
it is user-initiated and capped at 3/day free tier, so it's acceptable —
but it is the next candidate to test on flash.

**Rule 2 — the client never spends by default.** App lifecycle events
(launch, foreground, tab switch, scroll) may read caches and SELECT rows.
Only an explicit user gesture on a mounted surface may trigger a paid call.
This is now enforced in `DailyReadService`; apply the same pattern to any
future service (the `generateIfMissing: false` default is the template).

**Rule 3 — retries never re-bill a failing provider.** Parse/validation
failures may re-roll (bounded); API-level failures abort. A 429 from Google
means stop, not try harder. The job tables (`max_attempts`, `next_retry_at`)
are the right place for spaced retries — in-process loops are not.

**Rule 4 — every LLM call writes usage_tracking, in the same PR that adds
the call.** Model string, real token counts from `usageMetadata`, feature
label. A pricing row in `llm_model_pricing` ships in the same PR when the
model is new. CI idea for later: grep for `generateContent(` call sites and
fail if the file doesn't also reference `usage_tracking`.

**Rule 5 — degradation is the design (already house style — extend it).**
The Ask surface's principle ("facts always render; narration is a bonus")
is the correct cost posture for every AI feature: when quota or credits run
out, the deterministic layer keeps working and the LLM layer degrades to
null. Any new feature must answer "what renders when Gemini is down?"
before it ships.

**Rule 6 — caps are provider-side first.** In-code limits (Upstash daily
buckets, monthly caps) bound one user's blast radius; only the Google Cloud
budget with disable-billing-at-110% bounds the account. Both layers stay.
Service-role bypasses the per-user limiter by design, which is exactly why
Rule 1 exists: the machine-invoked paths must be cheap because they are
unmetered.

### What a healthy day should cost

With today's fixes, the realistic per-active-user day is: one daily read
(~25k in / ~2k out on flash ≈ $0.013), a handful of workout insights
(≈ $0.005 each), memo processing with Groq transcription (< $0.01), a few
Ask narrations (fractions of a cent — Layer 1 is free by design). Call it
**$0.03–0.08 per active user per day**, i.e. $1–2.50/month heavy-use. At
that rate the $7 day funds three months of solo beta. If the spend alert
ever shows a day above ~$0.50/user, something has regressed — that's the
new anomaly threshold, and now the alert can actually see it.

---

## 4 · Next candidates (not shipped today, ranked by leverage)

**Prompt caching / context diet for the athlete-state block.** The same
large context block is rebuilt and re-sent on every daily-read, insight,
and coaching-agent call. Gemini offers implicit cached-input discounts on
stable prefixes; structure prompts as [stable athlete block] + [small
per-call delta] to collect it. Cutting the 60-log lookback (the daily read
renders only 30 anyway) is a free ~40% input reduction on that call.

**`generate-training-plan` on flash.** Two `gemini-2.5-pro` calls per
generation, large structured output. Record a cassette, run it on flash,
compare. If quality holds, that's the last frontier-model call site gone.

**Dispatch-cron hygiene.** `dispatch-rpe-extraction` and
`dispatch-workout-parse` fire every minute; a poison item can be
re-dispatched repeatedly until the stale-cleanup sweeps it (the 33-in-one-
hour memo burst). Add an attempts guard at dispatch time, mirroring the
drain workers' `max_attempts` pattern.

**Retire the daily-read workout trigger while the surface is dark.** The
`training_logs` trigger re-renders today's read after a quality session —
for a screen that's unmounted. It's capped at once/day so it's small money,
but it's pure waste until the Read remounts. One migration to drop (or
no-op) the trigger; re-add when the surface returns.

**Log-based weekly review.** Ten minutes, once a week, same trigger as the
Slack alert: read `yesterday_llm_spend` trends and the top error strings
from function logs. The 429s, the 33-call burst, and the 46/5 limiter hits
were all visible in logs for days — nobody was looking, because nothing was
routing them to a human. The Slack webhook setup (Step 2 of the runbook)
closes that loop; do it alongside the billing cap.
