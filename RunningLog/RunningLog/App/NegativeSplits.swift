//
//  NegativeSplits.swift
//  RunningLog
//
//  Design system extension — "Negative Splits" aesthetic.
//
//  Restraint as foundation, intensity as accent.
//  Designed to coexist with and extend the existing `Color.drip` / `Font.drip`
//  system in DesignSystem.swift. All components here are additive — adopt them
//  per-screen as you migrate.
//
//  Naming: every component is prefixed `NS` (Negative Splits) so it's
//  unambiguous in the call site whether you're using the old or new system.
//
//  Migration pattern (per screen):
//   1. Replace card containers with NSCard or hairline-only sections.
//   2. Replace stat groups with NSStatStrip.
//   3. Replace KPI cards with NSKPITile.
//   4. Replace any "list of phases / steps" with NSTimelineStep.
//   5. Use NSEyebrow + Display headings instead of section titles inside cards.
//   6. Replace SF Symbol arrows in toggles/links with NSCaret / NSArrowUpRight.
//

import SwiftUI

// MARK: - Tokens

enum NSSpace {
    static let pagePadding: CGFloat = 20
    static let sectionGap: CGFloat = 32
    static let stackGap: CGFloat = 12
    static let inlineGap: CGFloat = 8
    static let hairline: CGFloat = 1
}

enum NSRadius {
    static let card: CGFloat = 14
    static let chip: CGFloat = 10
}

extension Color {
    /// Negative Splits semantic helpers built on the existing `Color.drip` palette.
    /// Pure aliases — no new hex values introduced.
    enum ns {
        static var paper:        Color { Color.drip.background }
        static var card:         Color { Color.drip.cardBackground }
        static var ink:          Color { Color.drip.textPrimary }
        static var slate:        Color { Color.drip.textSecondary }
        static var slateLight:   Color { Color.drip.textTertiary }
        static var hair:         Color { Color.drip.divider }
        static var amber:        Color { Color.drip.coral }       // accent
        static var greenOk:      Color { Color.drip.energized }   // positive delta
    }
}

extension Font {
    /// Mono caps eyebrow label — section headers, KPI labels, metadata.
    static func nsMono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    /// Italic serif annotation — quiet quotes, footnotes, captions.
    /// Uses system New York Italic so it works whether or not CrimsonPro-Italic
    /// is bundled. If you bundle CrimsonPro-Italic and want to use it, swap
    /// the body for: `.custom("CrimsonPro-Italic", size: size)`.
    static func nsAnnotation(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif).italic()
    }
}

// MARK: - Hairline

/// 1pt rule, full width by default. The workhorse divider.
struct NSHairline: View {
    var color: Color = .ns.hair
    var thickness: CGFloat = NSSpace.hairline
    var body: some View {
        Rectangle().fill(color).frame(height: thickness)
    }
}

// MARK: - Eyebrow

/// Small mono caps label that sits above titles or sections.
/// Usage: `NSEyebrow("WORKOUT · 3 STEPS")`
struct NSEyebrow: View {
    let text: String
    var color: Color = .ns.slate
    var size: CGFloat = 11
    var tracking: CGFloat = 1.2

    init(_ text: String, color: Color = .ns.slate, size: CGFloat = 11, tracking: CGFloat = 1.2) {
        self.text = text
        self.color = color
        self.size = size
        self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased())
            .font(.nsMono(size))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Display number

/// Large serif numeral. Use for headline figures (volume, ACWR, predicted time).
struct NSDisplayNumber: View {
    let text: String
    var size: CGFloat = 48
    var color: Color = .ns.ink
    var body: some View {
        Text(text)
            .font(.dripDisplay(size))
            .foregroundStyle(color)
            .monospacedDigit()
    }
}

// MARK: - Stat strip (3-column, hairline-divided, no card chrome)

/// Three (or N) labelled stats separated by vertical hairlines.
/// Replaces three side-by-side card-style StatCards.
struct NSStatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let unit: String?
        let valueColor: Color
        init(label: String, value: String, unit: String? = nil, valueColor: Color = .ns.ink) {
            self.label = label; self.value = value; self.unit = unit; self.valueColor = valueColor
        }
    }
    let items: [Item]
    var valueSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                column(items[idx])
                if idx < items.count - 1 {
                    Rectangle().fill(Color.ns.hair).frame(width: 1, height: 64)
                }
            }
        }
    }

    private func column(_ item: Item) -> some View {
        VStack(spacing: 6) {
            NSEyebrow(item.label)
            NSDisplayNumber(text: item.value, size: valueSize, color: item.valueColor)
            if let unit = item.unit {
                NSEyebrow(unit, color: .ns.slateLight, size: 10)
            } else {
                // keep column heights matched
                Color.clear.frame(height: 14)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - KPI tile

/// A 4-corner KPI tile with eyebrow / big numeral / unit / colored sub-line.
/// Used for the Trends home page (Volume / Fitness / Load / Risk).
struct NSKPITile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var sub: String? = nil
    var subColor: Color = .ns.slate
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NSEyebrow(label)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                NSDisplayNumber(text: value, size: 44,
                                color: accent ? .ns.amber : .ns.ink)
                if let unit { NSEyebrow(unit, color: .ns.slate, size: 10) }
            }
            .padding(.top, 4)
            Spacer(minLength: 8)
            if let sub {
                NSEyebrow(sub, color: subColor, size: 10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 116)
        .background(Color.ns.paper)
        .overlay(
            RoundedRectangle(cornerRadius: NSRadius.card)
                .stroke(Color.ns.hair, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NSRadius.card))
    }
}

// MARK: - Section (eyebrow + content, no card)

/// A flat section with an eyebrow label, optional right-side accessory, and
/// a hairline divider above. Replaces SectionHeader when you don't want the
/// content to live inside a card.
struct NSSection<Content: View, Accessory: View>: View {
    let eyebrow: String
    let content: () -> Content
    let accessory: () -> Accessory

    init(_ eyebrow: String,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.eyebrow = eyebrow
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NSSpace.stackGap) {
            HStack {
                NSEyebrow(eyebrow)
                Spacer()
                accessory()
            }
            content()
        }
    }
}

// MARK: - Timeline step

/// A single node on a vertical timeline (warm-up / active / cool-down etc.).
/// Open circle for low-intensity / passive phases, filled accent circle for
/// the active / hard phase. Connect multiple steps via the `connector`
/// view modifier; or wrap them in `NSTimelineList` which handles the line.
struct NSTimelineStep: View {
    let title: String
    let distance: String
    let target: String          // e.g. "6:26 – 7:38 / mi"
    let zoneTag: String         // e.g. "EASY", "MP", "LT"
    let zoneColor: Color        // green for easy, amber for hard
    let note: String            // italic descriptor, e.g. "conversational pace"
    var subAnnotation: String? = nil  // small mono extra, e.g. "YOUR MP 5:32 · −1% TODAY"
    var filled: Bool = false

    private let nodeRadius: CGFloat = 11
    private let lineWidth: CGFloat = 1
    private let nodeColumn: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Node + connecting line column
            ZStack(alignment: .top) {
                // The connecting line is drawn by NSTimelineList around steps;
                // here we just draw the node.
                Circle()
                    .fill(filled ? zoneColor : Color.ns.paper)
                    .overlay(Circle().stroke(zoneColor, lineWidth: filled ? 0 : 2))
                    .frame(width: nodeRadius * 2, height: nodeRadius * 2)
                    .padding(.top, 4)
            }
            .frame(width: nodeColumn)

            // Body block
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.dripDisplay(22))
                        .foregroundStyle(zoneColor)
                    Spacer()
                    Text(distance)
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.ns.ink)
                }
                HStack(spacing: 10) {
                    NSEyebrow("TARGET", color: .ns.slate, size: 10)
                    Text(target)
                        .font(.nsMono(11))
                        .foregroundStyle(zoneColor)
                    Text("·")
                        .font(.nsMono(11))
                        .foregroundStyle(Color.ns.slate)
                    Text(zoneTag)
                        .font(.nsMono(11))
                        .foregroundStyle(zoneColor)
                }
                Text(note)
                    .font(.nsAnnotation(15))
                    .foregroundStyle(Color.ns.slate)
                if let subAnnotation {
                    Text(subAnnotation.uppercased())
                        .font(.nsMono(10))
                        .tracking(1.0)
                        .foregroundStyle(Color.ns.slateLight)
                }
            }
        }
    }
}

/// Vertical timeline list — draws the connecting hairline behind a stack
/// of `NSTimelineStep`s. Pass the steps via a closure for spacing control.
struct NSTimelineList<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var nodeColumn: CGFloat = 44
    var stepSpacing: CGFloat = 28

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Connecting line lives in the node column, behind the steps
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.ns.hair)
                        .frame(width: 1)
                        .padding(.vertical, 22) // inset so it doesn't bleed past first/last node
                }
                .frame(width: nodeColumn)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: stepSpacing) {
                content()
            }
        }
    }
}

// MARK: - Vector glyphs (font-independent)

/// Small downward caret (▾) drawn as a triangle. Pair next to dropdown-like labels.
struct NSCaretDown: View {
    var size: CGFloat = 8
    var color: Color = .ns.slate
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: size / 2, y: size * 0.7))
            p.closeSubpath()
        }
        .fill(color)
        .frame(width: size, height: size * 0.7)
    }
}

/// Diagonal up-right arrow (↗). Use for "share" / "open external" links.
struct NSArrowUpRight: View {
    var size: CGFloat = 12
    var color: Color = .ns.amber
    var lineWidth: CGFloat = 1.5
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size))
            p.addLine(to: CGPoint(x: size, y: 0))
            p.move(to: CGPoint(x: size * 0.4, y: 0))
            p.addLine(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: size, y: size * 0.6))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}

// MARK: - Toggle pill (compact, accent-on)

/// A compact iOS-style toggle styled to the NS accent.
/// Reads the existing system toggle for accessibility — just retints.
struct NSAccentToggle: View {
    @Binding var isOn: Bool
    var label: String? = nil
    var body: some View {
        let toggle = Toggle(isOn: $isOn) {
            if let label { NSEyebrow(label) }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color.ns.amber))

        if label == nil {
            toggle.labelsHidden()
        } else {
            toggle
        }
    }
}

// MARK: - Quiet error / link row

/// Restrained error annotation — italic serif sentence + tappable mono link.
/// Replaces filled-orange error blocks with an annotation-style treatment.
struct NSQuietError: View {
    let message: String
    let actionLabel: String
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("——").foregroundStyle(Color.ns.slateLight)
                Text(message)
                    .font(.nsAnnotation(15))
                    .foregroundStyle(Color.ns.slate)
            }
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(actionLabel.uppercased())
                        .font(.nsMono(11))
                        .tracking(1.0)
                        .foregroundStyle(Color.ns.amber)
                    NSArrowUpRight(size: 10, color: .ns.amber, lineWidth: 1.4)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Card (subtle hairline-only container)

/// A flat container with a hairline border instead of a shadow.
/// Use sparingly — most NS sections should sit on the page directly.
struct NSCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ns.paper)
            .overlay(
                RoundedRectangle(cornerRadius: NSRadius.card)
                    .stroke(Color.ns.hair, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NSRadius.card))
    }
}

// MARK: - Preview

#if DEBUG
struct NegativeSplitsPreview: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Stat strip
                NSStatStrip(items: [
                    .init(label: "DISTANCE", value: "11.0", unit: "MILES"),
                    .init(label: "DURATION", value: "—",    unit: "TBD"),
                    .init(label: "STEPS",    value: "3",    unit: "PHASES"),
                ])
                NSHairline()

                // KPI tile grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NSKPITile(label: "VOLUME · 7D", value: "47.2", unit: "MI",
                              sub: "+8%  vs 4-WK AVG", subColor: .ns.greenOk)
                    NSKPITile(label: "FITNESS", value: "3:14", unit: "FULL",
                              sub: "−47s  vs 4 WEEKS AGO", subColor: .ns.greenOk)
                    NSKPITile(label: "LOAD · ACWR", value: "1.18",
                              sub: "PRODUCTIVE", subColor: .ns.greenOk)
                    NSKPITile(label: "INJURY RISK", value: "2.4", unit: "/ 10",
                              sub: "LOW · 4W AVG 2.1")
                }

                // Timeline
                NSSection("WORKOUT · 3 STEPS",
                          accessory: { NSEyebrow("11.0 MI TOTAL", color: .ns.slate) }) {
                    NSTimelineList {
                        NSTimelineStep(
                            title: "WARM-UP", distance: "2.0 mi",
                            target: "6:26 – 7:38 / mi", zoneTag: "EASY",
                            zoneColor: .ns.greenOk, note: "conversational pace")
                        NSTimelineStep(
                            title: "ACTIVE", distance: "7.0 mi",
                            target: "5:29 / mi", zoneTag: "MP",
                            zoneColor: .ns.amber, note: "goal marathon race pace",
                            subAnnotation: "your MP 5:32 · −1% today",
                            filled: true)
                        NSTimelineStep(
                            title: "COOL-DOWN", distance: "2.0 mi",
                            target: "6:26 – 7:38 / mi", zoneTag: "EASY",
                            zoneColor: .ns.greenOk, note: "conversational pace")
                    }
                }
            }
            .padding(NSSpace.pagePadding)
        }
        .background(Color.ns.paper)
    }
}
#endif
