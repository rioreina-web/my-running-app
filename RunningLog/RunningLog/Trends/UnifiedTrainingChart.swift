//
//  UnifiedTrainingChart.swift
//  RunningLog
//
//  The Trends tab centerpiece: one shared-x timeline stacking four tracks
//  so correlations surface by vertical alignment —
//    1. VOLUME + INTENSITY  weekly mileage bars; darker cap = quality miles
//    2. KEY SESSIONS · PACE coral dots + connecting line (higher = faster)
//    3. MOOD                one dot per week, colored by dominant mood
//    4. NIGGLES             a ring on any week a body part was mentioned
//
//  Drawn with a SwiftUI `Canvas` (matching `PaceVolumeSpectrumChart`'s
//  approach) for full control over the aligned layout + scrub crosshair.
//  Coral is spent only on the key-session dots and the scrub marker —
//  one accent per cluster, per the design system.
//
//  Charts can be refined later (Rio: "the charts can be refined"); this is
//  the structural V1.
//

import SwiftUI

// MARK: - Mood → color

enum TrendsMoodColor {
    static func color(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "energized":  Color.drip.energized
        case "positive":   Color.drip.positive
        case "neutral":    Color.drip.neutral
        case "tired":      Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured":    Color.drip.injured
        default:           Color.drip.neutral
        }
    }
}

// MARK: - Unified chart

struct UnifiedTrainingChart: View {
    let weeks: [TrendsWeek]
    /// Index of the scrubbed week (into `weeks`). `nil` → no crosshair; the
    /// readout above falls back to the most recent week.
    @Binding var scrubIndex: Int?

    // Fixed drawing height; width comes from the parent.
    private let chartHeight: CGFloat = 312

    // Horizontal insets inside the canvas.
    private let padL: CGFloat = 6
    private let padR: CGFloat = 8

    // Track bands (absolute y within `chartHeight`). The pace band gets the
    // most room — it's the "key sessions" story — and its plot is inset
    // (paceInset* below) so dot value-labels never collide with the header.
    private let volTop: CGFloat = 26
    private let volBottom: CGFloat = 118
    private let paceTop: CGFloat = 156
    private let paceBottom: CGFloat = 210
    private let moodY: CGFloat = 236
    private let nigY: CGFloat = 268
    private let axisY: CGFloat = 292

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, size in
                draw(ctx: ctx, w: size.width)
            }
            .frame(width: w, height: chartHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubIndex = index(forX: value.location.x, width: w)
                    }
            )
            .accessibilityLabel("Unified training chart: volume, pace, mood, and niggles over time")
        }
        .frame(height: chartHeight)
    }

    // MARK: x mapping

    private func slot(_ w: CGFloat) -> CGFloat {
        guard !weeks.isEmpty else { return 0 }
        return (w - padL - padR) / CGFloat(weeks.count)
    }

    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        padL + slot(w) * (CGFloat(i) + 0.5)
    }

    private func index(forX xPos: CGFloat, width w: CGFloat) -> Int {
        guard !weeks.isEmpty, slot(w) > 0 else { return 0 }
        let raw = Int((xPos - padL) / slot(w))
        return min(max(raw, 0), weeks.count - 1)
    }

    // MARK: drawing

    private func draw(ctx: GraphicsContext, w: CGFloat) {
        guard !weeks.isEmpty else { return }
        let n = weeks.count
        let bw = min(slot(w) * 0.56, 18)

        let maxMiles = max(weeks.map(\.miles).max() ?? 1, 1)
        let milesH = volBottom - volTop

        // pace scale over weeks that have a key session
        let paces = weeks.compactMap(\.keyPaceSec)
        let pMin = CGFloat(paces.min() ?? 0)
        let pMax = CGFloat(paces.max() ?? 1)
        let pSpan = max(pMax - pMin, 1)
        // Inset the pace plot inside its band so the top dot's value label
        // sits clear of the "KEY SESSIONS · PACE" header above it.
        let paceInsetTop = paceTop + 12
        let paceInsetBottom = paceBottom - 6
        func paceY(_ p: Int) -> CGFloat {
            paceInsetTop + (CGFloat(p) - pMin) / pSpan * (paceInsetBottom - paceInsetTop) // faster (low) → top
        }

        // ---- track labels ----
        label(ctx, "VOLUME · MI", at: CGPoint(x: padL, y: volTop - 10), anchor: .leading)
        label(ctx, "KEY SESSIONS · PACE", at: CGPoint(x: padL, y: paceTop - 16), anchor: .leading)
        label(ctx, "MOOD", at: CGPoint(x: padL, y: moodY - 13), anchor: .leading)
        label(ctx, "NIGGLES", at: CGPoint(x: padL, y: nigY - 13), anchor: .leading)

        // peak mileage tag
        label(ctx, "\(Int(maxMiles)) mpw", at: CGPoint(x: w - padR, y: volTop - 8), anchor: .trailing)

        // ---- volume baseline ----
        var baseline = Path()
        baseline.move(to: CGPoint(x: padL, y: volBottom))
        baseline.addLine(to: CGPoint(x: w - padR, y: volBottom))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)

        // ---- volume bars (easy base + quality cap) ----
        for (i, week) in weeks.enumerated() {
            let cx = x(i, w)
            let totH = CGFloat(week.miles / maxMiles) * milesH
            let qH = CGFloat(week.qualityMiles / maxMiles) * milesH
            let eH = max(totH - qH, 0)
            // easy
            let easyRect = CGRect(x: cx - bw / 2, y: volBottom - eH, width: bw, height: eH)
            ctx.fill(Path(easyRect), with: .color(Color.drip.paperDeep))
            // quality cap
            let qRect = CGRect(x: cx - bw / 2, y: volBottom - totH, width: bw, height: max(qH, 0))
            ctx.fill(Path(qRect), with: .color(Color.drip.textSecondary))
        }

        // ---- pace connecting line + dots ----
        var paceLine = Path()
        var started = false
        for (i, week) in weeks.enumerated() {
            guard let p = week.keyPaceSec else { continue }
            let pt = CGPoint(x: x(i, w), y: paceY(p))
            if started { paceLine.addLine(to: pt) } else { paceLine.move(to: pt); started = true }
        }
        ctx.stroke(paceLine, with: .color(Color.drip.coral.opacity(0.5)), lineWidth: 1.6)
        for (i, week) in weeks.enumerated() {
            guard let p = week.keyPaceSec else { continue }
            let r: CGFloat = 3.6
            let dot = CGRect(x: x(i, w) - r, y: paceY(p) - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(Color.drip.coral))
        }
        // Pace value labels. In short ranges (≤ 6 quality sessions) every
        // dot is labelled so the key-session paces are all legible; in
        // longer ranges only the endpoints are, to avoid clutter.
        let paced = weeks.enumerated().filter { $0.element.keyPaceSec != nil }
        let labelEvery = paced.count <= 6
        for (idx, item) in paced.enumerated() {
            guard let p = item.element.keyPaceSec else { continue }
            let isEndpoint = idx == 0 || idx == paced.count - 1
            guard labelEvery || isEndpoint else { continue }
            label(
                ctx,
                TrendsFormat.pace(p),
                at: CGPoint(x: x(item.offset, w), y: paceY(p) - 10),
                anchor: .center,
                color: Color.drip.textSecondary
            )
        }

        // ---- mood dots ---- (skip weeks with no logged mood — never
        // fabricate a feeling for an empty week). Dots ride a faint
        // baseline and carry a soft same-hue halo so the qualitative lane
        // reads at a glance instead of hiding under the volume bars —
        // mood is half the product's signal, it shouldn't whisper.
        var moodBase = Path()
        moodBase.move(to: CGPoint(x: padL, y: moodY))
        moodBase.addLine(to: CGPoint(x: w - padR, y: moodY))
        ctx.stroke(moodBase, with: .color(Color.drip.divider.opacity(0.6)), lineWidth: 1)
        for (i, week) in weeks.enumerated() {
            guard !week.mood.isEmpty else { continue }
            let color = TrendsMoodColor.color(week.mood)
            // 12%-wash halo — the same treatment as the MoodBadge pill.
            let hr: CGFloat = 8.5
            let halo = CGRect(x: x(i, w) - hr, y: moodY - hr, width: hr * 2, height: hr * 2)
            ctx.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.16)))
            let r: CGFloat = 4.6
            let dot = CGRect(x: x(i, w) - r, y: moodY - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(color))
        }

        // ---- niggle lane ----
        var nigBase = Path()
        nigBase.move(to: CGPoint(x: padL, y: nigY))
        nigBase.addLine(to: CGPoint(x: w - padR, y: nigY))
        ctx.stroke(nigBase, with: .color(Color.drip.divider.opacity(0.6)), lineWidth: 1)
        for (i, week) in weeks.enumerated() {
            guard !week.niggles.isEmpty else { continue }
            let r: CGFloat = 3.4
            let ring = CGRect(x: x(i, w) - r, y: nigY - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: ring), with: .color(Color.drip.injured), lineWidth: 1.6)
            if week.niggles.count > 1 {
                label(ctx, "×\(week.niggles.count)", at: CGPoint(x: x(i, w) + 7, y: nigY), anchor: .leading, color: Color.drip.textTertiary)
            }
        }

        // ---- month axis ----
        var lastMonth = ""
        for (i, week) in weeks.enumerated() {
            if week.month != lastMonth {
                label(ctx, week.month.uppercased(), at: CGPoint(x: x(i, w), y: axisY), anchor: .center, color: Color.drip.textTertiary)
                lastMonth = week.month
            }
        }

        // ---- scrub crosshair ----
        if let s = scrubIndex, s >= 0, s < n {
            let cx = x(s, w)
            var cross = Path()
            cross.move(to: CGPoint(x: cx, y: volTop - 14))
            cross.addLine(to: CGPoint(x: cx, y: nigY + 10))
            ctx.stroke(cross, with: .color(Color.drip.textPrimary.opacity(0.18)), lineWidth: 1)
            let r: CGFloat = 2.8
            let cap = CGRect(x: cx - r, y: volTop - 14 - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: cap), with: .color(Color.drip.coral))
        }
    }

    // MARK: text helper

    private func label(
        _ ctx: GraphicsContext,
        _ string: String,
        at point: CGPoint,
        anchor: UnitPoint,
        color: Color = Color.drip.textTertiary
    ) {
        let text = Text(string)
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundColor(color)
        ctx.draw(text, at: point, anchor: anchor)
    }
}
