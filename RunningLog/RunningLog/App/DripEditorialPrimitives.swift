//
//  DripEditorialPrimitives.swift
//  RunningLog
//
//  Small reusable view structs that match the Post Run Drip "editorial"
//  vocabulary: plate strips, hairlines, mono stat strips, key:value rows.
//  No new tokens are introduced; everything resolves to existing
//  `Color.drip.*` + `.dripCaption(n)`.
//

import SwiftUI

// MARK: - Plate strip
// Mono editorial header. Replaces the chunky `.toolbar` nav bar across
// the rebrand. Two stacked mono lines on each side, sized 10pt / 0.14em.

struct DripPlateStrip: View {
    let leadingTop: String
    let leadingBottom: String
    let trailingTop: String?
    let trailingBottom: String

    init(
        leadingTop: String = "RUNNING LOG",
        leadingBottom: String,
        trailingTop: String? = nil,
        trailingBottom: String
    ) {
        self.leadingTop = leadingTop
        self.leadingBottom = leadingBottom
        self.trailingTop = trailingTop
        self.trailingBottom = trailingBottom
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leadingTop)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textPrimary)
                Text("— " + leadingBottom)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                if let trailingTop {
                    Text(trailingTop)
                        .font(.dripCaption(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Text(trailingBottom)
                    .font(.dripCaption(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }
}

// MARK: - Hairline
// 1pt full-width rule. Use horizontal padding on the parent VStack so the
// rule respects the 24pt editorial margins.

struct DripHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(height: 1)
    }
}

// MARK: - Eyebrow
// Mono uppercase label, 10pt, 14% tracking. Optional coral variant for the
// one-hit-per-cluster active state.

struct DripEyebrow: View {
    let text: String
    var coral: Bool = false

    var body: some View {
        Text(text)
            .font(.dripCaption(10))
            .tracking(1.4)
            .foregroundStyle(coral ? Color.drip.coral : Color.drip.textSecondary)
    }
}

// MARK: - Stat strip
// N-cell hairline-bordered numeric strip. Mono numerals with optional unit
// hint. Replaces both the "Distance: 6.9 mi / Duration: 51:06 / …" serif
// paragraph AND the mint LINKED WORKOUT tile — one component does both jobs.

struct DripStat {
    let label: String          // e.g. "DIST"
    let value: String          // e.g. "6.9"
    let unit: String?          // e.g. "mi" (small, secondary)

    init(_ label: String, _ value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

struct DripStatStrip: View {
    let stats: [DripStat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { idx, stat in
                VStack(spacing: 6) {
                    Text(stat.label)
                        .font(.dripCaption(9))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stat.value)
                            .font(.dripCaption(18))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Color.drip.textPrimary)
                        if let unit = stat.unit {
                            Text(unit)
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                if idx < stats.count - 1 {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 1)
                }
            }
        }
        .overlay(alignment: .top) { DripHairline() }
        .overlay(alignment: .bottom) { DripHairline() }
    }
}

// MARK: - Underlined coral text link
// Replaces the pink "Get Coach Feedback" pill and the gray "Save Notes"
// pill. Lives inline — no card, no background fill.

struct DripTextLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.coral)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.drip.coral)
                        .frame(height: 1)
                        .offset(y: 2)
                }
                .padding(.bottom, 3)
        }
        .buttonStyle(.plain)
    }
}

// =====================================================================
// MARK: - Layout primitives (kit parity, added 2026-05-29)
//
// These cover the JSX vocabulary in
// `design-system/ui_kits/ios_app/Primitives.jsx` + `tokens.css` that had
// no Swift equivalent (the gap catalogued in
// `outputs/why-ios-design-parity-is-hard.md`, "minimal fix path" step 2).
// Every value below traces to a CSS class in `tokens.css`; the class name
// is noted in each MARK so a reviewer can diff against source.
//
// All labels here intentionally use `.dripEyebrow(n)` (system monospaced)
// — NOT `.dripCaption(n)` (PT Serif). The existing `DripEyebrow` above
// still uses the serif path (the catalogued eyebrow drift); fixing and
// migrating it is a separate, reviewable change, so these new parts do
// not depend on it.
// =====================================================================

/// Tracking helper: CSS `letter-spacing` is in `em`, SwiftUI `.tracking`
/// is in points. points = size × em. Centralised so every label below
/// derives tracking the same way instead of hand-picking values.
private func dripTracking(_ size: CGFloat, em: CGFloat) -> CGFloat { size * em }

/// Canonical small mono label used inside the kit parts below. Mirrors the
/// `.eyebrow` / `.caption` CSS classes: system mono, uppercase, tracked.
/// Defaults to the `.caption` spec (10pt / 0.10em); pass `coral` for the
/// one-hit-per-cluster active state.
private struct KitEyebrow: View {
    let text: String
    var size: CGFloat = 10
    var em: CGFloat = 0.10
    var color: Color = Color.drip.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.dripEyebrow(size))
            .tracking(dripTracking(size, em: em))
            .foregroundStyle(color)
    }
}

// MARK: - Section  (CSS `.section` / `.section--first`)
// Eyebrow row (left, optional coral) + optional right-aligned eyebrow,
// then arbitrary content. 6pt internal gap; 18pt top margin unless `first`.

struct DripSection<Content: View>: View {
    var eyebrow: String? = nil
    var eyebrowRight: String? = nil
    var eyebrowCoral: Bool = false
    var first: Bool = false
    @ViewBuilder var content: () -> Content

    init(
        eyebrow: String? = nil,
        eyebrowRight: String? = nil,
        eyebrowCoral: Bool = false,
        first: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.eyebrowRight = eyebrowRight
        self.eyebrowCoral = eyebrowCoral
        self.first = first
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if eyebrow != nil || eyebrowRight != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let eyebrow {
                        KitEyebrow(
                            text: eyebrow,
                            size: 11, em: 0.14,
                            color: eyebrowCoral ? Color.drip.coral : Color.drip.textSecondary
                        )
                    }
                    if eyebrowRight != nil { Spacer(minLength: 8) }
                    if let eyebrowRight {
                        KitEyebrow(text: eyebrowRight, size: 11, em: 0.14)
                    }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, first ? 0 : 18)
    }
}

// MARK: - Stat tile  (CSS `.stat-tile`)
// White numeral card: mono label / big mono value (+ optional unit) /
// optional delta. This is the `<StatTile>` from the kit — distinct from
// the older `StatCard` in DesignSystem.swift (icon + value + label, no
// delta slot, no unit). New surfaces should prefer this one.

enum DripDeltaTone { case positive, negative }

struct DripStatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    var deltaTone: DripDeltaTone = .positive

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KitEyebrow(text: label, size: 10, em: 0.10)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.dripStat(28))
                    .monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.dripStat(10))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            if let delta {
                KitEyebrow(
                    text: delta,
                    size: 10, em: 0.10,
                    color: deltaTone == .positive ? Color.drip.energized : Color.drip.coral
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Mood radio  (CSS `.mood-radio-row` / `.mood-radio`)
// The Today "how are you feeling?" cluster. 14pt hollow dots; active dot
// is a coral ring with a coral inset fill; active name turns coral. Five
// moods only (no `injured` — that is a logged state, not a daily check-in).

struct DripMoodRadio: View {
    @Binding var selection: String?
    var moods: [String] = ["energized", "positive", "neutral", "tired", "struggling"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(moods, id: \.self) { mood in
                let active = selection == mood
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .strokeBorder(active ? Color.drip.coral : Color.drip.textTertiary, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        if active {
                            Circle()
                                .fill(Color.drip.coral)
                                .frame(width: 10, height: 10)
                        }
                    }
                    KitEyebrow(
                        text: mood,
                        size: 9, em: 0.10,
                        color: active ? Color.drip.coral : Color.drip.textSecondary
                    )
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { selection = mood }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Race strip  (CSS `.race-strip`)
// Five-cell predictions row with right dividers. Presentation only.
//
// NB — CLAUDE.md hard rule #7: predictions ship as a RANGE + CONFIDENCE,
// never a single seconds-precision point. Feed `value` a range like
// "3:08–3:14" and use `delta` for the confidence/midpoint note. Do not
// pass a single projected finish like "3:09:30".

struct DripRaceCell: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var delta: String? = nil
}

struct DripRaceStrip: View {
    let cells: [DripRaceCell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { idx, cell in
                VStack(spacing: 4) {
                    KitEyebrow(text: cell.label, size: 9, em: 0.10)
                    Text(cell.value)
                        .font(.dripStat(18))
                        .monospacedDigit()
                        .foregroundStyle(Color.drip.textPrimary)
                    if let delta = cell.delta {
                        Text(delta)
                            .font(.dripStat(10))
                            .foregroundStyle(Color.drip.energized)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                if idx < cells.count - 1 {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(width: 1, height: 28)
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Week strip  (CSS `.wkstrip` / `.wkday`)
// Mon–Sun day capsules. Today is a 12pt coral dot inside a coral-wash ring
// with coral text; done days are an ink dot; rest days dim the numerals;
// planned days are a 9pt tertiary dot.

enum DripDayState { case planned, today, done, rest }

struct DripWeekDay: Identifiable {
    let id = UUID()
    let name: String
    let miles: String
    let type: String
    var state: DripDayState = .planned
}

struct DripWeekStrip: View {
    let days: [DripWeekDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    KitEyebrow(
                        text: day.name,
                        size: 9, em: 0.10,
                        color: day.state == .today ? Color.drip.coral : Color.drip.textSecondary
                    )
                    dot(for: day.state)
                        .frame(height: 18)
                    Text(day.miles)
                        .font(.dripStat(14))
                        .monospacedDigit()
                        .foregroundStyle(milesColor(day.state))
                    KitEyebrow(
                        text: day.type,
                        size: 9, em: 0.10,
                        color: typeColor(day.state)
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func dot(for state: DripDayState) -> some View {
        switch state {
        case .today:
            ZStack {
                Circle().fill(Color.drip.coralWash).frame(width: 18, height: 18)
                Circle().fill(Color.drip.coral).frame(width: 12, height: 12)
            }
        case .done:
            Circle().fill(Color.drip.textPrimary).frame(width: 9, height: 9)
        case .planned, .rest:
            Circle().fill(Color.drip.textTertiary).frame(width: 9, height: 9)
        }
    }

    private func milesColor(_ state: DripDayState) -> Color {
        switch state {
        case .today: Color.drip.coral
        case .rest: Color.drip.textTertiary
        default: Color.drip.textPrimary
        }
    }

    private func typeColor(_ state: DripDayState) -> Color {
        switch state {
        case .today: Color.drip.coral
        case .rest: Color.drip.textTertiary
        default: Color.drip.textSecondary
        }
    }
}

// MARK: - Mini line chart  (JSX `<LineChart>` / CSS `.chart-wrap`)
// Tiny inline trend line with a coral dot on the latest point. Mirrors the
// JSX scaling: 6pt top inset, line min→max normalised over (h − 14).

struct DripMiniLineChart: View {
    let data: [Double]
    var height: CGFloat = 90
    var lineColor: Color = Color.drip.textPrimary
    var dotColor: Color = Color.drip.coral

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = data.min() ?? 0
            let maxV = data.max() ?? 1
            let range = (maxV - minV) == 0 ? 1 : (maxV - minV)

            let point: (Int) -> CGPoint = { i in
                let x = data.count <= 1 ? 0 : CGFloat(i) / CGFloat(data.count - 1) * w
                let norm = CGFloat((data[i] - minV) / range)
                let y = h - norm * (h - 14) - 6
                return CGPoint(x: x, y: y)
            }

            if data.count >= 2 {
                Path { p in
                    p.move(to: point(0))
                    for i in 1..<data.count { p.addLine(to: point(i)) }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .position(point(data.count - 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Zone bar  (JSX `<ZoneBar>`)
// Segmented horizontal bar (e.g. HR zones). Each segment is a color + a
// percentage of the total width; the bar is 12pt tall with a 3pt radius.

struct DripZone: Identifiable {
    let id = UUID()
    let color: Color
    let pct: Double   // 0…100
}

struct DripZoneBar: View {
    let zones: [DripZone]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(zones) { zone in
                    Rectangle()
                        .fill(zone.color)
                        .frame(width: geo.size.width * CGFloat(zone.pct) / 100)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Preview (debug-only; aids visual parity review)

#if DEBUG
#Preview("Kit parity primitives") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            DripSection(eyebrow: "Opening figure", eyebrowRight: "Fig. 1", first: true) {
                Text("The 5-second view.")
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            HStack(spacing: 10) {
                DripStatTile(label: "Volume · 7d", value: "47.2", unit: "MI", delta: "+8%  vs 4-wk avg")
                DripStatTile(label: "Load · ACWR", value: "1.18", unit: "ratio", delta: "Hot", deltaTone: .negative)
            }

            DripMoodRadio(selection: .constant("tired"))

            DripRaceStrip(cells: [
                DripRaceCell(label: "5K", value: "19:4x", delta: "±10s"),
                DripRaceCell(label: "10K", value: "41:0x"),
                DripRaceCell(label: "HM", value: "1:30s"),
                DripRaceCell(label: "Full", value: "3:08–3:14", delta: "HIGH"),
            ])

            DripWeekStrip(days: [
                DripWeekDay(name: "Mon", miles: "6", type: "Easy", state: .done),
                DripWeekDay(name: "Tue", miles: "8", type: "Tempo", state: .done),
                DripWeekDay(name: "Wed", miles: "5", type: "Easy", state: .today),
                DripWeekDay(name: "Thu", miles: "—", type: "Rest", state: .rest),
                DripWeekDay(name: "Fri", miles: "10", type: "MP", state: .planned),
                DripWeekDay(name: "Sat", miles: "6", type: "Easy", state: .planned),
                DripWeekDay(name: "Sun", miles: "18", type: "Long", state: .planned),
            ])

            DripMiniLineChart(data: [230, 226, 222, 220, 214, 209, 202, 198, 195])
                .padding(.horizontal, 4)

            DripZoneBar(zones: [
                DripZone(color: Color.drip.neutral, pct: 30),
                DripZone(color: Color.drip.energized, pct: 40),
                DripZone(color: Color.drip.tired, pct: 20),
                DripZone(color: Color.drip.coral, pct: 10),
            ])
        }
        .padding(24)
    }
    .background(Color.drip.background)
}
#endif
