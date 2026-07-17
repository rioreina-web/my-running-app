# Improvement Task List
**Date:** 2026-07-01 · Built from the UI audit (`ui-function-audit-2026-07-01.md`) plus the existing roadmap and production-readiness notes. Ordered by impact — work top to bottom. Checkboxes so you can track progress.

## Wave 1 — Make the core loop trustworthy (do first)
A beta lives or dies on whether logging a run feels reliable.

- [ ] **Visible voice-memo failure states.** "Processing failed — tap to retry" directly on the journal card, with different copy for network vs. transcription failures. (Audit H3)
- [ ] **Inline error + Retry on every tab.** No more endless spinners or silently stale data when a fetch fails. (H6)
- [ ] **Offline sync confirmation.** "Syncing 2 pending items… all caught up" toast when connectivity returns, so users know memos weren't lost. (M7)
- [ ] **Journal skeletons + finish pagination** so older history is reachable and loading looks intentional. (M9)

## Wave 2 — One consistent language
Every screen should describe the same run the same way.

- [ ] **Retire "Tempo"/"Threshold" everywhere** — replace with the 10-zone labels (Steady/MP/HMP/LT…) across all 15+ screens and the manual-entry picker. (H1)
- [ ] **Collapse to one workout-detail screen** (Plate 23) and route every entry point to it; archive the other three. (H4)
- [ ] **Design-token pass:** extract the Eyebrow primitive, tokenize spacing, enforce one-coral-per-cluster, kill remaining em-dash placeholders. (M11, L1)

## Wave 3 — Nail the first-run experience
Every new beta invite hits this path before anything else.

- [ ] **HealthKit denial recovery** in onboarding — detect the denial, show "Enable in Settings ↗", explain what's missing. (M5)
- [ ] **Fix onboarding defaults** — visible skip, no silently-created Half Marathon 1:30 goal. (L2)
- [ ] **Wire up `data_depth` gating** so new users see plain factual UI instead of editorial pull-quotes about data they don't have yet. (H2)
- [ ] **No-plan states:** empty-state + CTA in Train analytics; one canonical goal surface, with the goal visible in Plan's empty state. (M1, M2)
- [ ] **Fix the false sign-in failure** and prefetch Trends at launch. (M6, L4)

## Wave 4 — Strengthen what makes the app different
- [ ] **Coach Daily Read polish:** generating state with expected wait, friendly failure/rate-limit messages, browsable archive of past Reads. (H5)
- [ ] **Explain the jargon:** one-line plain-English definitions for ACWR, monotony, strain; label chart axes fully and note the inverted pace axis. (M3, M4)
- [ ] **Race anchoring (roadmap Phase 2):** pace zones and fitness prediction anchored on `confirmed_races` instead of goal time — reality over aspiration.
- [ ] **4-tab IA (roadmap Phase 3):** collapse Plan into Train, ship Log · Trends · Train · Coach. Resolves the Train/Plan redundancy and most hamburger-only features. (M8)

## Wave 5 — Ready for a bigger audience
- [ ] **Accessibility basics:** VoiceOver traits on the custom tab bar and record button, Dynamic Type via scalable fonts, 44pt tap targets, chart accessibility descriptors, contrast check on ink-3/paper. (H7)
- [ ] **Finish eval-harness coverage (roadmap Phase 1)** so AI-prompt changes are tested before shipping.
- [ ] **Production blockers:** add GitHub secrets + branch protection to activate CI, take Supabase out of dev mode, push the pending `athlete_settings` migration, fix the landing page and legal docs.
- [ ] **Cleanup:** archive `FitnessPredictorView_Rebrand.swift`/`ContentView.swift`, replace hardcoded tab tags with a named enum, gate coach surfaces behind verified coach accounts. (L5, L6, M12)

## Ongoing — learn from your beta users
- [ ] **Set up a feedback loop:** TestFlight feedback prompts or a simple in-app "something off?" link, plus basic anonymous analytics (which tabs get used, where people drop out of onboarding). You can't prioritize the next list without this.
- [ ] **Re-run this audit** after Waves 1–3 land to catch regressions.

**Rule of thumb for sequencing:** anything that makes an existing user distrust the app (Wave 1) beats anything that impresses a new user (Wave 4).
