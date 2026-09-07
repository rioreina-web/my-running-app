//
//  EfficiencyIndexCard.swift
//  RunningLog · Trends
//
//  Instruments card 03 — efficiency. Lifted out of
//  `InstrumentsCardsTraining.swift` on 2026-08-18 when it stopped being one
//  raw metres-per-beat line through every session and became an index against
//  the athlete's own speed-and-heat curve. The old line had the same flaw the
//  key-pace card fixed on 2026-08-09: m/beat rises with speed for every
//  runner alive, so a line through mixed zones measures the training
//  schedule, not fitness. Substrate and rules: `EfficiencyIndexModels.swift`;
//  spec and validation: `HR-EFFICIENCY-INDEX-APPLY.md`.
//
//  Encodings, matching key pace where the same thing is meant:
//    dot   = one quality session, hue = zone from `PaceSpectrum`
//    diamond = long run (different quantity, same curve)
//    hollow  = heat-adjusted (scored on cool-equivalent pace)
//    coral   = the latest session, exactly once
//    gray hairline at 100 = the athlete's own curve — neutral, never green
//

import SwiftUI

// MARK: - Card

struct InstrumentEfficiencyCard: View {
    let service: TrendsService

    /// One band, shared with Trends section 04, the Signal Lab and key pace.
    @State private var settingsStore = BandSettingsStore.shared

    /// Card-local window, same ruling as the key-pace card: the Instruments
    /// tab has no host-level time control, so this stays fixed until it does.
    private let window: TrendsWindow = .sixMonths

    /// `nil` means ALL.
    @State private var zone: String?
    @State private var selected: EfficiencyPoint?
    @State private var dayWorkouts: DayWorkouts?

    private var read: EfficiencyIndexRead {
        EfficiencyIndexBuilder.build(
            sessions: service.keySessions,
            bandLaps: service.bandLaps,
            settings: settingsStore.settings,
            window: window
        )
    }

    var body: some View {
        let read = self.read
        let visible = read.points(zone: zone)

        InstrumentCard(
            eyebrow: "EFFICIENCY",
            title: EfficiencyIndexProse.headline(read),
            sub: EfficiencyIndexProse.subtitle(read)
        ) {
            trailingStat(read: read)
        } content: {
            if let reason = read.notYetReason {
                InstrumentEmpty(title: reason)
            } else if read.isEmpty {
                InstrumentEmpty(
                    title: "Quality sessions with heart rate land here as dots against your own curve."
                )
            } else {
                expanded(read: read, visible: visible)
            }
        }
        .sheet(item: $dayWorkouts) { workouts in
            HistoryDetailPager(entries: workouts.entries, initial: workouts.initial, onUpdate: {})
        }
    }

    // MARK: Collapsed stat

    @ViewBuilder
    private func trailingStat(read: EfficiencyIndexRead) -> some View {
        if let headline = read.headline {
            InstrumentStat(
                value: String(format: "%.0f", headline),
                caption: "EFF INDEX · \(EfficiencyIndexBuilder.headlineDays) D"
            )
        } else if let latest = read.latest, let idx = latest.index {
            InstrumentStat(
                value: String(format: "%.0f", idx),
                caption: "LATEST SESSION"
            )
        }
    }

    // MARK: Expanded

    @ViewBuilder
    private func expanded(read: EfficiencyIndexRead, visible: [EfficiencyPoint]) -> some View {
        chips(read: read)
            .padding(.bottom, 4)

        EfficiencyIndexChart(points: visible, selected: $selected)
            .frame(height: 150)
            .onChange(of: visible.map(\.id)) { _, ids in
                if selected == nil || !ids.contains(selected?.id ?? "") {
                    selected = visible.last
                }
            }

        if let point = selected ?? visible.last {
            readout(point)
                .padding(.top, 12)
        }

        InstrumentLegendRow(items: legendItems(read: read))

        InstrumentStatRow(items: statItems(read: read))

        if !read.zoneMeans.isEmpty {
            InstrumentStatRow(items: read.zoneMeans.prefix(4).map { entry in
                .init(
                    value: String(format: "%.0f", entry.mean),
                    unit: zoneLabel(entry.zone),
                    detail: "\(entry.count) SESSIONS"
                )
            })
        }

        if !read.excluded.isEmpty {
            Text("NOT COUNTED · " + read.excluded.map { "\($0.count) \($0.label)" }.joined(separator: " · "))
                .instrumentTick()
                .padding(.top, 10)
        }

        if let note = EfficiencyIndexProse.note(read) {
            InstrumentNote(note)
        }
    }

    // MARK: Chips

    private func chips(read: EfficiencyIndexRead) -> some View {
        let present = presentZones(read: read)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "ALL", token: nil)
                ForEach(present, id: \.self) { token in
                    chip(label: zoneLabel(token), token: token)
                }
            }
        }
    }

    private func presentZones(read: EfficiencyIndexRead) -> [String] {
        let tokens = Set(read.points.map { $0.isLongRun ? EfficiencyIndexBuilder.longZoneToken : $0.zone })
        return (KeyZone.order + [EfficiencyIndexBuilder.longZoneToken]).filter { tokens.contains($0) }
    }

    private func chip(label: String, token: String?) -> some View {
        let isOn = zone == token
        return Button {
            zone = token
        } label: {
            Text(label)
                .font(.dripEyebrow(9).weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(isOn ? Color.drip.cardBackground : Color.drip.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.drip.textPrimary : Color.drip.paperDeep)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter to \(label)")
    }

    private func zoneLabel(_ token: String) -> String {
        token == EfficiencyIndexBuilder.longZoneToken ? "LONG" : KeyZone.label(token).uppercased()
    }

    // MARK: Readout

    private func readout(_ point: EfficiencyPoint) -> some View {
        Button {
            openWorkout(point)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let idx = point.index {
                    Text(String(format: "%.0f", idx))
                        .font(.dripStat(17))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Text(readoutCaption(point))
                    .font(.dripEyebrow(8.5))
                    .tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                Spacer()
                Text("OPEN ›")
                    .font(.dripEyebrow(8.5).weight(.semibold))
                    .tracking(0.85)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open workout, \(point.dateLabel)")
    }

    private func readoutCaption(_ point: EfficiencyPoint) -> String {
        var parts = [point.dateLabel.uppercased()]
        parts.append(point.isLongRun ? "LONG" : KeyZone.label(point.zone).uppercased())
        parts.append(String(format: "%.2f M/BEAT", point.mpb))
        parts.append("\(point.hr) BPM")
        parts.append("\(TrendsFormat.pace(point.paceSec)) /MI")
        if point.isHeatAdjusted, let category = point.heatCategory {
            parts.append(category.replacingOccurrences(of: "_", with: " ").uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Legend & stats

    private func legendItems(read: EfficiencyIndexRead) -> [(InstrumentLegendItem.Swatch, String)] {
        var items: [(InstrumentLegendItem.Swatch, String)] = [
            (.dot(PaceSpectrum.hmp), "QUALITY · ZONE HUE"),
        ]
        if read.points.contains(where: { $0.isLongRun }) {
            items.append((.fill(PaceSpectrum.steady), "LONG RUN ◇"))
        }
        if read.points.contains(where: { $0.isHeatAdjusted }) {
            items.append((.dot(Color.drip.textTertiary), "HOLLOW = HEAT-ADJ"))
        }
        items.append((.line(Color.drip.textTertiary), "100 = YOUR CURVE"))
        items.append((.dot(Color.drip.coral), "LATEST"))
        return items
    }

    private func statItems(read: EfficiencyIndexRead) -> [InstrumentStatRow.Item] {
        var items: [InstrumentStatRow.Item] = []
        if let headline = read.headline {
            items.append(.init(
                value: String(format: "%.0f", headline),
                unit: "EFF INDEX",
                detail: "\(read.headlineCount) SESSIONS · \(EfficiencyIndexBuilder.headlineDays) D"
            ))
        }
        if let anchor = read.anchorStat {
            items.append(.init(
                value: String(format: "%.2f", anchor.mpb),
                unit: "M/BEAT",
                detail: "AT \(TrendsFormat.pace(anchor.paceSec)) · COOL"
            ))
        }
        if let cost = read.heatCostPctPerStep {
            items.append(.init(
                value: String(format: "\u{2212}%.1f%%", abs(cost)),
                unit: "HEAT COST",
                detail: "PER STEP · YOURS"
            ))
        } else if let trend = read.trendPerMonth {
            items.append(.init(
                value: String(format: "%+.1f", trend),
                unit: "/ 30 D",
                detail: "TREND IN WINDOW"
            ))
        }
        return items
    }

    private func openWorkout(_ point: EfficiencyPoint) {
        Task {
            dayWorkouts = await service.resolveDay(dayISO: point.date, focusLogId: point.id)
        }
    }
}

// MARK: - Chart

/// The one renderer for the efficiency index. Dots over real dates against
/// the athlete's 100 rule. If a detail surface arrives later it renders THIS
/// view at a taller height — never a second implementation.
struct EfficiencyIndexChart: View {
    let points: [EfficiencyPoint]
    @Binding var selected: EfficiencyPoint?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let indexed = points.filter { $0.index != nil }
            let days = indexed.map { Double($0.dayNumber) }
            let values = indexed.compactMap(\.index)

            if indexed.isEmpty {
                Text("NOT YET")
                    .instrumentTick()
                    .position(x: w / 2, y: h / 2)
            } else {
                let dayLo = days.min() ?? 0
                let dayHi = days.max() ?? 1
                let daySpan = max(dayHi - dayLo, 1)
                // The 100 rule always sits inside the frame.
                let lo = min((values.min() ?? 100), 100) - 2
                let hi = max((values.max() ?? 100), 100) + 2
                let span = max(hi - lo, 0.001)
                let x: (EfficiencyPoint) -> CGFloat = {
                    indexed.count == 1
                        ? w / 2
                        : w * 0.04 + (w * 0.92) * CGFloat((Double($0.dayNumber) - dayLo) / daySpan)
                }
                let y: (Double) -> CGFloat = { h - h * CGFloat(($0 - lo) / span) }

                ZStack(alignment: .topLeading) {
                    // The athlete's own curve — neutral gray, never green.
                    Rectangle()
                        .fill(Color.drip.textTertiary)
                        .frame(height: 1)
                        .position(x: w / 2, y: y(100))
                    Text("100")
                        .instrumentTick()
                        .position(x: 12, y: y(100) - 8)

                    ForEach(indexed) { point in
                        let isLatest = point.id == indexed.last?.id
                        let isSelected = point.id == selected?.id
                        dot(point, latest: isLatest)
                            .frame(width: isLatest || isSelected ? 10 : 8,
                                   height: isLatest || isSelected ? 10 : 8)
                            .position(x: x(point), y: y(point.index ?? 100))
                            .accessibilityLabel(accessibilityText(point))
                    }

                    if let selected, let idx = selected.index,
                       indexed.contains(where: { $0.id == selected.id }) {
                        Rectangle()
                            .fill(Color.drip.divider)
                            .frame(width: 1, height: h)
                            .position(x: x(selected), y: h / 2)
                        Text(String(format: "%.0f", idx))
                            .instrumentTick(color: Color.drip.textPrimary)
                            .position(x: x(selected), y: max(y(idx) - 14, 6))
                    }

                    if let first = indexed.first, let last = indexed.last, indexed.count > 1 {
                        Text(first.dateLabel.uppercased())
                            .instrumentTick()
                            .position(x: 24, y: h - 6)
                        Text(last.dateLabel.uppercased())
                            .instrumentTick()
                            .position(x: w - 24, y: h - 6)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selected = indexed.min {
                                abs(x($0) - value.location.x) < abs(x($1) - value.location.x)
                            }
                        }
                )
            }
        }
    }

    @ViewBuilder
    private func dot(_ point: EfficiencyPoint, latest: Bool) -> some View {
        let color = latest ? Color.drip.coral : zoneColor(point)
        if point.isLongRun {
            // A long run is a different quantity — an open diamond, matching
            // key pace.
            Rectangle()
                .strokeBorder(color, lineWidth: 1.6)
                .rotationEffect(.degrees(45))
        } else if point.isHeatAdjusted {
            Circle()
                .strokeBorder(color, lineWidth: 1.6)
        } else {
            Circle()
                .fill(color)
        }
    }

    private func zoneColor(_ point: EfficiencyPoint) -> Color {
        switch point.zone.lowercased() {
        case "mp": PaceSpectrum.mp
        case "hmp": PaceSpectrum.hmp
        case "10k": PaceSpectrum.tenK
        case "5k": PaceSpectrum.fiveK
        case "3k": PaceSpectrum.threeK
        case "mile": PaceSpectrum.mile
        default: PaceSpectrum.steady
        }
    }

    private func accessibilityText(_ point: EfficiencyPoint) -> String {
        let idx = point.index.map { String(format: "index %.0f", $0) } ?? "no index"
        return "\(point.dateLabel), \(point.isLongRun ? "long run" : KeyZone.label(point.zone)), \(idx)"
    }
}

// MARK: - Previews

#Preview("Efficiency card") {
    ScrollView {
        InstrumentEfficiencyCard(service: TrendsService(preview: []))
            .padding(.horizontal, 24)
    }
    .background(Color.drip.background)
}
