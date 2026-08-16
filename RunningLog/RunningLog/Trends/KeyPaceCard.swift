//
//  KeyPaceCard.swift
//  RunningLog · Trends
//
//  Instruments card 02 — key pace. Lifted out of `InstrumentsCardsTraining.swift`
//  on 2026-08-09 when it stopped being a weekly average and became a
//  session-level chart with a target behind it and a workout on the other side
//  of a tap. See `KeyPaceModels.swift` for the diagnosis and the rules.
//
//  Collapsed, this card is a glance: a headline that names its zone, and the
//  latest pace in that zone. Expanded, it is the same `KeyPaceChart` the
//  detail renders, at 140pt instead of 250 — one renderer, so the glance and
//  the detail can never disagree about the same sessions.
//
//  **On the window.** The Instruments tab has no time control of its own, so
//  this card owns one and hands a binding to its detail. That is deliberately
//  card-local state, NOT a second global control competing with the Trends
//  tab's: change it here and only this card moves. When the Instruments tab
//  grows a host-level picker, hoist these four `@State`s into the host and pass
//  bindings down — do not add a second picker beside it.
//

import SwiftUI

struct InstrumentKeyPaceCard: View {
    let service: TrendsService

    /// One band, shared with Trends section 04 and the Signal Lab. Moving the
    /// slow edge in any of the three moves it in all of them.
    @State private var settingsStore = BandSettingsStore.shared

    @State private var window: TrendsWindow = .sixMonths
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
    @State private var customTo = Date()

    /// `nil` means ALL. Seeded once to the dominant zone so the card opens on
    /// the zone its own headline is speaking about, then left to the athlete.
    @State private var zone: String?
    @State private var didSeedZone = false

    @State private var includeLongRuns = false
    @State private var showHeatTicks = true
    @State private var mode: KeyPaceMode = .absolute
    /// Watch pace leads. The correction is still computed and still available
    /// one tap away in the detail — it is offered, not applied behind her back.
    @State private var basis: KeyPaceBasis = .watch
    /// The second lane costs 34pt. The card is the glance; the detail is where
    /// it earns that space.
    @State private var lane: KeyPaceLane = .efficiency
    @State private var selected: KeyPacePoint?
    @State private var showDetail = false
    @State private var dayWorkouts: DayWorkouts?

    private var read: KeyPaceRead {
        KeyPaceBuilder.read(
            sessions: service.keySessions,
            bandLaps: service.bandLaps,
            settings: settingsStore.settings,
            window: window
        )
    }

    var body: some View {
        let read = self.read
        let visible = read.points(zone: zone, includeLongRuns: includeLongRuns)

        InstrumentCard(
            eyebrow: "KEY PACE",
            title: KeyPaceProse.headline(read: read, includeLongRuns: includeLongRuns, basis: basis),
            sub: KeyPaceProse.subtitle(read: read, includeLongRuns: includeLongRuns)
        ) {
            trailingStat(read: read)
        } content: {
            if read.isEmpty {
                InstrumentEmpty(
                    title: "Log a quality session and it appears here as a dot you can open."
                )
            } else {
                expanded(read: read, visible: visible)
            }
        }
        .task(id: service.keySessions.count) { seedZone(read: read) }
        .sheet(item: $dayWorkouts) { workouts in
            HistoryDetailPager(entries: workouts.entries, initial: workouts.initial, onUpdate: {})
        }
        .fullScreenCover(isPresented: $showDetail) {
            KeyPaceDetailView(
                service: service,
                settings: $settingsStore.settings,
                window: $window,
                customFrom: $customFrom,
                customTo: $customTo,
                zone: $zone,
                includeLongRuns: $includeLongRuns,
                showHeatTicks: $showHeatTicks,
                lane: $lane,
                mode: $mode,
                basis: $basis,
                selected: $selected
            )
        }
    }

    // MARK: Collapsed stat

    @ViewBuilder
    private func trailingStat(read: KeyPaceRead) -> some View {
        if let dominant = read.dominantZone(includeLongRuns: includeLongRuns),
           let latest = read.latest(zone: dominant, includeLongRuns: includeLongRuns) {
            InstrumentStat(
                value: TrendsFormat.pace(latest.sec(basis)),
                caption: "/ MI · \(KeyZone.label(dominant).uppercased()) · LATEST"
            )
        }
    }

    // MARK: Expanded

    @ViewBuilder
    private func expanded(read: KeyPaceRead, visible: [KeyPacePoint]) -> some View {
        KeyPaceZoneChips(read: read, includeLongRuns: includeLongRuns, zone: $zone)
            .padding(.bottom, 4)

        KeyPaceChart(
            points: visible,
            anchorSteps: read.anchorSteps,
            band: bandTuple(read),
            anchorSec: read.anchorSec,
            anchorColor: read.anchor.color(in: read.ladder),
            lowConfidence: read.lowConfidence,
            mode: .absolute,
            basis: basis,
            showHeatTicks: showHeatTicks,
            trend: read.trendLine(zone: zone, includeLongRuns: includeLongRuns, basis: basis),
            volumeDomain: read.volumeDomain(zone: zone, includeLongRuns: includeLongRuns),
            lane: .off,
            hrDomain: nil,
            efficiencyDomain: nil,
            hrFloor: zone.flatMap { read.floors.floor(for: $0) },
            density: .glance,
            height: 168,
            dotRadius: 3.8,
            hint: "DRAG TO SCRUB",
            selected: $selected,
            onOpen: openWorkout
        )
        .onChange(of: visible.map(\.id)) { _, ids in
            // The filter moved under the crosshair. Land on the newest visible
            // session rather than leaving the readout pointing at a dot that
            // is no longer drawn.
            if selected == nil || !ids.contains(selected?.id ?? "") {
                selected = visible.last
            }
        }

        if let point = selected ?? visible.last {
            KeyPaceReadout(point: point, basis: basis, onOpen: openWorkout)
                .padding(.top, 12)
        }

        KeyPaceLegend(
            read: read,
            includeLongRuns: includeLongRuns,
            showHeatTicks: showHeatTicks,
            mode: .absolute,
            basis: basis,
            hasVolume: read.volumeDomain(zone: zone, includeLongRuns: includeLongRuns) != nil,
            density: .glance
        )

        KeyPaceStatRow(read: read, zone: zone, includeLongRuns: includeLongRuns, basis: basis)

        InstrumentNote(
            KeyPaceProse.note(
                read: read,
                zone: zone,
                includeLongRuns: includeLongRuns,
                basis: basis,
                compact: true
            )
        )

        Button {
            showDetail = true
        } label: {
            Text("⤢  EXPAND · ALL \(read.points.count) SESSIONS")
                .font(.dripEyebrow(9.5).weight(.semibold))
                .tracking(1.35)
                .foregroundStyle(Color.drip.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(Color.drip.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .accessibilityLabel("Expand key pace. All \(read.points.count) sessions.")
    }

    // MARK: Plumbing

    private func bandTuple(_ read: KeyPaceRead) -> (fast: Int, slow: Int)? {
        guard let fast = read.fastSec, let slow = read.slowSec else { return nil }
        return (fast, slow)
    }

    /// Seed the chip to the zone the headline speaks for, once. After that the
    /// athlete owns it — re-seeding on every load would fight her taps.
    private func seedZone(read: KeyPaceRead) {
        guard !didSeedZone, !read.isEmpty else { return }
        didSeedZone = true
        zone = read.dominantZone(includeLongRuns: includeLongRuns)
    }

    private func openWorkout(_ point: KeyPacePoint) {
        Task {
            dayWorkouts = await service.resolveDay(dayISO: point.date, focusLogId: point.id)
        }
    }
}

// MARK: - Previews

#Preview("Key pace card") {
    ScrollView {
        InstrumentKeyPaceCard(service: TrendsService(preview: []))
            .padding(.horizontal, 24)
    }
    .background(Color.drip.background)
}
