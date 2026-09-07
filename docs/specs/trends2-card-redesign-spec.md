# Trends 2 card redesign — build spec (for the Xcode agent)

**Goal:** make the "Trends 2" (`TrendsInsightsTabView`) cards look like the approved prototype's deep-dive cards — a real 12-week trend line + delta inside each card — instead of prose + two chips.

**Design source of truth:** `outputs/trends-tab-rebuilt-prototype-2026-07-23.html` (the deep-dive card anatomy: eyebrow + delta, headline, mini line chart, editorial read).

**Division of labor:** the backend is done (already committed) — each card now carries a full `series`. This spec is the SwiftUI: a new `InsightTrendChart` view + a redesigned `InsightCardView`. Build these in Xcode where you can compile + preview. **Do not** reintroduce the 2-point line that shipped earlier — draw the full `series.points`.

---

## 1. Data is ready (backend already committed)

`trends-insights` now returns an optional `series` on each card. Wire format:

```jsonc
{
  "id": "B1", "group": "B", "status": "active",
  "headline": "Same pace, fewer beats",
  "body": "At your 7:00-ish miles, your heart rate has come down…",
  "evidence": [ { "week": "Jun 8", "value": 152, "label": "bpm" }, … ],
  "confidence": "high",
  "series": {                       // ← NEW. Absent on some cards → prose-only.
    "points": [152,151,150,149,147,146,145,144],   // full weekly values, oldest→newest
    "labels": ["May 5","May 12", … ],              // aligned 1:1 to points (optional)
    "unit": "bpm",                                 // mi | sec | % | bpm | bpm/60s | spm
    "polarity": "down_good",                       // up_good | down_good | neutral
    "markerIdx": [5,9,10],                         // optional: indices to ring (A1 niggle weeks)
    "band": { "lo": 0, "hi": 5 }                   // optional: reference band (B2 <5% drift)
  }
}
```

Which cards carry a series today: **A1, A2** (weekly miles + `markerIdx`), **A3** (key pace, `down_good`), **B1** (HR-at-pace, `down_good`), **B2** (decoupling %, `down_good`, band 0–5), **B5** (HR recovery, `up_good`). `quiet` cards intentionally have no series (they stay prose-only).

---

## 2. Swift model — add to `TrendInsightsService.swift`

Add the struct and the optional field. Both `Decodable`; snake_case maps via keys.

```swift
/// Full series behind a card, for the in-card mini-chart. Optional — a card
/// without one renders prose-only.
struct TrendSeries: Decodable {
    let points: [Double]
    let labels: [String]?
    let unit: String?
    let polarity: String?          // "up_good" | "down_good" | "neutral"
    let markerIdx: [Int]?
    let band: Band?

    struct Band: Decodable { let lo: Double; let hi: Double }

    enum CodingKeys: String, CodingKey {
        case points, labels, unit, polarity, band
        case markerIdx = "marker_idx"   // NB: JSON is camelCase already ("markerIdx");
    }
    // If your decoder isn't converting keys, the endpoint sends "markerIdx"
    // verbatim — set the CodingKey to "markerIdx". Confirm against a live payload.
}
```

> **One thing to verify against a real payload:** the endpoint emits the key exactly as written in TS — `markerIdx` (camelCase), `band`, `unit`, `polarity`, `labels`, `points`. If your `JSONDecoder` uses `.convertFromSnakeCase`, it will mangle `markerIdx`; if it uses default keys, map `case markerIdx = "markerIdx"`. Match whatever `TrendInsightCard` already relies on.

Then add to `TrendInsightCard`:

```swift
    let series: TrendSeries?        // add to the struct + it decodes automatically
```

`TrendInsightCard` is `Decodable` with matching property names, so adding `series` is all that's needed.

---

## 3. New view — `InsightTrendChart.swift`

A proper multi-point line, oriented so **improvement reads upward** (per the prototype), with optional markers + reference band. Drop this in a new file.

```swift
import SwiftUI

/// The in-card trend line for a `TrendSeries`. Draws the full series (not two
/// points), orients by polarity so the win reads upward, rings `markerIdx`,
/// and shades an optional reference `band`. Coral line; one accent per card.
struct InsightTrendChart: View {
    let series: TrendSeries
    var active: Bool = true

    private let height: CGFloat = 92
    private let padX: CGFloat = 4
    private let padY: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            let pts = series.points
            guard pts.count >= 2 else { return }

            // Value domain includes any band bounds so the band stays on-chart.
            var lo = pts.min() ?? 0
            var hi = pts.max() ?? 1
            if let b = series.band { lo = min(lo, b.lo); hi = max(hi, b.hi) }
            let span = max(hi - lo, 0.0001)

            // Orient: for "down_good", a LOWER value should sit HIGHER on the
            // chart (improvement up). Others map value→height normally.
            let downGood = (series.polarity == "down_good")
            func yFrac(_ v: Double) -> CGFloat {
                let t = CGFloat((v - lo) / span)          // 0 at lo … 1 at hi
                return downGood ? t : (1 - t)             // downGood: lo→top
            }
            let w = max(size.width - padX * 2, 1)
            let h = max(size.height - padY * 2, 1)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: padX + w * CGFloat(i) / CGFloat(pts.count - 1),
                        y: padY + h * yFrac(pts[i]))
            }

            let line = active ? Color.drip.coral : Color.drip.textTertiary

            // Reference band (e.g. decoupling < 5%).
            if let b = series.band {
                let y1 = padY + h * yFrac(b.lo)
                let y2 = padY + h * yFrac(b.hi)
                let rect = CGRect(x: padX, y: min(y1, y2), width: w, height: abs(y2 - y1))
                ctx.fill(Path(rect), with: .color(Color.drip.energized.opacity(0.08)))
            }

            // The line.
            var path = Path()
            for i in pts.indices {
                let p = pt(i)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(line.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            // Endpoint dots.
            for i in [0, pts.count - 1] {
                let p = pt(i); let r: CGFloat = 2.8
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)),
                         with: .color(line))
            }

            // Markers (A1 niggle weeks): hollow rings.
            for i in (series.markerIdx ?? []) where i >= 0 && i < pts.count {
                let p = pt(i); let r: CGFloat = 4.5
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)),
                           with: .color(Color.drip.injured), lineWidth: 1.6)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)   // the prose + evidence carry the meaning for VO
    }
}
```

---

## 4. Redesign `InsightCardView` (in `TrendsInsightsTabView.swift`)

Replace the current `InsightCardView.body`. Anatomy matches the prototype: **eyebrow + delta row → headline → chart → body → evidence chips**. The delta is neutral (three-palette rule — no green/coral on the number).

```swift
private struct InsightCardView: View {
    let card: TrendInsightCard

    private var eyebrow: String {
        card.isActive ? "PATTERN · \(card.confidence.uppercased())" : "NO PATTERN"
    }

    /// Neutral first→last delta from the series (pace in seconds, else the unit).
    private var deltaLabel: String? {
        guard let s = card.series, let first = s.points.first, let last = s.points.last,
              s.points.count >= 2 else { return nil }
        let d = last - first
        guard abs(d) >= 0.5 else { return nil }
        let arrow = d > 0 ? "↑" : "↓"
        let unit = s.unit ?? ""
        if unit == "sec" { return "\(arrow) \(Int(abs(d).rounded()))s" }
        let u = unit.isEmpty ? "" : " \(unit)"
        return "\(arrow) \(Int(abs(d).rounded()))\(u)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(eyebrow)
                    .font(.dripEyebrow(9)).tracking(1.0)
                    .foregroundStyle(card.isActive ? Color.drip.coral : Color.drip.textTertiary)
                Spacer(minLength: 8)
                if let d = deltaLabel {
                    Text(d)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Text(card.headline)
                .font(.dripDisplay(19))
                .foregroundStyle(Color.drip.textPrimary)

            if let s = card.series, s.points.count >= 2 {
                InsightTrendChart(series: s, active: card.isActive)
                    .padding(.top, 2)
            }

            Text(card.body)
                .font(.dripBody(15))
                .foregroundStyle(card.isActive ? Color.drip.textPrimary : Color.drip.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !card.evidence.isEmpty {
                evidenceRow.padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, card.isActive ? 13 : 0)
        .overlay(alignment: .leading) {
            if card.isActive {
                Rectangle().fill(Color.drip.coral.opacity(0.5)).frame(width: 2)
            }
        }
    }

    // evidenceRow + fmt(...) — keep the existing implementations unchanged.
}
```

Update the `#Preview` sample cards to include a `series` on the active ones so the canvas preview shows the line (e.g. B1: `TrendSeries(points: [152,151,150,149,147,146,145,144], labels: nil, unit: "bpm", polarity: "down_good", markerIdx: nil, band: nil)`).

---

## 5. Notes & guardrails

- **Orientation:** `down_good` metrics (pace, HR, drift) are drawn so *improvement rises* — matches the prototype's HR-at-pace card. If you or Rio prefer the raw axis (line follows the actual numbers), delete the `downGood` branch in `yFrac` — it's one line.
- **Three-palette rule:** line = coral (active) / grey (quiet); band = faint green (`energized` wash); markers = `injured` (niggles). No new hues. Delta text is neutral grey — never green/coral.
- **Honesty:** cards without a `series` (all `quiet` cards) stay prose-only — no empty chart frame.
- **`prefers-reduced-motion`:** the chart is static (no draw-in), so nothing to gate.
- **Accessibility:** chart is `accessibilityHidden` on purpose; the headline + body + evidence chips already read the pattern for VoiceOver.

## 6. Verify

1. Build; open **Trends 2**. Each active card (body-vs-load, same-pace, drift, bounce-back) now shows a **full multi-point line**, not a straight 2-point diagonal.
2. `Same pace, fewer beats` and `The drift…` lines **rise** (improvement up) even though the numbers fall — because `polarity: down_good`.
3. `The body talks back to the load` shows weekly miles with **hollow rings** on the niggle weeks.
4. `The drift…` shows a faint green **band** behind the line (the <5% durable zone).
5. Compare against `outputs/trends-tab-rebuilt-prototype-2026-07-23.html` deep-dive cards — same anatomy.
