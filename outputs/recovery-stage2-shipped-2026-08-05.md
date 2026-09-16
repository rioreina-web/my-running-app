# Recovery score Stage 2 — code shipped, your switch-flips remain

**Date:** 2026-08-05 · Companion to `outputs/recovery-score-9-of-10-plan-2026-08-05.md` and `SLEEP-HRV-APPLY-NOTES.md`.

All Stage 2 *code* is now on disk in your repo. What remains is exactly the set of steps only you can do: build/test in Xcode, push migrations, deploy two functions, and flip one Junction toggle. In order:

---

## What was applied today (by the Cowork session)

**Backend (both files type-checked with Deno against the real imports):**

- `supabase/functions/vital-webhook/index.ts` — the sleep branch from the apply notes, inserted above the workout-event guard. `daily.data.sleep.created/updated` events now upsert into `daily_biometrics` (tentative→confirmed restatements collapse onto one row per night).
- `supabase/functions/trends-timeline/index.ts` + `timeline.ts` — each `days[]` entry now carries `hrv_rmssd`, `resting_hr`, `sleep_total_min` (from `daily_biometrics`) and `sleep_quality` (from `daily_checkins`). Additive and failure-safe: if the tables don't exist yet (migration not pushed), the decoration silently skips — deploying before pushing cannot 500 the Trends tab.

**iOS:**

- `Trends/TrendsModels.swift` — `TrendsDay` carries the four new optional fields; nil when absent, never fabricated (same contract as `mood`).
- `Trends/TrendsService.swift` — the day DTO decodes them (older payloads still decode fine).
- `Trends/TrendsRecoveryFactors.swift` — **Factor 6 · Overnight**: HRV read only paired with resting HR, weekly means vs your own 28-day baseline, 0.5×SD threshold, ≥5 valid nights or the row is absent; only HRV-down-with-RHR-up subtracts (−6). **Factor 7 · Sleep**: one-tap quality first (rough −6 / ok 0 / good +4), 7-day total-sleep-time vs your own 3-week average as the weak fallback (±45-min gate). One deliberate improvement over the apply notes: an athlete with **no sleep data at all in 21 days gets no Sleep row** — the receipt never carries a permanent "not enough data" line for a pipeline that was never connected. `theoreticalRange` updated (best 85 / worst clamped 8; all four bands still attainable, asserted by test).
- `RunningLogTests/TrendsRecoveryFactorsTests.swift` — new suites: the 9-cell Overnight table (only one cell may subtract), the 5-night gate, both-low-is-adaptation, sleep quality mapping, quality-beats-duration, the ±45-min TST gate (one 3-hour night doesn't move it), absence behavior, and 7-factor assembly.
- `App/SleepCheckInPrompt.swift` (new) + `App/TodayHomeView.swift` — the one-tap check-in ("LAST NIGHT · How did you sleep? ROUGH / OK / GOOD"), styled to match the mood prompt and placed directly under it. Unlike the mood prompt it writes through to `daily_checkins` (optimistic tap, rollback on failure), because the ledger needs the row server-side.

---

## Your steps, in order (~15 minutes plus one overnight wait)

### 1 · Xcode — verify the Swift (5 min)
Open the project → **⌘B** → **⌘U**. Watch `TrendsRecoveryFactorsTests` (should be all green, including the new Overnight/Sleep suites). Run the app: the sleep check-in should sit under the mood prompt on Today; the Recovery receipt is unchanged (no biometrics data yet — the new rows appear only when data exists).

### 2 · Terminal — commit, then push migrations (hard rule #9)
```bash
cd ~/my-running-app
git checkout -b sleep-hrv
git add -A && git commit -m "Recovery Stage 2: sleep/HRV ingestion + ledger factors + one-tap check-in"
supabase migration list        # review what's pending before pushing
supabase db push
```
Note: `db push` applies **every** pending migration, not just the two sleep tables — per your docs the previously-authored ones (0615 athlete_settings repoints, 0703 plan-builder, 0731 stress-load) are all intended, but eyeball the list first.

### 3 · Terminal — deploy the two functions
```bash
supabase functions deploy vital-webhook --no-verify-jwt
supabase functions deploy trends-timeline
```

### 4 · Junction dashboard — flip on sleep
On the Garmin connection: enable the **sleep** data type, and add `daily.data.sleep.created` + `daily.data.sleep.updated` to the existing webhook endpoint.

### 5 · Wait one night, then verify (per the apply notes)
```bash
supabase functions logs vital-webhook
```
Confirm `sleep_rows: 1` on the first real night and check rows in `daily_biometrics`. Two field names need confirming against the live payload: the restatement field (`s.state` vs `s.status`) and the firmware path (`s.source.firmware_version`) — both flagged inline in the webhook code.

### 6 · What you'll see, when
- **Tonight:** tap the sleep check-in → tomorrow's Recovery receipt grows a **Sleep** line.
- **After ~5 nights of watch data:** nothing yet — the Overnight factor needs ≥5 valid nights *and* 2 weeks of baseline.
- **After ~3 weeks:** the **Overnight** line appears, and the receipt reads all seven factors.

---

## Open call to make before other beta users get the Overnight factor

Cycle-phase confound (recovery-trend-v2 §3a): the Overnight factor is honest for you but systematically confounded ~half of every cycle for female athletes. The options on the table: gate it behind cycle capture, or drop its weight −6 → −4 until then. It's flagged in the factor's doc comment; decide before beta widens.

## Then: Stage 3 (the 8→9 gap)
Backtest the ledger against your 278 stored runs (band distribution + felt-RPE correlation) — see the Stage 3 section of the 9-of-10 plan. That's the next session's work; the data it needs is already flowing.
