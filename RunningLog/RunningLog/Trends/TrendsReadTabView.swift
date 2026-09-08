//
//  TrendsReadTabView.swift
//  RunningLog · Trends
//
//  Host for `TrendsReadView` — the fetch gate, and nothing else.
//
//  Mirrors `TrendsTabView` deliberately, including the reason it exists:
//  every tab in `MainTabView` is constructed at launch and merely hidden
//  with `.opacity`, so a plain `.task` on the content would fire a
//  timeline request for a tab nobody opened. The gate lives here.
//
//  It reads the same `TrendsService.shared` the Trends tab does, so
//  opening either tab populates both and there is still exactly one fetch
//  owner. `refresh()` is a no-op once loaded, so the second visit is free.
//
//  The service hands back the whole fetched window — six months of days.
//  `TrendsReadView` slices that into calendar months and shows one at a
//  time; the host does not window it, so the month stepper has every month
//  the payload contains to walk back through.
//
//  UNLINKED as of 2026-08-19. This was the DEBUG-only comparison surface
//  for the Read, mounted beside Trends at tag 7 so the two could be judged
//  on device. Trends won, so both the branch in `MainTabView` and the
//  `DripTab.read` case are gone and tag 7 is retired — do not reuse it.
//  The view is kept, not deleted, so the surface can be restored as a tab
//  or pushed from one without rebuilding it.
//

import SwiftUI

struct TrendsReadTabView: View {
    @Environment(\.selectedTab) private var selectedTab

    @State private var service = TrendsService.shared

    /// The Read's tab index in `DripTabBar`. Fresh tag — see `DripTab`.
    private static let tabIndex = 7

    var body: some View {
        TrendsReadView(days: service.days, keySessions: service.keySessions)
            .background(Color.drip.background)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: selectedTab.wrappedValue) {
                if selectedTab.wrappedValue == Self.tabIndex {
                    await service.refresh()
                }
            }
    }
}

#Preview("The Read · tab host") {
    NavigationStack {
        TrendsReadView(
            days: TrendsDay.previewMonthRich,
            keySessions: KeySession.previewLadder
        )
    }
}
