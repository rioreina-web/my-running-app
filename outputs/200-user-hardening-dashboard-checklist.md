# Dashboard checklist — 200-user hardening (ADR #1 + #6)

Companion runbook for `outputs/200-user-production-hardening.md`. These
items can't be done from the CLI or MCP — they're Supabase dashboard
clicks. Estimated total: **30–45 minutes** of your time.

Project: **RunningAppMVP2** (`aqdijapxmjqaetursrde`) — verify the project
selector before clicking anything. The inactive `RunningMVP` project is
unrelated.

---

## ADR #1 — Enable Point-in-Time Recovery

**Why:** Without PITR, the worst-case rollback is last night's snapshot →
a day of `voice_logs` and `training_log` data gone. Tier-up + PITR is the
single highest-value hardening item.

**Verify current state first:**

1. Dashboard → Settings → Add-Ons → confirm **Pro tier** is active.
   - If on Free, this is a billing change. Pro is required for PITR.
2. Dashboard → Database → Backups → look for the "Point-in-Time Recovery"
   panel.

**Enable:**

3. If PITR is disabled, click **Enable Point-in-Time Recovery**.
4. Default retention is 7 days. For a 200-user launch, 7 days is fine; if
   you anticipate slower incident triage, 14 days adds a few dollars/month
   and buys breathing room.
5. Confirm the next scheduled snapshot has run after enabling. PITR
   coverage starts from the first base backup, not the moment you click.

**Test (recommended within the first week):**

6. Schedule a backup-restore drill: pick an arbitrary timestamp from
   yesterday, restore to a branch, confirm row counts and a sample
   `training_logs` row match the source. Document the runbook in
   `docs/deploy/backup-restore-drill.md` (does not exist yet — write it
   when you do the drill). Without a tested restore, PITR is theater.

---

## ADR #6 — Lock auth defaults

**Why:** Defaults that are fine for 5 internal beta users become abuse
vectors as soon as the gate opens. Each toggle is 30 seconds; the whole
batch is under 10 minutes. The advisor independently flags one of these
already.

Dashboard → Authentication → Providers / Settings / Rate Limits panels.

### 6.1 Require email confirmation
- **Auth → Providers → Email** → toggle **Confirm email** to ON.
- Effect: new signups can't sign in until they verify their email.
  Prevents fake-email enumeration attacks and bot signups.
- Side effect: your onboarding flow needs to handle the unverified state
  gracefully. Check that the iOS sign-in path shows a clear "check your
  email" state — `RunningLog/Auth/SignInView.swift`. If it currently
  assumes immediate sign-in, this toggle will break first-run UX for new
  accounts. Fix before enabling.

### 6.2 Enable leaked-password protection
- **Auth → Policies → Password Policy** → toggle **Leaked password
  protection** to ON.
- This is the advisor finding `auth_leaked_password_protection` (WARN) —
  confirmed disabled as of 2026-05-22. Enabling checks new/changed
  passwords against HaveIBeenPwned without ever sending the password.
- No app-side changes required. The signup/password-reset paths return a
  standard error if the password is in a known breach corpus.

### 6.3 Tighten rate limits
- **Auth → Rate Limits** → review each row. Defaults are *very* permissive
  (e.g. 30 password resets / hour / IP).
- Recommended floors for 200-user launch:

| Limit | Default | Set to |
|---|---|---|
| Password reset emails | 30/hr/IP | **5/hr/IP** |
| Sign-up emails | 30/hr/IP | **10/hr/IP** |
| Magic link / OTP emails | 30/hr/IP | **10/hr/IP** |
| Token refresh | 1800/hr/user | leave default |
| `/verify` (email confirmation) | 360/hr/IP | leave default |

  Tighter caps surface abuse early and add zero friction for real users.

### 6.4 JWT expiry sanity check
- **Auth → Sessions → JWT Expiry** → confirm it's **3600 seconds (1 hour)**
  or shorter.
- If higher than 3600, lower it. Refresh tokens handle long-running
  sessions; a long-lived JWT just increases the blast radius of a stolen
  token.

### 6.5 Optional but worth it: enable MFA for the admin/Rio account
- **Account → Security → Multi-factor authentication** → enable TOTP on
  the Supabase account that owns this project.
- Not in the ADR but the same logic applies: project-owner credential
  loss is the worst incident a small team can have.

---

## Verification after the dashboard work

Re-run the Supabase advisor (Database → Database Linter → Security tab).
The following finding should disappear after 6.2:

- `auth_leaked_password_protection` — Leaked Password Protection Disabled

The other advisor findings (RLS on `debug_coach_log`, storage bucket
listing, `current_coach_id` mutable search_path) clear separately once
the three pending security migrations land — see the deploy section in
`outputs/200-user-production-hardening.md` and the migration files at
`supabase/migrations/2026052[12]*.sql`.

---

## What is NOT in this checklist

- Migration deploys — those are CLI/MCP work, separate runbook.
- PITR restore drill itself — schedule it as its own session; it's worth
  the 30 minutes of practice before you actually need it.
- Migration drift remediation — the `user_profiles` / `coach_insight_jobs`
  story uncovered in the audit is a structural reconciliation project,
  not dashboard config. See the audit notes.
