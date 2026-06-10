//
//  DripWorkoutPrimitives.swift
//  RunningLog
//
//  Editorial chart kit for the rebranded workout detail screen.
//  Everything is hand-drawn with `Path` to keep the very thin,
//  one-coral look — `Charts` framework would impose its own grid
//  treatments and axis chrome.
//
//  Building blocks:
//    Time-series traces
//      • DripHRZoneChart       — HR over time, faint zone bands, dashed avg
//      • DripPaceOverTimeChart — pace over time, inverted Y, neg-split shading
//      • DripCadenceChart      — cadence line + avg
//      • DripElevationProfile  — thin shaded elevation strip
//
//    Distributions
//      • DripTimeInZoneRow     — single Z1…Z5 row (bar + minutes + %)
//
//    Bivariate
//      • DripHRPaceScatter     — efficiency plot, dots + regression line
//
//    Derived
//      • DripHRDriftChart      — 1st vs 2nd half pace+HR bars + drift %
//      • DripHRRecoveryArc     — post-finish HR curve + big −BPM/60s readout
//
//    Per-mile
//      • DripMileSparklines    — grid of mini HR sparklines, one per mile
//      • DripSplitRow          — single split table row
//
//    Comparison
//      • DripComparisonRow     — this vs 4w-avg, single metric
//
//    Composition
//      • DripHeroStatBlock     — big-number cell for the hero row
//      • DripHRZone            — zone descriptor with .defaultZones(maxHR:)
//

import SwiftUI

// MARK: - HR zones ────────────────────────────────────────────────────

struct DripHRZone: Identifiable, Equatable {
    let id: String
    let name: String
    let low: Int
    let high: Int
    let color: Color
    let isPrimary: Bool

    static func defaultZones(maxHR: Int = 185) -> [DripHRZone] {
        [
            .init(id: "Z1", name: "Recovery",  low: 0,                            high: Int(Double(maxHR) * 0.67), color: Color.drip.textTertiary, isPrimary: false),
            .init(id: "Z2", name: "Aerobic",   low: Int(Double(maxHR) * 0.67),    high: Int(Double(maxHR) * 0.75), color: Color.drip.positive,    isPrimary: false),
            .init(id: "Z3", name: "Tempo",     low: Int(Double(maxHR) * 0.75),    high: Int(Double(maxHR) * 0.82), color: Color.drip.coral,       isPrimary: true),
            .init(id: "Z4", name: "Threshold", low: Int(Double(maxHR) * 0.82),    high: Int(Double(maxHR) * 0.89), color: Color.drip.tired,       isPrimary: false),
            .init(id: "Z5", name: "VO2",       low: Int(Double(maxHR) * 0.89),    high: maxHR,                     color: Color.drip.injured,     isPrimary: false),
        ]
    }
}

// MARK: - Pace zones ──────────────────────────────────────────────────

struct DripPaceZone: Identifiable, Equatable {
    let id: String         // P1…P5
    let name: String
    let low: Int           // seconds per mile (low = slow boundary)
    let high: Int
    let color: Color
    let isPrimary: Bool
}

// MARK: - HR over time ────────────────────────────────────────────────

struct DripHRZoneChart: View {
    let samples: [Double]
    let zones: [DripHRZone]
    var yMin: Double = 80
    var yMax: Double = 200
    var showYAxis: Bool = true
    var showAvg: Bool = true

    private var avg: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        GeometryReader { geo in
            chartContent(geo: geo)
        }
    }

    // Extracted out of the GeometryReader trailing closure: local
    // `let`/`func` declarations aren't allowed inside @ViewBuilder.
    // A plain method body isn't a result builder, so locals are fine.
    private func chartContent(geo: GeometryProxy) -> some View {
        let padL: CGFloat = showYAxis ? 32 : 6
        let padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 6
        let plotW = geo.size.width - padL - padR
        let plotH = geo.size.height - padT - padB
        func y(_ v: Double) -> CGFloat { padT + plotH - CGFloat((v - yMin) / (yMax - yMin)) * plotH }
        func x(_ i: Int) -> CGFloat {
            guard samples.count > 1 else { return padL }
            return padL + CGFloat(i) / CGFloat(samples.count - 1) * plotW
        }

        return ZStack(alignment: .topLeading) {
            // Coral tempo band only — single coral per cluster
            ForEach(zones.filter { $0.isPrimary }) { z in
                let top = y(min(Double(z.high), yMax))
                let bot = y(max(Double(z.low), yMin))
                if bot > top {
                    Rectangle()
                        .fill(Color.drip.coral.opacity(0.06))
                        .frame(width: plotW, height: bot - top)
                        .offset(x: padL, y: top)
                }
            }
            // Hairline zone separators
            ForEach(zones.dropLast()) { z in
                Path { p in
                    let yy = y(Double(z.high))
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.divider, lineWidth: 0.5)
            }
            if showYAxis {
                ForEach([100, 120, 140, 160, 180], id: \.self) { v in
                    Text("\(v)")
                        .font(.dripCaption(8))
                        .foregroundStyle(Color.drip.textTertiary)
                        .monospacedDigit()
                        .frame(width: padL - 6, alignment: .trailing)
                        .offset(x: 0, y: y(Double(v)) - 6)
                }
            }
            if showAvg, avg > 0 {
                Path { p in
                    let yy = y(avg)
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.coral.opacity(0.6),
                        style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                Text("AVG \(Int(avg))")
                    .font(.dripCaption(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .monospacedDigit()
                    .offset(x: padL + plotW - 50, y: y(avg) - 12)
            }
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: y(samples[0])))
                for i in 1 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
            }
            .stroke(Color.drip.coral,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Pace over time ──────────────────────────────────────────────
// Y is inverted — faster pace renders higher on screen.

struct DripPaceOverTimeChart: View {
    let samples: [Double]        // seconds per mile
    var showSplit: Bool = false  // shade first half + label both halves

    private var avg: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }
    private var firstAvg: Double {
        let n = samples.count / 2
        guard n > 0 else { return 0 }
        return samples.prefix(n).reduce(0, +) / Double(n)
    }
    private var secondAvg: Double {
        let n = samples.count - samples.count / 2
        guard n > 0 else { return 0 }
        return samples.suffix(n).reduce(0, +) / Double(n)
    }

    var body: some View {
        GeometryReader { geo in
            chartContent(geo: geo)
        }
    }

    private func chartContent(geo: GeometryProxy) -> some View {
        let padL: CGFloat = 32, padR: CGFloat = 6, padT: CGFloat = 8, padB: CGFloat = 6
        let plotW = geo.size.width - padL - padR
        let plotH = geo.size.height - padT - padB
        let minSec = 410.0, maxSec = 560.0
        func y(_ v: Double) -> CGFloat { padT + CGFloat((v - minSec) / (maxSec - minSec)) * plotH }
        func x(_ i: Int) -> CGFloat {
            guard samples.count > 1 else { return padL }
            return padL + CGFloat(i) / CGFloat(samples.count - 1) * plotW
        }

        return ZStack(alignment: .topLeading) {
            // Y-axis pace lines
            ForEach([420, 450, 480, 510], id: \.self) { v in
                Path { p in
                    let yy = y(Double(v))
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.divider, lineWidth: 0.5)
                Text(paceText(Double(v)))
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
                    .monospacedDigit()
                    .frame(width: padL - 6, alignment: .trailing)
                    .offset(x: 0, y: y(Double(v)) - 6)
            }
            // First-half shade
            if showSplit {
                Rectangle()
                    .fill(Color.drip.textTertiary.opacity(0.05))
                    .frame(width: plotW / 2, height: plotH)
                    .offset(x: padL, y: padT)
                Path { p in
                    let xx = padL + plotW / 2
                    p.move(to: CGPoint(x: xx, y: padT))
                    p.addLine(to: CGPoint(x: xx, y: padT + plotH))
                }
                .stroke(Color.drip.textSecondary,
                        style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                Text("1ST · \(paceText(firstAvg))")
                    .font(.dripCaption(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                    .monospacedDigit()
                    .offset(x: padL + 4, y: padT + 4)
                Text("2ND · \(paceText(secondAvg))")
                    .font(.dripCaption(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .monospacedDigit()
                    .offset(x: padL + plotW * 0.55, y: padT + 4)
            }
            // Avg line
            if avg > 0 {
                Path { p in
                    let yy = y(avg)
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.textSecondary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            }
            // Trace
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: y(samples[0])))
                for i in 1 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
            }
            .stroke(Color.drip.textPrimary,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }

    private func paceText(_ sec: Double) -> String {
        let m = Int(sec) / 60, s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Cadence ─────────────────────────────────────────────────────

struct DripCadenceChart: View {
    let samples: [Double]    // spm

    private var avg: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        GeometryReader { geo in
            chartContent(geo: geo)
        }
    }

    private func chartContent(geo: GeometryProxy) -> some View {
        let pad: CGFloat = 6
        let plotW = geo.size.width - pad * 2
        let plotH = geo.size.height - pad * 2
        let yMin = 150.0, yMax = 185.0
        func y(_ v: Double) -> CGFloat { pad + plotH - CGFloat((v - yMin) / (yMax - yMin)) * plotH }
        func x(_ i: Int) -> CGFloat {
            guard samples.count > 1 else { return pad }
            return pad + CGFloat(i) / CGFloat(samples.count - 1) * plotW
        }

        return ZStack(alignment: .topTrailing) {
            if avg > 0 {
                Path { p in
                    let yy = y(avg)
                    p.move(to: CGPoint(x: pad, y: yy))
                    p.addLine(to: CGPoint(x: pad + plotW, y: yy))
                }
                .stroke(Color.drip.textSecondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                Text("AVG \(Int(avg))")
                    .font(.dripCaption(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                    .monospacedDigit()
                    .padding(.trailing, 4)
                    .padding(.top, max(0, y(avg) - 14))
            }
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: y(samples[0])))
                for i in 1 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
            }
            .stroke(Color.drip.textSecondary,
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            .opacity(0.85)
        }
    }
}

// MARK: - Elevation profile ───────────────────────────────────────────

struct DripElevationProfile: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            chartContent(geo: geo)
        }
    }

    private func chartContent(geo: GeometryProxy) -> some View {
        let pad: CGFloat = 4
        let plotW = geo.size.width - pad * 2
        let plotH = geo.size.height - pad * 2
        let lo = samples.min() ?? 0
        let hi = samples.max() ?? 1
        let span = max(hi - lo, 1)
        func x(_ i: Int) -> CGFloat {
            guard samples.count > 1 else { return pad }
            return pad + CGFloat(i) / CGFloat(samples.count - 1) * plotW
        }
        func y(_ v: Double) -> CGFloat { pad + plotH - CGFloat((v - lo) / span) * plotH }

        return ZStack {
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: pad + plotH))
                for i in 0 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
                p.addLine(to: CGPoint(x: x(samples.count - 1), y: pad + plotH))
                p.closeSubpath()
            }
            .fill(Color.drip.textPrimary.opacity(0.08))
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: y(samples[0])))
                for i in 1 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
            }
            .stroke(Color.drip.textPrimary.opacity(0.55), lineWidth: 1)
        }
    }
}

// MARK: - HR × Pace scatter ───────────────────────────────────────────

struct DripHRPaceScatter: View {
    let hrSamples: [Double]
    let paceSamples: [Double]    // sec/mi, parallel to hrSamples

    var body: some View {
        GeometryReader { geo in
            chartContent(geo: geo)
        }
    }

    private func chartContent(geo: GeometryProxy) -> some View {
        let padL: CGFloat = 32, padR: CGFloat = 12, padT: CGFloat = 12, padB: CGFloat = 24
        let plotW = geo.size.width - padL - padR
        let plotH = geo.size.height - padT - padB
        let hrMin = 110.0, hrMax = 165.0
        let paceMin = 420.0, paceMax = 510.0
        let pairs = zip(hrSamples, paceSamples).map { ($0, $1) }
        func x(_ p: Double) -> CGFloat { padL + CGFloat((paceMax - p) / (paceMax - paceMin)) * plotW }
        func y(_ h: Double) -> CGFloat { padT + plotH - CGFloat((h - hrMin) / (hrMax - hrMin)) * plotH }

        // Linear regression
        let n = max(pairs.count, 1)
        let meanX = pairs.reduce(0) { $0 + $1.1 } / Double(n)
        let meanY = pairs.reduce(0) { $0 + $1.0 } / Double(n)
        let num = pairs.reduce(0) { $0 + ($1.1 - meanX) * ($1.0 - meanY) }
        let den = pairs.reduce(0) { $0 + pow($1.1 - meanX, 2) }
        let slope = den == 0 ? 0 : num / den
        let intercept = meanY - slope * meanX
        func line(_ p: Double) -> Double { slope * p + intercept }

        return ZStack {
            // Frame
            Path { p in
                p.move(to: CGPoint(x: padL, y: padT))
                p.addLine(to: CGPoint(x: padL, y: padT + plotH))
                p.addLine(to: CGPoint(x: padL + plotW, y: padT + plotH))
            }
            .stroke(Color.drip.divider, lineWidth: 0.6)
            // Gridlines + tick labels
            ForEach([120, 130, 140, 150, 160], id: \.self) { v in
                Path { p in
                    let yy = y(Double(v))
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.divider.opacity(0.6), lineWidth: 0.4)
                Text("\(v)")
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
                    .monospacedDigit()
                    .frame(width: padL - 6, alignment: .trailing)
                    .position(x: padL / 2 - 3, y: y(Double(v)))
            }
            // Regression line
            Path { p in
                p.move(to: CGPoint(x: x(paceMin), y: y(line(paceMin))))
                p.addLine(to: CGPoint(x: x(paceMax), y: y(line(paceMax))))
            }
            .stroke(Color.drip.coral.opacity(0.7),
                    style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            // Dots
            ForEach(pairs.indices, id: \.self) { i in
                let pr = pairs[i]
                let mile = min(7, i / max(1, pairs.count / 7) + 1)
                Circle()
                    .fill(Color.drip.textPrimary)
                    .opacity(0.20 + Double(mile) / 14.0)
                    .frame(width: 4, height: 4)
                    .position(x: x(pr.1), y: y(pr.0))
            }
            // Axis labels
            Text("HEART RATE")
                .font(.dripCaption(8))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .rotationEffect(.degrees(-90))
                .position(x: padL - 22, y: padT + plotH / 2)
            Text("PACE (faster →)")
                .font(.dripCaption(8))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .position(x: padL + plotW / 2, y: geo.size.height - 6)
        }
    }
}

// MARK: - HR drift / decoupling ───────────────────────────────────────

struct DripHRDriftChart: View {
    let hrSamples: [Double]
    let paceSamples: [Double]

    private func halves<T>(_ a: [T]) -> ([T], [T]) {
        let m = a.count / 2
        return (Array(a.prefix(m)), Array(a.suffix(a.count - m)))
    }
    private func avg(_ a: [Double]) -> Double {
        a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count)
    }

    var body: some View {
        let (h1, h2) = halves(hrSamples)
        let (p1, p2) = halves(paceSamples)
        let hrA = avg(h1), hrB = avg(h2)
        let paceA = avg(p1), paceB = avg(p2)
        let ratioA = paceA / max(hrA, 1)
        let ratioB = paceB / max(hrB, 1)
        let drift = (ratioB - ratioA) / max(ratioA, 0.001) * 100

        return VStack(spacing: 14) {
            // 1ST · 2ND eyebrows
            HStack {
                Text("1st HALF").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("2nd HALF").font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            // PACE row
            driftBars(label: "PACE",
                      a: paceA, b: paceB,
                      norm: { (v: Double) in 1 - (v - 420) / 140 },
                      fmt: paceText)
            // HR row
            driftBars(label: "AVG HR",
                      a: hrA, b: hrB,
                      norm: { (v: Double) in (v - 90) / 80 },
                      fmt: { String(Int($0)) })
            // Decoupling summary
            Text("DECOUPLING · \(drift > 0 ? "+" : "")\(String(format: "%.1f", drift))% · \(abs(drift) < 5 ? "AEROBIC" : "DRIFTING")")
                .font(.dripCaption(9))
                .tracking(1.0)
                .foregroundStyle(abs(drift) < 5 ? Color.drip.energized : Color.drip.coral)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func driftBars(label: String, a: Double, b: Double,
                           norm: @escaping (Double) -> Double,
                           fmt: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.dripCaption(8)).tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.drip.paperDeep).frame(height: 10)
                    GeometryReader { g in
                        Rectangle()
                            .fill(Color.drip.textSecondary)
                            .opacity(0.7)
                            .frame(width: g.size.width * CGFloat(max(0, min(1, norm(a)))), height: 10)
                    }
                    .frame(height: 10)
                }
                Text(fmt(a))
                    .font(.dripCaption(11))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(width: 48, alignment: .trailing)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.drip.paperDeep).frame(height: 10)
                    GeometryReader { g in
                        Rectangle()
                            .fill(Color.drip.coral)
                            .opacity(0.85)
                            .frame(width: g.size.width * CGFloat(max(0, min(1, norm(b)))), height: 10)
                    }
                    .frame(height: 10)
                }
                Text(fmt(b))
                    .font(.dripCaption(11))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func paceText(_ sec: Double) -> String {
        let m = Int(sec) / 60, s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - HR recovery (post-finish) ───────────────────────────────────

struct DripHRRecoveryArc: View {
    let samples: [Double]   // 1 sample/sec for ~90 seconds after finish

    var body: some View {
        let drop60 = (samples.first ?? 0) - (samples.count > 29 ? samples[29] : (samples.last ?? 0))
        return HStack(alignment: .top, spacing: 12) {
            GeometryReader { geo in
                arcContent(geo: geo)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("DROP / 60s")
                    .font(.dripCaption(8)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Text("−\(Int(drop60))")
                    .font(.dripCaption(32))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.coral)
                Text("BPM")
                    .font(.dripCaption(8)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(drop60 > 30 ? "strong" : drop60 > 20 ? "healthy" : "sluggish")
                    .font(.dripBody(11).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }
            .frame(width: 70)
        }
    }

    private func arcContent(geo: GeometryProxy) -> some View {
        let padL: CGFloat = 28, padR: CGFloat = 6, padT: CGFloat = 14, padB: CGFloat = 20
        let plotW = geo.size.width - padL - padR
        let plotH = geo.size.height - padT - padB
        let yMin = 60.0, yMax = 160.0
        func x(_ i: Int) -> CGFloat {
            guard samples.count > 1 else { return padL }
            return padL + CGFloat(i) / CGFloat(samples.count - 1) * plotW
        }
        func y(_ v: Double) -> CGFloat { padT + plotH - CGFloat((v - yMin) / (yMax - yMin)) * plotH }

        return ZStack(alignment: .topLeading) {
            ForEach([80, 100, 120, 140], id: \.self) { v in
                Path { p in
                    let yy = y(Double(v))
                    p.move(to: CGPoint(x: padL, y: yy))
                    p.addLine(to: CGPoint(x: padL + plotW, y: yy))
                }
                .stroke(Color.drip.divider, lineWidth: 0.4)
                Text("\(v)")
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
                    .monospacedDigit()
                    .frame(width: padL - 6, alignment: .trailing)
                    .offset(x: 0, y: y(Double(v)) - 6)
            }
            if samples.count > 29 {
                Path { p in
                    p.move(to: CGPoint(x: x(29), y: padT))
                    p.addLine(to: CGPoint(x: x(29), y: padT + plotH))
                }
                .stroke(Color.drip.coral.opacity(0.6),
                        style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
                Text("60s").font(.dripCaption(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.coral)
                    .offset(x: x(29) + 4, y: padT + 2)
            }
            Path { p in
                guard !samples.isEmpty else { return }
                p.move(to: CGPoint(x: x(0), y: y(samples[0])))
                for i in 1 ..< samples.count {
                    p.addLine(to: CGPoint(x: x(i), y: y(samples[i])))
                }
            }
            .stroke(Color.drip.coral,
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Mile small-multiples ────────────────────────────────────────

struct DripMileSparklines: View {
    let hrSamples: [Double]
    let splits: [(mile: Int, paceText: String, hr: Int, paceSec: Int, isFastest: Bool)]

    private func slice(forMile idx: Int) -> [Double] {
        let n = max(1, hrSamples.count / max(splits.count, 1))
        let start = idx * n
        let end = min(start + n, hrSamples.count)
        return Array(hrSamples[start ..< end])
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(splits.indices, id: \.self) { idx in
                let s = splits[idx]
                let series = slice(forMile: idx)
                VStack(spacing: 2) {
                    Text("\(s.mile)")
                        .font(.dripCaption(8))
                        .tracking(1.0)
                        .foregroundStyle(s.isFastest ? Color.drip.coral : Color.drip.textTertiary)
                    GeometryReader { g in
                        sparkline(geo: g, series: series, isFastest: s.isFastest)
                    }
                    .frame(height: 28)
                    Text(s.paceText)
                        .font(.dripCaption(10))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(s.isFastest ? Color.drip.coral : Color.drip.textPrimary)
                    Text("\(s.hr)")
                        .font(.dripCaption(8))
                        .monospacedDigit()
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.drip.divider).frame(height: 1)
                }
            }
        }
    }

    private func sparkline(geo g: GeometryProxy, series: [Double], isFastest: Bool) -> some View {
        let lo = 100.0, hi = 165.0
        func x(_ i: Int) -> CGFloat {
            guard series.count > 1 else { return 0 }
            return CGFloat(i) / CGFloat(series.count - 1) * g.size.width
        }
        func y(_ v: Double) -> CGFloat {
            g.size.height - CGFloat((v - lo) / (hi - lo)) * g.size.height
        }
        return Path { p in
            guard !series.isEmpty else { return }
            p.move(to: CGPoint(x: x(0), y: y(series[0])))
            for i in 1 ..< series.count {
                p.addLine(to: CGPoint(x: x(i), y: y(series[i])))
            }
        }
        .stroke(isFastest ? Color.drip.coral : Color.drip.textSecondary,
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Time-in-zone histogram row ──────────────────────────────────

struct DripTimeInZoneRow: View {
    let id: String
    let seconds: TimeInterval
    let totalSeconds: TimeInterval
    let isPrimary: Bool

    private var pct: Double { totalSeconds > 0 ? (seconds / totalSeconds) * 100 : 0 }
    private var minSec: String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(id).font(.dripCaption(9)).tracking(1.2)
                .foregroundStyle(isPrimary ? Color.drip.textPrimary : Color.drip.textSecondary)
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.drip.paperDeep).frame(height: 6)
                    Rectangle()
                        .fill(isPrimary ? Color.drip.coral : Color.drip.textSecondary)
                        .opacity(isPrimary ? 1.0 : 0.5)
                        .frame(width: geo.size.width * CGFloat(pct / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text(minSec).font(.dripCaption(12)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(isPrimary ? Color.drip.coral : Color.drip.textSecondary)
                .frame(width: 56, alignment: .trailing)
            Text("\(Int(pct.rounded()))%")
                .font(.dripCaption(9)).tracking(1.2).monospacedDigit()
                .foregroundStyle(isPrimary ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

// MARK: - Split row ───────────────────────────────────────────────────

struct DripSplitRow: View {
    let index: Int
    let distanceMi: Double
    let paceSec: Int
    let paceText: String
    let hr: Int?
    let cadence: Int?
    let fastest: Bool
    let slowest: Bool
    let maxPaceSec: Int
    let minPaceSec: Int

    private var barFraction: CGFloat {
        guard maxPaceSec > minPaceSec else { return 0.5 }
        let t = Double(maxPaceSec - paceSec) / Double(maxPaceSec - minPaceSec)
        return CGFloat(0.25 + 0.75 * t)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)").font(.dripCaption(9)).tracking(1.2)
                .foregroundStyle(fastest ? Color.drip.coral : Color.drip.textTertiary)
                .frame(width: 20, alignment: .trailing)
            HStack(spacing: 6) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(fastest ? Color.drip.coral
                              : slowest ? Color.drip.textTertiary : Color.drip.textSecondary)
                        .opacity(fastest ? 1 : slowest ? 0.5 : 0.85)
                        .frame(width: geo.size.width * barFraction, height: 4)
                }
                .frame(height: 4)
                Text(String(format: "%.2fmi", distanceMi))
                    .font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(paceText).font(.dripCaption(13)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(fastest ? Color.drip.coral : Color.drip.textPrimary)
                .frame(width: 50, alignment: .trailing)
            Text(hr.map(String.init) ?? "—").font(.dripCaption(12)).monospacedDigit()
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 36, alignment: .trailing)
            Text(cadence.map(String.init) ?? "—").font(.dripCaption(12)).monospacedDigit()
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

// MARK: - Comparison row (this vs recent avg) ─────────────────────────

struct DripComparisonRow: View {
    let label: String
    let nowText: String          // pre-formatted
    let thenText: String
    let nowNorm: Double          // 0…1 for bar length
    let thenNorm: Double         // 0…1
    let pctDelta: Double         // e.g. +4.2 or −3.1
    let better: Bool             // colors the delta

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text("\(pctDelta >= 0 ? "+" : "")\(String(format: "%.1f", pctDelta))%")
                    .font(.dripCaption(9)).tracking(1.2).monospacedDigit()
                    .foregroundStyle(better ? Color.drip.energized : Color.drip.coral)
            }
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    GeometryReader { g in
                        Rectangle().fill(Color.drip.coral)
                            .frame(width: g.size.width * CGFloat(nowNorm), height: 8)
                    }
                    .frame(height: 8)
                    Text(nowText).font(.dripCaption(12)).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(Color.drip.coral)
                        .frame(width: 56, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    GeometryReader { g in
                        Rectangle().fill(Color.drip.textTertiary).opacity(0.5)
                            .frame(width: g.size.width * CGFloat(thenNorm), height: 8)
                    }
                    .frame(height: 8)
                    Text(thenText).font(.dripCaption(12)).monospacedDigit()
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.drip.coral).frame(width: 5, height: 5)
                    Text("TODAY").font(.dripCaption(8)).tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.drip.textTertiary).frame(width: 5, height: 5)
                    Text("4W AVG").font(.dripCaption(8)).tracking(1.0)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

// MARK: - Hero stat block ─────────────────────────────────────────────

struct DripHeroStatBlock: View {
    let label: String
    let value: String
    let sub: String?
    var coral: Bool = false
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label).font(.dripCaption(9)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
            // Auto-shrink aggressively so longer values fit the narrow
            // middle cell on phones — e.g. `1:02:16` for the TIME cell on
            // workouts over an hour. Floor of 0.5 lets a 7-char value
            // come down to ~18pt without truncating.
            Text(value).font(.dripCaption(36)).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(coral ? Color.drip.coral : Color.drip.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let sub {
                Text(sub).font(.dripCaption(9)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .padding(.vertical, 14)
    }
}
