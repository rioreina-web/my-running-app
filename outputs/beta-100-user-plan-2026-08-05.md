# Post Run Drip — 100-User Beta Plan

**Date:** 2026-08-05 · **Target: first invites out in 2–3 weeks (week of Aug 24), 100 testers onboarded by late September**

---

## 1. Where the beta actually stands (verified today, not from docs)

I checked the live production backend (`RunningAppMVP2`), the deployed edge functions, the applied migration ledger, and the repo docs. Here's the honest picture:

**The beta never opened.** Production has **2 user accounts** (you plus one test account), zero external sign-ins in the last 30 days, and no TestFlight build has ever been distributed. The July 13 launch date in `post-run-drip-beta-launch-plan.md` came and went. That plan targeted 25–50 testers; this one targets 100, so some of its assumptions change (Section 4).

**But the app is real and actively alive.** You logged training data today; a migration was pushed to prod today (`20260805171724`); the Daily Read pipeline has dispatched 1,200+ times. This is not a stale project — it's a heavily-used single-user product that has never met a second user.

**And most of the scary stuff from the July audits is actually fixed in prod.** This matters — the July 15 beta-failure audit and July 17 risk sweep read terrifying, but I verified against the live database that the big ones landed:

| July finding | Status today (verified) |
|---|---|
| Voice memos in a public storage bucket (health-data leak) | ✅ Fixed — `make_user_storage_buckets_private` applied in prod |
| Anon-key RLS holes on 5 tables (home GPS, coachable moments, etc.) | ✅ Fixed — `close_anon_rls_holes` applied in prod |
| Multi-user isolation | ✅ PASS — 35/35 user tables RLS-enabled, verified statically *and* behaviorally (2026-07-20 audit) |
| "Cut" LLM functions (custom-plan-builder, form-check, biomechanics) live in prod | ✅ Gone — not in the deployed function list |
| Unbounded Gemini bill (rate limiting failed open) | ✅ Code fails closed now + monthly caps wired into 21 LLM functions — but see the Upstash verification item below |
| HealthKit/mic denial → app looks broken | ✅ Fixed 07-16 (honest 5-state detection, empty states) |
| Crash-on-launch if Secrets.xcconfig missing from archive | ✅ Build-phase guard added 07-16 |
| Edge functions invisible when failing | ✅ Sentry wired into the core 9 functions (needs `SENTRY_DSN` secret set — verify) |

**What's genuinely still open** is a much shorter list, and it's Section 2.

---

## 2. The gap list — ranked

### Tier 0 — blockers. No invite goes out until these are done. (~3–5 working days)

**1. Account deletion is not deployed.** I verified: migration `20260720120000_delete_user_account_function` is **not** in the prod ledger, `delete_user_account()` does not exist in the database, and there is no `delete-account` edge function deployed. The code was written and documented on 07-20 (`account-deletion-2026-07-20.md`) — it just never shipped. Apple Guideline 5.1.1(v) requires in-app deletion for any app with account creation, and for a health-data app you do not want 100 strangers you can't erase. **Action: commit → `supabase db push` → `supabase functions deploy delete-account` → include the Settings UI in the beta build → test with a throwaway account.**

**2. Legal docs are still TODO-laden drafts, unlinked.** Verified today: both `docs/legal/privacy-policy.md` and `terms-of-service.md` still open with "⚠️ DRAFT — NOT LEGAL ADVICE" and carry 28 TODOs between them, and the public landing page has no privacy/terms links. **TestFlight external testing goes through Beta App Review, which requires a working privacy policy URL** — this literally gates the invite link. Action: fill in the TODOs (contact email, dates, governing law), get at minimum a quick professional read (this is health data), host both pages on the web app, link from landing footer + App Store Connect + the app's Settings.

**3. Anon-callable SECURITY DEFINER RPCs are back (or never fully closed).** Today's live security advisor flags **13 SECURITY DEFINER functions executable by `anon`** via PostgREST — including `dedupe_recent_training_logs`, which the July 17 sweep described as a global delete sweep that bypasses RLS. That sweep said these were revoked in `close_anon_rls_holes`, but the advisor sees them callable now — either later migrations re-granted EXECUTE or new functions shipped without the revoke. **Action: one migration revoking EXECUTE from `anon`/`authenticated` on all 13 (list is in the advisor output); re-run the advisor to confirm zero.** Also in the same pass: drop the two backup tables with RLS disabled (`_heat_backfill_backup_20260805`, `_dup_cleanup_backup_20260803`) and enable leaked-password protection in Auth settings (one dashboard toggle).

**4. TestFlight from zero.** Nothing exists yet, and this has real lead time, so start it Day 1 in parallel:
   - Apple Developer Program enrollment active ($99/yr if not already)
   - App Store Connect app record: name, bundle ID, privacy policy URL, App Privacy questionnaire (be accurate: health & fitness data, audio, location — this is scrutinized for HealthKit apps)
   - Archive a build with the Secrets guard passing, upload, distribute to **internal testers** (you) first
   - Create an **external tester group**; the first build submitted to it triggers Beta App Review (typically ~1–2 days, occasionally longer for health apps — budget a week)
   - Write the 3-step install guide with screenshots (the July plan already calls for this; TestFlight confuses non-technical runners)

**5. Money guardrails verified, not assumed.** The code fails closed now, but three operator items from `ai-big-bill-risks.md` need eyes-on confirmation: **(a)** `UPSTASH_REDIS_URL`/`TOKEN` set as function secrets in prod (a `redis-probe` function exists — invoke it), **(b)** the Google Cloud billing cap on the Gemini project actually configured in the console (5 minutes, the single most important cost control), **(c)** the daily spend alert firing. Also confirm **Supabase PITR** is on — "data continuity is the value proposition," and a bad migration during the beta with no point-in-time recovery costs testers days of data and you their trust.

**6. Repo hygiene enough to deploy safely.** The working tree is on `snapshot/trends-v2-wip-2026-07-31` with 92 uncommitted changes. You don't need perfect CI in 2 weeks, but you do need: the beta build cut from a committed SHA, migrations pushed from that SHA (hard rule #9), and the deploy workflow's GitHub secrets added so redeploys aren't hand-run. Freeze feature work on the beta branch once wave 1 goes out.

### Tier 1 — before you scale past ~25 testers (during weeks 2–4, in parallel with early waves)

1. **The onboarding data story.** The product promise is "lands in a product that already knows her," but the import is still the 30-most-recent-runs path (per the July audit; verify current state). For 100 self-coached runners, first-session impression is everything. Either ship a bounded backfill (e.g., 6 months, with `generate-workout-insight` skipping rows older than 90 days to control cost — the audit's own suggestion) or set expectations explicitly in the onboarding email ("it reads your last ~30 runs and gets smarter from there"). Deciding this is a Day-1 product call; don't let it be discovered by testers.
2. **Record the stub eval cassettes.** The golden safety families (`reschedule-plan`, `coaching-agent-*`) still had ~16 empty cassettes as of 07-15, and the unrecorded cases are exactly the safety-baitable ones ("push through injury," "athlete self-diagnoses"). One `record.ts` run with `GEMINI_API_KEY`, ~$0.05. With 100 strangers poking the Coach, this is cheap insurance on the "AI advises, never acts" principle.
3. **iOS multi-device correctness items** from the July 17 sweep, because 100 users means shared devices, flaky networks, and sign-out/sign-in flows you never hit alone: offline queue stamps userId + purges on sign-out (cross-account voice-memo leak), auto-sync upsert (duplicate runs → double-counted mileage), token-refresh failure handling. One iOS PR.
4. **Coach-portal exposure.** Every beta athlete can currently reach the web coach portal and mint a coach account. Not a data leak, but it exposes an unfinished B2B surface to consumer testers — gate it behind a role check or hide the nav.
5. **The app-loop manual test** from `multi-user-isolation-verification-2026-07-20.md`: two fresh accounts on real devices, confirm zero bleed-through, then delete-account round trip. This is the last unchecked box on multi-user isolation and takes an hour once TestFlight works.

### Tier 2 — during the beta (don't block on these)

- Sentry on the remaining ~30 edge functions + a failed-job alert on the outbox drains
- Strava token encryption; `/api/vital-stream` IDOR fix (or disable the route if Vital stays off for beta)
- The P2 list from the July sweeps (polling loops, MainActor stream building, CI action pinning)
- Landing page aligned to the Maya wedge (nice for credibility when run-club strangers google you)

---

## 3. Recruiting 100 testers (the July plan scaled up)

The July plan's math: personal network converts ~50%, and it was sized for 25–50. **For 100 onboarded you need ~180–220 invites**, which outruns your personal network. Three rings, worked in order:

**Ring 1 — personal network (~30–40 onboarded).** The existing 1:1 invite copy in `post-run-drip-beta-recruiting-copy.md` still works. These are also your soft-launch wave — highest tolerance for bugs, fastest feedback.

**Ring 2 — run clubs (~40–50 onboarded).** This becomes the workhorse ring at 100 scale. Target 4–6 clubs, not 2–3. One captain intro per club, forwardable pitch (already drafted), and offer the club something: a "founding club" shout-out, or a group leaderboard follow-up call. Runners in clubs are pre-qualified (consistent mileage) and socially accountable.

**Ring 3 — warm online communities (~20–30 onboarded).** New at this scale: your own Strava/IG following, local subreddit or r/running-adjacent communities where personal-project posts are welcome, and a waitlist link in your Strava bio. Screen sign-ups with the same filter: self-coached, 20+ mpw, iPhone, has a race or goal. **Keep the screener** — 100 low-mileage curious installs generate no signal for the smart features and burn your support time.

**Waves, strictly.** 10 → fix → 25 → fix → 30 → 35. A bug at tester #8 is a Tuesday; the same bug at tester #100 is a wasted beta. At 100 testers you cannot personally DM everyone, so the infrastructure the July plan called "nice-to-have" becomes must-have: onboarding email sequence, a weekly 5-question feedback form, and a single support channel (a dedicated email or small Discord/WhatsApp group — pick one).

**iOS only, still.** Say it on the landing page to save everyone time.

---

## 4. Week-by-week

**Week 1 (Aug 5–12) — unblock.**
- Deploy account deletion (migration + function + Settings UI in build)
- Legal docs: fill TODOs, professional read, host + link everywhere
- Security migration: revoke the 13 anon RPCs, drop backup tables, enable leaked-password protection; re-run advisor to zero
- Verify Upstash secrets, Google Cloud billing cap, PITR, `SENTRY_DSN`
- App Store Connect record + first internal TestFlight build on your phone
- Decide the onboarding-import story (backfill vs. framed expectation)
- Start Ring 1 list (names + channel per person) and line up run-club captains

**Week 2 (Aug 13–19) — soft launch.**
- Submit build to Beta App Review (external group) — budget for one rejection cycle
- 3–5 closest runner friends install via TestFlight; watch them onboard **without helping**
- Fix what breaks; run the two-account isolation + delete-account manual test
- Stand up feedback form, onboarding email, support channel, install guide
- Ship the iOS multi-device PR; record eval cassettes

**Week 3 (Aug 20–26) — wave 1–2.**
- 10 invites, then 25 more once the first 10 onboard cleanly
- Personally watch the activation funnel daily (queries below)
- Post the organic social ask; run-club pitches go out

**Weeks 4–6 (Sept) — scale to 100.**
- Waves of ~30 as clubs and online sign-ups convert
- Weekly feedback pulse; the "did it notice something true?" question from week 2 of each tester's life
- Week-3-of-each-cohort is the real test (enough data for the smart features) — push Coach Read generation + 1–5 accuracy rating

**Realism check:** invites *start* in 2–3 weeks. 100 *onboarded* lands late September, because waves and Beta App Review are non-negotiable. If someone promises you 100 users in 2 weeks from a standing start, they're proposing the all-at-once launch the July plan correctly ruled out.

---

## 5. What it costs

| Item | Estimate |
|---|---|
| Apple Developer Program | $99/yr (may already be paid) |
| Supabase Pro + PITR add-on | ~$25/mo + PITR add-on (check current pricing in dashboard; non-negotiable for beta) |
| LLM spend at 100 active users | Roughly $50–150/mo based on your own cost docs (coaching-agent dominates; onboarding burst is the spike — bounded if backfill skips insight-generation on old rows). The billing cap makes the worst case a config value, not a surprise. |
| Legal review | One-off; a few hundred dollars for a template review is money well spent on a health-data app |
| Tester thank-yous | ~$300 (the July plan's highest-leverage spend, scaled: reward the ~20 most-active finishers) |
| Landing/forms | ~$0–40 (existing web app + a form tool) |

Total: comfortably under ~$700 + legal, for the whole beta.

---

## 6. Success metrics (July plan, rescaled to 100)

- **Onboarded:** 100 installs with ≥1 run logged by end of September
- **Activation:** 70% log ≥1 run + 1 voice note in week 1
- **The number that matters:** **40+ testers still logging real runs in their week 3**
- **Coach Read:** 2+ generated per active tester; **60%+ answer yes to "did it notice something true?"**
- **Structured feedback:** 60+ form responses, 10–12 interviews
- Same three comparable tasks for everyone: log 4 runs + 2 voice notes over 2 weeks → generate a Read → rate accurate/useful 1–5 + one right thing/one wrong thing

Funnel queries to run weekly against prod (installs come from App Store Connect; the rest from SQL): distinct users in `training_logs` (7d), users with ≥1 voice memo, `daily_coaching_reads` per user, distinct users active in week-3-since-signup. I can build these as a saved dashboard when you're ready.

---

## 7. What I verified vs. what needs your eyes

**Verified against live prod today:** user counts, applied migrations (RLS fixes ✅, storage privacy ✅, account deletion ❌), deployed edge functions (cut functions gone ✅, delete-account absent ❌), security advisors (13 anon RPCs ⚠️, 2 RLS-off backup tables ⚠️, leaked-password protection off ⚠️), legal doc state (still draft ⚠️), repo branch state.

**Needs your confirmation (I can't see these):** Apple Developer / App Store Connect status, Upstash + Sentry + `ALLOWED_ORIGIN` function secrets in prod, Google Cloud billing cap, PITR toggle, whether the 30-run import is still current behavior in the latest build, and whether `web/.env.local`'s service-role key was ever rotated (July 17 finding #2 — treat as burned if unsure; rotation is minutes).
