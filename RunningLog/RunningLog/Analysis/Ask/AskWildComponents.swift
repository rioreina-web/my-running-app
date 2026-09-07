//
//  AskWildComponents.swift
//  RunningLog · Analysis · Ask
//
//  Direction I parts for the Ask tab. Hairlines, one red, tabular figures,
//  no cards and no shadows — `POSTRUNDRIPSYSTEM.md` §4: "Hairlines replace
//  cards, tints and shadows. Depth is not part of this brand."
//
//  The one tint in here is `paperDeep` behind the pull editor, which the doc
//  allows for an inset well. Everything else separates on a 1pt rule.
//
//  CHARTS ARE HAND-DRAWN, not Swift Charts. Three reasons: the marks are two
//  colours and one dash and nothing more, the axis has to stay off (the
//  figure above it already carries the number), and a self-normalising axis
//  is the bug this app has shipped before — a chart that rescales with its
//  own bars shows no change at all. Drawing the path keeps the domain
//  explicit and visible in one place.
//

import SwiftUI

// MARK: - Chip

/// A pill in the label face. `min-height: 0` is deliberate: Direction I sets
/// a 44pt minimum on every button, and a chip that obeys it inflates into an
/// oval. The chip keeps its lozenge and the RAIL carries the hit target.
struct WildChip: View {
    let title: String
    var selected: Bool = false
    var tinted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.wildLabel(9))
                .tracking(9 * 0.16)
                .foregroundStyle(selected ? Color.wild.paper
                                 : (tinted ? Color.wild.redText : Color.wild.ink2))
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 7)
                .background(
                    Capsule().fill(selected ? Color.wild.ink : Color.clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? Color.wild.ink : (tinted ? Color.wild.red : Color.wild.rule),
                        lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 0)
    }
}

/// The 44pt rail chips sit in, so the finger still has a target even though
/// each lozenge is shorter than that.
struct WildChipRail<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(minHeight: 44, alignment: .leading)
    }
}

// MARK: - Charts

private func domain(_ values: [Double], includingGhost ghost: Double?) -> (lo: Double, hi: Double) {
    var all = values
    if let ghost { all.append(ghost) }
    guard var lo = all.min(), var hi = all.max() else { return (0, 1) }
    if hi == lo { hi += 1; lo -= 1 }
    let pad = (hi - lo) * 0.22
    return (lo - pad, hi + pad)
}

/// Line. The last point carries the one red dot; the dashed line is whatever
/// the pull is comparing against.
///
/// The y-mapping lives on the struct rather than inside the `GeometryReader`
/// closure: a `func` declared inside a `@ViewBuilder` closure will not
/// compile, and hoisting it also keeps the domain in one readable place.
struct AskSparkline: View {
    let values: [Double]
    var ghost: Double?
    var height: CGFloat = 34

    private func y(_ v: Double, in h: CGFloat) -> CGFloat {
        let d = domain(values, includingGhost: ghost)
        return h - CGFloat((v - d.lo) / (d.hi - d.lo)) * h
    }

    private func path(in size: CGSize) -> Path {
        var p = Path()
        let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : size.width
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * stepX, y: y(v, in: size.height))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let ghost {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(ghost, in: geo.size.height)))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y(ghost, in: geo.size.height)))
                    }
                    .stroke(Color.wild.ink3, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
                path(in: geo.size)
                    .stroke(Color.wild.red, style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
                if let last = values.last {
                    Circle()
                        .fill(Color.wild.red)
                        .frame(width: 6, height: 6)
                        .position(x: geo.size.width, y: y(last, in: geo.size.height))
                }
            }
        }
        .frame(height: height)
    }
}

/// Bars. The most recent bar is the red one; a zero week draws as a hairline
/// tick rather than vanishing, because "no threshold work" is a reading.
struct AskMiniBars: View {
    let values: [Double]
    var ghost: Double?
    var height: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let hi = max((values.max() ?? 1), ghost ?? 0) * 1.1
            let bw = values.isEmpty ? w : w / CGFloat(values.count)
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let barH = hi > 0 ? CGFloat(v / hi) * h : 0
                    Rectangle()
                        .fill(i == values.count - 1 ? Color.wild.red : Color(hex: "E2E2E2"))
                        .frame(width: bw * 0.68, height: max(barH, 1))
                        .offset(x: CGFloat(i) * bw + bw * 0.16, y: 0)
                }
                if let ghost, hi > 0 {
                    Path { p in
                        let gy = h - CGFloat(ghost / hi) * h
                        p.move(to: CGPoint(x: 0, y: gy))
                        p.addLine(to: CGPoint(x: w, y: gy))
                    }
                    .stroke(Color.wild.ink, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
            }
        }
        .frame(height: height)
    }
}

/// Dots. For a metric that is a reading per week rather than a flow.
struct AskMiniDots: View {
    let values: [Double]
    var height: CGFloat = 34

    private func y(_ v: Double, in h: CGFloat) -> CGFloat {
        let d = domain(values, includingGhost: nil)
        return h - CGFloat((v - d.lo) / (d.hi - d.lo)) * h
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.wild.rule, lineWidth: 1)

                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let last = i == values.count - 1
                    let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : geo.size.width
                    Circle()
                        .fill(last ? Color.wild.red : Color.wild.paper)
                        .overlay(Circle().strokeBorder(last ? Color.wild.red : Color.wild.ink3, lineWidth: 1.2))
                        .frame(width: last ? 8 : 6, height: last ? 8 : 6)
                        .position(x: CGFloat(i) * stepX, y: y(v, in: geo.size.height))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Pull block

struct AskPullBlock: View {
    let reading: AskPullReading
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onOpenEditor: () -> Void
    let onAsk: () -> Void
    let onChange: (AskPull) -> Void
    let onMove: (Bool) -> Void
    let onRemove: () -> Void
    let onDone: () -> Void

    private var pull: AskPull { reading.pull }
    private var values: [Double] { reading.points.map(\.value) }

    private var toneColor: Color {
        switch reading.tone {
        case .good:  return Color.wild.positive
        case .watch: return Color.wild.tired
        case .flat:  return Color.wild.ink2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            figureRow
            if pull.chart != .figure, values.count > 1 { chart.padding(.top, 10) }

            if let caveat = reading.caveat, isEditing {
                Text(caveat)
                    .font(.wildMachine(11))
                    .foregroundStyle(Color.wild.tired)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            footer
            if isEditing { editor.padding(.top, 16) }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onAsk() } }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isEditing ? Color.wild.red : Color.wild.rule)
                .frame(height: isEditing ? 2 : 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pull.name)
                    .font(.wildDisplay(16.5))
                    .tracking(16.5 * -0.03)
                    .foregroundStyle(Color.wild.ink)
                WildLabel("\(pull.window.label) · vs \(pull.compare.label)", size: 9, tracking: 0.20)
            }
            Spacer(minLength: 8)
            Button(action: onOpenEditor) {
                Text("···")
                    .font(.wildData(15, semibold: true))
                    .foregroundStyle(Color.wild.ink2)
                    .frame(width: 34, height: 30, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(pull.name)")
        }
    }

    private var figureRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(reading.figure)
                .font(.wildData(23, semibold: true))
                .monospacedDigit()
                .tracking(23 * -0.02)
                .foregroundStyle(Color.wild.ink)
            if !pull.metric.unit.isEmpty {
                Text(pull.metric.unit)
                    .font(.wildData(11))
                    .foregroundStyle(Color.wild.ink2)
            }
            Spacer(minLength: 8)
            Text(reading.deltaText)
                .font(.wildData(11))
                .monospacedDigit()
                .foregroundStyle(toneColor)
        }
        .padding(.top, 9)
    }

    @ViewBuilder private var chart: some View {
        switch pull.chart {
        case .line:   AskSparkline(values: values, ghost: reading.ghost)
        case .bars:   AskMiniBars(values: values, ghost: reading.ghost)
        case .dots:   AskMiniDots(values: values)
        case .figure: EmptyView()
        }
    }

    /// Provenance only. There used to be an "ask about this ›" button here,
    /// which was a second way to do what tapping the block already does.
    private var footer: some View {
        WildLabel(reading.source, size: 9, tracking: 0.18)
            .lineLimit(1)
            .padding(.top, 9)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionRow("Metric", AskMetric.allCases, current: pull.metric, label: \.short) { m in
                var p = pull
                p.metric = m
                // Renaming follows the metric unless the athlete has renamed
                // it themselves — their word beats ours.
                if p.name == pull.metric.short { p.name = m.short }
                onChange(p)
            }
            optionRow("Window", AskWindow.allCases, current: pull.window, label: \.label) { w in
                var p = pull; p.window = w; onChange(p)
            }
            optionRow("Compare to", AskCompare.allCases, current: pull.compare, label: \.label) { c in
                var p = pull; p.compare = c; onChange(p)
            }
            optionRow("Chart", AskPullChart.allCases, current: pull.chart, label: \.label) { c in
                var p = pull; p.chart = c; onChange(p)
            }

            VStack(alignment: .leading, spacing: 8) {
                WildLabel("Name", size: 9, tracking: 0.20)
                TextField("Name", text: Binding(
                    get: { pull.name },
                    set: { var p = pull; p.name = $0; onChange(p) }))
                    .font(.wildDisplay(16))
                    .foregroundStyle(Color.wild.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.wild.paper)
                    .overlay(Rectangle().strokeBorder(Color.wild.rule, lineWidth: 1))
            }

            HStack(spacing: 8) {
                moveButton(up: true, enabled: canMoveUp)
                moveButton(up: false, enabled: canMoveDown)
                Button(action: onRemove) {
                    Text("REMOVE PULL")
                        .font(.wildLabel(9))
                        .tracking(9 * 0.18)
                        .foregroundStyle(Color.wild.redText)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color.wild.red, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 0)
                Spacer()
                Button(action: onDone) {
                    Text("DONE")
                        .font(.wildLabel(9))
                        .tracking(9 * 0.18)
                        .foregroundStyle(Color.wild.paper)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.wild.ink))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 0)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.wild.paperDeep)
    }

    private func moveButton(up: Bool, enabled: Bool) -> some View {
        Button { onMove(up) } label: {
            Text(up ? "↑" : "↓")
                .font(.wildData(12, semibold: true))
                .foregroundStyle(Color.wild.ink2)
                .frame(width: 32, height: 30)
                .overlay(Rectangle().strokeBorder(Color.wild.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 0)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(up ? "Move up" : "Move down")
    }

    private func optionRow<T: Identifiable & Equatable>(
        _ title: String,
        _ options: [T],
        current: T,
        label: KeyPath<T, String>,
        onPick: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WildLabel(title, size: 9, tracking: 0.20)
            WildChipRail {
                FlowRow(spacing: 5) {
                    ForEach(options) { opt in
                        WildChip(title: opt[keyPath: label], selected: opt == current) {
                            onPick(opt)
                        }
                    }
                }
            }
        }
    }
}
