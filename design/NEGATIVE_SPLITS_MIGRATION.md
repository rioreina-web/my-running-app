# Negative Splits — App-Wide Migration Guide

This guide tells you how to apply the *Negative Splits* aesthetic from the mockup plates across the rest of the app, screen by screen, without breaking what's already shipping.

The new components live in `RunningLog/App/NegativeSplits.swift`. They are purely additive — they coexist with `Color.drip` / `Font.drip*` and `StatCard` / `MoodBadge` / `SectionHeader` from `DesignSystem.swift`. Nothing in the existing codebase changes until you choose to swap a screen over.

---

## Mental model

The Negative Splits aesthetic is a tightening of what `editorial-v2` already started. Same warm paper, same coral/amber accent, same Crimson Pro display, same monospaced stats. What changes is **chrome density**:

- Fewer cards, more hairlines
- Numbers grow, labels recede
- Color is information, never decoration
- The accent color appears **once** per composition, not once per element

If a screen feels like it's shouting, it's probably over-chrome'd. The fix is almost always to remove a card background or shrink a label, not to add another visual element.

---

## Component cheat sheet

| Use this NS component | When you'd reach for | Replaces / supersedes |
|---|---|---|
| `NSStatStrip(items:)` | Three labelled stats side by side | Three `StatCard`s in an HStack |
| `NSKPITile(label:value:unit:sub:subColor:)` | A KPI tile with a colored delta line | `StatCard` when you also need a delta |
| `NSEyebrow(text:)` | Section label, tile label, metadata | `Text(...).font(.dripCaption(11)).tracking(1.5)` |
| `NSDisplayNumber(text:size:)` | The big serif numeral on a screen | `Text(...).font(.dripDisplay(48))` |
| `NSSection("EYEBROW") { ... }` | A flat section with eyebrow + content | `SectionHeader("...") + content stacked below` |
| `NSTimelineStep(...)` + `NSTimelineList { ... }` | A vertical phase/step list (warm-up / active / cool-down) | Stacked `WorkoutStepRow`s with shared card background |
| `NSCaretDown()` / `NSArrowUpRight()` | Vector glyphs that survive any font swap | SF Symbols `chevron.down` / `arrow.up.right` |
| `NSAccentToggle($binding)` | The toggle in the heat card | `Toggle(...).tint(Color.drip.coral)` |
| `NSQuietError(message:actionLabel:action:)` | A non-shouting error with a refresh action | A red/orange filled error block |
| `NSCard { ... }` | A subtle container with hairline border (use sparingly) | `RoundedRectangle.fill(Color.drip.cardBackground).shadow(...)` |
| `NSHairline()` | A 1pt rule | `Rectangle().fill(Color.drip.divider).frame(height: 1)` |

---

## Migration order (recommended)

Migrate in this order — earlier screens are higher-traffic and lower-risk.

1. **DayDetailSheet** — `HeatCalculatorCard` first (largest visual delta), then the workout steps timeline. See the worked example below.
2. **WorkoutDetailHeader** (called from DayDetailSheet at line 105) — convert the three-stat row to `NSStatStrip`.
3. **WorkoutDetailView** — same pattern as DayDetailSheet. Heat card is shared.
4. **TrainingDashboardView** — the dashboard's KPI row converts to `NSKPITile`s.
5. **HistoryDetailSheet / WorkoutDetailView** — apply `NSTimelineStep` if the screen surfaces structured workouts.
6. **Trends tab** (when you build it per the PRD) — uses `NSKPITile` directly.

Don't bulk-migrate. One screen per PR keeps each diff reviewable.

---

## Worked example — `HeatCalculatorCard` (DayDetailSheet.swift, lines 1293–1647)

### What's there today (paraphrased — read the file for the full thing)

- A filled card with a coral-tinted background.
- Header row: thermometer SF Symbol, `"HEAT CALCULATOR"` caption, on/off toggle on the right.
- Tappable `"Run at 7 AM (default)"` pill that opens a wheel-picker sheet, plus a `Reset` link.
- Either a three-stat conditions line (temp / dew / humidity) **or** an error state with a `Refresh` button.
- A pace impact table (MP / LT / Easy original → adjusted) when adjustment is meaningful.

### The shape it should take after migration

```swift
NSSection("HEAT · COMPENSATION", accessory: {
    NSAccentToggle($heatAdjustmentEnabled)
}) {
    // Time picker line — serif title + caret
    HStack(alignment: .firstTextBaseline) {
        Button { showPicker = true } label: {
            HStack(spacing: 8) {
                Text("Run at \(formattedRunTime)")
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.ns.ink)
                NSCaretDown()
            }
        }
        .buttonStyle(.plain)
        Spacer()
        Button("Reset", action: resetTime)
            .font(.nsMono(11))
            .foregroundStyle(Color.ns.slate)
    }

    // Body — conditions OR quiet error
    if let forecast {
        // Conditions readout — three small mono columns, hairline separated
        HStack(spacing: 0) {
            condColumn("TEMP", "\(Int(forecast.tempF))°")
            Rectangle().fill(Color.ns.hair).frame(width: 1, height: 32)
            condColumn("DEW",  "\(Int(forecast.dewF))°")
            Rectangle().fill(Color.ns.hair).frame(width: 1, height: 32)
            condColumn("HUM",  "\(Int(forecast.humidity))%")
        }
    } else if hasError {
        NSQuietError(
            message: "forecast service unreachable.",
            actionLabel: "Refresh forecast",
            action: { Task { await onRefresh() } }
        )
    }

    // Pace impact (only when meaningful) — small two-row table
    if isMeaningful, let equiv = equivalentPaces {
        VStack(spacing: 0) {
            NSHairline()
            paceImpactRow("MARATHON",   from: forecast.mp,   to: equiv.mp)
            paceImpactRow("THRESHOLD",  from: forecast.lt,   to: equiv.lt)
            paceImpactRow("EASY",       from: forecast.easy, to: equiv.easy)
        }
        .padding(.top, 8)
    }
}
.padding(.vertical, 16)
```

### What this changes visually

- The orange card chrome disappears. The eyebrow + toggle pair is enough to signal the section.
- The "Run at 6 AM" treatment switches from a coral pill to a serif title with a caret — same affordance, less weight.
- The error state stops shouting. It becomes an italic sentence with a tappable mono link.
- The conditions line becomes three hairline-separated columns instead of comma-joined text.

### What this preserves

- Every callback (`onTimeChange`, `onRefresh`) stays the same — `NSAccentToggle` reads the same `@AppStorage` binding, and the time-picker sheet keeps its existing presentation.
- The `forecast` / `lastForecastFetchError` reactive flow is untouched.
- The `isMeaningful()` gating on the pace-impact table is untouched.

---

## Patterns to apply elsewhere

### Three-stat row (e.g. `WorkoutDetailHeader`)

Before:
```swift
HStack {
    StatCard(value: "\(distance)", label: "miles", icon: "figure.run")
    StatCard(value: durationStr, label: "duration", icon: "clock")
    StatCard(value: "\(stepCount)", label: "steps", icon: "list.number")
}
```

After:
```swift
NSStatStrip(items: [
    .init(label: "DISTANCE", value: "\(distance)", unit: "MILES"),
    .init(label: "DURATION", value: durationStr,   unit: "TBD"),
    .init(label: "STEPS",    value: "\(stepCount)", unit: "PHASES"),
])
```

### Workout step row (replace stacked cards with timeline)

Before — `ForEach(workout.steps) { WorkoutStepRow(...) }` with shared rounded-card background.

After:
```swift
NSTimelineList {
    ForEach(workout.steps) { step in
        NSTimelineStep(
            title: step.kind.displayName,         // "WARM-UP" etc.
            distance: step.distanceLabel,        // "2.0 mi"
            target: step.targetPaceRange,        // "6:26 – 7:38 / mi"
            zoneTag: step.zoneTag,               // "EASY", "MP", "LT"
            zoneColor: step.zoneColor,           // green for easy, amber for MP/LT
            note: step.note ?? "",               // "conversational pace"
            subAnnotation: step.heatAnnotation,  // "your MP 5:32 · −1% today"
            filled: step.kind.isAccent           // true for the active block
        )
    }
}
```

The line that used to be drawn by SF Symbol icons in colored circles is now drawn by `NSTimelineList`'s vertical hairline + `NSTimelineStep`'s node circle. The semantic is identical; the visual is calmer.

### KPI tile row (for the Trends dashboard, when built)

```swift
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
    NSKPITile(label: "VOLUME · 7D", value: athleteState.rolling7dMiles.formatted(),
              unit: "MI", sub: athleteState.volumeDeltaLabel,
              subColor: athleteState.volumeDeltaColor)
    NSKPITile(label: "FITNESS", value: fitnessSnapshot.predictedMarathonTime,
              unit: "FULL", sub: fitnessSnapshot.deltaLabel,
              subColor: fitnessSnapshot.deltaColor)
    NSKPITile(label: "LOAD · ACWR", value: "\(athleteState.acwr.formatted(.number.precision(.fractionLength(2))))",
              sub: athleteState.acwrInterpretation,
              subColor: athleteState.acwrInterpretationColor)
    NSKPITile(label: "INJURY RISK", value: "\(athleteState.injuryRiskScore)",
              unit: "/ 10",
              sub: athleteState.injuryRiskBucket)
}
```

---

## Style rules to internalize

1. **One accent per composition.** If you want to use coral/amber in two places on the same screen, ask whether one of them should be `Color.ns.ink` instead. Almost always yes.
2. **Numerals grow, labels shrink.** When in doubt, push the eyebrow to 11pt and the numeral to 40pt+.
3. **Hairlines over cards.** A `NSHairline()` divides as cleanly as a card boundary, with one-tenth the visual weight.
4. **Italic serif for prose, mono for metadata.** A short qualitative sentence ("trending toward goal") wants italic serif; a metric label ("ACWR · 1.18") wants mono caps.
5. **Empty space is a decision.** Pages that feel "unfinished" because they have whitespace below the content are right; pages that fill every pixel are wrong.
6. **No icons in the top bar of a section.** The eyebrow itself is the marker. Icons crowd what should be a whisper.

---

## When to break the rules

- **Empty states** can use a single SF Symbol — the page is a moment, not a flow, so the icon earns its weight.
- **Recording / logging** views want the `PulsingRecordButton` from the existing system. Don't try to flatten it.
- **The Coach tab** is a conversation; chat bubbles don't fit the eyebrow/timeline grammar. Leave that screen alone for now.

---

## How to verify a migration

After porting a screen:

1. Open the SwiftUI preview. Compare to the Negative Splits mockup plate (when one exists).
2. Count distinct color hex values used on the screen. Goal: 4–6 (paper, ink, slate, hair, accent, optionally green-ok). If it's more, find what's stealing the eye and remove it.
3. Resize the preview to iPad. The hierarchy should still hold — if the screen falls apart, the layout was anchored to chrome rather than typography.
4. Switch to dark mode. The components themselves are dark-mode-neutral via `Color.ns.*` aliases, but if the screen uses raw `Color.drip.*` values directly, those still resolve in dark mode through the existing system.
5. Run the app, navigate to the screen, screenshot, drop it next to the mockup plate. They should feel like siblings.

---

## What's not in this guide

- **Coach tab redesign** — the conversation surface needs its own pass; the eyebrow/timeline grammar doesn't apply.
- **Onboarding flow** — separate spec; needs warmth and reassurance, not the same restraint.
- **The Voice Log capture button** — the existing `PulsingRecordButton` is correct as-is; the recording moment needs presence, not whisper.
- **Coach-side analytics dashboard** — its own spec; multi-athlete tables don't translate to single-athlete typography.

If/when you're ready to migrate any of these, ping me and I'll do a focused pass per surface.
