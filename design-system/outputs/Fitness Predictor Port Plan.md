# Fitness Predictor Port · Implementation Plan

**Where:** `RunningLog/RunningLog/Analysis/FitnessPredictorView.swift` (847 lines)
**Spec:** `Post Run Drip Design System/Fitness Predictor Rebrand.html` (artboard **B**)
**Decision:** Same screen, same data, same routing — just brand-aligned. No model changes, no service changes.

---

## What's broken (and what the brand rule is)

| # | Current | PRD rule | Fix |
|---|---|---|---|
| 1 | Nav-bar `Text("FITNESS PREDICTOR")` toolbar title (line 94-97) | *Plate strip is the single most identifiable visual gesture; use on every editorial surface* | Drop the toolbar title; add `PlateStrip(surface: "FITNESS PREDICTOR  ·  FORWARD READ", fig: "FIG. 29")` inside the `ScrollView` |
| 2 | `RacePredictionsCard` (line 168-201) wraps 5 `RacePredictionTile`s, each of which sets `.background(Color.drip.background.opacity(0.5))` — card-in-card | *Cards stand alone on the paper — no card-in-card* | Flatten to a single editorial list: 5 rows, hairline rules between, no inner tiles |
| 3 | `RacePredictionTile.pace` is rendered in `Color.drip.coral` (line 246). Anchor row also renders the race tag and the "Xw ago" capsule in coral. 3 corals per cluster. | *One coral element per visual cluster, maximum* | Coral stays on the pace per row; anchor "Xw ago" → ink-3 mono; anchor race label → ink-2 mono |
| 4 | `PredictionErrorBanner` (line 605-625) — coral-tinted fill, coral border, SF-symbol with `Color.drip.tired` | *Error / liability tone is quiet italic secondary, not a coral fill* | Replace with a top-of-page hairline strip: `MONO eyebrow · italic body`, no fill, no border |
| 5 | `EmptyPredictionState` (line 555-602) — coral circle + trophy SF-symbol + coral "Get Predictions" Capsule button | Empty state pattern from `docs/conventions/empty-states.md`: *state the absence, then say what will fill it; italic, secondary, no illustration* | Replace with an editorial empty: italic body, single underlined coral link (`Run a prediction ↗`) |
| 6 | `RacePredictionTile` headline uses `.system(size: ..., weight: .semibold, design: .monospaced)` ✓ but `RacePredictionsCard`'s anchor row uses **sans** at line 175 (`.system(size: 12, weight: .semibold)`) for the race-type label and 184 for "Xw ago" | *Three families, sharply assigned. Numerals and uppercase labels are monospaced.* | Anchor row text → `.dripEyebrow(10).tracking(1.4)`; "Xw ago" → `.system(size: 10, design: .monospaced)` ink-3 |
| 7 | `TrainingCard` status pill uses `.system(size: 10, weight: .bold)` sans (line 372) | Same as 6 — uppercase labels are mono | `.dripEyebrow(10).tracking(1.4)` |
| 8 | Coral toolbar refresh icon (line 102-109) — third coral element while predictions are visible | One coral per cluster | Move to `Color.drip.textSecondary`; it's a utility action, not the active hit |

Models, service, snapshot fetching, HealthKit auth, navigation — **untouched**. This is a view-layer port.

---

## What to land

Three commits, in order. Each one is independently shippable.

1. **Add the page header.** Drop the toolbar title; add `PlateStrip` inside the scroll view; demote the refresh icon to `textSecondary`.
2. **Flatten the predictions card + fix the error banner.** Rewrite `RacePredictionsCard` as a hairline list. Rewrite `PredictionErrorBanner` as a quiet strip. Rewrite `EmptyPredictionState` as editorial.
3. **Mono pass + coral audit.** Run through every `.font(.system(...))` in this file; convert uppercase-label sites to `.dripEyebrow(...)` and numeral sites to `.system(..., design: .monospaced)`. Cap coral at one per cluster.

---

## 1 · Page header (lines 14-118)

### Delete (toolbar title + coral refresh)

```swift
// lines 91-110 — remove these toolbar items
ToolbarItem(placement: .principal) {
    Text("FITNESS PREDICTOR")
        .font(.dripCaption(12))
        .foregroundStyle(Color.drip.textSecondary)
        .tracking(2)
}
ToolbarItem(placement: .topBarTrailing) {
    Button(action: predict) {
        if predictor.isAnalyzing {
            ProgressView()
                .tint(Color.drip.coral)
                .scaleEffect(0.7)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.drip.coral)   // ← coral overuse
        }
    }
    .disabled(predictor.isAnalyzing)
}
```

### Insert (plate strip inside scroll content)

At the top of the `VStack(spacing: 20)` block (line 24), **before** the error-banner branch:

```swift
PlateStrip(
    surface: "FITNESS PREDICTOR  ·  FORWARD READ",
    fig: "FIG. 29"
)
.padding(.horizontal, 24)
.padding(.top, 4)
```

### Keep the refresh action, just demote it

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button(action: predict) {
        if predictor.isAnalyzing {
            ProgressView()
                .tint(Color.drip.textSecondary)   // was coral
                .scaleEffect(0.7)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))   // was .semibold
                .foregroundStyle(Color.drip.textSecondary)  // was coral
        }
    }
    .disabled(predictor.isAnalyzing)
}
```

`.toolbarBackground(Color.drip.background, for: .navigationBar)` stays — the nav bar is just a clear container for the back button now.

---

## 2 · Flatten `RacePredictionsCard` + rewrite error + empty (lines 168-272, 555-625)

### Replace `RacePredictionsCard` and `RacePredictionTile` entirely

```swift
// MARK: - Race Predictions (flat editorial list)

private struct RacePredictionsList: View {
    let predictions: FitnessPrediction
    let anchor: RaceAnchorInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let anchor { AnchorStrip(anchor: anchor) }

            EditorialRule()
                .padding(.vertical, 14)

            ForEach(Array(predictions.races.enumerated()), id: \.element.id) { idx, race in
                RacePredictionRow(race: race)
                if idx < predictions.races.count - 1 {
                    Hairline()
                }
            }

            Text("Range is where the time lives 80% of the time, off today's fitness. Marathon and half round to the minute — seconds at that distance are math, not signal.")
                .font(.system(size: 11, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .lineSpacing(2)
                .padding(.top, 12)
        }
        // NB: no .background, no card. Sits on the paper.
    }
}

private struct AnchorStrip: View {
    let anchor: RaceAnchorInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Anchored on")
                    .font(.dripEyebrow(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("\(anchor.weeksAgo)w ago")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)   // was coral capsule
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(anchor.raceType)
                    .font(.dripEyebrow(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.coral)          // the one coral here
                Text(anchor.time)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            Text("\(anchor.date) — your most recent timed effort. The forward read is rooted here.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
    }
}

private struct RacePredictionRow: View {
    let race: RacePredictionItem

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(race.distance)            // already uppercase
                    .font(.dripEyebrow(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textSecondary)
                Text(RacePredictionFormatting.headline(for: race))
                    .font(.system(size: race.distance == "MARATHON" ? 30 : 28,
                                  weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let range = RacePredictionFormatting.range(for: race) {
                    Text(range)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Text(race.pace)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.drip.coral)          // the one coral
            }
        }
        .padding(.vertical, 14)
    }
}
```

Update the call site (line 33-37):
```swift
RacePredictionsList(
    predictions: predictions,
    anchor: predictions.raceAnchor
)
.padding(.horizontal, 24)
```

### Replace `PredictionErrorBanner` (lines 605-625)

```swift
private struct PredictionErrorBanner: View {
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("Network  ·  Offline")
                    .font(.dripEyebrow(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.coral)        // eyebrow only — not a fill
                Text(message)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            Hairline()
        }
    }
}
```

No more `.background(Color.drip.tired.opacity(0.1))`, no `RoundedRectangle.stroke`, no SF-symbol. The eyebrow + italic body *is* the pattern from `docs/conventions/empty-states.md`.

### Replace `EmptyPredictionState` (lines 555-602)

```swift
private struct EmptyPredictionState: View {
    let onPredict: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing read yet")
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text("Predicted times.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Run a prediction and your next five distances — mile through marathon — will land here. The system needs a recent race or timed effort to anchor on.")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(3)
            Button(action: onPredict) {
                Text("Run a prediction \u{2197}")     // "↗" matches "Mark complete ↗"
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.coral)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.drip.coral).frame(height: 1)
                    }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // NB: no card. No coral circle. No SF-symbol. No capsule button.
    }
}
```

---

## 3 · Mono pass + coral audit

A grep-and-fix pass on the rest of the file. Search and convert:

| Line | Find | Replace with |
|---|---|---|
| ~372 | `.font(.system(size: 10, weight: .bold))` (status pill) | `.font(.dripEyebrow(10)).tracking(1.4)` |
| ~427-432 | `paceRow` `.font(.system(size: 12, weight: .medium))` | `.font(.system(size: 13, design: .serif))` (body, not mono — these are word labels) |
| ~441 | `paceRow` `.font(.system(size: 13, weight: .semibold, design: .monospaced))` | ✓ already correct |
| ~485 | `stimulusStat` value `.font(.system(size: 15, weight: .semibold, design: .monospaced))` | ✓ correct |
| ~498 | `stimulusStat` label `.font(.system(size: 9, weight: .medium))` | `.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.0)` |
| ~770-779 | `DataSourcesRow` value `.font(.system(size: 11, weight: .semibold, design: .monospaced))` | ✓ |
| ~773 | `DataSourcesRow` label `.font(.system(size: 9, weight: .medium))` | `.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.0)` |
| ~755 | `DataSourcesRow` `.background(Color.drip.cardBackground)` | drop — sits on the paper |
| ~516 | `FitnessSummaryCard` `Image(systemName: "brain.head.profile")` coral | swap to plain text eyebrow `AI ANALYSIS` (mono) without the icon — the icon adds nothing and is the second coral on that card |

Coral audit — when this is done, only these elements should be coral:
- The eyebrow on each section header
- The pace on each prediction row (5 of them, one per row — these are different clusters)
- The "Anchored on" race-type label
- The trend arrow when it indicates improvement (already gated on `> 1.15`)
- The single underlined editorial link in the empty state

If the file has more coral than that, drop the lowest-priority instance to `textSecondary`.

---

## What I'm **not** including (and why)

- **`FitnessTrendCard` / `TrendSparkline` (lines 627-825).** The sparkline already uses `.dripCaption` + monospaced numerals + coral *only* on the active dot — it's the one piece of this view that already matches the brand. Leave it alone in this port.
- **`TrainingEffortChart` (line 52 reference).** That component lives in its own file (`TrainingEffortChart.swift`) and is shared with other surfaces — its own port plan.
- **Model / service changes.** `FitnessPrediction`, `RacePredictionItem`, `RaceAnchorInfo` are untouched. This is purely a view-layer rebrand.
- **Adding a `PlateFooter`.** The `FitnessSummaryCard` already plays the role of the footer caption. Adding another italic-serif line below would over-quote the device.

---

## QA checklist

Do these in order. Stop and fix at the first ✗.

| # | Check | Where |
|---|---|---|
| 1 | Compiles | Build |
| 2 | `PlateStrip` shows `FITNESS PREDICTOR · FORWARD READ · FIG. 29` at the top of the scroll, not a nav-bar title | Open from Trends |
| 3 | The 5 race predictions render as a flat hairline list — no inner tiles, no card on a card | Light mode, fresh prediction |
| 4 | Exactly **one** coral element per visual cluster — pace per row, eyebrow per section | Eyeball the whole screen |
| 5 | "Xw ago" is mono ink-3, not a coral capsule | Anchor row |
| 6 | Pull network off → error banner shows as a hairline-bracketed italic line, **not** a coral-tinted fill | Airplane mode + force refresh |
| 7 | Empty state (no predictions yet) reads as an editorial italic paragraph + one underlined coral link. No coral circle, no trophy, no sparkles | Fresh account |
| 8 | `Maintaining` / `Building` / `Light` / `Detraining` status pill is mono uppercase, tracked, not sans-bold | TrainingCard, scroll into view |
| 9 | All numerals (race times, paces, stimulus stats, data-sources counts) are monospaced, tabular-nums; no system sans | Eyeball each section |
| 10 | Toolbar refresh icon is ink-2, not coral | Top-right corner |

---

**Estimated total scope:** ~140 lines of `FitnessPredictorView.swift` rewritten (lines 92-272, 555-625), ~30 lines touched in the mono pass, **zero** changes to `FitnessPredictorService.swift`, `FitnessPredictorModels.swift`, or any navigation host. A focused half-day including device QA.
