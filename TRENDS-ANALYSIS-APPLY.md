# Trends 04–06 + the Signal Lab · apply notes

*Placed 2026-08-05. Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*

Adds three sections to the **Trends** tab and one new screen, the **Signal Lab**,
reached from the foot of Trends.

**No backend work. No deploy. No migration.** Every number below is computed on
device from payloads `TrendsService` already fetches (`pace_bands`,
`quality_sessions`, `quality_volume`, `days`) plus the `trends-insights` cards,
whose Swift client (`TrendInsightsService`) was already written and until now had
zero call sites.

---

## 1 · What was placed automatically (new files, additive — safe)

### Trends sections

| File | What it is |
|---|---|
| `RunningLog/RunningLog/Trends/TrendsThresholdModels.swift` | Pure. `ThresholdGrade` / `ThresholdPoint` / `ThresholdRead` / `ThresholdBuilder`. Reads `PaceBands` and grades in-band minutes. |
| `RunningLog/RunningLog/Trends/TrendsThresholdView.swift` | `TrendsThresholdView` — Canvas, chrome-free, scrub + tap-to-open. |
| `RunningLog/RunningLog/Trends/TrendsQualitySpectrum.swift` | Pure. `QualityZoneSlice` / `QualitySpectrumRead` / `QualitySpectrumBuilder`. |
| `RunningLog/RunningLog/Trends/TrendsQualitySpectrumView.swift` | `TrendsQualitySpectrumView` — a thin wrapper over the existing `PaceVolumeSpectrumChart`. |
| `RunningLog/RunningLog/Trends/TrendsGrowthModels.swift` | Pure. `GrowthVocabulary` / `GrowthOpportunity` / `GrowthRead` / `GrowthBuilder`. |
| `RunningLog/RunningLog/Trends/TrendsGrowthView.swift` | `TrendsGrowthView` — rows, no chart, real empty state. |

### The Signal Lab

| File | What it is |
|---|---|
| `RunningLog/RunningLog/Analysis/SignalLabModels.swift` | Pure. `SignalLabMath` + the four client-side metric builders. |
| `RunningLog/RunningLog/Analysis/SignalLabPrimitives.swift` | `LabCard` / `LabReadout` / `LabLegendChip` / `LabDraw`. |
| `RunningLog/RunningLog/Analysis/SignalLabCharts.swift` | `LabDriftChart` / `LabEfficiencyChart` / `LabMoodLoadChart` / `LabHeatChart`. |
| `RunningLog/RunningLog/Analysis/SignalLabView.swift` | `SignalLabView` — the sheet. |

### Tests

| File | Cases |
|---|---|
| `RunningLog/RunningLogTests/TrendsThresholdTests.swift` | 15 — the grading rule, totals, time-weighted HR, the trend's exclusions and units. |
| `RunningLog/RunningLogTests/TrendsGrowthTests.swift` | 20 — the vocabulary lint, the gates, each rule firing and staying quiet. |
| `RunningLog/RunningLogTests/SignalLabMetricsTests.swift` | 26 — the maths, card selection, and every "absent, never estimated" refusal. |

**Naming was checked against the whole tree.** `AnalysisView`, `AnalysisModels.swift`,
`DriftPoint` and `EfficiencyPoint` already exist, which is why the Lab's types are
`SignalLab*` / `AerobicDrift*` / `BeatEfficiency*` / `HeatImpact*` rather than the
obvious names. Do not rename them back.

If the Xcode project uses file-system–synchronized groups, all thirteen files are
picked up on next open. Otherwise add the ten app files to the app target and the
three test files to the test target once.

---

## 2 · What you apply by hand — `TrendsV2View.swift` (one tracked file)

Five edits. Line numbers are from the file as of 2026-08-03.

### 2.1 · New state — after `dayWorkouts` (~line 44)

```swift
    /// The Signal Lab sheet. Trends stays the five-second read; the Lab is
    /// where you go to look hard at one thing.
    @State private var showLab = false
```

### 2.2 · New derived reads — after the `bucketSet` computed (~line 71)

```swift
    /// Section 04. `nil` until the pace-bands payload lands; the section
    /// renders its own empty state rather than the tab hiding a number.
    private var thresholdRead: ThresholdRead? {
        service.paceBands.map {
            ThresholdBuilder.build(bands: $0, band: .hm, windowDays: window.days)
        }
    }

    /// Section 05.
    private var spectrumRead: QualitySpectrumRead {
        QualitySpectrumBuilder.build(
            keyVolume: service.keyVolume,
            keySessions: service.keySessions,
            set: bucketSet
        )
    }

    /// Section 06 — reads the two above, so it can only ever say things the
    /// sections above it already showed.
    private var growthRead: GrowthRead {
        GrowthBuilder.build(
            set: bucketSet,
            threshold: thresholdRead,
            spectrum: spectrumRead,
            keySessions: service.keySessions
        )
    }
```

### 2.3 · The three new sections — inside `content`, after section 03 closes (~line 163, immediately before the `} else if service.isLoading {`)

```swift
            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Threshold", number: "04",
                    sub: "Every session with time inside your half-marathon band, heat-neutral. "
                        + "Minutes count as work when the effort clears the floor.") {
                if let read = thresholdRead, !read.isEmpty {
                    TrendsThresholdView(read: read) { logId in
                        guard let iso = dayISO(forLogId: logId) else { return }
                        openDay(iso, focusLogId: logId)
                    }
                } else {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No band work yet",
                        title: "Once a few sessions spend time at half-marathon pace, this draws "
                            + "the trend and grades each one on effort."
                    )
                }
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Where the fast miles went", number: "05",
                    sub: "Time at each work zone, priced at the pace you ran it. Easy miles aren't on this chart yet.") {
                if spectrumRead.isEmpty {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No work volume yet",
                        title: "This fills in once you've run a few sessions at marathon pace or faster."
                    )
                } else {
                    TrendsQualitySpectrumView(read: spectrumRead)
                }
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Where to grow", number: "06",
                    sub: "Ranked by cost — the cheapest move first. Silence here is a real answer.") {
                TrendsGrowthView(read: growthRead)
            }

            EditorialRule().padding(.vertical, 24)

            labDoor
```

### 2.4 · The Lab door + the log-id lookup — next to `openDay` (~line 295)

```swift
    // MARK: The Signal Lab door

    private var labDoor: some View {
        Button { showLab = true } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    DripEyebrow(text: "Signal lab", coral: true)
                    Text("Drift, threshold, efficiency, mood and heat — the long look.")
                        .font(.dripBody(12.5))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text("›")
                    .font(.dripDisplay(20))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// The day a key session sits on, so a tap in the threshold chart can open
    /// it. The threshold chart carries `training_log_id`; `openDay` wants a
    /// date, and the tab already holds the mapping.
    private func dayISO(forLogId logId: String) -> String? {
        service.keySessions.first { $0.id.lowercased() == logId.lowercased() }?.date
    }
```

### 2.5 · Present the sheet — after the existing `.sheet(item: $dayWorkouts)` (~line 89)

```swift
        .sheet(isPresented: $showLab) {
            SignalLabView(service: service) { logId in
                showLab = false
                if let iso = dayISO(forLogId: logId) {
                    openDay(iso, focusLogId: logId)
                }
            }
        }
```

---

## 3 · Verify

1. **Build in Xcode.** I can't compile Swift in the cloud sandbox — please build to
   confirm. Every symbol was cross-checked against the real sources (memberwise
   initialiser argument order included), but a compiler is the only proof.
2. **Run the tests (⌘U)** — 61 new cases across three suites, all green expected.
   ⚠️ See §5: one *pre-existing* test file will fail to compile until it's deleted.
3. **Trends tab.** Sections 01–03 unchanged. 04 Threshold draws the band as shading
   with dots sized by minutes; scrub reads a session, a second tap opens it.
   05 shows the work-zone spectrum. 06 lists moves, or an honest empty state.
4. **Change the window control** and confirm every new section recounts — none of
   them carries a range of its own.
5. **Tap `Signal lab ›`** at the foot. Five sections. Section 01 will show its
   waiting-on-streams state until a `trends-insights` decoupling card has fired;
   that's correct, not a bug.

---

## 4 · The decisions worth arguing with

**The heart-rate floor (160 bpm), not a tighter band edge.** Your 2026-08-02 audit
found four long runs clipping the band's slow edge, worth 49 minutes of credited
threshold that wasn't. Tightening the edge to +7% fixes it on a cool day and breaks
it on a hot one, when real threshold work legitimately slows. The floor survives
both. It currently lives in `ThresholdBuilder.defaultHrFloor` as an absolute number
calibrated on your own data — when per-athlete HR zones ship, it wants to become
zone-relative.

**Unclassed is a third state, not a rounding.** A session with no heart rate on its
in-band miles is neither work nor cruising. Folding it into either would make the
headline minutes drift with sensor coverage rather than with training.

**Section 05 is named "where the fast miles went", not "every mile".** A true
all-miles spectrum needs `training_logs.pace_segments`, which doesn't travel on the
`trends-timeline` wire. If you want the honest version, that's the one backend
change worth making — a `pace_histogram[]` block on the timeline response.

**Section 06 is linted, not just written.** `GrowthVocabulary.banned` mirrors the
`trends-insights` detector lint (`rest`, `ice`, `should`, `must`, `because`,
`caused`, `stop running`), and `TrendsGrowthTests` asserts every string the builder
can emit against it. Add a rule, and the lint covers it automatically.

**The Lab is a sheet, not a tab.** Five daily destinations is the tab bar's job.
If it earns a tab later, the view moves without changing.

---

## 5 · Clean-up this surfaces (not done — your call)

1. **`RunningLogTests/TrendsAggregationTests.swift` cannot compile.** It references
   `TrendsAggregation.monthly(...)`, which doesn't exist anywhere in the tree — it
   went with `UnifiedTrainingChart` in the 2026-07-27 cull. This is pre-existing, but
   it means ⌘U is currently red before any of my changes. Delete the file.
2. **`TRENDS-WEEKLY-MONTHLY-APPLY.md` is stale.** It describes a `TrendsTabView`
   with `segmenter` / `readout` / `granularityToggle` that no longer exists.
3. **`TrendsPaceLadderView` is orphaned** — declared, previewed, never instantiated.
   It's chrome-free and stateless and would drop straight into a Trends section if
   you want a seventh.
4. **`TrendsEfficiencyView` is orphaned too**, and the Lab's section 03 now covers
   the same question with a metric that survives a hot month. Worth deleting.
5. **There is still no `DripCard`.** Four Trends surfaces re-inline the same three
   modifiers; `LabCard` is a fifth, scoped to the Lab on purpose. Promoting one
   shared card to `DesignSystem.swift` is a small, separate, worthwhile diff.
