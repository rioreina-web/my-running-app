//
//  TrendsEfficiencyView.swift
//  RunningLog · Trends
//
//  The aerobic efficiency curve — the efficiency section's "different idea"
//  beyond the pace ladder. The ladder asks *am I faster at each pace?*; this
//  asks *is my engine cheaper?* — HR against pace across the whole range, with
//  a fitted line for now vs earlier in the block. Fitness shows up as the whole
//  curve sliding DOWN: the same pace costs fewer beats everywhere.
//
//  Drawn in ink, not coral — it's an effort/HR measure, and coral is
//  alert-only (three-palette rule).
//
//  Demo data today. The real version aggregates heart-rate-at-pace-band from
//  `external_streams` (the `trends-insights` B1 path), split into two periods
//  — heat-corrected, same as the ladder.
//

import SwiftUI

struct EfficiencyPoint { let paceSec: Double; let hr: Double }

struct EfficiencySeries {
    let label: String
    let points: [EfficiencyPoint]
}

struct TrendsEfficiencyView: View {
    let earlier: EfficiencySeries    // e.g. first 6 weeks
    let recent: EfficiencySeries     // e.g. last 6 weeks

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            curve
                .frame(height: 176)

            HStack(spacing: 16) {
                legend(recent.label, color: Color.drip.textPrimary, opacity: 1)
                legend(earlier.label, color: Color.drip.textTertiary, opacity: 1)
            }
            .padding(.top, 10)

            Text("HR vs pace · the line sits lower when the same pace costs fewer beats · heat-corrected")
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
        }
    }

    // MARK: Headline — derived from the shift at a shared pace

    private var headline: String {
        // Compare fitted HR at a mid pace (~8:00/mi = 480s).
        let p = 480.0
        guard let hNow = fit(recent.points)?.hr(at: p),
              let hThen = fit(earlier.points)?.hr(at: p) else {
            return "Not enough heart-rate-at-pace data yet to draw the curve."
        }
        let drop = Int((hThen - hNow).rounded())
        let pace = "8:00"
        if drop >= 2 {
            return "The same \(pace) pace cost \(Int(hThen.rounded())) bpm earlier in the block; \(Int(hNow.rounded())) now — the whole curve has dropped \(drop) beats. That’s the engine, measured without a race."
        } else if drop <= -2 {
            return "The same \(pace) pace is costing \(abs(drop)) more beats than earlier in the block — worth reading next to sleep and load before drawing anything from it."
        }
        return "Heart rate at a given pace hasn’t moved much this block — inside the week-to-week noise. Switch scale to see whether it’s shifting underneath."
    }

    // MARK: Curve drawing

    /// Maps a (pace, HR) point into the plot: fast pace → right, high HR → top.
    private struct Mapper {
        let size: CGSize; let paceLo: Double; let paceHi: Double; let hrLo: Double; let hrHi: Double
        func pt(_ e: EfficiencyPoint) -> CGPoint {
            let x = size.width * CGFloat((e.paceSec - paceLo) / max(1, paceHi - paceLo))
            let y = size.height * CGFloat((e.hr - hrLo) / max(1, hrHi - hrLo))
            return CGPoint(x: size.width - x, y: size.height - y)   // flip: fast right, high top
        }
    }

    private var curve: some View {
        GeometryReader { geo in
            let all = earlier.points + recent.points
            let m = Mapper(size: geo.size,
                           paceLo: all.map(\.paceSec).min() ?? 360,
                           paceHi: all.map(\.paceSec).max() ?? 560,
                           hrLo: (all.map(\.hr).min() ?? 140) - 4,
                           hrHi: (all.map(\.hr).max() ?? 185) + 4)
            ZStack {
                scatter(earlier.points, m: m, color: Color.drip.textTertiary, r: 2.4)
                scatter(recent.points, m: m, color: Color.drip.textPrimary, r: 2.8)
                fitLine(earlier.points, m: m, color: Color.drip.textTertiary, dashed: true)
                fitLine(recent.points, m: m, color: Color.drip.textPrimary, dashed: false)
            }
        }
    }

    private func scatter(_ pts: [EfficiencyPoint], m: Mapper, color: Color, r: CGFloat) -> some View {
        Path { p in
            for e in pts {
                let c = m.pt(e)
                p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
        }
        .fill(color.opacity(0.65))
    }

    private func fitLine(_ pts: [EfficiencyPoint], m: Mapper, color: Color, dashed: Bool) -> some View {
        Path { p in
            guard let f = fit(pts) else { return }
            let a = EfficiencyPoint(paceSec: m.paceLo, hr: f.hr(at: m.paceLo))
            let b = EfficiencyPoint(paceSec: m.paceHi, hr: f.hr(at: m.paceHi))
            p.move(to: m.pt(a)); p.addLine(to: m.pt(b))
        }
        .stroke(color, style: StrokeStyle(lineWidth: dashed ? 1.4 : 2,
                                          lineCap: .round, dash: dashed ? [4, 4] : []))
    }

    private func legend(_ text: String, color: Color, opacity: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color.opacity(opacity)).frame(width: 7, height: 7)
            Text(text.uppercased()).font(.dripCaption(8)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    // MARK: Least-squares fit (HR as a function of pace)

    private struct Fit { let slope: Double; let intercept: Double; func hr(at pace: Double) -> Double { slope * pace + intercept } }
    private func fit(_ pts: [EfficiencyPoint]) -> Fit? {
        guard pts.count >= 2 else { return nil }
        let n = Double(pts.count)
        let sx = pts.reduce(0) { $0 + $1.paceSec }
        let sy = pts.reduce(0) { $0 + $1.hr }
        let sxx = pts.reduce(0) { $0 + $1.paceSec * $1.paceSec }
        let sxy = pts.reduce(0) { $0 + $1.paceSec * $1.hr }
        let denom = n * sxx - sx * sx
        guard denom != 0 else { return nil }
        let slope = (n * sxy - sx * sy) / denom
        return Fit(slope: slope, intercept: (sy - slope * sx) / n)
    }
}

// MARK: - Preview data

extension TrendsEfficiencyView {
    /// Two point clouds: `earlier` sits higher (more beats per pace), `recent`
    /// dropped ~7 bpm across the range — a block where the engine grew.
    static var preview: TrendsEfficiencyView {
        func jitter(_ base: [(Double, Double)], _ seed: Double) -> [EfficiencyPoint] {
            base.enumerated().map { i, pr in
                let n = (sin(Double(i) * 12.9 + seed) * 43758.5).truncatingRemainder(dividingBy: 1)
                return EfficiencyPoint(paceSec: pr.0 + n * 8, hr: pr.1 + n * 3)
            }
        }
        let paces: [Double] = [545, 520, 495, 470, 445, 420, 395, 370, 545, 500, 460, 420, 385]
        let earlier = paces.map { p -> (Double, Double) in (p, 196 - (p - 360) * 0.20) }   // higher line
        let recent  = paces.map { p -> (Double, Double) in (p, 189 - (p - 360) * 0.20) }   // ~7 bpm lower
        return TrendsEfficiencyView(
            earlier: EfficiencySeries(label: "6 weeks ago", points: jitter(earlier, 1.3)),
            recent: EfficiencySeries(label: "now", points: jitter(recent, 7.7))
        )
    }
}

#Preview("Efficiency curve") {
    TrendsEfficiencyView.preview
        .padding()
        .background(Color.drip.cardBackground)
}
