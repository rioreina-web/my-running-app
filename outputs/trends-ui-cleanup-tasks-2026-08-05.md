# Trends page UI — cleanup task list

**Date:** 2026-08-05 · Follows the UI review in this session and `outputs/trends-analytics-audit-2026-08-05.md`.
Each task is written to be handed to a coding agent as-is (the *Prompt* block), in order. T1–T2 are one session together; T3 is its own session; T4 is a quick one; T5 is the big broom and should go last, on its own branch.

**Before starting any of these:** build (⌘B) and test (⌘U) today's committed changes, and eyeball two things in the simulator — whether the WORDS/RUNS/NIGHTS group eyebrows feel too heavy at 8pt, and whether the five axis labels collide at narrow custom windows. Both are one-line tweaks; fix them in whichever task touches the file first.

---

## T1 · Connect the page (tap-through + haptics) — Small/Medium

The page displays beautifully but responds minimally: The Read's verdict chips look tappable and aren't, the recovery score sits two sections from its own trend line with no link, and the scrub is silent.

**Files:** `Trends/TrendsV2View.swift`, `Trends/TrendsSignalSections.swift` (chips + card), `Trends/TrendsSignalLanes.swift` (scrub haptic).

**Prompt:**
> In the Trends v2 page (`TrendsV2View.swift`), wrap the scroll content in a `ScrollViewReader` and give each section a stable `.id` ("signals", "recovery", "findings"). In `TrendsReadHeader` (`TrendsSignalSections.swift`), make each verdict chip a `Button` that anchor-scrolls (withAnimation) to its section: Miles / Key work / Mood / Niggles → "signals", Recovery → "recovery". Add a pressed state consistent with the design system (no new colors — ink at 0.06 wash is fine) and `accessibilityAddTraits(.isButton)`. In `TrendsRecoveryLedgerView`, make the band gauge row tappable, scrolling to "signals" so the athlete can see the score's trend in the recovery lane; give it an `accessibilityLabel` of "See recovery trend". In `TrendsSignalLanes.swift`, add `.sensoryFeedback(.selection, trigger: scrubIndex)` (iOS 17 API — the project targets it) so scrubbing ticks as it snaps columns. Do not add any new colors, do not change section order, and keep all copy observational — no imperatives. Build with ⌘B and run the TrendsSignal test suites.

**Accept when:** every chip scrolls to its section with a visible press state; tapping the gauge lands on the lanes; scrubbing gives selection haptics on column change; VoiceOver announces chips as buttons.

---

## T2 · Week drill-down (kill the dead end) — Medium

At week grain the lanes offer no tap at all ("rather than offering a dead tap" — honest, but the athlete's next question is *show me that week*). The data is already on device.

**Files:** `Trends/TrendsSignalLanes.swift` (tap handling at week grain), `Trends/TrendsV2View.swift` (sheet), `Trends/TrendsService.swift` (day fetch reuse).

**Prompt:**
> In the Trends v2 page, add a week drill-down: at week grain, tapping a scrubbed column (same interaction that opens a day at day grain — see `TrendsV2View.openDay`) presents a sheet for that ISO week. The sheet lists the seven days (date · miles · session channel · mood word · niggle area if any), built from `TrendsService.days` sliced to the bucket's `startISO`…+6 — no new network call. Each day row with miles > 0 is tappable and opens the existing `HistoryDetailPager` via the same hardest-session ordering `openDay` uses. Style: plate eyebrow "WEEK OF <label>", rows in the log-feed register (see `LogView.swift` rows), `EmptyStateView` if the week is all rest. Never fabricate a mood or pace for a day that has none — render nothing in that slot. Presentation detents `[.medium, .large]`. Build and verify at 3-month and 1-year windows.

**Accept when:** week columns open the sheet; day rows page into the workout detail; rest weeks show the empty state; day-grain behavior is unchanged.

---

## T3 · Accessibility pass (the important one) — Large

The five-lane Canvas is one static VoiceOver label; mood is color-only across adjacent warm hues; the editorial micro-mono (7.5–8pt) ignores Dynamic Type. This is the highest-priority remaining UI work before beta widens.

**Files:** `Trends/TrendsSignalLanes.swift` (bulk), `App/DesignSystem.swift` (type floors), `Trends/TrendsSignalSections.swift`.

**Prompt:**
> Make the Trends v2 page accessible. (1) In `TrendsSignalLanes.swift`, replace the single static `accessibilityLabel` on the Canvas with `accessibilityChildren` that expose one element per visible bucket, labeled like "July 14 — 6.2 miles, key session; recovery 62, Steady; mood positive; niggle: calf, sore" — omit any channel with no data rather than saying "none". Additionally implement `AXChartDescriptorRepresentable` for the lanes (five series over the shared date axis) and attach it with `.accessibilityChartDescriptor` so audio graphs work. (2) Mood must not be color-alone: encode mood rank into the mood strip's mark height (a 5-step ramp, energized tallest) while keeping the colors, and reflect that in the legend. (3) Dynamic Type: introduce `@ScaledMetric`-driven sizes for `dripEyebrow` usages on this page with a floor of 9pt (the 7.5–8pt micro labels scale up but never below their current size), and verify the page at the accessibility XL size — labels may wrap or truncate with `.minimumScaleFactor` but must never overlap. (4) Run a contrast check on `textTertiary` over `background` for the axis labels; if it fails 4.5:1 at small sizes, move axis labels to `textSecondary`. Do not change any arithmetic, any copy, or any color's *hue*. Build, run tests, and verify with VoiceOver in the simulator (Accessibility Inspector audit on the Trends screen).

**Accept when:** VoiceOver walks bucket-by-bucket with real values; the audio graph plays all five series; mood is readable with color filters on (grayscale check); the page survives accessibility-XL type without overlap; Accessibility Inspector shows no critical issues on Trends.

---

## T4 · Explainers collapse (stop re-introducing the page) — Small

Every section carries its explainer paragraph forever ("Every score shows its own arithmetic…"). Charming on visit one, wallpaper by visit ten.

**Files:** `Trends/TrendsV2View.swift` (the `section(eyebrow:number:sub:)` chrome).

**Prompt:**
> In `TrendsV2View.swift`, make the section explainer paragraphs first-run-only: store a visit counter in `@AppStorage("trendsV2Visits")`, incremented once per appearance of the page; show the `sub` text under each section header only while the counter is ≤ 3. After that, collapse to the eyebrow row plus a small "ⓘ" affordance (11pt, `textTertiary`, trailing in the header HStack) that toggles the paragraph back with animation for that render. No third-party dependencies, no persistence of the toggle. The empty-state and error paths are unchanged. Keep the paragraph text itself exactly as written.

**Accept when:** a fresh install shows explainers for the first three visits; a seasoned user sees clean headers with ⓘ recall; toggling works per-section.

---

## T5 · The big broom — dead-code sweep of the Trends folder — Large, own branch

The Trends+Analysis folders are ~16.5k lines and the majority is orphaned prior generations, each carrying comments that contradict the live code (both pace-axis orientations "per the house rule", three recovery philosophies, two severity vocabularies). It's not just weight — it's active misinformation for the next agent that greps the folder.

**Files:** `RunningLog/Trends/*`, `RunningLog/Analysis/*`. **Branch:** `trends-sweep`, separate from feature work.

**Prompt:**
> On a new branch `trends-sweep`, delete the orphaned Trends generations, verifying each file has zero live references first (grep the whole app target, excluding `.perf-worktree` and each file's own `#Preview`). Delete list to verify: `TrendsCalendarView.swift`, `TrendsCalendarLede.swift`, `TrendsEfficiencyView.swift` (header admits demo data), `TrendsRecoveryView.swift`, `TrendsRecoveryDayWeek.swift`, `TrendsQualitySpectrum.swift`, `TrendsQualitySpectrumView.swift`, `TrendsPaceLadderView.swift`, `TrendsZoneDetailView.swift`, `TrendsKeySessionsView.swift`, `TrendsKeySessionsSection.swift`, `TrendsLoadView.swift`, `TrendsBlockModels.swift`, `TrendsMoodBlockView.swift`, `TrendsGrowthView.swift`, `TrendsGrowthModels.swift`, `TrendsSectionHeadline.swift`, `FastSegmentSampleData` (the sample block inside `FastSegmentModels.swift`), `TrendsSampleData` (inside `TrendsModels.swift` — previews that use it move to tiny inline fixtures), and the unreferenced apparatus inside `TrendsDetailViews.swift` (`VolumeChart`, `flagBanner`/`flagRow`, `SectionAChart`, `SectionBView`/`Chart`, `SectionCView`/`Chart`, `InvitationChart`, `DetailHead`, the retired `KeySessionsDetailView` header/chipRow/narrative machinery). DO NOT delete anything referenced by `TrendsLegacyTabView` (DEBUG v1 door), `SignalLabView` + `TrendsThreshold*` (pending a product decision to link it), `PaceSignalView`/`SignalService`, `RacePredictionViews`, `TrendsSessionGrid`, `CompareDashboardCharts`/`CompareMetrics`, or `FastSegmentsDTO`. After deletion: fix any broken previews, run the full test suite, build both Debug and Release configurations, and report the LOC delta. Do not refactor anything you aren't deleting — this branch removes code only.

**Accept when:** Debug and Release both build, all tests pass, the Trends folder drops by several thousand lines, and no deleted symbol appears anywhere in the repo. Merge only after a day of using the app on this branch.

---

## Parking lot (not cleanup — product decisions first)

- **Link Signal Lab from the foot of the Trends page** — one NavigationLink, but decide the 160bpm HR-floor caveat first.
- **Give speed/pace a release-build home** — brings the blue palette (and the "am I faster?" answer) to the page; this is the Phase-content decision, not a UI task.
- **Custom-window presets** ("this block", "since last race") on the window picker.
- **iPad / landscape layouts** — after the accessibility pass, using the same lane architecture.
