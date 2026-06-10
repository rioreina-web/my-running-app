# LLM cost controls — runbook

How the app protects itself from runaway LLM spend, what to set up
before going live with users, and how to read the daily Slack alert.

**TL;DR**: the hard cap lives in Google Cloud Billing — not in our
code. Our code is the trend signal. Two manual steps are required
before this protection is real: set the Cloud budget, and create the
Slack webhook.

---

## The architecture

There are three layers of cost protection, ordered from outermost
(strongest) to innermost (weakest):

| Layer | Where | What it does | Status |
|---|---|---|---|
| 1. Provider hard cap | Google Cloud Billing | Auto-disables billing on the Gemini project at 110% of budget. **The only layer that can actually stop spending.** | ⚠️ **Manual setup required** |
| 2. Daily Slack alert | `daily-llm-spend-alert` pg_cron | Posts yesterday's spend by model to `#alerts-prod` each morning. Trend signal, not a gate. | ✅ Migration `20260512210000_daily_llm_spend_alert.sql` |
| 3. Per-route rate limits | `_shared/rateLimit.ts` (edge) + `web/src/lib/rate-limit.ts` (web) | Caps individual users' calls per minute. Bounds one user's blast radius. | ✅ Partial — see W2.3 to standardize |

Cost-cap code that used to live inside `generate-workout-insight`
(`dailyBudgetExceeded()` + `COACH_INSIGHT_DAILY_BUDGET` env var) has
been **removed**. The provider-side cap supersedes it.

---

## Step 1 — Set the Google Cloud billing budget

**Owner:** repo admin with Cloud Console access to the project that
owns the Gemini API key.
**Time:** ~5 minutes.

1. Sign in to [Google Cloud Console](https://console.cloud.google.com/).
2. Confirm you're in the project that owns `GEMINI_API_KEY` (top
   project picker; same project as the API key in
   [APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials)).
3. Navigate to **Billing → Budgets & alerts**:
   `https://console.cloud.google.com/billing/budgets`
4. Click **Create budget**.
5. **Scope:**
   - Name: `Gemini API hard cap`
   - Time range: `Monthly`
   - Projects: select this project only
   - Services: filter to **Generative Language API** (and **Vertex AI
     API** if used)
6. **Amount:**
   - Budget type: `Specified amount`
   - Target amount: **$50** (raise as user count grows; rule of thumb
     is 2× expected monthly spend)
7. **Actions / thresholds:**
   - Alert at **50%** — email to owner
   - Alert at **80%** — email to owner
   - Alert at **100%** — email to owner
   - Alert at **110%** — email to owner **AND** check
     `Disable billing to stop usage`. This is the hard cap.

   ⚠️ Disabling billing breaks every Google-Cloud-backed service in
   the project, not just Gemini. If you co-host other services in the
   same project (you shouldn't), this will take them down. Verify the
   project only contains the Gemini API key.

8. **Save.** Capture the budget resource name and paste it into the
   commit message of any related PR for traceability.

**Verify:** trigger a test alert by lowering the budget to $0.01,
making a single Gemini call from the app, waiting ~5 minutes. The
50%/80%/100% emails should arrive. Then reset budget to $50.

---

## Step 2 — Create the Slack webhook + store in Supabase vault

**Owner:** Slack workspace admin + repo admin.
**Time:** ~10 minutes.

### Create the webhook

1. In Slack, open
   [Slack App directory → Incoming Webhooks](https://api.slack.com/apps?new_app=1).
2. Create a new app (or use an existing internal app):
   - App name: `LLM cost alerts`
   - Workspace: your team workspace
3. **Features → Incoming Webhooks**: toggle on.
4. **Add New Webhook to Workspace**.
5. Select channel `#alerts-prod` (create it if it doesn't exist;
   private channel is fine).
6. Authorize. Copy the resulting webhook URL — it looks like
   `https://hooks.slack.com/services/T0XXX/B0XXX/aBc123...`

### Store it in Supabase vault

The cron job reads the webhook from `vault.decrypted_secrets`, so it
never appears in code or env files.

1. Open the Supabase project dashboard.
2. **Database → Vault → Secrets**.
3. **New secret**:
   - Name: `slack_alerts_webhook_url`
   - Secret: paste the webhook URL from above
   - Description: `Slack incoming webhook for #alerts-prod — used by daily-llm-spend-alert and future cost/error alerts`
4. **Save.**

### Apply the migration

```bash
supabase db push                  # local dev
# or in prod:
supabase migration up --linked    # against the linked remote project
```

The cron job will fire daily at **13:00 UTC** (6am Pacific / 9am
Eastern in summer). The first message arrives the morning after the
migration applies.

---

## Step 3 — Verify the alert fires

After the migration applies and the webhook is in vault, run this in
the Supabase SQL editor to confirm the view works:

```sql
SELECT * FROM yesterday_llm_spend ORDER BY est_cost_usd DESC NULLS LAST;
```

You should see one row per model with calls, input/output tokens,
and `est_cost_usd`. If yesterday had no LLM calls (e.g. fresh
project), the view is empty — that's fine.

To **dry-run the Slack message immediately** without waiting for
13:00 UTC:

```sql
DO $$
DECLARE
    _webhook_url TEXT;
    _total_cost  NUMERIC;
    _total_calls BIGINT;
    _breakdown   TEXT;
    _slack_body  TEXT;
BEGIN
    _webhook_url := (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'slack_alerts_webhook_url' LIMIT 1
    );

    SELECT COALESCE(SUM(est_cost_usd), 0), COALESCE(SUM(calls), 0)
    INTO _total_cost, _total_calls
    FROM yesterday_llm_spend;

    SELECT COALESCE(
        STRING_AGG(
            format('• `%s` — %s calls, $%s',
                   model, to_char(calls, 'FM999G999'),
                   to_char(est_cost_usd, 'FM999G990.00')),
            E'\n'),
        'No LLM calls yesterday.')
    INTO _breakdown
    FROM (SELECT * FROM yesterday_llm_spend
          ORDER BY est_cost_usd DESC NULLS LAST LIMIT 8) top;

    _slack_body := jsonb_build_object('text', format(
        E':bar_chart: *DRY-RUN: LLM spend yesterday* — $%s across %s calls\n\n%s',
        to_char(_total_cost, 'FM999G990.00'),
        to_char(_total_calls, 'FM999G999'),
        _breakdown
    ))::TEXT;

    PERFORM net.http_post(
        url := _webhook_url,
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := _slack_body::JSONB
    );
END;
$$;
```

The message should land in `#alerts-prod` within a few seconds.

---

## Reading the daily alert

Example morning alert:

```
:bar_chart: LLM spend yesterday — $4.27 across 2,134 calls

• coach_insight_proxy_gemini-2.5-flash — 847 calls, $0.96
• moderate-gemini-gemini-2.5-flash — 612 calls, $1.84
• complex-gemini-gemini-2.5-flash — 89 calls, $0.91
• gemini-2.5-pro — 12 calls, $0.43
• simple-groq-llama-3.1-8b-instant — 421 calls, $0.04
• gemini-2.5-flash — 153 calls, $0.09
• cache — 67 calls, $0.00
• groq-whisper — 312 calls, $0.00

Cloud billing dashboard is ground truth; this is a trend signal.
Budget cap: $50/mo (see docs/deploy/llm-cost-controls.md).
```

**What to look at:**

- **Total $ vs. yesterday and last week.** A 2–3× spike means
  something is off — a retry loop, a prompt regression, or a real
  user-growth jump. Investigate before the budget cap forces the
  question.
- **Top model.** If `gemini-2.5-pro` jumps above $2/day at 1k users,
  someone shipped a Pro call site that should be Flash.
- **`cache` line item.** When prompt caching (C.3) lands, this row
  shows cache hits, which are free. A flat `cache` count while
  Flash spend climbs means the cache key is busted.
- **`coach_insight_proxy_*` row.** This is an estimate based on job
  count, not real token logging. It's an undercount until C.2 ships
  per-call token logging to `usage_tracking` from
  `generate-workout-insight`.

**What it does NOT do:**

- Block any LLM call. The Cloud billing cap is the only thing that
  blocks.
- Account precisely. Use Cloud's billing dashboard for monthly
  reconciliation.
- Alert on a cost spike in real time. It's a once-a-day post.
- Cover non-LLM cost (Supabase compute, Storage, ml-service). Those
  have their own dashboards.

---

## When to update the pricing table

When a provider changes prices, edit `llm_model_pricing` via a
new migration. Don't edit `20260512210000_daily_llm_spend_alert.sql`
— migrations are append-only (see CLAUDE.md hard rules).

```sql
-- supabase/migrations/<new-timestamp>_update_llm_pricing.sql
INSERT INTO llm_model_pricing (model, input_per_1m_usd, output_per_1m_usd, notes)
VALUES ('gemini-2.5-flash', 0.25, 2.00, 'Price drop effective 2026-MM-DD')
ON CONFLICT (model) DO UPDATE
SET input_per_1m_usd  = EXCLUDED.input_per_1m_usd,
    output_per_1m_usd = EXCLUDED.output_per_1m_usd,
    notes             = EXCLUDED.notes,
    updated_at        = NOW();
```

---

## When to remove this alert

When the eval harness (W2.1) and the C.2/C.3 instrumentation are
both live, the daily Slack alert can be augmented or replaced with:

- Per-prompt-version cost regression detection in CI
- Sentry counters on `prompt_response_truncated` and
  `gemini_request_count` (already partially wired)
- A Grafana / Metabase dashboard pulling `usage_tracking` directly

The Slack alert is intentionally simple. It exists to be useful from
day one, not to be the final answer.
