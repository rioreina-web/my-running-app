# Trends — Weekly ↔ Monthly overview switch · apply notes

*Placed 2026-07-23. Mirrors the repo's `APPLY-NOTES.md` + additive-new-files convention.*

Adds a **Weekly / Monthly** toggle to the Trends overview chart. Monthly rolls the
loaded timeline up into calendar-month buckets and feeds the **same**
`UnifiedTrainingChart` + readout — no new chart, no backend/deploy change.

## What was placed automatically (new, additive — safe)

- `RunningLog/RunningLog/Trends/TrendsGranularity.swift`
  — `TrendsGranularity` enum (`weekly` / `monthly`) + `TrendsAggregation.monthly(_:)`,
    a pure weekly→monthly rollup (sums volume/quality, fastest key pace, modal mood,
    de-duped niggle union).
- `RunningLog/RunningLogTests/TrendsAggregationTests.swift`
  — 8 `Testing`-framework cases covering the rollup (sums, fastest pace, nil-pace
    month, modal mood + tie-break, niggle union, empty input).

These are new files. **If the Xcode project uses file-system–synchronized groups**
(the tiny `project.pbxproj` suggests it does), they're picked up automatically on
next open. Otherwise, add both to the app / test targets in Xcode once.

## What you apply by hand — `TrendsTabView.swift` (one tracked file)

Six small edits. `window` stays weekly (the This-Week strip + insights are
"this week" and must not change); only the **chart + readout** switch on granularity.

**1) New state — after the `scrubIndex` state (~line 29):**
```swift
    /// Overview granularity — Weekly (shipped default) or Monthly, which rolls
    /// the loaded timeline into month buckets for the chart + readout.
    @State private var granularity: TrendsGranularity = .weekly
```

**2) New `chartData` computed — right after the `window` computed (~line 49):**
```swift
    /// Rows the overview chart + readout render. Weekly = the selected week
    /// window; Monthly = the whole loaded timeline rolled into months (the
    /// range segmenter is week-based, so it's hidden in monthly). Pure
    /// aggregation over the same `[TrendsWeek]`, so no new shapes downstream.
    private var chartData: [TrendsWeek] {
        switch granularity {
        case .weekly:  return window
        case .monthly: return TrendsAggregation.monthly(service.weeks)
        }
    }
```

**3) Point `readoutWeek` at `chartData` (replace the body, ~lines 57–60):**
```swift
    private var readoutWeek: TrendsWeek? {
        if let s = scrubIndex, s >= 0, s < chartData.count { return chartData[s] }
        return chartData.last(where: { $0.miles > 0 }) ?? chartData.last
    }
```

**4) Reset scrub on granularity change — after the `.onChange(of: range)` line (~line 81):**
```swift
        .onChange(of: granularity) { _, _ in scrubIndex = nil }
```

**5) The control + chart call in `loadedContent` (replace the `segmenter …
UnifiedTrainingChart(weeks: window …)` block, ~lines 131–138):**
```swift
            granularityToggle
                .padding(.top, 20)

            if granularity == .weekly {
                segmenter
                    .padding(.top, 8)
            }

            readout
                .padding(.top, 14)

            UnifiedTrainingChart(
                weeks: chartData,
                scrubIndex: $scrubIndex,
                peakUnit: granularity == .monthly ? "mi/mo" : "mpw"
            )
            .padding(.top, 6)
```

**6a) New `granularityToggle` view — next to the `segmenter` definition (~line 461).**
Mirrors the segmenter's styling exactly:
```swift
    // MARK: granularity toggle (Weekly ↔ Monthly)

    private var granularityToggle: some View {
        HStack(spacing: 2) {
            ForEach(TrendsGranularity.allCases) { g in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { granularity = g }
                } label: {
                    Text(g.label.uppercased())
                        .font(.dripEyebrow(10))
                        .tracking(0.8)
                        .foregroundStyle(granularity == g ? Color.drip.textPrimary : Color.drip.textSecondary)
                        .fontWeight(granularity == g ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(granularity == g ? Color.drip.cardBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.drip.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
```

**6b) Readout label + animation key (in the `readout` view, ~lines 491 & 520):**
```swift
        // was: Text("WEEK OF \(week.dateLabel.uppercased())")
        Text("\(granularity == .monthly ? "MONTH OF" : "WEEK OF") \(week.dateLabel.uppercased())")
```
```swift
        // was: .animation(.easeInOut(duration: 0.12), value: week.id)
        .animation(.easeInOut(duration: 0.12), value: week.dateLabel)
```
(The animation-key change avoids a re-fade each render, because monthly rows are
rebuilt with fresh UUIDs; `dateLabel` is stable and unique in both modes.)

## What you apply by hand — `UnifiedTrainingChart.swift` (one tracked file)

Two lines, so the peak tag reads honestly in monthly (not "209 mpw").

**A) New property — after `@Binding var scrubIndex: Int?` (~line 46):**
```swift
    /// Unit on the peak tag (top-right): "mpw" for weekly bars, "mi/mo" for
    /// monthly rollups.
    var peakUnit: String = "mpw"
```

**B) Use it in the peak label (~line 131):**
```swift
        // was: label(ctx, "\(Int(maxMiles)) mpw", at: …)
        label(ctx, "\(Int(maxMiles)) \(peakUnit)", at: CGPoint(x: w - padR, y: volTop - 8), anchor: .trailing)
```

The `peakUnit` default keeps the existing call site and the `#Preview` compiling
unchanged.

## Verify

1. Build in Xcode (I can't compile Swift in the cloud sandbox — please build to confirm).
2. Run `TrendsAggregationTests` (⌘U) — 8 green.
3. Trends tab: **Weekly** = today's behavior (4wk/12wk/6mo range visible). Tap
   **Monthly** → the range control hides, bars roll into ~6 months, pace line = each
   month's fastest key session, scrub reads "MONTH OF MAY", peak tag reads "mi/mo".

## UX decision (easy to change)

Weekly and Monthly **coexist**; the 4wk/12wk/6mo range control shows only in Weekly
(it's week-based), and Monthly always shows the full loaded timeline (~6 months).
If you'd rather Weekly/Monthly *replace* the range control (Weekly = last 12 wk,
Monthly = last 6 mo, one control), that's a small follow-up — say the word.

## Later: move the rollup server-side (optional)

`TrendsAggregation.monthly` is pure and mirrors what `trends-timeline` could return
as a `monthly[]` block (calendar-month buckets in the athlete's tz), so the two
altitudes can never disagree. Client-side is correct for v1 and needs no deploy.
