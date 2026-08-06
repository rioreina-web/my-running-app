//
//  AskComponents.swift
//  RunningLog · Analysis
//
//  The pieces an Ask answer is made of. Post Run Drip: warm paper, black ink,
//  one coral accent used like punctuation.
//
//  Design rules enforced here rather than left to callers:
//    • Coral is a punctuation mark, not a paint — at most one coral element
//      per card, and it is the "computed" badge. Fact tones use the mood
//      palette (positive / tired), never coral. The three-palette rule
//      (blue = pace, warm = mood, coral = alert) holds.
//    • A fact renders exactly what the server sent. No client-side rounding,
//      no unit inference, no recomputation. If a number is not in `facts`,
//      it does not exist.
//    • Coverage renders under every answer, not only weak ones.
//

import SwiftUI

// MARK: - Chip

/// The rail's unit. Mono, pill, hairline — same vocabulary as the Read's
/// evidence chips, so the two surfaces read as one product.
struct AskChip: View {
    let label: String
    var emphasis: Emphasis = .standard
    var isDisabled: Bool = false
    let action: () -> Void

    enum Emphasis {
        /// Standing rail — a question the athlete can always ask.
        case standard
        /// A follow-up the previous answer emitted.
        case followup
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.dripEyebrow(10))
                .tracking(0.5)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isDisabled ? Color.drip.textTertiary : Color.drip.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        emphasis == .followup ? Color.drip.coralWash : Color.drip.cardBackground
                    )
                )
                .overlay(
                    Capsule().stroke(
                        emphasis == .followup
                            ? Color.drip.coral.opacity(0.35)
                            : Color.drip.divider,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Group header

struct AskGroupHeader: View {
    let title: String
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.dripEyebrow(10))
                    .tracking(1.2)
                Image(systemName: isOpen ? "minus" : "plus")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(isOpen ? Color.drip.background : Color.drip.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isOpen ? Color.drip.textPrimary : Color.clear))
            .overlay(
                Capsule().strokeBorder(
                    isOpen ? Color.clear : Color.drip.divider,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fact grid

struct AskFactGrid: View {
    let facts: [AskFact]

    private var columns: [GridItem] {
        facts.count == 1
            ? [GridItem(.flexible(), spacing: 1)]
            : [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(facts) { fact in
                AskFactCell(fact: fact)
            }
        }
        .background(Color.drip.divider)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }
}

struct AskFactCell: View {
    let fact: AskFact

    /// Mood palette, never coral — coral is reserved for the one accent per
    /// card. `nil` for neutral so the value sits in plain ink.
    private var deltaColor: Color {
        switch fact.tone {
        case .good: return Color.drip.positive
        case .watch: return Color.drip.tired
        default: return Color.drip.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fact.value)
                    .font(.dripStat(20))
                    .foregroundStyle(Color.drip.textPrimary)
                if let unit = fact.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                if let delta = fact.delta, !delta.isEmpty {
                    Text(delta)
                        .font(.dripStat(11))
                        .foregroundStyle(deltaColor)
                        .padding(.leading, 2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(fact.label.uppercased())
                .font(.dripEyebrow(8))
                .tracking(0.9)
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.drip.cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.label): \(fact.value)\(fact.unit ?? "")\(fact.delta.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Coverage

/// "9 sessions · 63 days · 2 without HR" plus the confidence tier. Always
/// present. This is what separates an analytical surface from a guessing one.
struct AskCoverageRow: View {
    let coverage: AskCoverage

    private var summary: String {
        var parts = [
            "\(coverage.sessionsUsed) \(coverage.sessionsUsed == 1 ? "session" : "sessions")",
            "\(coverage.windowDays) days",
        ]
        parts.append(contentsOf: coverage.missing)
        return parts.joined(separator: " · ")
    }

    private var tierColor: Color {
        switch coverage.confidence {
        case .high: return Color.drip.positive
        case .moderate: return Color.drip.tired
        case .low: return Color.drip.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Text(summary.uppercased())
                    .font(.dripEyebrow(8.5))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(coverage.confidence.rawValue.uppercased()) CONF")
                    .font(.dripEyebrow(8))
                    .tracking(0.9)
                    .foregroundStyle(tierColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tierColor.opacity(0.13)))
                    .fixedSize()
            }
            .padding(.top, 11)
        }
    }
}

// MARK: - Chart

/// Renders an analyzer's `SeriesSpec`. Deliberately plain: this chart exists
/// to show the shape behind the facts, not to be explored. Tapping, scrubbing
/// and legends belong to Trends.
///
/// `invertY` matters — for a pace series lower is faster, so the axis flips
/// and an improving athlete's line rises. Getting this backwards would make
/// every pace chart in the surface read as a decline.
struct AskChart: View {
    let series: AskSeries

    private var values: [Double] { series.points.map(\.y) }
    private var secondary: [Double] { series.points.compactMap(\.y2) }
    private var hasSecondary: Bool { secondary.count == series.points.count && series.points.count > 1 }

    private var bounds: (lo: Double, hi: Double) {
        var all = values
        if hasSecondary { all += secondary }
        if let band = series.band, band.count == 2 { all += band }
        guard let min = all.min(), let max = all.max() else { return (0, 1) }
        if min == max { return (min - 1, max + 1) }
        let pad = (max - min) * 0.12
        return (min - pad, max + pad)
    }

    var body: some View {
        Canvas { context, size in
            guard series.points.count > 1 else { return }
            let (lo, hi) = bounds
            let span = hi - lo
            guard span > 0 else { return }

            let inset: CGFloat = 4
            let plotWidth = size.width - inset * 2
            let plotHeight = size.height

            func x(_ i: Int) -> CGFloat {
                inset + plotWidth * CGFloat(i) / CGFloat(series.points.count - 1)
            }
            func y(_ v: Double) -> CGFloat {
                let t = (v - lo) / span
                // invertY: lower value (faster pace) sits higher on screen.
                let normalized = series.isInverted ? t : 1 - t
                return plotHeight * (1 - normalized)
            }

            if let band = series.band, band.count == 2 {
                let y1 = y(band[0]), y2 = y(band[1])
                let rect = CGRect(
                    x: inset,
                    y: Swift.min(y1, y2),
                    width: plotWidth,
                    height: Swift.abs(y1 - y2)
                )
                context.fill(Path(rect), with: .color(Color.drip.paceFast.opacity(0.10)))
            }

            switch series.kind {
            case .bar:
                let slot = plotWidth / CGFloat(series.points.count)
                for (i, point) in series.points.enumerated() {
                    let barX = inset + slot * CGFloat(i) + slot * 0.2
                    let top = y(point.y)
                    let rect = CGRect(
                        x: barX,
                        y: top,
                        width: slot * 0.6,
                        height: Swift.max(1, plotHeight - top)
                    )
                    let isLast = i == series.points.count - 1
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .color(isLast ? Color.drip.coral : Color.drip.paceFast.opacity(0.55))
                    )
                }

            case .line:
                if hasSecondary {
                    var path = Path()
                    for (i, point) in series.points.enumerated() {
                        guard let v = point.y2 else { continue }
                        let p = CGPoint(x: x(i), y: y(v))
                        i == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                    context.stroke(
                        path,
                        with: .color(Color.drip.textTertiary),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                    )
                }

                var path = Path()
                for (i, point) in series.points.enumerated() {
                    let p = CGPoint(x: x(i), y: y(point.y))
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                context.stroke(
                    path,
                    with: .color(Color.drip.paceFast),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                for (i, point) in series.points.enumerated() {
                    let isLast = i == series.points.count - 1
                    let r: CGFloat = isLast ? 4 : 2.5
                    let rect = CGRect(x: x(i) - r, y: y(point.y) - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(isLast ? Color.drip.coral : Color.drip.paceFast)
                    )
                }
            }
        }
        .frame(height: 96)
        .accessibilityLabel("Chart of \(series.points.count) points")
        .accessibilityHidden(series.points.count < 2)
    }
}

/// x-axis: first, middle and last label only. A dense axis fights the facts
/// for attention and the facts are the answer.
struct AskChartAxis: View {
    let series: AskSeries

    private var marks: [String] {
        let xs = series.points.map(\.x)
        guard xs.count > 2 else { return xs }
        return [xs[0], xs[xs.count / 2], xs[xs.count - 1]]
    }

    var body: some View {
        HStack {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                Text(mark.uppercased())
                    .font(.dripEyebrow(8))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
                if index < marks.count - 1 { Spacer() }
            }
        }
    }
}
