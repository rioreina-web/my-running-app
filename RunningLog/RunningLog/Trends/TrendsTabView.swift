//
//  TrendsTabView.swift
//  RunningLog · Trends
//
//  The Trends tab. Since 2026-08-03 this is a thin host around
//  `TrendsV2View` — the five-signal surface (mileage · key work · recovery ·
//  mood · niggles on one 30-day axis). See
//  `outputs/trends-audit-2026-08-03.md` for why the swap was made.
//
//  The previous tab is intact in `TrendsLegacyTabView` and is one tap away in
//  DEBUG builds via the `v1 ›` capsule in the v2 header. Nothing was deleted:
//  the pace spectrum, threshold miles and race prediction live there until
//  they get a screen that suits them — they answer "how fast am I", which is
//  a different question from "how am I trending", and mixing the two is what
//  made the old tab an eleven-block scroll.
//
//  This host exists for one reason beyond the swap: the tab must not fetch
//  until the athlete actually opens it. Every tab in `RunningLogApp` is
//  constructed at launch and merely hidden with `.opacity`, so a plain
//  `.task` on the content view would fire a timeline request for a tab that
//  was never visited. The gate lives here and `TrendsV2View` takes
//  `autoLoad: false`.
//

import SwiftUI

struct TrendsTabView: View {
    @Environment(\.selectedTab) private var selectedTab

    @State private var service = TrendsService.shared

    /// Visits to the Trends page, ever. Read by `TrendsV2View` to retire the
    /// section explainers once the page has stopped being new.
    @AppStorage("trendsV2Visits") private var visitCount: Int = 0

    #if DEBUG
    @State private var showLegacy = false
    #endif
    /// The Signal Lab, opened as a sheet from the Trends header. A sheet and
    /// not a tab, deliberately: the tab bar is the app's daily destinations,
    /// and the Lab is where you go when you want to look hard at one thing.
    @State private var showLab = false

    /// The Trends tab's index in `DripTabBar`.
    private static let tabIndex = 4

    var body: some View {
        content
            .background(Color.drip.background)
            .toolbar(.hidden, for: .navigationBar)
            // Load when the tab becomes active. `refresh()` is a no-op once
            // loaded, so re-entry is cheap and no fetch fires for a tab the
            // athlete never opens.
            .task(id: selectedTab.wrappedValue) {
                if selectedTab.wrappedValue == Self.tabIndex {
                    // A visit is counted here rather than in `TrendsV2View`'s
                    // `onAppear`, because every tab is constructed at launch
                    // and merely hidden with `.opacity` — `onAppear` fires
                    // once, for a page nobody has opened. This is the same
                    // signal the fetch gate uses, and it's what decides
                    // whether the section explainers still show.
                    visitCount += 1
                    await service.refresh()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        TrendsV2View(
            service: service,
            autoLoad: false,
            onOpenLegacy: { showLegacy = true },
            onOpenLab: { showLab = true }
        )
        .sheet(isPresented: $showLab) { SignalLabView(service: service) }
        .fullScreenCover(isPresented: $showLegacy) {
            NavigationStack {
                TrendsLegacyTabView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showLegacy = false }
                        }
                        ToolbarItem(placement: .principal) {
                            Text("TRENDS · V1")
                                .font(.dripEyebrow(11)).tracking(1.3)
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    .toolbarBackground(Color.drip.background, for: .navigationBar)
            }
        }
        #else
        TrendsV2View(
            service: service,
            autoLoad: false,
            onOpenLab: { showLab = true }
        )
        .sheet(isPresented: $showLab) { SignalLabView(service: service) }
        #endif
    }
}

#Preview("Trends tab") {
    NavigationStack {
        TrendsV2View(
            service: TrendsService(
                preview: [],
                days: TrendsDay.previewMonthRich,
                keySessions: KeySession.previewLadder
            )
        )
    }
}
