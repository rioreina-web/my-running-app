//
//  InstrumentsTabView.swift
//  RunningLog · Trends
//
//  The Charts tab — "The Instruments." A feed of expandable data-viz cards:
//  volume, key pace, efficiency, mood, heat, key sessions, reps, head to head,
//  mood × volume, pace ladder.
//
//  Card pattern (from `Post Run Drip Design System/trends-expandable-cards-mock.html`):
//  collapsed = eyebrow + headline + right-hand stat; tap expands to the chart, a
//  stat row, and a derived observation.
//
//  **Every figure comes from `TrendsService`** — the same real feed `TrendsV2View`
//  uses — via the derivations in `InstrumentsCardKit.swift`. Headlines are
//  computed from those series rather than authored, so a card cannot claim
//  something the data doesn't show. Cards with no rows render `EmptyStateView`.
//
//  Like `TrendsTabView`, this host gates the fetch: every tab is constructed at
//  launch and merely hidden with `.opacity`, so loading has to wait until the
//  athlete actually opens the tab. It shares `TrendsService.shared` with Trends,
//  so opening both never doubles the fetch.
//

import SwiftUI

// MARK: - InstrumentsTabView

struct InstrumentsTabView: View {
    @Environment(\.selectedTab) private var selectedTab

    @State private var service = TrendsService.shared

    /// This tab's index in `DripTabBar` (`DripTab.instruments`).
    private static let tabIndex = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(surface: "RUNNING LOG — THE INSTRUMENTS")
                    .padding(.top, 16)   // breathing room under the status bar

                if service.isLoading, service.weeks.isEmpty {
                    loading
                } else if let error = service.lastError, service.weeks.isEmpty {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "COULDN'T LOAD",
                        title: error.localizedDescription,
                        cta: .init(label: "Try again") {
                            Task { await service.refresh(force: true) }
                        }
                    )
                    .padding(.top, 40)
                } else {
                    cards
                }

                // No footer: this surface has no caption to print, and the
                // standing tagline that used to sit here was removed
                // 2026-08-09 (see `PlateFooter`).
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.drip.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: selectedTab.wrappedValue) {
            if selectedTab.wrappedValue == Self.tabIndex {
                await service.refresh()
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        sectionHeader("TRAINING", coral: true, note: "TAP A CARD TO OPEN")
        InstrumentVolumeCard(service: service)
        InstrumentKeyPaceCard(service: service)
        InstrumentEfficiencyCard(service: service)

        EditorialRule().padding(.vertical, 24)

        sectionHeader("BODY & CONDITIONS")
        InstrumentMoodCard(service: service)
        InstrumentHeatCard(service: service)

        EditorialRule().padding(.vertical, 24)

        sectionHeader("SESSIONS")
        InstrumentKeySessionsCard(service: service)
        InstrumentRepsCard(service: service)
        InstrumentHeadToHeadCard(service: service)

        EditorialRule().padding(.vertical, 24)

        sectionHeader("SYNTHESIS")
        InstrumentMoodLoadCard(service: service)
        InstrumentPaceLadderCard(service: service)
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Color.drip.coral)
            Text("READING YOUR LOG")
                .font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sectionHeader(_ title: String, coral: Bool = false, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(coral ? Color.drip.coral : Color.drip.textSecondary)
            Spacer()
            if let note {
                Text(note)
                    .font(.dripEyebrow(9))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.top, 18)
    }
}

// MARK: - Previews

#Preview("Instruments tab") {
    NavigationStack {
        InstrumentsTabView()
    }
}
