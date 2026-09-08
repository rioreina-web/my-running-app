# Recovery Score → 9/10 — plan and status

**Date:** 2026-08-05 · Follows from `outputs/trends-analytics-audit-2026-08-05.md` §2.3 (Recovery Score rated 5/10) and `outputs/recovery-score-status-2026-08-04.md`.

The 5/10 rating had one cause and one shape: the *transparency pattern* (base 50, factor receipt, arithmetic line) is the best idea in the product's analytics, but the arithmetic behind it was wrong (unreachable Clear band, today-only mood, subtract-only consistency), the copy overclaimed, and the chart scale disagreed with the clamp. Getting to 9/10 is three stages: fix what's broken (done today), add the missing signal (sleep + overnight — the code is already written), then make it accurate to *you* (calibration + the learning loop).

---

## Stage 1 — APPLIED TODAY (by this session, directly in your repo)

These edits are on disk now. **You need to build in Xcode (⌘B) and run the tests (⌘U) to verify** — I can't compile iOS from here. All four files are in synced folders, so no Xcode project surgery was needed.

1. **Wired `TrendsRecoveryFactors` into the live ledger** (`Trends/TrendsSignalModels.swift`).
   `TrendsRecoveryLedger.ledger(days:at:)` now delegates to `TrendsRecoveryFactors.all(days:at:)` — the corrected factor set that was sitting unwired. What this changes on screen:
   - **Clear is now reachable.** Factor maxima now sum to 78 against Clear ≥ 75 (was 69 — unreachable). Well-rested weeks with good mood logs can now actually reach the top band.
   - **Mood reads the trailing 7 days**, recency-weighted (today ≈ 3× a week ago), and says how many days it rests on ("ENERGIZED · TIRED · 4 DAYS IN 7") — it no longer goes silent on unlogged days or lurches when a single log lands.
   - **"Days on" → "Clear days."** Consistency is no longer a standing penalty: a clear day in the last 3 days credits +5, and only a genuinely long unbroken stretch (14+ days) subtracts.
   - Removed the now-duplicate `moodPoints` table and stale `dayGap` helper from the ledger — one factor table, one home (the duplicated-logic disease from the audit).
2. **Fixed the overclaiming footer** (`Trends/TrendsSignalSections.swift`): "four of five inputs are your own words" → "mood and body mentions are your own words, the rest is your runs." Also fixed the matching doc-comment claim in the ledger.
3. **Made the daily delta respect the noise rule** (same file): moves smaller than `TrendsRead.noiseThreshold` (3 points) now read "LEVEL VS YESTERDAY" instead of "+2 VS YESTERDAY" — the score no longer contradicts the Read's own "moves under 3 points are noise."
4. **Fixed the lane's y-scale** (`Trends/TrendsSignalLanes.swift`): the recovery lane now maps 8–96 (matching the score's actual clamp, was 10–96, which plotted floor scores below the lane) and the bottom band ground starts at 8.
5. **Updated one stale test** (`RunningLogTests/TrendsSignalTests.swift`): the unlogged-mood test now expects the 7-day window's honest evidence line ("nothing logged in 7 days"). The retool's own guard tests (`TrendsRecoveryFactorsTests.swift`) already existed and pass against the new arithmetic — including the band-reachability test.

**Verification checklist for you (5 minutes in Xcode):**
- ⌘B builds clean.
- ⌘U — watch `TrendsRecoveryFactorsTests` and `TrendsSignalTests` in particular.
- Run the app → Trends → Recovery Score: the factor rows should now read "Clear days" instead of "Days on," and the mood row should cite days-in-7.

Expect your own score to shift by a few points versus yesterday's build — that's the corrected arithmetic, not a data change. The receipt shows exactly why.

## Stage 1b — small follow-ups for your coding agent (not done today, low risk)

- **Memoize the ledger series.** `TrendsV2View.bucketSet` recomputes the full-history ledger at least 3× per render (audit §2.5). Cache keyed on `(window, days.count)`. Perf, not correctness.
- **Cache invalidation** in `TrendsService` (new run → refresh) so the score updates without an app restart. This is audit roadmap item #3 and it matters double now that the score is right.
- Optional polish: the "+N over window" lane-header delta and The Read still use raw first-vs-last / half-vs-half buckets — the partial-week fix from the audit (item #2) also improves the recovery lane's window delta.

---

## Stage 2 — Sleep + Overnight factors (the missing signal) — ~everything is already written

This is what moves the score from "honest about words and runs" to a real recovery score. Follow `SLEEP-HRV-APPLY-NOTES.md` steps 1→5 in order; every code block exists there already. Sequence, with what each unlocks:

1. **Push the two migrations** (`20260804090000_daily_biometrics`, `20260804090100_daily_checkins`) plus the still-unapplied stress-load migration (`20260731120000`). Per hard rule #9: `supabase db push` from a committed SHA, no dashboard SQL.
2. **Paste the webhook sleep branch** into `vital-webhook/index.ts` and redeploy; flip on the sleep data type in Junction. Then **stop for a day** and confirm rows land in `daily_biometrics` (the apply notes flag two field names to verify against the live payload).
3. **Ship the one-tap sleep check-in** (Rough / OK / Good) on the Log tab next to mood capture. Your own evidence review calls self-reported sleep the strongest single signal — one tap, no hardware dependency.
4. **Add the four optional fields to `TrendsDay`** and the two ledger factors (**Sleep**, **Overnight** = HRV paired with resting HR, 5-night minimum, only the HRV-down/RHR-up cell subtracts). The receipt line grows automatically — no UI work.
5. **Re-check band reachability after adding factors.** The new factors widen the range by roughly −9…+7; update `TrendsRecoveryFactors.theoreticalRange` and its test so the reachability guard covers seven factors, not five. (The apply notes' test list §6 covers the rest.)

One open call flagged in the apply notes worth deciding before other beta users see it: the Overnight factor is confounded for roughly half of every cycle for female athletes — either gate it behind cycle capture or keep its weight gentle (−4) until then.

## Stage 3 — Accuracy and trust (the 8→9 gap)

A 9/10 score is one you've *checked against reality*, not just designed well. In order of value:

1. **Backtest on your own history before beta users see it.** One script (or a DEBUG-only chart): compute the ledger for every day of your 278 stored runs, and look at (a) the score's distribution — all four bands should actually occur at sane frequencies; if Clear shows up 40% of the time or 0.4%, retune the band edges, and (b) score-vs-next-day: does a low score predict anything (worse felt-RPE, lower pace-at-HR, a skipped session)? You already collect felt-vs-planned RPE on every run — that's the ground truth column, and it's live today.
2. **The felt-RPE feedback loop** (the "accuracy engine" from the status doc, still unspecced): when the score says Worn and the run felt easy — or Clear and it felt terrible — that disagreement is the most valuable data point the product collects. Start by just *counting* those disagreements in a DEBUG view; per-athlete weight learning comes after there's a few weeks of data.
3. **A confidence line on the receipt.** The Daily Read design already specs this. Cheap version: the receipt footer states how many of the factors had real evidence today ("5 of 7 factors had data"). It's the same honesty pattern, applied to the score itself — and it's what your analytics menu says every metric needs.
4. **Then** decide ledger-vs-Daily-Read (status doc step 5). Recommendation implicit in today's work: keep evolving the ledger — it already ships, shows its receipt, and now has correct arithmetic; the Daily Read design's convergence gate and baseline logic can be folded in as factor upgrades rather than a rewrite.

## What NOT to do (guardrails from your own docs)

- No ACWR revival in the score — `recovery-trend-v2` §7.1 dismantled it; the Load factor's own-baseline design is the replacement.
- No sleep stages / sleep scores / efficiency — self-report quality first, total-time as a weak fallback (v2 §7.4).
- No prescriptions on the receipt — factors count and state; "keep today easy" stays banned.
- Don't resurrect the legacy readiness /100 tile or the convergence card as parallel surfaces — one recovery philosophy, one number, one receipt. Delete those files in the dead-code sweep instead.

## Scorecard: where each stage lands

| After | Score | Why |
|---|---|---|
| Stage 1 (today) | **7/10** | Arithmetic correct, bands reachable, copy honest, scale true. Still words + runs only. |
| Stage 2 | **8/10** | Sleep + overnight biometrics on the receipt, degrading honestly when absent. |
| Stage 3 | **9/10** | Distribution-checked, RPE-validated, confidence-labelled, and learning you. |

The last point (9→10) is intentionally out of reach: it belongs to months of real athlete data, not to design.
