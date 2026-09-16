//
//  WeekComponents.swift
//  RunningLog · Week
//
//  The pieces the Week tab is made of. Charts here are plain SwiftUI shapes
//  rather than Swift Charts: every mark on this surface is a bar, a line or a
//  stacked segment, and the editorial spec wants flat fills with a 2pt gap
//  between stacked segments — cheaper to draw directly than to fight a
//  framework's defaults into the house style.
//

import SwiftUI

// MARK: - Type

struct WeekEyebrow: View {
    let text: String
    var tint: Color = Color.drip.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.dripEyebrow(11))
            .tracking(1.3)
            .foregroundStyle(tint)
    }
}

struct WeekCaption: View {
    let text: String
    var tint: Color = Color.drip.textTertiary

    var body: some View {
        Text(text.uppercased())
            .font(.dripEyebrow(10))
            .tracking(1.0)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The `· line · dot · line ·` divider between question sections.
struct WeekRuleView: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            Circle().fill(Color.drip.textTertiary).frame(width: 3, height: 3)
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .padding(.vertical, 26)
    }
}

// MARK: - Card

/// White card with the house radius and shadow. `anchor` makes it a scroll
/// target for an evidence chip; when that chip is tapped the card flashes a
/// coral ring so the athlete can see what they landed on.
struct WeekCard<Content: View>: View {
    let anchor: WeekAnchor?
    let flashed: WeekAnchor?
    let content: Content

    init(anchor: WeekAnchor? = nil,
         flashed: WeekAnchor? = nil,
         @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.flashed = flashed
        self.content = content()
    }

    private var isFlashing: Bool {
        guard let anchor, let flashed else { return false }
        return anchor == flashed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.coral, lineWidth: 2)
                    .opacity(isFlashing ? 1 : 0)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
            .animation(.easeOut(duration: 0.45), value: isFlashing)
    }
}

// MARK: - Chips

/// Capsule with a status dot. `strikethrough` is the resolved-niggle look.
struct WeekChip: View {
    let text: String
    let tint: Color
    var strikethrough: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text.uppercased())
                .font(.dripEyebrow(9.5))
                .tracking(0.8)
                .strikethrough(strikethrough, color: Color.drip.textTertiary)
                .foregroundStyle(strikethrough ? Color.drip.textTertiary : Color.drip.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
    }
}

/// The tappable citation on a proposal. The trailing arrow is the affordance:
/// this chip goes somewhere.
struct WeekEvidenceChip: View {
    let evidence: WeekRead.Evidence
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(evidence.tint).frame(width: 6, height: 6)
                Text(evidence.label.uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Evidence: \(evidence.label). Jump to the chart it came from.")
    }
}

// MARK: - Line chart

/// Weekly pace trend. Faster paces are smaller numbers, and they plot HIGHER —
/// improvement rises, which is the only orientation an athlete reads without
/// being told.
struct WeekLineChart: View {
    let points: [WeekRead.Point]
    let tint: Color
    var height: CGFloat = 64
    /// Tapping a point opens what it was derived from. Every point on this
    /// chart is one or more real sessions; the tap is how the athlete gets to
    /// them.
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                linePath(in: geo.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(index == points.count - 1 ? tint : Color.drip.background)
                        .overlay(
                            Circle().stroke(tint, lineWidth: index == points.count - 1 ? 2 : 1.5)
                        )
                        .frame(width: index == points.count - 1 ? 8 : 5,
                               height: index == points.count - 1 ? 8 : 5)
                        .position(position(index, in: geo.size))
                }

                // Full-height tap columns, so the target is a finger rather
                // than an 8pt dot.
                HStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, _ in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect?(index) }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Weekly trend, \(points.count) weeks")
    }

    private var lowBound: Int { (points.map(\.paceSec).min() ?? 0) - 3 }
    private var highBound: Int { (points.map(\.paceSec).max() ?? 1) + 3 }

    private func position(_ index: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: xValue(index, in: size), y: yValue(points[index].paceSec, in: size))
    }

    private func xValue(_ index: Int, in size: CGSize) -> CGFloat {
        guard points.count > 1 else { return size.width / 2 }
        // 4pt inset each side so the end dots aren't clipped by the frame.
        let usable = size.width - 8
        return 4 + usable * CGFloat(index) / CGFloat(points.count - 1)
    }

    private func yValue(_ pace: Int, in size: CGSize) -> CGFloat {
        let span = max(highBound - lowBound, 1)
        let usable = size.height - 8
        return 4 + usable * CGFloat(pace - lowBound) / CGFloat(span)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        for index in points.indices {
            let point = position(index, in: size)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - Load chart

/// Weekly load, stacked by pace zone, against the athlete's own 8-week
/// baseline band. Bar HEIGHT is total load; stacking only changes what the bar
/// is made of. The band behind is drawn from the athlete's own history — it is
/// never a population number, and the surface never divides one by the other.
struct WeekLoadChart: View {
    let load: WeekRead.Load
    @Binding var selectedIndex: Int?
    var onSelect: ((WeekRead.LoadWeek) -> Void)? = nil

    private let chartHeight: CGFloat = 92

    private var peak: Double {
        max(load.weeks.map(\.total).max() ?? 1, load.baselineHi)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WeekCaption(text: load.baselineLabel)

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.drip.textPrimary.opacity(0.05))
                    .frame(height: bandHeight)
                    .offset(y: -bandOffset)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(load.weeks.enumerated()), id: \.element.id) { index, week in
                        WeekLoadBar(
                            week: week,
                            peak: peak,
                            chartHeight: chartHeight,
                            isSelected: selectedIndex == index
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            onSelect?(week)
                        }
                    }
                }
            }
            .frame(height: chartHeight)

            HStack {
                WeekCaption(text: load.weeks.first?.label ?? "")
                Spacer()
                WeekCaption(text: load.weeks.last?.label ?? "")
            }
        }
    }

    private var bandHeight: CGFloat {
        chartHeight * CGFloat((load.baselineHi - load.baselineLo) / peak)
    }

    private var bandOffset: CGFloat {
        chartHeight * CGFloat(load.baselineLo / peak)
    }
}

private struct WeekLoadBar: View {
    let week: WeekRead.LoadWeek
    let peak: Double
    let chartHeight: CGFloat
    let isSelected: Bool

    /// Sharp end on top — the deep blue sits where the stress came from.
    private var stackTopDown: [WeekZone] {
        Array(WeekZone.allCases.reversed()).filter { (week.minutes[$0] ?? 0) > 0 }
    }

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(stackTopDown) { zone in
                Rectangle()
                    .fill(zone.color)
                    .frame(height: segmentHeight(zone))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.drip.textPrimary, lineWidth: 1.5)
                .opacity(isSelected ? 1 : 0)
        )
        .accessibilityElement()
        .accessibilityLabel("\(week.label): \(Int(week.total)) load minutes")
    }

    private func segmentHeight(_ zone: WeekZone) -> CGFloat {
        guard peak > 0 else { return 0 }
        return chartHeight * CGFloat((week.minutes[zone] ?? 0) / peak)
    }
}

// MARK: - Spectrum bar

/// Share of recent miles by pace zone, one continuous bar. The flagged slice
/// gets a coral tick beneath it — the zone a proposal is about to reference.
struct WeekSpectrumBar: View {
    let slices: [WeekRead.SpectrumSlice]
    var onSelect: ((WeekRead.SpectrumSlice) -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(slices) { slice in
                        Rectangle()
                            .fill(slice.zone.color)
                            .frame(width: width(for: slice, in: geo.size))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect?(slice) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            GeometryReader { geo in
                ForEach(slices) { slice in
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 4, height: 4)
                        .opacity(slice.flagged ? 1 : 0)
                        .position(x: tickX(for: slice, in: geo.size), y: 3)
                }
            }
            .frame(height: 6)
        }
    }

    private var total: Double {
        max(slices.reduce(0) { $0 + $1.share }, 0.001)
    }

    private func width(for slice: WeekRead.SpectrumSlice, in size: CGSize) -> CGFloat {
        let raw = size.width * CGFloat(slice.share / total)
        return max(raw - 2, 2)
    }

    private func tickX(for slice: WeekRead.SpectrumSlice, in size: CGSize) -> CGFloat {
        var offset: Double = 0
        for entry in slices {
            if entry.id == slice.id { break }
            offset += entry.share
        }
        let start = size.width * CGFloat(offset / total)
        return start + width(for: slice, in: size) / 2
    }
}

// MARK: - Week strip

struct WeekStripView: View {
    let days: [WeekRead.Day]
    let changedDayNames: Set<String>
    /// Tapping a day opens the runs behind it. A day this athlete ran three
    /// times has three rows to show; the total on the cell is the sum.
    var onSelect: ((WeekRead.Day) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    WeekCaption(text: day.name)

                    Circle()
                        .fill(day.isQuality ? Color.drip.textPrimary : Color.drip.paperDeep)
                        .overlay(
                            Circle().stroke(
                                day.isQuality ? Color.drip.textPrimary : Color.drip.textTertiary,
                                lineWidth: 1.5
                            )
                        )
                        .frame(width: 8, height: 8)

                    Text(day.miles.map { $0 == floor($0) ? String(Int($0)) : String(format: "%.1f", $0) } ?? "—")
                        .font(.dripStat(13))
                        .foregroundStyle(day.miles == nil ? Color.drip.textTertiary : Color.drip.textPrimary)

                    // A day this athlete ran twice shows both, stacked —
                    // "6.0 + 4.0" — because the total alone hides the session
                    // structure that the rest of the tab reasons about.
                    if day.runs.count > 1 {
                        Text(day.runs.map { String(format: "%.1f", $0.miles) }
                                .joined(separator: " + "))
                            .font(.dripEyebrow(7))
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Text(day.label.uppercased())
                        .font(.dripEyebrow(7.5))
                        .tracking(0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            changedDayNames.contains(day.name)
                                ? Color.drip.coral
                                : (day.miles == nil ? Color.drip.textTertiary : Color.drip.textSecondary)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.drip.coralWash)
                        .opacity(changedDayNames.contains(day.name) ? 1 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !day.runs.isEmpty else { return }
                    onSelect?(day)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(dayLabel(day))
                .accessibilityAddTraits(day.runs.isEmpty ? [] : .isButton)
            }
        }
    }

    private func dayLabel(_ day: WeekRead.Day) -> String {
        guard let miles = day.miles else { return "\(day.name), rest" }
        let runs = day.runs.count > 1 ? ", \(day.runs.count) runs" : ""
        return String(format: "%@, %.1f miles%@", day.name, miles, runs)
    }
}

// MARK: - Unavailable

/// Why a section is dark, in plain prose. Never a dash where a number would
/// go, never a greyed-out chart with no data in it — a sentence.
struct WeekUnavailableNote: View {
    let note: WeekRead.Unavailable

    var body: some View {
        Text(note.message)
            .font(.dripBody(12.5))
            .italic()
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

// MARK: - Provenance sheet

/// What a tapped chart element was derived from: the method in a sentence,
/// then every source row that went into it.
///
/// The rows are real or the sheet does not open. `WeekBuilder` only attaches
/// sources it read off the athlete's own days and sessions, so there is no
/// path here that can invent a row.
struct WeekProvenanceSheet: View {
    let provenance: WeekProvenance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WeekEyebrow(text: provenance.eyebrow, tint: Color.drip.coral)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(provenance.title)
                            .font(.dripStat(30))
                            .foregroundStyle(Color.drip.textPrimary)
                        Circle().fill(provenance.tint).frame(width: 8, height: 8)
                    }
                    .padding(.top, 8)

                    Text(provenance.subtitle)
                        .font(.dripBody(13.5))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 4)

                    WeekRuleView()

                    WeekEyebrow(text: "How it's worked out")
                    Text(provenance.method)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    if provenance.rows.isEmpty {
                        // Should be unreachable: a datum with no sources must
                        // not offer a tap in the first place. If this renders,
                        // the bug is upstream in WeekBuilder.
                        Text("No source rows were attached to this value.")
                            .font(.dripBody(13))
                            .italic()
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.top, 20)
                    } else {
                        HStack {
                            WeekEyebrow(text: "From \(provenance.rows.count) \(provenance.rows.count == 1 ? "run" : "runs")")
                            Spacer()
                            WeekCaption(text: provenance.valueHeader)
                        }
                        .padding(.top, 26)

                        VStack(spacing: 0) {
                            ForEach(provenance.rows) { row in
                                sourceRow(row)
                            }
                        }
                        .padding(.top, 6)
                    }

                    if !provenance.coverage.isEmpty {
                        WeekCaption(text: provenance.coverage)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .background(Color.drip.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
    }

    private func sourceRow(_ row: WeekSourceRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.date)
                    .font(.dripEyebrow(10))
                    .foregroundStyle(Color.drip.textSecondary)
                Text(row.name)
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textPrimary)
                WeekCaption(text: row.detail)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(row.value)
                    .font(.dripStat(15))
                    .foregroundStyle(Color.drip.textPrimary)
                if let secondary = row.secondary {
                    WeekCaption(text: secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}
