# Beta cost guardrails — the "never again" checklist

Written 2026-08-13, after the Aug-11 runaway (1,269 unmetered Gemini calls
from a trigger loop; post-mortem in migration
`20260813180000_stop_no_op_writes_from_enqueueing_parses.sql`) and the $7-day
audit (`COST-AUDIT-2026-08-13.md`). This doc is the operating answer to "make
sure that never happens with beta users on the app." Companion runbook:
`docs/deploy/llm-cost-controls.md`.

## The defense in depth, outermost first

**Layer 0 — Google Cloud billing cap.** The only layer that can stop spending
no matter what the code does. Monthly budget scoped to the Generative
Language API, email alerts at 50/80/100%, `Disable billing to stop usage` at
110%. ⚠️ STILL MANUAL — Step 1 of `llm-cost-controls.md`. Do this before
topping up credits, and absolutely before inviting the first beta user.
Suggested budget: $25/month now; ~$3–5 per expected weekly-active user once
testers join (Rule-of-thumb ceiling from the audit: healthy usage is
$0.03–0.08 per active user per day).

**Layer 1 — the DB budget guard** (`public.llm_budget_allows`, migration
`20260813180100`). Two ceilings in one function: a global daily call ceiling
(default 250) and a per-subject 24h ceiling (default 6) that catches a single
row stuck in a loop within minutes. Every permitted call writes a row to
`llm_call_ledger`. When the ceiling trips it posts to Slack once per day and
refuses further dispatch — jobs are durable and drain after midnight UTC.
Wired into: the `workout_parse` and `rpe_extract` SQL dispatchers
(`20260813180200`), and — as of today — the three highest-volume edge
functions via `_shared/llm-budget.ts`: `coaching-daily-read` (`daily_read`),
`generate-workout-insight` (`coach_insight`), `process-training-memo`
(`voice_memo`). The guard deliberately does NOT bypass for service-role
callers: machine-invoked paths are exactly what runaways ride in on.

**Layer 2 — no-op-write trigger hygiene** (`20260813180000`). Every trigger
that can enqueue LLM work compares OLD vs NEW and returns early when nothing
changed. The Postgres trap that caused Aug-11: `AFTER UPDATE OF col` fires on
*assignment*, not on *change*.

**Layer 3 — per-user quotas** (`_shared/rateLimit.ts`). Daily buckets +
monthly caps per feature per user, Upstash-backed, fail-closed in prod. These
bound one abusive or buggy *client*; Layers 0–1 bound the *system*.

**Layer 4 — CI enforcement** (`.github/scripts/check_llm_guardrails.py`, job
`llm-cost-gate` in `ci.yml`). Two rules, both ratchets: a new edge function
that calls an LLM without consulting the budget guard fails the build
(existing pre-guard files are grandfathered as warnings — wire one up, remove
it from the baseline list, it can never regress); a new migration adding an
UPDATE trigger that enqueues work without `IS DISTINCT FROM` fails the build.

**Layer 5 — visibility.** `llm_spend_today` (live, by surface),
`yesterday_llm_spend` + the daily Slack alert (13:00 UTC), and the widened
`usage_tracking` (migration `20260813120000` — the old CHECK constraint was
silently dropping rows, which is why the $7 day looked like $0.02).

## Before the first beta user — the short list

1. Google Cloud billing cap set (Layer 0). Non-negotiable.
2. Slack webhook in vault as `slack_alerts_webhook_url` (Step 2 of
   `llm-cost-controls.md`) — without it, both the daily spend alert and the
   budget-trip alert degrade to log lines nobody reads.
3. Deploy the guarded functions:
   `supabase functions deploy coaching-daily-read generate-workout-insight process-training-memo`
   and `supabase db push` from a committed SHA.
4. Rebuild + ship the iOS app (SELECT-only daily-read client).
5. Sanity-run: `SELECT * FROM llm_spend_today;` after a day of use — every
   active surface should appear. A surface you know ran that is missing from
   the ledger is an unguarded path; wire it before it becomes the next loop.

## Scaling the ceilings as testers join

The global daily ceiling (250 calls) assumes ~1 active user with 5× headroom.
Rough guide: `daily_call_ceiling ≈ 50 × weekly-active users`, adjusted from
observed `llm_spend_today` after the first week. Raising it is an UPDATE, not
a deploy: `UPDATE public.llm_budget SET daily_call_ceiling = 500;`
Leave `per_subject_24h_ceiling` at 6 regardless of user count — it's a
per-row loop detector, and rows don't get busier because there are more users.

## When the ceiling trips

The Slack message includes the triage query. The intended reflex: check
whether the top (surface, subject) pair looks like a loop (one subject with
many calls = loop; spread across many subjects = real usage growth). Loop →
leave the ceiling alone, fix the trigger/dispatcher, let jobs drain
overnight. Real growth → raise the ceiling with the UPDATE above and note the
new baseline. Never "fix" a trip by disabling the guard.

## The rules that keep this true (from COST-AUDIT-2026-08-13.md)

Model tier is set by trigger, not surface prestige — machine-invoked paths
run flash-tier or cheaper, always. The client never spends by default — only
an explicit user gesture on a mounted surface triggers a paid call. Retries
never re-bill a failing provider. Every LLM call writes usage tracking in the
same PR that adds the call. Degradation is the design — every AI feature must
answer "what renders when Gemini is down?" And every trigger that can queue
paid work carries a value-change guard.
