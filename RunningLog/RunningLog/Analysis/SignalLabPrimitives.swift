//
//  SignalLabPrimitives.swift
//  RunningLog · Analysis
//
//  The pieces every Signal Lab chart is assembled from: the card container the
//  design system does not otherwise have, the one-line readout, the legend
//  chip, and the shared Canvas drawing helpers.
//
//  Split out from `SignalLabCharts.swift` so neither file passes the 500-line
//  lint warning, and so a future chart can be added without reading the four
//  that already exist.
//

import SwiftUI

// MARK: - Card

/// The card wrapper every Lab chart sits in.
///
/// The app has no `DripCard`; four Trends surfaces each re-inline the same
/// three modifiers by hand. This is that shape, named once. It is deliberately
/// scoped to the Lab rather than promoted to `DesignSystem.swift` — promoting
/// it means auditing and migrating those four call sites, which is its own
/// change with its own diff.
struct LabCard<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

/// The one-line readout above every Lab chart. Idle it states the series;
/// scrubbed it states the point. Same slot either way.
struct LabReadout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.dripEyebrow(9.5))
            .tracking(0.7)
            .foregroundStyle(Color.drip.textTertiary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.12), value: text)
    }
}

/// A legend chip. Identity is never carried by colour alone — every chip pairs
/// its swatch with a word.
struct LabLegendChip: View {
    let color: Color
    let label: String
    var hollow: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(hollow ? Color.drip.cardBackground : color)
                .overlay(Circle().stroke(hollow ? color : Color.clear, lineWidth: 1))
                .frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(.dripEyebrow(8.5))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Shared drawing helpers

enum LabDraw {
    static func label(_ ctx: GraphicsContext, _ text: String, at point: CGPoint, anchor: UnitPoint) {
        ctx.draw(
            Text(text)
                .font(.dripEyebrow(8.5))
                .foregroundStyle(Color.drip.textTertiary),
            at: point,
            anchor: anchor
        )
    }

    static func gridline(_ ctx: GraphicsContext, y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y.rounded() + 0.5))
        p.addLine(to: CGPoint(x: x1, y: y.rounded() + 0.5))
        ctx.stroke(p, with: .color(Color.drip.divider), lineWidth: 1)
    }

    /// A dashed fitted line. Dashed on purpose: a solid line reads as data,
    /// and this is a claim about the data.
    static func trend(
        _ ctx: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color
    ) {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
    }

    /// A data dot with a surface ring, so overlapping marks stay countable.
    static func dot(
        _ ctx: GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        fill: Color,
        emphasised: Bool = false
    ) {
        let rect = CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        )
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(
            Path(ellipseIn: rect),
            with: .color(Color.drip.cardBackground),
            lineWidth: emphasised ? 2 : 0.8
        )
    }
}

