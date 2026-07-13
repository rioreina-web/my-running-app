# UI Function Audit — iOS Athlete App
**Date:** 2026-07-01 · **Scope:** RunningLog iOS app (all 5 tabs, sheets, onboarding, sign-in) · **Method:** full code review of the SwiftUI surfaces, checked against the product rules in CLAUDE.md. High-severity claims spot-verified against source.

This report lists every user-function concern found, ordered by severity. Each entry says what the user experiences, where it lives in code, and the suggested fix.

---

## High severity — fix before wider beta

### H1. Legacy "Tempo" and "Threshold" labels are everywhere
The product decision was that workout labels ARE pace-zone labels, and "Tempo"/"Threshold" are dropped as ambiguous. But the old labels still appear across at least 15 files a user actually sees: `App/InsightsView.swift:129-130`, `App/TodayHomeView.swift:535`, `App/LogView.swift:172`, `Workouts/ManualWorkoutView.swift:82` (users can still *pick* "Tempo" when logging manually), `Workouts/HistoryDetailSections.swift:493`, `Analysis/FitnessPredictorView.swift:523`, `Analysis/TrainingAnalysisView.swift:530`, `App/CoachIntent.swift:63-64`, and more. Users see two competing vocabularies for the same run depending on which screen they're on. **Fix:** one systematic pass mapping tempo→Steady/MP and threshold→LT across every display layer and picker, including the manual-entry workout-type list.

### H2. `data_depth` gating exists but is never used
`Shared/AthleteState.swift:14-39` defines `AthleteDataDepth` with `allowsEditorialVoice` (depth ≥ 2), but no view reads it. A brand-new user with one run sees the same full editorial voice, pull-quotes, and trend narratives as a veteran with months of data — exactly what the depth-0/1 rules were written to prevent. Editorial claims without data behind them read as fake to a new user. **Fix:** thread `AthleteDataDepth` into Trends, Train, and Today surfaces and suppress editorial prose below depth 2.

### H3. Voice memo failure states are hard to see and recover from
The plumbing is decent — failed uploads queue for retry (`VoiceLogViewModel.swift:195`), stale records auto-retry (`:610`), and there's a manual `retryProcessing` (`:396`). The problem is the surface: failure status is a small `statusMessage` string, generic messages like "Retry failed. Try again later." (`:406`) give no cause or path forward, and the manual retry affordance is buried in the journal entry rather than shown prominently where the failed memo sits. Voice logging is the front door of the app; a user whose memo fails should see exactly what happened and one obvious retry button on the entry itself. **Fix:** a visible "processing failed — tap to retry" state on the journal card, with distinct copy for network vs. transcription failures.

### H4. Four different workout-detail screens
Depending on where a user taps a workout, they can land on `HistoryDetailSheet` (from Log and History), `WorkoutDetailView` (from the generator), `VitalWorkoutDetailView`, or `WorkoutDetailPlate23`. Same object, different layouts, different available actions. Users learn where a feature lives on one detail screen and can't find it on another. **Fix:** pick one canonical detail surface (Plate 23 is the design-system one) and route every entry point to it; delete or archive the rest.

### H5. The Coach "Daily Read" gives no feedback while generating and no history
Generation is on-demand and takes real seconds, but the user gets minimal latency feedback, no clear message when generation fails or when the rate limit is hit, and past Reads aren't browsable — each one is effectively ephemeral. For a feature that is the "synthesis" pillar of the app, an invisible spinner and a lost history undercut it. **Fix:** explicit generating state with expected wait, a friendly rate-limit/failure message, and a scrollable archive of past Reads.

### H6. Tab-level fetch failures fail silently
The only global error surface is the top `ErrorBanner` (`RunningLogApp.swift:135-147`), and it only fires if a view model explicitly calls `ErrorReporter.report()`. Several tab fetches log the error and stop — the user sees an endless spinner or silently stale data with no retry. **Fix:** every tab view model reports fetch errors and renders an inline error state with a Retry button.

### H7. Accessibility is broadly under-covered
Very few `accessibilityLabel`/`accessibilityHint` uses across 220 files. Specific gaps: the custom tab bar (`App/DripTabBar.swift`) doesn't expose proper tab traits to VoiceOver; charts (fitness curve, volume, ACWR) have no accessibility representation at all; custom fonts are used at fixed sizes so Dynamic Type doesn't scale text; several tap targets are under 44pt; and some ink-3-on-paper token pairs are likely below contrast minimums. Any user relying on VoiceOver or larger text sizes cannot use core surfaces. **Fix:** start with the tab bar traits, the record button, and Dynamic Type via `@ScaledMetric`/relative font sizing; then chart `accessibilityChartDescriptor`s.

---

## Medium severity

### M1. Goal editing has three competing entry points
Goals can be edited from the Train tab's collapsed "Goals & Targets" section, from the Plan tab, and from the sidebar's "Goals" destination. With no plan active, a goal set in Train doesn't visibly connect to anything in Plan ("PICK A STARTING POINT" still shows), so the goal appears to vanish. **Fix:** one canonical goal surface; when `activePlan == nil` but a goal exists, show it in Plan's empty state ("Your goal: 3:16 · Change").

### M2. Train's analytics show an all-zero grid when there's no plan
`Training/Analytics/TrainingTabView.swift:67-82` renders the full header, stats, and scope toggles with zeros/empties instead of the empty-state component with a CTA. `activePlan == nil` is supposed to be first-class. **Fix:** guard with `EmptyStateView` + "Create plan" CTA.

### M3. Training-load jargon is unexplained
ACWR appears as "Load balance · acute : chronic" with a 0.8–1.3 band (`Trends/TrendsDetailViews.swift:141`) and monotony/strain show as raw numbers ("Monotony 0.92 · strain 67", `Coaching/ModelOfYou/ModelOfYouView.swift:155`). A lay runner has no idea what these mean, and the safe zone is communicated by color only. **Fix:** one italic definitional line per metric ("this week's load vs. your 4-week average") and a text label on the safe band.

### M4. Chart axes are half-labeled
Volume chart labels only the top of the y-axis; the pace progression chart inverts the y-axis (faster = higher) with no legend saying so. Users can misread their own trend. **Fix:** label both axis ends and add a one-line footnote on the inverted pace axis.

### M5. HealthKit permission denial has no recovery path in onboarding
If the user denies the Health permission dialog, the onboarding button still reads "ALLOW ↗" (`OnboardingView.swift:163-181`) with no state change and no Settings deep-link. Since the app is built on HealthKit auto-population, a denied user lands in an app that looks broken. **Fix:** detect denial, flip the button to "Enable in Settings ↗", and explain what they'll be missing.

### M6. Sign-in shows a false failure
A 2–3s timeout after successful auth can show "Sign-in completed but the app didn't switch over. Try again." (`SignInView.swift:161-183`) even though sign-in worked; retapping then errors differently. **Fix:** lengthen the window and replace the error with a "finalizing…" state that keeps checking in the background.

### M7. Offline sync is invisible
The offline queue works, but after reconnecting there's no "syncing N pending items… all caught up" confirmation. A user who logged a memo offline reasonably assumes it was lost. **Fix:** a small sync toast when the queue drains.

### M8. Seven features are hidden behind the hamburger only
Goals, Pace Chart, Fitness Predictor, Training Analysis, Injuries, Content Library, Settings are reachable solely via the sidebar (`ContentLibrarySidebar.swift:30-48`). Miss the hamburger and these features don't exist. Some (Fitness Predictor, Injuries/Niggles) are roadmapped to fold into Trends anyway. **Fix:** short term, make the hamburger more prominent and cross-link from related tabs (e.g., Niggles tile on Trends → Injuries); long term, fold them per the roadmap.

### M9. Journal loading and pagination polish
The Log journal shows "Loading…" text rather than skeleton rows, and infinite scroll for entries older than 6 months isn't fully implemented — older history is effectively unreachable. **Fix:** skeleton placeholder rows and finish the pagination.

### M10. Duplicate workouts (HealthKit vs. manual) are invisible
`LogDedup` logic exists, but users can't see or resolve a duplicate when dedup misses. **Fix:** a "possible duplicate" badge with a merge/dismiss action.

### M11. Coral accent overuse and design drift reduce scannability
The design rule is one coral element per visual cluster; several screens use it on multiple competing elements, and widespread hardcoded `.font(.system(...))`/spacing values make identical elements render differently across tabs (documented in `outputs/design-parity-audit-2026-05-20.md`). This is a usability issue, not just polish: inconsistent components make the app harder to learn. **Fix:** the token/primitive extraction already planned (Eyebrow view, tokenized spacing), plus a coral pass.

### M12. Half-built coach-dyad surfaces are reachable
Some coach-side UI remains reachable to normal athlete users even though the dyad work is deprioritized — dead-end screens confuse beta users. (Note: the coach-mode toggle itself is fine — it exists in `Shared/SettingsView.swift:680`.) **Fix:** gate coach surfaces behind a verified coach account, not just the Settings toggle.

---

## Low severity

**L1. Em-dash placeholders linger** in inline data holes (`WorkoutDetailView.swift:479`, `TodayPlate18.swift:837`, injury stat strip in `InjuryPlate28.swift:156-167`) against hard rule #8. Replace with "No data yet" or the empty-state component.

**L2. Onboarding skip is easy to miss** — top-right text link (`OnboardingView.swift:95-104`); the goal step defaults to Half Marathon / 1:30, silently creating a goal the user didn't choose. Add a footer-level skip and a "No goal yet" default.

**L3. Disabled tabs at 32% opacity with no explanation** (`DripTabBar.swift:171-173`) — add an accessibility hint saying why.

**L4. Trends loads only on first visit** — first tap shows a spinner while other tabs prefetch at launch (`TrendsTabView.swift:74-82`). Add Trends to launch prefetch.

**L5. Dead/duplicate files invite regressions** — `FitnessPredictorView.swift` vs `FitnessPredictorView_Rebrand.swift` (only one is routed), unused `ContentView.swift`. Archive the inactive ones.

**L6. Tab tags are non-contiguous** (0,1,4,2,3) with hardcoded cross-tab jumps — no user impact today but a routing bug waiting to happen. Replace with a named enum.

---

## What's already good (keep it)

Predictions correctly ship as range + confidence, rounded to minutes — hard rule #7 is honored. Niggle surfaces quote verbatim, never diagnose, and carry the "not medical advice" disclaimer. The tab architecture preserves scroll/state across switches, launch tasks run in parallel, empty states in Plan and Trends use the proper editorial component with CTAs, the offline queue protects voice memos from loss, and per-tab navigation stacks are cleanly isolated.

## Suggested order of attack

1. **H3 + H6** (visible failures and retries) — trust in the core loop is everything in a beta.
2. **H1** (kill Tempo/Threshold) — one vocabulary before more users learn the wrong one.
3. **H4** (one workout detail screen) — biggest day-to-day consistency win.
4. **H5** (Coach Read feedback + history) — protects your differentiating feature.
5. **H2 + M1/M2** (data_depth gating, goal/plan empty states) — the new-user experience, which every beta invite hits first.
6. **H7** (accessibility basics) — tab bar traits and Dynamic Type first.

Corrections vs. raw review notes: the coach-mode toggle *does* exist in Settings (SettingsView.swift:680), and voice-memo uploads are *not* silently lost (offline queue + auto-retry exist) — the concern is visibility of the failure state, not data loss.
