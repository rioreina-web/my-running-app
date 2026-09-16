# Trends 2 → match the prototype · complete build spec

**For:** the in-Xcode agent (it can compile + preview; keep the prototype open beside the SwiftUI canvas and iterate until they match).
**Goal:** make the **Trends 2** screen (`TrendsInsightsTabView`) look like the approved prototype.
**Reference (open this side-by-side):** `outputs/trends-tab-rebuilt-prototype-2026-07-23.html`.
**Design tokens:** `RunningLog/App/DesignSystem.swift` (`Color.drip.*`, `.dripDisplay`, `.dripEyebrow`, `.dripBody`, `.dripStat`). Do not invent colors — pace = blue ramp, mood = warm, **one coral accent per cluster**, niggles = `injured`.

---

## 0. Read this first — you probably don't need to build most of this

The prototype's structure **already exists in this codebase**, fully built, in the **"Trends" tab** (`TrendsTabView.swift`, tab 3):

- the "This Week" strip → `TrendsTabView.thisWeekStrip`
- the overview chart ("shape of your block", weekly/monthly) → `UnifiedTrainingChart` + `TrendsTabView.segmenter` + the new `granularityToggle`/`TrendsAggregation`
- the Effort/Fitness/Signal segmented switcher + expandable rows → `TrendsTabView.deepGroupNav` + `expandableRow`

**Trends 2** (`TrendsInsightsTabView`) is a *different* screen: a flat list of narrative `TrendInsightCard`s.

So there are two honest paths — **pick one with Rio before building:**

- **Path A (recommended, least work):** Trends 2 stays a focused "What the chart shows" card feed, but its **cards** are upgraded to the prototype's compact card (§2 below). Then the "prototype look" for the full chart-centric screen already lives in tab 3 — polish that, and consider retiring the redundant tab. This is ~1 file of work.
- **Path B (full rebuild):** make Trends 2 itself the whole prototype screen (strip + overview + groups + cards). This **duplicates tab 3** — only do it if Trends 2 is meant to *replace* Trends. If so, reuse tab 3's components verbatim (don't re-author them) and feed the groups from `TrendInsightCard.group` ("A"/"B"/"C" → Signal/Fitness/Effort). §3 covers the assembly.

Everything below specifies the **card** (needed in both paths) and then the **screen assembly** (Path B only).

---

## 1. What the current card gets wrong vs the prototype

From the live screenshots, the cards are close in *language* but wrong in *proportion*:

1. **Chart too big + jagged.** It's ~88pt tall, full-bleed, drawn as sharp polylines over noisy weekly data → reads as an EKG. The prototype's card chart is **short (~40–52pt), smooth, and quiet** — a supporting sparkline, not the hero.
2. **No tags.** The prototype cards carry a small pill (`NEW · GARMIN`, or the confidence). Group B cards especially should read "Garmin".
3. **Flat weight.** Every card is full-size and equal. The prototype defaults cards to a compact one/two-line presence and lets the chart be secondary to the headline + read.

Fixing these three things is 80% of "make it look like the prototype" at the card level.

---

## 2. The compact insight card (both paths)

Rebuild `InsightCardView` in `TrendsInsightsTabView.swift`. Anatomy, top→bottom, matching the prototype's deep-dive card:

```
│ PATTERN · HIGH                         NEW · GARMIN   ↓ 8 bpm   ← eyebrow · tag · delta
│ Same pace, fewer beats                                          ← headline (dripDisplay 18)
│ ╭─────────────────────────────────────╮                        ← SMOOTHED sparkline, height 44
│ ╰─────────────────────────────────────╯
│ At your 7:00-ish miles, your heart rate…                        ← body (dripBody 14.5), italic-read feel
│ [ JUN 8 · 147 ] [ JUL 20 · 143 ]                                ← evidence chips (existing)
```

Concrete changes to the card you already have:
- **Shrink + smooth the chart.** Use the updated `InsightTrendChart` in §2.1 — height **44**, monotone-smoothed path, thinner line (1.5), lighter endpoints. Keep the polarity orientation, markers, and band.
- **Add a tag pill** on the eyebrow row, before the delta:
  - Group B cards → `NEW · GARMIN` (`plum` wash: `Color.drip.speed` bg 12%, text `speed`).
  - Otherwise → the confidence, subtle. Only one tag; keep it quiet.
- **Tighten spacing:** card vertical padding 14, `spacing: 7` in the VStack, chart `padding(.top, 2)`.
- Keep: the coral left rule on active cards, the delta (neutral mono, no green/coral), evidence chips, the quiet-card treatment (no chart, flat).

### 2.1 `InsightTrendChart` — smooth + compact (replace the file's `Canvas` body)

The jagged look is sharp line segments. Smooth with a monotone cubic (Catmull-Rom clamped) path and drop the height. Replace the stroke section:

```swift
// Build a smoothed path (Catmull-Rom → cubic Béziers) instead of straight segments.
func smoothedPath(_ pts: [CGPoint]) -> Path {
    var path = Path()
    guard pts.count > 1 else { return path }
    path.move(to: pts[0])
    for i in 0..<(pts.count - 1) {
        let p0 = pts[max(i - 1, 0)]
        let p1 = pts[i]
        let p2 = pts[i + 1]
        let p3 = pts[min(i + 2, pts.count - 1)]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    return path
}
```

- Set `height: CGFloat = 44` (was 88).
- Build `let pointArr = pts.indices.map { point($0) }` then `ctx.stroke(smoothedPath(pointArr), with: .color(lineColor.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))`.
- Endpoint dots `r = 2.2`. Markers (niggle rings) `r = 3.6`. Band unchanged.
- Keep everything else (domain incl. band, polarity orientation).

That single change — 44pt tall + smoothed + thinner — is what turns the EKG into the prototype's quiet trend line.

### 2.2 Tag pill helper

```swift
private struct CardTag: View {
    let text: String
    var tint: Color = Color.drip.speed   // plum for Garmin
    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
```
Show `CardTag(text: "NEW · GARMIN")` when `card.group == "B"`. (Confirm `Color.drip.speed` exists — it's the plum/`mood-speed` token; if the Swift name differs, use the matching one from `DesignSystem.swift`.)

---

## 3. Full screen assembly — **Path B only** (Trends 2 replaces Trends)

Only if Rio wants Trends 2 to *be* the whole prototype screen. Reuse tab 3's pieces; don't re-author them.

Top → bottom in `TrendsInsightsTabView`:

1. **Header** — keep the existing "What the chart is telling you." (or adopt tab 3's "The shape of your block." — Rio's call).
2. **This-Week strip** — reuse `TrendsTabView`'s strip pattern. It needs the weekly `TrendsService` data, not the insight cards; inject `TrendsService.shared` alongside `TrendInsightsService`.
3. **Overview chart** — `UnifiedTrainingChart(weeks: chartData, scrubIndex:)` + the Weekly/Monthly `granularityToggle` (already built). Same as tab 3.
4. **Segmented group nav** — `Effort · Fitness · Signal`, reuse `deepGroupNav`. Map `TrendInsightCard.group`: **A → Signal** (body/mood/load), **B → Fitness** (HR/pace/durability), plus the volume/effort cards → **Effort**. (Confirm the group→tab mapping with Rio; the letters are detector groups, not the UI tabs.)
5. **Grouped card list** — the selected group's `TrendInsightCard`s rendered as the §2 compact card, in `expandableRow`-style collapsible rows (collapsed = eyebrow + headline + delta + tiny sparkline; expanded = + chart + body + evidence).
6. **Footer** — the "Also checked N other patterns" quiet line.

Because tab 3 already wires 1–4, Path B is mostly: move `TrendInsightsService` into that view and render the cards in the groups. **This is why Path A is recommended unless you're consolidating the two tabs.**

---

## 4. Data — already done (deployed)

`trends-insights` now returns `series` on every active card (`points`, `labels`, `unit`, `polarity`, `markerIdx`, `band`). The Swift `TrendSeries` model + decoding are in `TrendInsightsService.swift`. Nothing more needed server-side for the card. The chart draws `series.points` directly.

---

## 5. Build + verify (the loop that actually converges)

1. Open `TrendsInsightsTabView.swift`; the `#Preview` has real `series` data, so the **canvas renders the cards without a build or deploy**. Tune §2 against the prototype **in the preview** — this is the fast loop.
2. When the card matches the prototype's deep card in the canvas, build to the Simulator (⌘R) and check Trends 2 with live data.
3. Side-by-side check vs `trends-tab-rebuilt-prototype-2026-07-23.html`: chart is short + smooth (not an EKG), Group B cards show the Garmin tag, spacing is tight, one coral accent per card.

---

## 6. Summary of edits

| File | Change | Path |
|---|---|---|
| `InsightTrendChart.swift` | height 44 + monotone-smoothed path + thinner line | A & B |
| `TrendsInsightsTabView.swift` | compact card: eyebrow·tag·delta row, tag pill, tighter spacing | A & B |
| `TrendsInsightsTabView.swift` | (Path B) strip + overview + group nav, reusing tab-3 components | B |
| — | decide with Rio: polish tab 3 + retire Trends 2, or consolidate into Trends 2 | decision |

**Recommendation:** do §2 (the compact card) first — it's one file, previewable instantly, and it's the piece that makes the cards read like the prototype. Decide Path A vs B with Rio before touching the screen structure.
