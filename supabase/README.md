# Supabase — Dev / Prod Promotion

This repo ships a single `supabase/` folder that drives **both** local
development (via the Supabase CLI) and the hosted project. Most of the
settings in `config.toml` apply to local only — hosted auth/SMTP/redirect
URLs live in the dashboard.

## Environments

| Env | Supabase project | Purpose |
|---|---|---|
| Local | `supabase start` via CLI | Dev, branch testing, local migrations |
| Prod (`RunningAppMVP2`) | `aqdijapxmjqaetursrde` | User-facing production |

The older `RunningMVP` project (`mkwxlsjzrdlzhoqdqtfa`) is archived — do
not deploy there.

## Prod one-time setup (HOTFIX-H.5)

Until this checklist lands, new users cannot receive confirmation emails.
Do each step in the Supabase dashboard for project `RunningAppMVP2`.

### 1. Set SMTP (SendGrid)

Dashboard → Project Settings → Auth → SMTP Settings:

- **Enable custom SMTP**: ON
- **Host**: `smtp.sendgrid.net`
- **Port**: `587`
- **Username**: `apikey` (literal string, not your API key)
- **Password**: your SendGrid API key (generate at
  https://app.sendgrid.com/settings/api_keys — restricted scope: Mail
  Send only)
- **Admin email**: `noreply@heatcheckmile.com` (or the prod sender you
  verified with SendGrid)
- **Sender name**: `HeatCheckMile` (or whatever brand name users will see)

> The `[auth.email.smtp]` section in `config.toml` already carries this
> wiring for local — it's the source of truth for the CLI `supabase start`
> flow. The dashboard values above drive the hosted project.
>
> **Alternative:** Resend is equally good. If you prefer Resend, flip the
> `host` in config.toml to `smtp.resend.com` and use the same pattern
> (username: `resend`, password: API key).

### 2. Site URL + redirect allow-list

Dashboard → Authentication → URL Configuration:

- **Site URL**: production web URL (e.g. `https://heatcheckmile.com`)
- **Redirect URLs** (add each as a separate entry):
  - `https://heatcheckmile.com`
  - `https://www.heatcheckmile.com` (if used)
  - `running-log://auth-callback` (iOS custom scheme — verify the exact
    scheme in `RunningLog.xcodeproj` → Info → URL Types)
  - `http://localhost:3000` (only if you want local dev to hit prod auth —
    usually no)

### 3. Email confirmations

Dashboard → Authentication → Providers → Email:

- **Enable email signups**: ON
- **Confirm email**: ON

Mirrors `enable_confirmations = true` in `config.toml:209`.

### 4. Trigger functions — `app.settings` vars

Every migration that uses `pg_net` reads two Postgres settings:

```
app.settings.supabase_url        → e.g. https://aqdijapxmjqaetursrde.supabase.co
app.settings.service_role_key    → service-role JWT from dashboard
```

Set them on the prod DB via the SQL editor:

```sql
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://aqdijapxmjqaetursrde.supabase.co';
ALTER DATABASE postgres SET app.settings.service_role_key = '<paste service-role JWT>';
```

Without these, the adaptive triggers (reconcile-log,
post-run-reconciliation) silently no-op with `RAISE WARNING`.

Migrations that depend on these settings:
- `20260306100000_schedule_weekly_reports.sql`
- `20260410100000_auto_process_voice_logs.sql`
- `20260416400000_adaptive_triggers.sql`
- `20260417500000_trigger_reconcile_log.sql`
- `20260417700000_weekly_plan_rebalance_cron.sql`

## Verifying the setup

Sign up a new test user on the production web app with a real inbox.
Expect:

- Confirmation email arrives within 60 seconds
- Click lands on the production URL (not localhost)
- The user record shows `email_confirmed_at` populated after the click

If the email doesn't arrive, check SendGrid → Activity to see whether it
was sent, bounced, or blocked.

## Promoting migrations

Migrations land in `supabase/migrations/` and get applied via:

```bash
# Apply all pending migrations to prod
cd my-running-app
npx supabase db push --project-ref aqdijapxmjqaetursrde
```

Or via the MCP `apply_migration` tool one-by-one for destructive or
sensitive migrations (anything that touches `athlete_state`, adds new
RLS policies, or drops columns warrants explicit apply).

## Promoting edge functions

```bash
cd my-running-app
npx supabase functions deploy <function-name> --project-ref aqdijapxmjqaetursrde
```

Edge function env vars (OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.) are set
per-project in the dashboard:
Dashboard → Edge Functions → Secrets.

## Rollback playbook

- **Migration gone wrong:** write a new down-migration. Do not delete
  history or amend prior migrations after they land in prod.
- **Edge function gone wrong:** redeploy a prior git SHA.
- **Auth settings:** dashboard has a one-level undo (just revert the
  field). SMTP password rotation: generate a new SendGrid key, update
  dashboard, revoke old.
