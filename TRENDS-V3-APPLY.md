# Trends page v3 + the Signal Lab · apply notes

*Placed 2026-08-05. Follows the repo's `APPLY-NOTES.md` additive-new-files convention.*
*Supersedes `TRENDS-ANALYSIS-APPLY.md`, which only covered three of the six sections.*

Builds **`trends-page-v3.html` as the Trends tab** — all six sections, same
order, same rhythm — plus the **Signal Lab**, a screen off the foot of it.

**No backend work. No deploy. No migration.** Every number is computed on device
from payloads `TrendsService` already fetches (`weeks`, `days`,
`quality_sessions`, `quality_volume`, `fast_segments`, `pace_bands`) plus the
`trends-insights` cards, whose Swift client was already written with zero call
sites.

**Two of the six sections are mostly wiring, not new code.** `TrendsSessionGrid`
and `HeadToHeadCard` already existed — chrome-free, stateless, and reachable only
from the legacy tab. Section 04 puts them back on the live surface rather than
drawing a second grid and a second comparison table.

---

## 1 · The six sections, and where each one comes from

| # | Section | View | Data |
|---|---|---|---|
| 01 | Load | `TrendsLoadView` | `days` + `weeks` (quality split) |
| 02 | Pace spectrum | `TrendsQualitySpectrumView` | `quality_volume` + `quality_sessions` |
| 03 | Threshold | `TrendsThresholdView` | `pace_bands` |
| 04 | Key sessions | `TrendsKeySessionsSection` | `quality_sessions` + `fast_segments` |
| 05 | Mood & block | `TrendsMoodBlockView` | `days` + `weeks` (voice quote) |
| 06 | Where to grow | `TrendsGrowthView` | reads 01–05, adds nothing |

---

## 2 · What was placed automatically (new files, additive — safe)

### Trends

| File | What it is |
|---|---|
| `Trends/TrendsBlockModels.swift` | Pure. `BlockWeek` / `LoadRead` / `KeySessionsRead` / `MoodBlockRead` / `TrendsBlockBuilder` — sections 01, 04, 05. |
| `Trends/TrendsLoadView.swift` | Section 01. Volume with quality inside, no-clear-day tint, load-ratio strip. |
| `Trends/TrendsQualitySpectrum.swift` | Pure. `QualityZoneSlice` / `QualitySpectrumRead` / `QualitySpectrumBuilder`. |
| `Trends/TrendsQualitySpectrumView.swift` | Section 02. Wraps the existing `PaceVolumeSpectrumChart`. |
| `Trends/TrendsThresholdModels.swift` | Pure. `ThresholdGrade` / `ThresholdPoint` / `ThresholdRead` / `ThresholdBuilder`. |
| `Trends/TrendsThresholdView.swift` | Section 03. Canvas, band shading, dots sized by minutes. |
| `Trends/TrendsKeySessionsSection.swift` | Section 04. Summary strip + `TrendsSessionGrid` + `HeadToHeadCard`. |
| `Trends/TrendsMoodBlockView.swift` | Section 05. Ribbon, verbatim quote, block stats. |
| `Trends/TrendsGrowthModels.swift` | Pure. `GrowthVocabulary` / `GrowthOpportunity` / `GrowthRead` / `GrowthBuilder`. |
| `Trends/TrendsGrowthView.swift` | Section 06. Rows, no chart, real empty state. |
| `Trends/TrendsSectionHeadline.swift` | The one big number per section header — miles per week leads. `TrendsHeadline` computes each figure from that section's own read. |
| `Trends/TrendsRecoveryFactors.swift` | The recovery ledger's five factors, retooled: `Clear days` replaces `Days on`, mood reads 7 days, top band made reachable. |

### The Signal Lab

| File | What it is |
|---|---|
| `Analysis/SignalLabModels.swift` | Pure. `SignalLabMath` + four client-side metric builders. |
| `Analysis/SignalLabPrimitives.swift` | `LabCard` / `LabReadout` / `LabLegendChip` / `LabDraw`. Sections 01 and 04 of Trends use `LabDraw` too. |
| `Analysis/SignalLabCharts.swift` | `LabDriftChart` / `LabEfficiencyChart` / `LabMoodLoadChart` / `LabHeatChart`. |
| `Analysis/SignalLabView.swift` | `SignalLabView` — the sheet. |

### Tests — 5 files, 103 cases

`RunningLogTests/TrendsBlockTests.swift` (20) · `TrendsThresholdTests.swift` (15) ·
`TrendsGrowthTests.swift` (20) · `SignalLabMetricsTests.swift` (26) ·
`TrendsRecoveryFactorsTests.swift` (22).

**Naming was checked against the whole tree.** `AnalysisView`,
`AnalysisModels.swift`, `DriftPoint` and `EfficiencyPoint` already exist, which is
why the Lab's types are `SignalLab*` / `AerobicDrift*` / `BeatEfficiency*` /
`HeatImpact*`. Do not rename them back.

---

## 3 · What you apply by hand — `TrendsV2View.swift` (one tracked file)

### 3.1 · New state — after `dayWorkouts` (~line 44)

```swift
    /// Zone table for the comparison card's pace colouring.
    @State private var paceZones = PaceZonesService.shared
    /// The Signal Lab sheet. Trends is the read; the Lab is the long look.
    @State private var showLab = false
```

### 3.2 · New derived reads — after the `bucketSet` computed (~line 71)

```swift
    /// Sections 01, 04 and 05 — one build, three readers.
    private var loadRead: LoadRead {
        TrendsBlockBuilder.load(
            set: bucketSet, weeks: service.weeks, keySessions: service.keySessions
        )
    }

    private var keyRead: KeySessionsRead {
        TrendsBlockBuilder.keySessions(set: bucketSet, keySessions: service.keySessions)
    }

    private var moodRead: MoodBlockRead {
        TrendsBlockBuilder.moodBlock(set: bucketSet, weeks: service.weeks)
    }

    /// Week columns for the session grid, matching section 01's bars exactly so
    /// a session sits under its own volume.
    private var gridWeeks: [TrendsWeek] {
        loadRead.weeks.map { w in
            TrendsWeek(
                month: String(w.label.prefix(3)), dateLabel: w.label,
                miles: w.miles, qualityMiles: w.qualityMiles, keyPaceSec: nil,
                mood: "", niggles: [], voiceQuote: nil, weekStart: w.weekStart
            )
        }
    }

    /// Section 02.
    private var spectrumRead: QualitySpectrumRead {
        QualitySpectrumBuilder.build(
            keyVolume: service.keyVolume, keySessions: service.keySessions, set: bucketSet
        )
    }

    /// Section 03. `nil` until the pace-bands payload lands.
    private var thresholdRead: ThresholdRead? {
        service.paceBands.map {
            ThresholdBuilder.build(bands: $0, band: .hm, windowDays: window.days)
        }
    }

    /// Section 06 — reads 01–05, so it can only say things already shown.
    private var growthRead: GrowthRead {
        GrowthBuilder.build(
            set: bucketSet, threshold: thresholdRead,
            spectrum: spectrumRead, keySessions: service.keySessions
        )
    }
```

### 3.2b · Give the section chrome a headline slot — replace `section(...)` (~line 196)

v3 put one big number at the top of every section: the five-second version, read
by glancing down the right-hand edge without touching an axis. The shipped helper
has no slot for it. `headline` is optional, so the two kept sections below can
omit it.

```swift
    @ViewBuilder
    private func section<Content: View>(
        eyebrow: String,
        number: String,
        sub: String,
        headline: (value: String, unit: String, ok: Bool)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: eyebrow)
                Spacer(minLength: 8)
                Text(number)
                    .font(.dripEyebrow(9))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            HStack(alignment: .top, spacing: 16) {
                Text(sub)
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let headline {
                    TrendsSectionHeadline(
                        value: headline.value,
                        unit: headline.unit,
                        isAvailable: headline.ok
                    )
                }
            }
            .padding(.top, 4)
            content()
        }
    }
```

### 3.3 · The page — replace the body of `content`'s `if !set.isEmpty` branch (lines ~126–163)

Keep `TrendsReadHeader` at the top; it is the v3 tab head. Everything after it is
replaced by the six sections.

```swift
        if !set.isEmpty {
            let read = TrendsRead.compute(set)

            TrendsReadHeader(read: read, set: set)
                .padding(.top, 22)

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Load", number: "01",
                    sub: "Volume with the quality riding inside it. Weeks that ran without a clear day are tinted.",
                    headline: TrendsHeadline.load(loadRead)) {
                TrendsLoadView(read: loadRead)
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Pace spectrum", number: "02",
                    sub: "Time at each work zone, priced at the pace you ran it.",
                    headline: TrendsHeadline.spectrum(spectrumRead)) {
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

            section(eyebrow: "Threshold", number: "03",
                    sub: "Every session with time inside your half-marathon band, heat-neutral. "
                        + "Minutes count as work when the effort clears the floor.",
                    headline: TrendsHeadline.threshold(thresholdRead)) {
                if let threshold = thresholdRead, !threshold.isEmpty {
                    TrendsThresholdView(read: threshold) { logId in
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

            section(eyebrow: "Key sessions", number: "04",
                    sub: "One mark per session. Pick any two and the table below redraws in place.",
                    headline: TrendsHeadline.keySessions(keyRead)) {
                TrendsKeySessionsSection(
                    read: keyRead,
                    weeks: gridWeeks,
                    fastSessions: service.fastSegments.sessions,
                    zones: paceZones.zones
                ) { logId in
                    guard let iso = dayISO(forLogId: logId) else { return }
                    openDay(iso, focusLogId: logId)
                }
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Mood & block", number: "05",
                    sub: "One cell per week, coloured by what you logged. A silent week stays grey.",
                    headline: TrendsHeadline.moodBlock(moodRead)) {
                TrendsMoodBlockView(read: moodRead)
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Where to grow", number: "06",
                    sub: "Ranked by cost — the cheapest move first. Silence here is a real answer.",
                    headline: TrendsHeadline.growth(growthRead)) {
                TrendsGrowthView(read: growthRead)
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "Recovery score · \(recoveryDayLabel(set))", number: "07",
                    sub: "Every score shows its own arithmetic. Starts at 50, and each line carries the evidence it moved on.") {
                if let ledger = currentLedger {
                    TrendsRecoveryLedgerView(ledger: ledger, previous: previousScore)
                } else {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No score yet",
                        title: "The score reads your mood logs, your niggles and your last few weeks of running. A few more days and it fills in."
                    )
                }
            }

            EditorialRule().padding(.vertical, 24)

            section(eyebrow: "What lines up", number: "08",
                    sub: "Computed from the window in view. When there isn't enough to say, it says that.") {
                TrendsFindingsView(findings: read.findings).padding(.top, 6)
            }

            EditorialRule().padding(.vertical, 24)

            labDoor
```

**Deleted by this edit:** the `Five signals` section (`TrendsSignalLanes`). Its
mileage lane is now section 01 and its mood lane is section 05, both larger and
scrubbable. `TrendsSignalLanes.swift` is not deleted — nothing else references it,
so it costs nothing to leave in place while you decide.

**07 and 08 are a judgement call.** v3 was six sections; Recovery score and What
lines up are shipped surfaces that v3 never had an opinion about, so they are kept
at the end rather than silently dropped. If you want the pure six, delete those two
blocks — nothing else depends on them.

### 3.4 · The Lab door + the log-id lookup — next to `openDay` (~line 295)

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

    /// The day a key session sits on. The threshold chart and the comparison
    /// card both hand back a `training_log_id`; `openDay` wants a date, and the
    /// tab already holds the mapping.
    private func dayISO(forLogId logId: String) -> String? {
        service.keySessions.first { $0.id.lowercased() == logId.lowercased() }?.date
    }
```

### 3.5 · Present the sheet — after the existing `.sheet(item: $dayWorkouts)` (~line 89)

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

## 3.6 · Retool the recovery score — `TrendsSignalModels.swift` (one tracked file)

Two defects and a latent bug, all in `TrendsRecoveryLedger`:

1. **`Days on` could only ever subtract.** Its four cases were 0 / −1 / −3 / −5 by
   consecutive days running, so training consistently was a standing penalty with
   no upside. Replaced by **`Clear days`**, which measures the same fact from the
   other end — how recently you had a day fully clear — and credits recent
   clearance rather than charging consistency. Six days on after a Sunday off goes
   from **−3 to +2**; three weeks unbroken still reads −5.
2. **Mood read only today.** `days[i].mood` and nothing else, scoring 0 when today
   carried no log — which on your data is most days, so the factor the ledger's own
   header calls the most load-bearing of the five was silent most of the time. It
   now reads the **trailing 7 days**, recency-weighted, and states how many days it
   rests on. It takes the weighted *mean*, so logging more often makes the reading
   more confident without moving it.
3. **The top band was unreachable.** Old factor maxima summed to
   `50 + 10 + 5 + 0 + 4 + 0 = 69`, against a `Clear` band starting at 75. Nobody,
   however fresh, could reach the best band, and the floor was 9 — the whole scale
   lived in 9…69 while presenting as 8…96. The retooled maxima reach **78**, so all
   four bands are attainable. `TrendsRecoveryFactorsTests` asserts this.

The arithmetic all moved into the new `TrendsRecoveryFactors.swift`, so the hand
edit is a deletion. **Replace the whole body of `TrendsRecoveryLedger.ledger(days:at:)`**
— every line from `let day = days[i]` down to the `return` — with:

```swift
    static func ledger(days: [TrendsDay], at i: Int) -> TrendsRecoveryLedger {
        guard days.indices.contains(i) else {
            return TrendsRecoveryLedger(factors: [], total: base, rawSum: base)
        }
        // The five factors live in `TrendsRecoveryFactors`, retooled 2026-08-05.
        // See that file's header for what changed and why.
        let factors = TrendsRecoveryFactors.all(days: days, at: i)
        let raw = base + factors.reduce(0) { $0 + $1.points }
        return TrendsRecoveryLedger(factors: factors, total: min(96, max(8, raw)), rawSum: raw)
    }
```

`base`, `Factor`, `Band`, `arithmetic` and `series(days:)` all stay exactly as they
are — `series` calls `ledger`, so it picks up the retool for free. The old
`moodPoints` table on `TrendsRecoveryLedger` becomes unused; leaving it costs
nothing, and deleting it is safe once nothing else references it.

**One thing to decide.** `Clear days` credits +5 for a clear day in the last three
and 0 for a fortnight without one. If you would rather consistency were *never*
scored at all — neither credit nor cost — delete the two negative cases and the
factor becomes purely a credit. That is a two-line change in
`TrendsRecoveryFactors.clearDays`.

---

## 4 · Verify

1. **Build in Xcode.** I can't compile Swift in the cloud sandbox. Every symbol,
   memberwise-initialiser argument order, design token and lint rule was
   cross-checked against the real sources, but a compiler is the only proof.
2. **Run the tests (⌘U)** — 81 new cases across four suites.
   ⚠️ See §6: one *pre-existing* test file fails to compile until it's deleted.
3. **The headline figures.** Glance down the right edge: miles per week, quality
   share, minutes in band, sessions, logs, moves. A figure the window can't earn
   shows an em dash, never a zero.
4. **Recovery score (section 07).** A consistently-trained week should now read
   `Steady` or better where it used to read `Worn`, and `Clear days` should show a
   positive number for any normal rhythm.
5. **Trends tab, top to bottom.** The read → six sections → Recovery → Findings →
   `Signal lab ›`. Every section recounts when you change the window control;
   none carries a range of its own.
6. **Section 01:** drag across the bars — the readout gives miles, quality, key
   count, clear days and the ratio for that week. Coral-tinted columns are weeks
   with no clear day.
7. **Section 04:** the grid, then two dropdowns. It opens on your two most recent
   sessions; change either and the table redraws in place. Change the window to
   one that excludes a selected session and it reseeds rather than blanking.
8. **Section 05:** tap a ribbon cell for that week's mood and how many days it
   rests on.

---

## 5 · The decisions worth arguing with

**The load ratio is not called ACWR.** `TrendsRecoveryLedger` documents why the app
turned away from it: the two terms share the acute week, so the ratio correlates
with injury from arithmetic alone, and the only randomised trial was null. What
survives is the descriptive question — is this week bigger than the four before it?
Same arithmetic, honest label. The first four weeks of any window carry no ratio at
all rather than dividing by a short baseline.

**A partial week is drawn but never averaged.** A three-day tail week is not a down
week, and averaging it in would say the block was smaller than it was.

**The heart-rate floor (160 bpm), not a tighter band edge.** Your 2026-08-02 audit
found four long runs clipping the band's slow edge — 49 minutes of credited
threshold that wasn't. Tightening the edge fixes it on a cool day and breaks it on
a hot one. The floor survives both. Sessions with no HR are a *third* state,
never folded into either.

**Section 02 is the work spectrum, not every mile.** A true all-miles histogram
needs `training_logs.pace_segments`, which doesn't travel on the timeline wire. If
you want the prototype's version, that's the one backend change worth making — a
`pace_histogram[]` block on the response.

**Section 06 is linted, not just written.** `GrowthVocabulary.banned` mirrors the
`trends-insights` detector lint, and `TrendsGrowthTests` asserts every string the
builder can emit against it.

**Comparison is a tool, not a destination.** Section 04 keeps head-to-head inside
the page. The previous surface made it its own screen, which meant you had to know
you wanted to compare before you could see that two sessions were worth comparing.

---

## 6 · Clean-up this surfaces (not done — your call)

1. **`RunningLogTests/TrendsAggregationTests.swift` cannot compile.** It references
   `TrendsAggregation.monthly(...)`, which went with `UnifiedTrainingChart` in the
   2026-07-27 cull. Pre-existing, but ⌘U is red before any of my changes. Delete it.
2. **`TRENDS-WEEKLY-MONTHLY-APPLY.md` and `TRENDS-ANALYSIS-APPLY.md` are stale.**
   The first describes a `TrendsTabView` that no longer exists; the second is
   superseded by this file.
3. **`TrendsSignalLanes` becomes unreferenced** once 3.3 is applied.
4. **`TrendsPaceLadderView` and `TrendsEfficiencyView` are orphaned** — declared,
   previewed, never instantiated. The Lab's section 03 now answers the efficiency
   question with a metric that survives a hot month.
5. **There is still no `DripCard`.** Four Trends surfaces re-inline the same three
   modifiers; `LabCard` is a fifth, scoped to the Lab on purpose. One shared card in
   `DesignSystem.swift` is a small, separate, worthwhile diff.
