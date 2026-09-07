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
///
/// When a scrubbed point can be opened, the readout grows an `OPEN` affordance
/// on its trailing edge. Ink and underline rather than coral: coral is the
/// alert palette, and on the drift chart it is already spent on the
/// over-the-band marks — a second coral element in the same cluster would
/// compete with the one that means something. Underlined ink is the same
/// openable-thing signal `TrendsPaceBandsView` already uses for session dates.
struct LabReadout: View {
    let text: String
    /// Supplied only when something is selected AND that something resolves to
    /// a workout. Absent, the slot renders exactly as it did before.
    var onOpen: (() -> Void)?

    init(text: String, onOpen: (() -> Void)? = nil) {
        self.text = text
        self.onOpen = onOpen
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text)
                .font(.dripEyebrow(9.5))
                .tracking(0.7)
                .foregroundStyle(Color.drip.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onOpen {
                Button(action: onOpen) {
                    Text("OPEN ↗")
                        .font(.dripEyebrow(9))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textPrimary)
                        .underline(true, color: Color.drip.textTertiary)
                }
                .buttonStyle(.plain)
                // The tap target is the word; give it the 44pt height the rest
                // of the app honours without moving the baseline.
                .contentShape(Rectangle().inset(by: -12))
                .accessibilityLabel("Open this workout")
            }
        }
        .animation(.easeInOut(duration: 0.12), value: text)
        .animation(.easeInOut(duration: 0.12), value: onOpen == nil)
    }
}

// MARK: - Scrubbing

/// The scrub gesture every Lab chart shares.
///
/// Three deliberate choices, each fixing something the hand-rolled per-chart
/// gestures got wrong:
///
/// 1. **Tap resolves at zero distance.** Selecting a point never requires a
///    drag. The old charts sat behind `DragGesture(minimumDistance: 12)`, so
///    the first 12 points of every gesture were dead and the mark appeared to
///    jump out of nowhere. A `SpatialTapGesture` also cannot compete with the
///    enclosing `ScrollView`, which is what the 12pt threshold was really
///    there to protect.
///
/// 2. **The axis is decided once per drag, not per frame.** The old guard
///    re-tested `|dx| >= |dy|` on every change, so a finger that wandered
///    vertically mid-sweep silently stopped scrubbing and then resumed —
///    the "it keeps losing me" feel. Here the decision is latched on the
///    first movement with enough signal to be meaningful, and held for the
///    rest of that drag.
///
/// 3. **Selection survives the finger lifting.** Otherwise there is nothing
///    to aim the OPEN affordance at. Tapping the selected point clears it.
///
/// Haptics come from `.sensoryFeedback(.selection:)` keyed on the selection
/// itself, matching `TrendsSignalLanes`. Driving them off the value rather
/// than firing inside the gesture handler means a point can only ever buzz
/// once per crossing, however many touch events the crossing spanned.
private struct LabScrubModifier<Key: Hashable>: ViewModifier {
    let width: CGFloat
    @Binding var selection: Key?
    let resolve: (CGFloat, CGFloat) -> Key?

    /// `nil` before this drag has committed to an axis, then latched.
    @State private var horizontal: Bool?

    /// Movement, in points, before the axis question is answerable. Below this
    /// a drag is mostly noise and guessing an axis from it is how a scrub
    /// steals a scroll.
    private let axisDecisionThreshold: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let key = resolve(value.location.x, width) else { return }
                        selection = (selection == key) ? nil : key
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if horizontal == nil {
                            let dx = abs(value.translation.width)
                            let dy = abs(value.translation.height)
                            guard max(dx, dy) >= axisDecisionThreshold else { return }
                            horizontal = dx > dy
                        }
                        guard horizontal == true else { return }
                        guard let key = resolve(value.location.x, width) else { return }
                        if selection != key { selection = key }
                    }
                    .onEnded { _ in horizontal = nil }
            )
            .sensoryFeedback(.selection, trigger: selection)
    }
}

extension View {
    /// Attach the shared Lab scrub gesture. `resolve` maps an x position (and
    /// the plot width) to whatever key the chart selects by — an index for the
    /// evenly-spaced charts, a session id for the date-scaled one.
    func labScrub<Key: Hashable>(
        width: CGFloat,
        selection: Binding<Key?>,
        resolve: @escaping (CGFloat, CGFloat) -> Key?
    ) -> some View {
        modifier(LabScrubModifier(width: width, selection: selection, resolve: resolve))
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

    /// The vertical rule under the scrubbed point.
    ///
    /// Dashed and tertiary so it reads as a pointer rather than as another
    /// series — the same reason `trend` is dashed. Drawn before the marks so
    /// the dots sit on top of it.
    static func crosshair(_ ctx: GraphicsContext, x: CGFloat, from y0: CGFloat, to y1: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x.rounded() + 0.5, y: y0))
        p.addLine(to: CGPoint(x: x.rounded() + 0.5, y: y1))
        ctx.stroke(
            p,
            with: .color(Color.drip.textTertiary.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
        )
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

