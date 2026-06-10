# Deploy Runbook

The thing you'll read at 2am when something breaks. Keep it current. Every new rollback capability or trigger gets a line here, same day.

---

## 1. Surfaces you can deploy

| Surface | Hosting | Deploy method | Rollback method |
|---|---|---|---|
| Web app (Next.js) | Vercel | `git push` to main → auto-deploy | Vercel dashboard → Deployments → previous build → "Promote to Production" |
| Edge functions | Supabase | `supabase functions deploy <name>` from CLI | Re-deploy previous version from git + CLI |
| Postgres migrations | Supabase | `supabase db push` | Write a reverse migration — **never** drop/rollback migrations blindly |
| iOS app | Apple App Store / TestFlight | Xcode → Archive → Upload | TestFlight: remove build; App Store: submit expedited review of previous version |

---

## 2. Before you deploy anything

Checklist, every time. Skipping it catches up with you.

- [ ] CI is green
- [ ] You know what's shipping (read the diff)
- [ ] You know the rollback path for the specific surface
- [ ] You know how you'll verify the deploy worked (a specific user flow or metric)
- [ ] Someone knows you're deploying (Slack / note to self, not silent)
- [ ] Time of day is reasonable (not 11pm Friday unless it's a hotfix)

If the deploy includes a migration: see §5 before running it.

---

## 3. Migration-specific protocol

Schema changes require extra care. Supabase migrations are forward-only by convention — rolling back means writing another migration.

**Before running a migration:**
- Read it. Understand what it does.
- If it touches a production table with >10K rows, ask: is there a lock? Will it block writes? Most `ALTER TABLE … ADD COLUMN` is fast; `ALTER TABLE … RENAME COLUMN` is also fast. `ALTER TABLE … ALTER COLUMN TYPE` or anything with a DEFAULT backfill on existing rows can be slow.
- If it's a destructive change (`DROP COLUMN`, `DROP TABLE`), **stop**. Do it in two releases: first mark deprecated and stop using in code, then drop in a later migration after a 30-day burn-in.

**Running:**
- `supabase db push` from a branch pointed at the correct project
- Verify from the Supabase dashboard that the migration shows up in the migrations list
- Verify the expected schema change (new column appears, etc.)

**If a migration fails mid-run:**
- Don't panic
- Check the Supabase SQL editor for the actual error
- The migration is likely in a half-applied state — you have to write a targeted fix, not re-run the same migration
- If it's a real emergency and nobody's watching, use `DROP … IF EXISTS` in a manual cleanup SQL + re-run

**Reverse migration pattern:**
- Write a new migration file with a timestamp AFTER the broken one
- It undoes what you don't want
- Commit and deploy
- Never delete migration files that have run on prod

---

## 4. Edge function deploy + rollback

Edge functions are simpler — they're stateless code.

**Deploy:**
```
supabase functions deploy <function-name> --project-ref <prod-ref>
```

**Verify:**
- Sentry for any spike in errors on that function
- `llm_requests` for the new deploy's cost profile (if it's an AI fn)
- Manually invoke with a known-good payload to confirm 200

**Rollback:**
```
# From the last-known-good commit SHA:
git checkout <prev-sha> -- supabase/functions/<name>/
supabase functions deploy <name> --project-ref <prod-ref>
# Then: git restore the local files so your branch isn't confused
git restore supabase/functions/<name>/
```

Rolling back an edge function doesn't affect data, so it's relatively safe. The exception: if the old version writes to a schema that the new migration changed, rolling back code without rolling back data is a problem.

---

## 5. iOS build rollback

TestFlight and the App Store have different rollback options.

**During TestFlight (beta):**
- Xcode Organizer → Archives → select the problematic build → Expire
- Push a fix build

**After App Store release:**
- You cannot "roll back" an already-released build. Apple doesn't allow it.
- The options are:
  1. Submit an expedited review of the previous build's source (contact Apple, explain it's a critical fix)
  2. Submit a new build with the fix and request expedited review
  3. Remove the app from sale temporarily (nuclear)
- Average expedited review time: 24–72 hours. Plan accordingly.

**The lesson:** iOS production bugs are expensive. TestFlight aggressively. Don't push to App Store unless you've dogfooded for at least 48 hours.

---

## 6. Rollback triggers (the "when to pull it" list)

These are the alarms. If any of these fire post-deploy, roll back first, diagnose second.

### Critical — roll back immediately

- **Auth error rate > 5%** of signup attempts in the first hour → likely a Supabase config issue. Revert the deploy, check config.
- **Sentry error rate spikes 3× baseline** and stays elevated for > 15 minutes → unknown regression, bail.
- **A user reports the coach told them to push through pain.** Stop-the-line. Pull the response, inspect the context, strengthen the safety rule in `coaching-agent` before re-deploy. This is the single reputational worst case.
- **Data leak complaint** — invoke breach-response protocol (section 8).
- **LLM spend per DAU > $2/day** → a coaching-agent call is runaway. Possible infinite loop, bad prompt, or rate-limit bypass. Disable the affected endpoint via feature flag (if wired) or by deploying an empty handler.

### Serious — investigate within 60 minutes

- **Coach response p95 latency > 8 seconds** → edge function cold-start problem or upstream LLM slow. Check multi-model router logs.
- **Training-log insert failures > 2%** → trigger cascade broken. Check `reconcile-log` and `invalidate_athlete_state_on_training_log` trigger functions.
- **`plan_adjustments` auto-applied action reported as clearly wrong** → revert that specific adjustment via `revert-plan-adjustment` edge function, then pause auto-apply for that `trigger_type` until investigated.
- **Sync lag between iOS and server > 5 minutes p95** → `athlete_state` rebuild performance issue, likely a slow query inside `rebuildAthleteState`.

### Monitor — log and review next day

- Any new 4xx or 5xx error type in the logs (even single occurrence)
- Unusual drop in DAU for the feature you just deployed
- Any user feedback in `coaching_feedback` with a negative sentiment

---

## 7. Post-deploy checklist

First 15 minutes after any deploy:

- [ ] Sentry dashboard open, watching error rate
- [ ] Vercel (or Supabase for edge fn) shows deploy succeeded
- [ ] One real user flow manually tested (login, log a workout, or whatever the deploy touched)
- [ ] For AI changes: one coach-chat interaction tested with real context

First 24 hours:

- [ ] Revisit Sentry for any new error patterns
- [ ] Check `llm_requests` for cost anomalies
- [ ] Check Supabase logs for migration-related noise
- [ ] Scan `coaching_feedback` for any user pushback

First week:

- [ ] Retention cohort review for users who signed up since deploy
- [ ] Sync-lag metrics nominal
- [ ] No escalations from users about the deployed feature

---

## 8. Incident response — basic version

You don't have a formal incident response plan yet. Here's the minimum-viable one to run when something goes wrong.

### When to invoke

Any of the "Critical" rollback triggers above. Any user reports data loss or their account doing something unexpected. Any suspected breach.

### Steps

1. **Stop making things worse.** If a deploy caused it, roll back before anything else.
2. **Write it down.** Start a note (anywhere — Notes app is fine). Time, what you know, what you don't.
3. **Assess scope.** How many users affected? Is data at risk? Is this public?
4. **Contain.** If there's user impact, acknowledge it publicly on whatever channel users watch (X, IG, email). "We're aware of an issue and are investigating. Updates to follow." Minimal, human, not legal-speak.
5. **Fix.** Diagnose, patch, deploy. Use §3 or §4 above.
6. **Verify.** The same verification steps as any deploy — don't trust the fix until tested.
7. **Postmortem.** Within 48 hours, write up what happened, why, and one thing that changes to make it less likely to recur. Save to `docs/postmortems/YYYY-MM-DD-<name>.md`.

### Breach-specific steps (if PII or sensitive data exposed)

- Invoke whatever cyber insurance policy you have (if any). They'll guide next steps.
- Document what data, how many records, which users, from when to when.
- Notify affected users within 72 hours for EU/UK residents (GDPR Art. 33), 30 days for Illinois/California residents per state law (varies — check).
- Notify state AGs per state breach-notification laws (threshold usually 500+ residents).
- Do not delete logs or artifacts that document the breach — preserve for legal.

---

## 9. Contacts

`[TODO: fill these in]`

- Supabase support: `support@supabase.io`
- Vercel support: dashboard → Help → Submit ticket
- Resend support: dashboard → Help
- Your lawyer (for any breach): `[TODO]`
- Cyber insurance carrier (if any): `[TODO]`
- Apple Developer Support (for expedited review): `[TODO]`

---

## 10. Version history of this runbook

| Date | Change | Who |
|---|---|---|
| 2026-04-24 | Initial version | rioreina |

Update this when you add new rollback capability, new trigger, or new surface.

---

*Companion docs: `docs/deploy/h5-supabase-prod-config.md` for the current blocker, `docs/legal/` for legal policies, `docs/adaptive-plan-loop-design.md` for the adaptive coaching architecture.*
