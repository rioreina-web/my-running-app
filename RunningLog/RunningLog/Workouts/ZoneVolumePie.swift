//
//  ZoneVolumePie.swift
//  RunningLog
//
//  A day's volume, split by pace zone, drawn as a pie whose AREA is the
//  volume.
//
//  WHY A PIE — this is a new shape in a codebase that deliberately has very
//  few. The house idiom for "proportion" is the horizontal stacked bar
//  (`RRZoneBar` in WorkoutReceiptCharts.swift), and for a single row that is
//  still the better tool: it aligns to a baseline, it labels cleanly, and it
//  compares across rows.
//
//  It cannot do the job here. `WeekTrainingLoadSection` puts seven of these
//  side by side inside columns whose WIDTHS already encode training load, so
//  the width channel is spent. Volume has to come through a second, unrelated
//  channel, and it has to work at seven different magnitudes at once (a 5-mile
//  recovery day next to a 20-mile long run). A disc has one honest size
//  channel — its area — that is independent of the column it sits in. A
//  stacked bar inside a fixed-width column can show composition or magnitude,
//  not both.
//
//  AREA, NOT RADIUS. Radius scales as √(miles / maxMiles). Scaling the radius
//  linearly would make an 18-miler look nine times a 6-miler instead of three,
//  which is the standard bubble-chart lie. Area is what the eye actually
//  ranks, so area is what carries the number.
//
//  Colour is `PaceSpectrum` and nothing else — blue is pace. No mood colour,
//  no coral, ever enters this view; see the three-palette rule in CLAUDE.md.
//

import SwiftUI

struct ZoneVolumePie: View {

    /// One wedge. Ordered slowest → fastest by the caller, so the ramp reads
    /// clockwise from pale to navy and two adjacent days are comparable at a
    /// glance rather than being shuffled by magnitude.
    struct Slice: Identifiable {
        let id = UUID()
        /// Raw zone token (`easy`, `mp`, `5k` …) — the vocabulary stays owned
        /// by `workoutSegmentation.ts`.
        let token: String
        let miles: Double
        let color: Color
    }

    let slices: [Slice]
    /// This day's total, in miles. Passed rather than summed so a caller that
    /// has already reconciled against `TrendsDay.miles` stays authoritative.
    let miles: Double
    /// The biggest day in the same week — the scale this pie is measured on.
    let maxMiles: Double
    /// Diameter the biggest day gets. Every other day is smaller.
    let maxDiameter: CGFloat

    /// Hairline between wedges, so two adjacent blues stay legible as two.
    private let sliceStroke: CGFloat = 0.75

    private var diameter: CGFloat {
        guard maxMiles > 0, miles > 0 else { return 0 }
        return maxDiameter * CGFloat((miles / maxMiles).squareRoot())
    }

    var body: some View {
        Canvas { ctx, size in
            let total = slices.reduce(0) { $0 + $1.miles }
            guard total > 0 else { return }
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            // A single-zone day is a plain disc. Drawing it as a 360° wedge
            // leaves a visible seam at 12 o'clock — and an all-easy day is
            // the most common day there is, so the seam would be everywhere.
            if slices.count == 1 {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(slices[0].color))
                return
            }

            var angle = Angle.degrees(-90) // start at 12 o'clock
            for s in slices {
                let sweep = Angle.degrees(360 * (s.miles / total))
                var p = Path()
                p.move(to: c)
                p.addArc(center: c, radius: r,
                         startAngle: angle, endAngle: angle + sweep,
                         clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(s.color))
                ctx.stroke(p, with: .color(Color.drip.cardBackground),
                           lineWidth: sliceStroke)
                angle += sweep
            }
        }
        .frame(width: diameter, height: diameter)
        // One element, one label — the caller supplies it. Seven pies each
        // announcing nine wedges would make the section unusable by voice.
        .accessibilityHidden(true)
    }
}
