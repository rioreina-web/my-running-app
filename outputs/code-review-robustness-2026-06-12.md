# Code review — robustness audit (2026-06-12)

Scope: full-repo review focused on "where does this break easily." Three parallel passes — backend (`supabase/`), iOS (`RunningLog/`), web + cross-language pace contract. The four most severe findings were independently re-verified by reading the code directly.

**Verdict: Request Changes.** The architecture is sound (auth helper, outbox pattern, service-key boundary are all genuinely good), but there are 2 confirmed security holes, 2 confirmed data-loss/corruption paths, and a cluster of silent-failure patterns that make breakage invisible when it happens.

---

## Critical (fix first)

### 1. IDOR: any authenticated user can write onto another user's training log ✅ verified
`supabase/functions/process-training-memo/index.ts:151-168`
Auth verifies the JWT matches `record.user_id` *as supplied in the request body* — but never verifies that the `training_logs` row `record.id` actually belongs to that user. Every subsequent read/write uses the service-role client keyed on `record.id` alone. An attacker can POST a victim's log ID with their own `user_id` and overwrite the victim's `cleaned_notes`, `mood`, `workout_type` — and the injury upsert (~line 576) reads `user_id` back from the DB, planting injuries on the victim's profile.
**Fix:** after auth, fetch the row once and require `row.user_id === authUserId` (404 otherwise), or add `.eq("user_id", authUserId)` to every operation on `record.id`. Bonus: this single up-front fetch also removes the 4× redundant `.single()` reads of the same row (lines 66, 199, 576, 632).

### 2. Impersonation: `coaching-agent` trusts a body-supplied userId ✅ verified
`supabase/functions/coaching-agent/index.ts:530-540`
When the JWT carries no user claim (i.e. the public **anon key**), the function falls back to `payloadUserId` from the body. Anyone holding the anon key can invoke the coach agent as any user — reading their athlete state, writing their conversations. This is the exact anti-pattern `_shared/auth.ts:requireAuthOrServiceRole` was built to kill.
**Fix:** replace the fallback with `requireAuthOrServiceRole(req, payloadUserId, corsHeaders)`. The iOS app must send the user's session JWT (it already has one), not anon key + body userId.

### 3. Voice memo data loss: the offline queue is dead code ✅ structure verified
`RunningLog/RunningLog/Services/OfflineQueue.swift` (whole file), `Workouts/VoiceLogView.swift:660-682`, `VoiceLogViewModel.swift:117-122`
`enqueueVoiceLog`/`enqueueManualWorkout`/`enqueueTrainingLog` have **zero call sites** — only `drainQueue` is wired. When upload fails (offline, 5xx), the catch sets a status message but `confirmAndUpload` clears `recordingURL` unconditionally, orphaning the m4a with no retry path. For a voice-first product this is loss of the core artifact. And even if enqueueing were wired, the drain path POSTs the wrong body shape (flat fields instead of the DB-trigger `{record:{id, audio_url}}` shape) and never inserts the `training_logs` row first — it cannot work as written.
**Fix:** on failure, keep the file + call `enqueueVoiceLog`; extract the insert-then-process sequence into one function shared by the live and drain paths.

### 4. Destructive delete by time window only ✅ verified
`RunningLog/RunningLog/Services/WorkoutSyncService.swift:170-188` (`removeAutoSyncEntry`)
Deletes every `auto_sync` row within ±5 minutes of the voice log's workout. The `distance` parameter is accepted and **never used**, and there's no `.eq("user_id", …)` (RLS is the only guard). A doubles day or a watch+phone pair within 5 minutes deletes the wrong workout — silently corrupting training history, ACWR, and volume.
**Fix:** add the user filter and match on distance (fetch candidates, delete by id where `abs(dist − distance) < 0.2`).

---

## High

### Backend
5. **`reschedule-plan` ships none of its mandated safety constraints** (`reschedule-plan/index.ts:90-112, 177-198`). LLM output is JSON.parsed (with a regex "repair") and returned verbatim — no validation against `WORKOUT_CODES_BY_DAY`, no date sanity, no RACE-day protection, nothing written to `plan_adjustments`, rate limit is 10/day not 1/day. Also returns raw `String(error)` in 500 bodies. The decision log (`outputs/plan-mutations-and-race-design.md`) lists these as launch requirements.
6. **`priorBlockAvg` divides 3 weeks of miles by 4** ✅ verified (`_shared/athlete-state.ts:1112`). `weeklyAvg28d − rolling7d/4` = `(28d−7d)/4`, but the remaining window is 3 weeks → prior average understated ~25%, biasing trajectory framing ("building"/"peaking" overdetected) in every AI prompt. Fix: `(rolling28dMiles − rolling7dMiles) / 3`.
7. **Mood trend is almost always "improving" with exactly 3 entries** (`athlete-state.ts:661-665`). `scores.slice(3)` is empty → older avg = 0 → any recent avg > 0.5 reports improving. Three "tired" check-ins → `mood_trend: "improving"`. Require ≥4 scores, else `null`.
8. **athlete-state writes fail silently** (`athlete-state.ts:284-287, 1363-1369`). The rebuild's final upsert and `rebuild_started_at` clear are unchecked — a persistent schema error (this repo's known failure mode) means every caller silently re-runs the full 13-query rebuild forever.
9. **`.limit(100)`/`.limit(400)` truncate high-volume athletes before dedup** (`athlete-state.ts:353, 428`). Same run appears 2-3× across sources; Supabase drops the oldest rows → ACWR chronic denominator shrinks → inflated ACWR. Raise limits or dedup in SQL; log when `data.length === limit`.
10. **Outbox failure path lacks the CAS guard the success path has** (`drain-coachable-moment-jobs/index.ts:193-220`). Success checks `.eq("last_enqueued_at", job.version)`; the failure/retry updates match on `athlete_user_id` alone — a re-armed job gets clobbered to `failed`, discarding the fresh enqueue.
11. **Suppression check-then-insert kills whole batches** (`evaluate-coachable-moment/index.ts:294-321`). Concurrent invocations both pass the pre-flight SELECT; the batch insert then hits the partial unique index and *all* rules in the batch are rejected. Insert per-row or upsert with `ignoreDuplicates: true`.
12. **LLM-extracted fields written unvalidated to `training_logs`** (`process-training-memo/index.ts:548-562`). `workout_type`, `pace_per_mile`, `distance_miles`, `duration_minutes` get no type/range/vocabulary checks; `training_logs.workout_type` has no CHECK constraint. Hallucinated values poison ACWR fallback weights and dedup downstream.
13. **Pervasive UTC date math against athlete-local dates** (`athlete-state.ts:325, 570-575, 843-851`; `context.ts:113-115`; `evaluate-coachable-moment/index.ts:55-62`; mirrored on web — see #20). `today_workout` is wrong around midnight for non-UTC athletes; "days until race" fires a day early west of UTC; window filters drift on boundary days. Fix once with a shared `localDateFor(user, now)` helper + an athlete timezone column.

### iOS
14. **Continuation leak can hang auto-sync for the session** (`Health/HealthKitManager.swift:475-482`). In the route-query error branch, `continuation.resume` is only called when `done == true` — HealthKit doesn't guarantee that. The awaiting sync task hangs forever and `isSyncing` never resets. Always resume in the error branch.
15. **HealthKit authorization check can't detect denial** (`HealthKitManager.swift:38-69`). Denied read access returns empty results, not an error — denied users are reported `isAuthorized = true` and see a permanently empty app with no banner. Treat read-auth as undeterminable; key UI off "has any data ever arrived."
16. **`AuthManager.userId` returns `""` instead of failing** (`Auth/AuthManager.swift:26-32`). Pre-auth or post-signout calls upload audio to a root-level `"/file.m4a"` storage path, then the row insert fails on RLS. Make it `String?` and force call sites to handle nil.
17. **Stream split math: OOB crash + wrong default** (`Health/VitalManager.swift:152-167, 316`). `velocities?[i]` unguarded against a shorter `velocity_smooth` array (crash); HR slice length never validated; and `velocities?[i] ?? 1.0 >= 1.6` means nil velocity → everything counts as "stopped" → 0:00 pace splits. These paths are live for HealthKit/Strava streams.
18. **No audio-session interruption handling** (`Workouts/VoiceLogView.swift:608-658`; zero `interruptionNotification` observers repo-wide). A phone call mid-memo pauses the recorder while `isRecording` stays true — the user records minutes of nothing. No `AVAudioRecorderDelegate` either, so encode failures are invisible. Session is also activated but never deactivated (user's music stays interrupted).

### Web / contract
19. **The "fixed" legacy seconds-offset ladder is still live as fallback data** (`web/src/components/coach/workout-helpers.ts:196-209`, `REFERENCE_PACE_SEC_PER_MILE`). Race zones are literal MP-offsets (−15/−20/−40/−60/−80/−100s) and aerobic bands use the pre-2026-06 convention — disagreeing with `derivePaceTableFromGoal` by 5–49 s/mi per zone. It's the fallback in `resolvePaceTable`, `basePaceSecPerMile`, and `paceRangeLabel`: a coach without a goal time sees one ladder; setting a goal silently shifts every zone. Fix: derive the constant from `derivePaceTableFromGoal(450, "marathon")` at module load.
20. **`/api/assign-plan` is structurally broken** (`web/src/app/api/assign-plan/route.ts:33-46`). It forwards the service-role key as the Bearer token and puts the coach's identity in a body field the edge function never reads; `getAuthenticatedUser` fails on the service key → 401 every time. Forward the user's session JWT so the coach-relationship check runs against the real caller. Audit `/api/weekly-report` for the same pattern.
21. **`raceKeyForInput` diverges web vs server** (`workout-helpers.ts:408-417` vs `paces.ts:75-89`). Web is case-sensitive, accepts 5 exact strings, and silently defaults everything else to **marathon** — `"half"` or `"10K"` derives a wildly wrong table. Port the server normalizer; return `null` for unknown instead of guessing.

---

## Medium

22. **Band-midpoint convention differs iOS vs web/server** (`PaceModels.swift:502-506` pace-midpoints vs `TRAINING_MP_SPEED_RATIO` speed-midpoints; ~3-4 s/mi divergence). The contract test's 0.005 tolerance was widened specifically to let this pass. Pick one convention, tighten to 0.0001.
23. **`longRun` zone renders differently per platform** — iOS aliases it to easy; web/server keep the legacy 85–75% band (43 s/mi apart at MP 8:00 for stored steps rendered via `safePaceRangeLabel`).
24. **Pace constants re-declared locally** in `pace-chart-client.tsx:43-57` and `pace-reference-editor.tsx:27-44` — third copies of ratios/distances in files that already import from `workout-helpers.ts`. Export and import instead. Also `1.60934` vs the canonical `1.609344` in `plan-builder-client.tsx` and `PaceCalculator.swift:172,180`.
25. **`parseTimeString` treats marathon "3:10" as 190 seconds** (`pace-chart-client.tsx:135-143`) — comment says it mirrors iOS H:MM handling; code never receives the distance. iOS does it correctly.
26. **Contract test gaps** (`cross-language-pace-contract.test.ts`): does NOT pin the race-equivalence ratio table across the three platforms (the most load-bearing constants), `RACE_DISTANCE_MI` parity, `oneHourPaceSecPerMile` output parity, or `raceKeyForInput` normalization. The existing read-Swift-as-text technique extends naturally to all of these.
27. **Web queries coerce errors into empty states** (`pace-chart/page.tsx:32-33`, `plan/page.tsx:128-129`, coach-portal athlete pages). `.error` is never inspected; a Postgres outage renders as "No pace data yet — complete a few runs." Render a distinct error card.
28. **Web/iOS date-key bugs**: `new Date(w.date)` (UTC midnight) vs local-midnight Monday anchors shifts "This Week" buckets (`coach-portal/athletes/[id]/page.tsx:243-246`); `getNextMonday` returns Sunday in UTC+ zones (`plan-assignment-modal.tsx:224-230`); iOS `DateFormatter("yyyy-MM-dd")` lacks `en_US_POSIX` locale (`HealthKitManager.swift:169`, `VitalManager.swift:32`, `FitnessPredictorService.swift:494`) — non-Gregorian device calendars produce year-2569 keys.
29. **process-training-memo concurrency guard is check-then-act** (`index.ts:176-196`) — two near-simultaneous triggers both run Whisper + Gemini. Atomic claim: `UPDATE … WHERE id=? AND status IS DISTINCT FROM 'processing' … RETURNING id`.
30. **`"dev-user"` fallback in prod** (`process-training-memo/index.ts:583`) — failed row read → injuries upserted to literal `"dev-user"`. Skip instead.
31. **`strava-sync` decodes service-role JWTs without signature verification** (`strava-sync/index.ts:407-423`) — safe only if deployed with `verify_jwt = true`; no in-code assertion. Require the literal service key like the other drain workers.
32. **Legacy type labels in load math** (`athlete-state.ts:610, 768`; `weeklyAnalytics.ts:58-82`). `alwaysHardTypes`/`TYPE_FALLBACK_WEIGHTS` key on `tempo`/`intervals`, which the taxonomy drops — as `MP`/`HMP`/`LT`/`5K` labels roll out, hard-session counts and ACWR weights silently decay. Add the 10-zone labels now.
33. **Client-side dedup races + no user filter in `syncUnloggedWorkouts`** (`WorkoutSyncService.swift:24-68`) — two devices double-insert, inflating volume. Server-side unique index on `(user_id, vital_workout_id)` + upsert.
34. **Unstructured polling Tasks never cancelled** (`VoiceLogViewModel.swift:85-116, 418-448`) — up to 20 round-trips per upload continue after backgrounding/signout, and every failed poll iteration fires a user-facing error banner for an operation that already succeeded.
35. **`.single()` where zero rows is normal** — `plan/page.tsx:117` (`activePlan == nil` is first-class per the product framing) and `settings/page.tsx:16-20` (against `user_profiles`, which doesn't exist in prod). Use `.maybeSingle()`.

## Low (selected)

36. Rate limiting: `incr`/`expire` non-atomic; fail-closed + per-isolate circuit breaker turns a Redis blip into a product-wide LLM outage while `getCurrentUsage` reports 0 (`rateLimit.ts:116-170, 249-258`). Unknown feature names silently inherit `coaching` limits (`:231`) — throw instead.
37. `calculateACWR` returns a healthy-looking `1.0` with zero history (`weeklyAnalytics.ts:239-241`) — return `null`; consumers already handle it.
38. Regex JSON "repair" can corrupt valid string contents (`reschedule-plan/index.ts:191`, `parse-training-plan/index.ts:73-77`) — only attempt repair after a parse failure.
39. `UTType` force unwrap crashes the import sheet if the UTI isn't registered (`ImportTrainingPlanSheet.swift:142`).
40. `VitalWorkoutSummary.toRunningWorkout` fabricates `Date()`/random UUIDs on parse failure (`VitalManager.swift:470-494`) — breaks identity stability; make it failable. (Dormant, but it's the template for the Terra integration.)
41. `VoiceLogView` builds a private `HealthKitManager()` instead of `.shared` (`VoiceLogView.swift:13`) — duplicate state, stale auth banner.
42. `randomNonceString` charset typo (missing `W`, `AuthManager.swift:216`) — harmless but hand-rolled crypto-adjacent code; use Apple's reference implementation.
43. Dead/drifting vocab in `coach-portal/athletes/[id]/page.tsx:85-110` — unused `MOOD_META` with a non-canonical mood vocabulary; `TYPE_LABEL` still carries dropped `tempo`/`intervals`.
44. RLS shipped one migration late for `llm_model_pricing` (since remediated) — add a CI lint: fail any migration that `CREATE TABLE`s without `ENABLE ROW LEVEL SECURITY` in the same file.
45. Stale CLAUDE.md: `(app)/coach` is already deleted; the pace-zone section still documents the pre-2026-06 band convention (`MP/0.765`, `MP/0.925`, ±5%) that the code has moved past.

---

## What looks good

- **`_shared/auth.ts`** — dual-mode user/service auth with timing-safe key comparison and mandatory subject naming; 38/38 sampled functions have an auth gate. The two Critical auth findings are functions that *bypassed* this helper, not flaws in it.
- **Service-role key boundary on web is exemplary** — single audited export (`env.server.ts`), an eslint rule banning direct `process.env` reads, and a contract test that greps the tree for violations.
- **The outbox pattern** (claim RPCs with SKIP LOCKED + `last_enqueued_at` CAS) is a thoughtful burst-coalescing design; #10 is a gap in an otherwise correct mechanism.
- **The pace contract core is holding**: the race-equivalence ratio table is byte-identical across all three platforms, and the read-Swift-source-as-text contract test is a genuinely clever cross-language pin — it just needs wider coverage (#26).
- Honest-fallback discipline: `FitnessPredictorService` returns nil rather than fabricating predictions (hard rule #7); `safePaceLabel` guards the `NaN:NaN/mi` legacy case.

## Suggested fix order

1. **Security pair** (#1, #2) — both are small diffs against the existing `requireAuthOrServiceRole` helper. Hours, not days.
2. **Data-destruction pair** (#3, #4) — voice memo retry + scoped delete. Protects the core product artifact.
3. **Silent-failure cluster** (#8, #27, #14, #15) — these don't break the app; they make every *other* breakage invisible.
4. **Math/trend bugs feeding AI prompts** (#6, #7, #9, #37) — one-line fixes; they bias every Coach Read until fixed.
5. **Pace-contract drift** (#19, #21–26) — fold into the Phase 2 race-anchoring work, and extend the contract test first so fixes can't regress.
6. **reschedule-plan** (#5) — either build the mandated validation layer or feature-flag it off until Phase 1 eval coverage lands.

Cross-cutting recommendation: the single most repeated root cause is **date handling** (8+ findings across all three platforms). One shared convention — athlete-local date strings everywhere, one `localDateFor` helper per platform, `en_US_POSIX`/fixed-format parsing, never compare a date-string to a timestamp — would eliminate an entire class of recurring bugs.
