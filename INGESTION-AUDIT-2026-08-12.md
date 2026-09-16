# Data Ingestion Audit — Post Run Drip
**Date:** 2026-08-12 · **Scope:** every path by which workout and health data enters the system

---

## The short version

**Overall: 4.5 / 10.**

The *design* is well above average — you have real dedup logic, a signed webhook, source-precedence rules, physiological bounds on biometrics, and a two-stage voice pipeline that never loses an athlete's audio. Someone thought hard about this.

The *wiring* is where it falls down. Two of the three device integrations cannot be connected by a real user at all. There are six different deduplication rules that contradict each other, and the one that runs on the server **deletes rows**. There is one ingestion endpoint that lets any caller read and write another athlete's data. And there is no way for a new user to bring their training history with them.

Almost everything below is fixable in days, not months. But several items are the kind that quietly destroy data while looking healthy, so order matters.

### Scores by path

| Path | Score | One-line verdict |
|---|---|---|
| Manual entry + voice memos | **7/10** | Best-built path. Real validation, graceful failure, never loses audio. |
| Strava | **5/10** | Works mechanically, but polls instead of using webhooks, drops data past 100 activities, and no user can actually connect it. |
| Apple HealthKit | **4/10** | Excellent permission handling; no incremental cursor, no background sync, and a bug that permanently kills sync for most users. |
| Garmin / Vital | **3/10** | Correct webhook crypto sitting behind a config flag that almost certainly 401s every delivery. Nothing calls the connect function. |
| Cross-source dedup | **3/10** | Six competing rules. The server-side one deletes genuine second runs of the day. |
| File import (GPX / FIT / TCX / bulk export) | **0/10** | Does not exist. |
| Reconciliation (plan ↔ actual) | **3/10** | Two rival reconcilers, both reading a table that was deleted. |
| Security posture of ingestion | **3/10** | One cross-tenant read+write hole; a server API key shipped inside the iOS app. |

---

## Fix these first (data loss / security)

### 1. `post-run-reconciliation` lets anyone read and write another athlete's data
`supabase/functions/post-run-reconciliation/index.ts:96-99`

```ts
let userId = await getAuthenticatedUser(req);
if (!userId && bodyUserId) userId = bodyUserId;   // ← trusts the request body
```

The anon key shipped in your iOS binary and web bundle is a valid JWT, so it passes the gateway, returns `null` from `getAuthenticatedUser`, and falls through to whatever `user_id` the caller typed. Then the function fetches the log **by id only, with no `user_id` filter** (`:107-111`), returns the athlete's mood and notes to the caller, and writes to `training_logs` (`:197`), `ai_insights` (`:201`) and `scheduled_workouts` (`:213`) — none scoped to the owner.

**Fix:** swap in `requireAuthOrServiceRole(req, bodyUserId, corsHeaders)` and add `.eq("user_id", userId)` to the fetch and the update. ~20 minutes.

### 2. Your Junction/Vital **server** API key is inside the shipped iOS app
`RunningLog/RunningLog/Health/VitalManager.swift:19-20` · `RunningLog/Info.plist:29-32`

An `sk_us_…` key is read from the app bundle and sent from the device. That key is **team-scoped** — anyone who extracts it from the binary can read every athlete's Garmin summaries and GPS streams. Worse, `VITAL_USER_ID` is also hardcoded, so *every install queries one specific athlete's account* (`VitalManager.swift:35`; same shape on web at `web/src/lib/vital.ts:8,83`).

**Fix:** rotate the key, delete both values from the bundle, and route reads through an edge function that resolves the caller's own Vital id.

### 3. HealthKit sync dies permanently for anyone running under ~3×/week
`RunningLog/RunningLog/Services/WorkoutSyncService.swift:93,156` · `RunningLog/RunningLog/App/RunningLogApp.swift:263`

The app fetches the **last 30 running workouts with no date floor**, but only checks the last **90 days** for existing rows. For a 2×/week runner, the 30th workout is ~105 days old — invisible to the dedup check, so it gets re-inserted with a byte-identical key, hits the unique constraint, and because the insert is **one un-upserted batch**, *all 30 rows fail — including genuinely new runs*. The user sees a generic error banner and their runs stop appearing forever.

**Fix:** `.upsert(..., onConflict: "user_id,external_id", ignoreDuplicates: true)`, and make the fetch window and the dedup window the same number defined once.

### 4. Strava only ever reads the first 100 activities, then moves the bookmark forward
`supabase/functions/strava-sync/index.ts:459-469, 698-702`

No `page` parameter anywhere. The watermark advances to `now()` unconditionally. Fine today; the moment anyone runs the 365-day backfill your own spec calls for, everything past activity #100 is silently gone forever.

### 5. A single failed stream fetch blanks a run permanently
`supabase/functions/strava-sync/index.ts:486, 526-537`

If Strava returns a 500 or a rate-limit 429 on the streams call, the wrapper object is still written — so the next sync's `external_streams == null` check reads false, and that run never gets its heart rate or GPS. One transient blip = one permanently degraded run, logged only as a `console.warn`.

### 6. Strava rate limiting is completely unhandled
Zero references to `429`, `X-RateLimit`, or `Retry-After` in the whole path. Strava allows 200 requests / 15 min and 2,000 / day. Your cron burns roughly **100 calls per user per day before a single run is imported**:

| Users | Idle daily calls | vs. 2,000/day cap |
|---|---|---|
| 20 | ~2,000 | at the cap |
| 100 | ~10,000 | 5× over |
| 1,000 | ~100,000 | 50× over |

You hit the ceiling at about **20 connected users.** Combined with #5, exceeding it also destroys data.

### 7. The Garmin webhook is very likely rejecting every delivery
`supabase/config.toml` has no `[functions.vital-webhook]` block, so CI deploys it with `verify_jwt = true`. Junction sends no Supabase JWT → the gateway 401s **before your (correctly written) signature check ever runs**, with no logs. And the 401 path at `vital-webhook/index.ts:149` logs nothing, so this is indistinguishable from "Garmin sent nothing" — which is exactly what the comment at `HealthBiometricsSync.swift:9-12` describes: *"delivered nothing since 2026-04-03."*

**Fix:** two lines in `config.toml`. Then log the 401.

---

## Structural problems

### Nobody can actually connect Strava or Garmin
- The onboarding "Strava · CONNECT ↗" row is cosmetic — the tap handler is literally `stravaConnected.toggle()` (`OnboardingView.swift:211-217`). The only OAuth exchange that exists is buried in a debug test function.
- `vital-connect` has **zero callers** anywhere in the app or web. `vital_credentials` can only be populated by hand — which means the webhook's "no user mapping → 200, ignored" branch (`vital-webhook:184,218`) silently discards everything.

These are the two features the whole ingestion story rests on.

### Six deduplication rules that disagree, and the destructive one is wrong
| Where | Match key |
|---|---|
| `WorkoutSyncService.swift:77-86` | ±300s AND ±0.2mi, or same local day AND ±0.5mi |
| `LogDedup.swift:40-93` | local day → GPS beats voice → 0.1mi clusters |
| `VoiceLogView.swift:1409` | ±300s AND ±2min |
| `HistoryDetailViewModel.swift:430` | ±4 **hours** AND max(0.5mi, 8%) |
| `strava-sync/index.ts:67-114` | ±15min AND ±0.3mi |
| `dedupe_recent_training_logs()` (cron, every 30 min) | UTC day + distance **rounded to 0.5mi** → **DELETE** |

The server one is the problem:
- `round(miles*2)/2` is a **bucket, not a window**. Two copies 0.02mi apart (5.24 / 5.26) never merge; two *different* runs 0.49mi apart (5.25 / 5.74) land in the same bucket and one gets deleted.
- It groups by **UTC date**. Your own code documents the cost — `SessionRollup.swift:125-135`: *"misplaces 8 rows / 39.2 mi of this athlete's history onto the wrong date."* For a UTC-5 athlete, Tuesday evening and Wednesday morning share a UTC date.
- **Genuine doubles get deleted.** A 5.1mi AM + 5.2mi PM both bucket to 5.0, both are lapless (HealthKit rows structurally cannot have laps), so the second is dropped. `LogDedup.swift:83-88` deliberately *preserves* this exact case. The client and server are in direct opposition, and the server wins because it deletes.

Meanwhile `vital-webhook` has no twin-matching at all, so a Garmin run arriving after a Strava run creates a permanent duplicate the sweep provably cannot clean.

### No way to bring history in
Verified by repo-wide search: **no GPX, no TCX, no FIT import** (`FITExportService.swift` is export-only), no CSV, no Strava bulk-export importer, no web upload of any kind. An athlete arriving with three years of Garmin files has no path. For a journey-centric product this is arguably the single biggest product gap in the list.

### Two rival reconcilers, both reading a deleted table
Both `post-run-reconciliation` and `reconcile-log` fire `AFTER INSERT ON training_logs`. Both query `user_profiles` — the ghost table that was deliberately never recreated. `maybeSingle()` swallows the error, so weather data is always `null` and **the entire heat-adjusted pace comparison is dead code**. `hit_target` in `workout_reconciliations` is permanently null.

Also: `post-run-reconciliation` always matches session 1 of the day (`.order("session").limit(1)`), so on a doubles day the PM quality session is scored against the AM easy run. `reconcile-log` falls back to `candidates[0]` from an unordered ±1-day query — a 3mi recovery jog can be scored against a 20mi long run, miss by >10, and trigger `adapt-plan` to rewrite the athlete's block off a phantom failure.

---

## Accuracy issues worth knowing about

- **Timezone.** Strava captures `utc_offset` and then throws it away (no column stores it), so the client guesses. A travelling athlete's runs slide days.
- **Paused time.** HealthKit's `duration` excludes pauses but the stream time axis is wall-clock elapsed, so charts and summary pace disagree on any run with a stop.
- **Treadmill runs are never flagged.** `HKMetadataKeyIndoorWorkout` is never read, so watch-estimated (often 5-10% off) treadmill distance feeds pace zones, race prediction, and ACWR identically to GPS.
- **Two conflicting distances per row** — summary distance vs. GPS point-sum differ by 1-3% routinely.
- **Non-canonical workout types written** — `WorkoutSyncService` writes `"tempo"` and `"interval"`, both retired from the taxonomy. `WorkoutLabel.swift:98-103` records that this already split production: 14 `interval` + 9 `intervals`, 13 `tempo` + 10 `threshold`.
- **Garmin non-runs become 0-mile runs** — `vital-webhook:225` short-circuits when `sport` is absent, so a strength session lands in ACWR as a 0-mile run.
- **Sleep upserts are destructive** — a `confirmed` restatement missing HRV nulls out the value the `tentative` row carried (`vital-webhook:191-209`).

---

## Privacy & compliance

- **Full-precision GPS with no privacy zone.** Raw start/end coordinates — the athlete's home address — upload with every run. Strava and Garmin both offer privacy zones; you don't.
- **No "Powered by Strava" attribution, no "View on Strava" link, no deauthorize handling, no disconnect UI.** Zero matches repo-wide. These are straightforward Strava API Agreement breaches and revocation is not appealable in practice.
- **Strava data is shown to coaches** (`web/src/lib/coach-dashboard/from-supabase.ts:291`) and flows into third-party LLMs. Both need an explicit position under the current Agreement.
- **Health data first 100 chars logged in plaintext** (`process-training-memo:757`) — routinely "my knee's been hurting since Tuesday."
- **HealthKit purpose string doesn't disclose** that HR, GPS, sleep and HRV are uploaded to a backend and processed by an LLM provider. That's an App Review 5.1.3 risk.
- **No prompt-injection defense anywhere** — zero hits across all 40 prompt files. The sharpest case: prior `cleaned_notes` are concatenated into each new memo's prompt (`process-training-memo:942-948`), so one poisoned memo affects every later one.

---

## What's genuinely good

Worth saying, because it's not nothing:

- **The voice memo pipeline.** Two-stage reveal writes the raw transcript before analysis runs, so a failed LLM call never loses the athlete's words. Retry with exponential backoff, capped. Best-designed path in the codebase.
- **Biometrics source discipline.** Hardcoding `source='healthkit'` server-side so Apple SDNN and Garmin RMSSD can never collide on the `(user_id, date, source)` key, plus `pickBiometricSource` pinning one source per read window — this is a subtle hazard, correctly identified and correctly closed.
- **The Svix signature verification** in `vital-webhook` is a textbook-correct implementation: raw bytes, fail-closed on missing secret, timestamp window, constant-time compare.
- **HealthKit denial modelling.** `HealthReadState` + `probeAnyVisibleData()` correctly handle the fact that HealthKit never reports read denial. Most apps get this wrong.
- **Rate limiting fails closed** in production when Redis is down, with a circuit breaker.
- **Storage buckets are private** with owner-scoped paths derived server-side from the JWT.
- **Manual workout parse never writes** — a failed parse can't lose the athlete's data.

---

## Suggested order of work

**Week 1 — stop the bleeding**
1. `post-run-reconciliation` auth + user scoping (~20 min)
2. `[functions.vital-webhook] verify_jwt = false` in config.toml (~2 min) + log the 401
3. HealthKit batch → upsert with conflict tolerance (~1 hr)
4. Rotate the Vital key, pull it and `VITAL_USER_ID` out of the app bundle
5. Add `.eq("user_id", …)` to the three unscoped dedup lookups

**Week 2 — stop losing data**
6. Strava pagination + 429/`X-RateLimit` handling + don't advance the watermark on failure
7. Fix the "has streams" check so failed fetches retry
8. Rewrite `dedupe_recent_training_logs()`: distance *window* not bucket, start-time proximity not UTC date
9. Port `findDeviceTwin` into `vital-webhook`

**Week 3-4 — make it real**
10. Build the actual Strava OAuth connect flow; delete the fake toggle
11. Wire `vital-connect` to a Settings button, or delete the Vital path entirely
12. Surface sync status to the athlete (`last_sync_error` + a Settings row). Today every failure is invisible.
13. Repoint both reconcilers off the ghost `user_profiles` table
14. Collapse six dedup rules into one shared function

**Then — scale & product**
15. Replace Strava polling with webhooks. This one change fixes the rate-limit ceiling, the 15-minute latency, *and* the edited/deleted-activity compliance gap.
16. HealthKit `HKAnchoredObjectQuery` + background delivery (the entitlement is already granted and unused)
17. Move `external_streams` out of `training_logs` — it's 500KB-2MB per run in your hottest table
18. Build a GPX / Strava-bulk-export importer
19. "Powered by Strava" + deauthorize + a privacy radius on GPS

---

*Full per-path detail available on request — this summary is drawn from four independent audits of the Strava, Vital/Garmin, HealthKit, and manual/voice/document paths, with every claim traced to a file and line number.*
