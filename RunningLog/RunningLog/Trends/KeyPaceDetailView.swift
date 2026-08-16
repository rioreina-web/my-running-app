//
//  KeyPaceDetailView.swift
//  RunningLog · Trends
//
//  The full-screen half of Instruments card 02. Follows the shape
//  `TrendsThresholdDetailView` established on 2026-08-07: the inline card is
//  the glance and is unchanged; this is where the range, the band and the
//  session list live.
//
//  **Everything here is shared, not copied.**
//    • The chart is `KeyPaceChart` at 250pt — the same view the card renders at
//      140. Handed a taller frame, not a second implementation.
//    • The band controls are `TrendsThresholdControls` writing to
//      `BandSettingsStore.shared`. Move the slow edge here and Trends section
//      04 has already moved.
//    • The window is a `@Binding` to the card's, not a copy. Change the range
//      here and the card behind it is already changed.
//
//  If a change below would need a second chart, a second band or a second
//  window — stop, it's the wrong change.
//

import SwiftUI

struct KeyPaceDetailView: View {

    let service: TrendsService

    @Binding var settings: BandSettings
    @Binding var window: TrendsWindow
    @Binding var customFrom: Date
    @Binding var customTo: Date
    @Binding var zone: String?
    @Binding var includeLongRuns: Bool
    @Binding var showHeatTicks: Bool
    @Binding var lane: KeyPaceLane
    @Binding var mode: KeyPaceMode
    @Binding var basis: KeyPaceBasis
    @Binding var selected: KeyPacePoint?

    @Environment(\.dismiss) private var dismiss

    @State private var dayWorkouts: DayWorkouts?
    @State private var controlsExpanded = false

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    private var read: KeyPaceRead {
        KeyPaceBuilder.read(
            sessions: service.keySessions,
            bandLaps: service.bandLaps,
            settings: settings,
            window: window
        )
    }

    private var accent: Color { settings.anchor.color(in: read.ladder) }

    var body: some View {
        let read = self.read
        let visible = read.points(zone: zone, includeLongRuns: includeLongRuns)

        VStack(spacing: 0) {
            head

            // Fixed rather than scrolling, for the reason the threshold detail
            // fixed its own: this screen exists to change the range and the
            // band while watching the chart, and a control you have to scroll
            // back to is the problem it is solving.
            TrendsWindowPicker(
                window: $window,
                customFrom: $customFrom,
                customTo: $customTo,
                isPinned: true,
                meta: meta(read: read)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chartPanel(read: read, visible: visible)
                    sessionPanel(read: read, visible: visible)
                    notCountedPanel(read: read)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
        .background(Color.drip.background)
        .sheet(item: $dayWorkouts) { workouts in
            HistoryDetailPager(entries: workouts.entries, initial: workouts.initial, onUpdate: {})
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Drawn rather than borrowed: `fullScreenCover` has no drag
            // indicator, and without one the screen reads as a navigation push
            // it can't be dismissed like.
            Capsule()
                .fill(Color.drip.divider)
                .frame(width: 34, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    DripEyebrow(text: "Card 02", coral: true)
                    Text("Key pace")
                        .font(.dripDisplay(24))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Spacer(minLength: 12)
                Button("Done") { dismiss() }
                    .font(.dripEyebrow(smallType).weight(.semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.textPrimary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
    }

    /// The dates the window resolved to and what is inside them. Built off the
    /// same read the chart draws, so the meta line and the chart cannot differ.
    private func meta(read: KeyPaceRead) -> (range: String, count: String)? {
        guard let first = read.points.first, let last = read.points.last else { return nil }
        let n = read.points.count
        return (
            range: "\(first.dateLabel) – \(last.dateLabel)",
            count: "\(n) key \(n == 1 ? "session" : "sessions")"
        )
    }

    // MARK: Chart panel

    @ViewBuilder
    private func chartPanel(read: KeyPaceRead, visible: [KeyPacePoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            segments

            KeyPaceZoneChips(read: read, includeLongRuns: includeLongRuns, zone: $zone)
                .padding(.top, 12)

            toggles.padding(.top, 10)

            KeyPaceChart(
                points: visible,
                anchorSteps: read.anchorSteps,
                band: bandTuple(read),
                anchorSec: read.anchorSec,
                anchorColor: accent,
                lowConfidence: read.lowConfidence,
                mode: mode,
                basis: basis,
                showHeatTicks: showHeatTicks,
                trend: read.trendLine(zone: zone, includeLongRuns: includeLongRuns, basis: basis),
                volumeDomain: read.volumeDomain(zone: zone, includeLongRuns: includeLongRuns),
                lane: lane,
                hrDomain: read.hrDomain(zone: zone, includeLongRuns: includeLongRuns),
                efficiencyDomain: read.efficiencyDomain(
                    zone: zone, includeLongRuns: includeLongRuns, basis: basis
                ),
                medianEfficiency: read.medianEfficiency(
                    zone: zone, includeLongRuns: includeLongRuns, basis: basis
                ),
                hrFloor: zone.flatMap { read.floors.floor(for: $0) },
                density: .full,
                height: 250,
                dotRadius: 4.4,
                selected: $selected,
                onOpen: openWorkout
            )
            .padding(.top, 14)
            .onChange(of: visible.map(\.id)) { _, ids in
                if selected == nil || !ids.contains(selected?.id ?? "") {
                    selected = visible.last
                }
            }

            chartFooter(read: read, visible: visible)

            KeyPaceLegend(
                read: read,
                includeLongRuns: includeLongRuns,
                showHeatTicks: showHeatTicks,
                mode: mode,
                basis: basis,
                hasVolume: read.volumeDomain(zone: zone, includeLongRuns: includeLongRuns) != nil,
                lane: lane,
                hrFloor: zone.flatMap { read.floors.floor(for: $0) },
                density: .full
            )

            KeyPaceStatRow(
                read: read, zone: zone, includeLongRuns: includeLongRuns, basis: basis
            )

            InstrumentNote(
                KeyPaceProse.note(
                    read: read, zone: zone, includeLongRuns: includeLongRuns, basis: basis
                )
            )

            bandAccordion(read: read)
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    /// The band caveat and the readout, grouped so the panel's `VStack` stays
    /// clear of `ViewBuilder`'s ten-child ceiling.
    @ViewBuilder
    private func chartFooter(read: KeyPaceRead, visible: [KeyPacePoint]) -> some View {
        if mode == .vsTarget, zone == nil, read.hasBand {
            // A band is anchor-relative, and across zones there is no single
            // anchor to draw it against. Say so rather than drawing one zone's
            // band behind every zone's dots.
            Text("BAND HIDDEN · SELECT ONE ZONE TO SEE IT")
                .instrumentTick()
                .padding(.top, 10)
        }

        if let point = selected ?? visible.last {
            KeyPaceReadout(point: point, basis: basis, onOpen: openWorkout)
                .padding(.top, 12)
        }
    }

    /// The two axis controls, grouped so the panel's `VStack` stays clear of
    /// `ViewBuilder`'s ten-child ceiling.
    private var segments: some View {
        VStack(spacing: 8) {
            modeSegment
            basisSegment
            laneSegment
        }
    }

    /// Which second track to show. Efficiency leads because a bpm number is
    /// not comparable between sessions and metres per beat is.
    private var laneSegment: some View {
        HStack(spacing: 0) {
            ForEach(KeyPaceLane.allCases) { option in
                Button {
                    lane = option
                } label: {
                    Text(option.label)
                        .font(.dripEyebrow(microType).weight(.semibold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(lane == option ? Color.drip.background : Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .background(lane == option ? Color.drip.textPrimary : Color.drip.cardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lane, \(option.label)")
                .accessibilityAddTraits(lane == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: Mode

    private var modeSegment: some View {
        HStack(spacing: 0) {
            ForEach(KeyPaceMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(.dripEyebrow(microType).weight(.semibold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(mode == option ? Color.drip.background : Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                        .background(mode == option ? Color.drip.textPrimary : Color.drip.cardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.drip.divider, lineWidth: 1))
    }

    /// Which pace the surface leads with. Two states, both named in full — a
    /// switch labelled only "adjust for heat" would leave the athlete guessing
    /// which number she is currently reading.
    private var basisSegment: some View {
        HStack(spacing: 0) {
            ForEach(KeyPaceBasis.allCases) { option in
                Button {
                    basis = option
                } label: {
                    Text(option.label)
                        .font(.dripEyebrow(microType).weight(.semibold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(basis == option ? Color.drip.background : Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .background(basis == option ? Color.drip.textPrimary : Color.drip.cardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(basis == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.drip.divider, lineWidth: 1))
    }

    // MARK: Toggles

    private var toggles: some View {
        HStack(spacing: 6) {
            toggle("Long runs", isOn: includeLongRuns) { includeLongRuns.toggle() }
            toggle("Show \(basis.other.short.lowercased())", isOn: showHeatTicks) { showHeatTicks.toggle() }
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dripEyebrow(microType).weight(.semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(isOn ? Color.drip.background : Color.drip.textSecondary)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(isOn ? Color.drip.textPrimary : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.clear : Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Band controls

    @ViewBuilder
    private func bandAccordion(read: KeyPaceRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline().padding(.top, 16)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { controlsExpanded.toggle() }
            } label: {
                HStack {
                    Text("THE BAND · \(bandSummary(read))")
                        .font(.dripEyebrow(microType).weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: controlsExpanded ? "minus" : "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint(controlsExpanded ? "Collapses the band controls" : "Expands the band controls")

            if controlsExpanded {
                TrendsThresholdControls(
                    settings: $settings,
                    ladder: read.ladder,
                    accent: accent,
                    layout: .tabbed
                )
                .padding(.top, 8)
                .transition(.opacity)

                Text("These write to the one band this app has. Move an edge here and Trends section 04 has already moved.")
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 12)
            }
        }
    }

    private func bandSummary(_ read: KeyPaceRead) -> String {
        guard let anchorSec = read.anchorSec else {
            return "NO LADDER YET"
        }
        let floor: String
        if settings.hrFloor <= 0 {
            floor = "GRADING OFF"
        } else if let zone, let derived = read.floors.floor(for: zone) {
            floor = "\(KeyZone.label(zone).uppercased()) FLOOR \(derived)"
        } else {
            floor = "FLOOR PER ZONE"
        }
        return "\(settings.anchor.label) \(TrendsFormat.pace(anchorSec)) \(settings.widthLabel) · \(floor)"
    }

    // MARK: Session list

    @ViewBuilder
    private func sessionPanel(read: KeyPaceRead, visible: [KeyPacePoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SESSIONS")
                    .font(.dripEyebrow(smallType))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Text("\(visible.count)")
                    .font(.dripEyebrow(smallType))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
            }

            Text("Newest first. Tap one to open the workout.")
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 5)

            if visible.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    title: "No key sessions in this zone and window. Log a workout and it appears here, and as a dot above."
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(visible.reversed())) { point in
                    row(point: point, read: read)
                    if point.id != visible.first?.id { Hairline() }
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.top, 14)
    }

    private func row(point: KeyPacePoint, read: KeyPaceRead) -> some View {
        Button {
            openWorkout(point)
        } label: {
            HStack(spacing: 9) {
                KeyPaceMark(
                    grade: point.grade,
                    isLongRun: point.isLongRun,
                    colour: KeyZone.color(point.zone),
                    radius: 4
                )
                .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(KeyZone.label(point.zone).uppercased())
                            .font(.dripEyebrow(8).weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.cardBackground)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(KeyZone.color(point.zone))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(rowCaption(point: point, read: read))
                            .font(.dripEyebrow(8.5))
                            .tracking(0.68)
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Text(point.structure ?? "\(KeyZone.label(point.zone)) session")
                        .font(.dripDisplay(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(TrendsFormat.pace(point.sec(basis)))
                        .font(.dripStat(13))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(rowTrailing(point: point))
                        .font(.dripEyebrow(8))
                        .tracking(0.64)
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(point.accessibilityLabel)")
    }

    private func rowCaption(point: KeyPacePoint, read: KeyPaceRead) -> String {
        var bits = [point.dateLabel.uppercased()]
        if let volume = point.volumeShortLabel { bits.append(volume) }
        if let efficiency = point.efficiencyLabel(basis) { bits.append(efficiency) }
        else if let hr = point.hrAvg { bits.append("\(hr) BPM") }
        switch point.grade {
        case .work: bits.append("WORK")
        case .cruise:
            bits.append(read.floors.floor(for: point.zone).map { "UNDER \($0)" } ?? "CRUISE")
        case .unclassed: bits.append("NO HR")
        }
        if read.isInBand(point, basis: basis) { bits.append("IN BAND") }
        return bits.joined(separator: " · ")
    }

    private func rowTrailing(point: KeyPacePoint) -> String {
        var bits: [String] = []
        if point.hasCorrection {
            bits.append("+\(point.correctionSec)s HEAT → \(TrendsFormat.pace(point.sec(basis.other)))")
        }
        if let delta = point.delta(basis) {
            bits.append("\(KeyPaceProse.signedSec(delta)) VS \(KeyZone.label(point.zone).uppercased())")
        }
        return bits.isEmpty ? "LOGGED" : bits.joined(separator: " · ")
    }

    // MARK: Not counted

    @ViewBuilder
    private func notCountedPanel(read: KeyPaceRead) -> some View {
        if let text = KeyPaceProse.notCounted(
            read: read, zone: zone, includeLongRuns: includeLongRuns
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOT COUNTED")
                    .font(.dripEyebrow(smallType))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                Text(text)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.top, 14)
        }
    }

    // MARK: Plumbing

    private func bandTuple(_ read: KeyPaceRead) -> (fast: Int, slow: Int)? {
        guard mode == .absolute, let fast = read.fastSec, let slow = read.slowSec else { return nil }
        return (fast, slow)
    }

    private func openWorkout(_ point: KeyPacePoint) {
        Task {
            dayWorkouts = await service.resolveDay(dayISO: point.date, focusLogId: point.id)
        }
    }
}
