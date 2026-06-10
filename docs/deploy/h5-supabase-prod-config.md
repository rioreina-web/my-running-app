# HOTFIX-H.5 — Supabase Production Configuration Runbook

**Status:** Not yet executed. Blocks public launch — without this, new-user signup in production is broken.
**Estimated time:** 3–4 hours (bulk of it is DNS propagation).
**Cost:** $0 on Resend free tier (100 emails/day) + whatever Supabase Pro you already pay for.
**Who executes:** Rio. This is mostly dashboard work that requires your accounts and DNS access.

---

## Why this matters

Your Supabase project is currently configured for local development:
- `site_url` points to `http://localhost:3000`
- SMTP is routed to Inbucket (a local test email server)
- Email confirmation is disabled

In this state, **nobody can actually complete signup in production**. They'll hit "check your email to confirm" and nothing arrives. This is the #1 blocker for any real launch.

---

## What you'll do, in order

### Step 1 — Set up Resend (60–90 min, mostly DNS wait time)

Resend is the email provider we're using. Free tier: 100 emails/day, unlimited on paid tiers. They have the cleanest Supabase integration.

1. **Create an account** at https://resend.com. Use a workspace / team email, not your personal one.
2. **Add your domain** (e.g., `postrundrip.com`) via Domains → Add Domain.
3. **Add the DNS records** Resend gives you (SPF + DKIM + DMARC) to your registrar (Cloudflare, Namecheap, Route 53, wherever you have your DNS). This is usually 3–5 records.
4. **Wait for DNS propagation.** Resend shows a green "Verified" badge when it's good. Typically 10 minutes to 2 hours. You can continue to Step 2 while waiting.
5. **Create a sending address.** I recommend `noreply@postrundrip.com` for transactional emails and `hello@postrundrip.com` for manually-sent communications. Verify both.
6. **Generate an API key** for Supabase to use. Restrict it to the "send" scope only, if Resend offers scope control. Copy it — you'll paste it in Step 2.

### Step 2 — Wire Supabase Auth to Resend (15 min, once DNS is verified)

In your Supabase production project (**not dev**):

1. **Authentication → Email Templates.** Review each template (confirmation, password reset, magic link). They're generic by default — you may want to brand them slightly, but this is optional for v1.

2. **Authentication → Providers → Email → SMTP Settings:**
   - Enable Custom SMTP
   - Host: `smtp.resend.com`
   - Port: `465`
   - Username: `resend`
   - Password: your Resend API key from Step 1
   - Sender name: `Post Run Drip`
   - Sender email: `noreply@postrundrip.com` (must match a verified address in Resend)

3. **Save.** Supabase will run a test send immediately. If it fails, double-check the verified address + API key + DNS.

4. **Send yourself a test.** From Authentication → Users, trigger a password reset to an email you control. Confirm it arrives and the branding is correct.

### Step 3 — Turn on email confirmation (5 min)

In the production Supabase project:

1. **Authentication → Settings → Sign Ups:**
   - ✅ Enable email confirmations
   - Set "Secure email change" to enabled
   - Set "Prevent sign ups if new user has not confirmed email" to enabled

2. Decide on a confirmation token expiration. Default 24 hours is fine for v1.

### Step 4 — Set the real site URL (5 min)

Still in production Supabase:

1. **Authentication → URL Configuration:**
   - Site URL: `https://postrundrip.com` (or your actual production domain)
   - Additional Redirect URLs: add any alternative hostnames and your iOS custom scheme
     - `https://www.postrundrip.com/*`
     - `postrundrip://*` (if you have a custom scheme for deep links on iOS)

2. **Save.** Every new confirmation/reset link will now point at your real site.

### Step 5 — Set the trigger-function Postgres settings (10 min)

The `reconcile-log` and `athlete-state-invalidate` triggers need two settings available at Postgres runtime to call edge functions via `pg_net`:

```sql
-- Run in Supabase SQL editor, production project only
ALTER DATABASE postgres SET "app.settings.supabase_url" TO 'https://<YOUR-PROD-PROJECT-REF>.supabase.co';
ALTER DATABASE postgres SET "app.settings.service_role_key" TO '<YOUR-SERVICE-ROLE-JWT>';
```

Replace:
- `<YOUR-PROD-PROJECT-REF>` with the project reference from your Supabase dashboard URL
- `<YOUR-SERVICE-ROLE-JWT>` with your service-role key from Authentication → API (the long JWT that starts with `eyJ...`)

These become default settings for all database connections in this project. The triggers read them via `current_setting('app.settings.supabase_url')`.

**Do NOT commit these values to the repo.** They're set at the database level, not in a migration file. Ephemeral in your SQL editor.

**Verify it worked:**
```sql
SELECT current_setting('app.settings.supabase_url', true);
SELECT current_setting('app.settings.service_role_key', true);
```
Both should return non-null values.

### Step 6 — Remove dev config from repo `config.toml` (10 min, clean up)

`supabase/config.toml` has dev-mode values. For v1 it's fine to leave them (they only apply to local dev), but the production project should **not** be sourced from `config.toml` — it's configured via the dashboard. To prevent accidental promotion of dev values:

1. Add a prominent comment at the top of `supabase/config.toml`:
   ```
   # ⚠️ LOCAL DEV ONLY — production settings live in the Supabase dashboard.
   # Changes here only affect local `supabase start` environments.
   ```

2. Consider creating `supabase/config.prod.toml.example` with the production shape as a reference, but do not use it to deploy. Production settings are a manual dashboard concern.

### Step 7 — End-to-end verification (15 min, the step everyone skips)

Don't trust the dashboard. Verify the whole signup flow:

1. In an incognito browser, go to your production web app (`https://postrundrip.com`).
2. Click "Sign up" with a real email address you control.
3. Confirm you receive the confirmation email within 60 seconds. Subject should make sense, body should have a clickable link, from-address should be your `noreply@`.
4. Click the link. Verify you land on your production site (not localhost). Verify the account is confirmed.
5. Sign out. Sign back in. Verify the full login flow works.
6. Trigger a password reset. Verify that email arrives and the reset link works.
7. Log a workout or do anything that would insert a `training_logs` row. Verify in the dashboard that `athlete_state.last_updated_at` gets invalidated (the trigger fires). If it doesn't, Step 5 wasn't set correctly.

---

## Common failures

- **"Email not arriving."** 95% of the time this is DNS not fully propagated. Check Resend's dashboard for the domain's verification status. Wait another hour. If still broken, check the spam folder and the Supabase Auth logs (Authentication → Logs) for SMTP errors.

- **"Confirmation link goes to localhost."** Step 4 wasn't saved. Go back and re-check Authentication → URL Configuration.

- **"Triggers not firing."** Step 5 wasn't executed, or the SQL editor was pointed at dev instead of prod. Run the verification queries in Step 5 to confirm the settings are set.

- **"Email is in spam."** Make sure all DNS records Resend gave you are present, including DMARC. Send a test email to `mail-tester.com` to get a deliverability score. Aim for 9+/10.

---

## What "done" looks like

- [ ] Resend account created, domain verified, API key issued
- [ ] Supabase prod SMTP pointed at Resend, test send works
- [ ] Email confirmation enabled on prod
- [ ] Production `site_url` set, confirmation links go to the real domain
- [ ] Trigger Postgres settings (`app.settings.supabase_url` + `app.settings.service_role_key`) set on prod
- [ ] Full signup → confirm → login cycle tested with a real email
- [ ] Password reset tested end-to-end
- [ ] Training log insert on prod triggers `athlete_state` invalidation (verify in DB)

Once all 8 boxes are checked, HOTFIX-H.5 is done. You can credibly run a public signup flow.

---

## What this doesn't cover (defer)

- Custom branded email templates (nice-to-have, not launch-blocking)
- Sender rotation / multiple domains (premature)
- DMARC enforcement policy stronger than `p=quarantine` (start permissive, tighten after a month of clean sending)
- Bounce / complaint handling (Resend handles this; add dashboards when volume warrants)

---

*Tag commits for this work with `HOTFIX-H.5` so they're greppable in the commit log.*
