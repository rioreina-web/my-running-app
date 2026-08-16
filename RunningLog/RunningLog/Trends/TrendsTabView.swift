//
//  TrendsTabView.swift
//  RunningLog · Trends
//
//  The Trends tab. Since 2026-08-11 this is a thin host around
//  `TrendsLegacyTabView` — the v1 surface, restored as the tab (Rio).
//
//  Why the swap back: v2 answered "how am I trending" with five signals on one
//  axis and little else. v1 answers the same question with the sections the
//  athlete actually opens the tab for — load and the ramp, where the miles
//  fell, the key-session grid, recovery, where the block points. Two things v1
//  did not have came back with it from v2, and only those two:
//
//    • THE RECOVERY SCORE — the ledger card, closing section 04.
//    • ASK — the chip rail at the foot of the scroll.
//
//  `TrendsV2View` is unlinked, not deleted. No door leads to it from the tab
//  in either build configuration; the file stays in the target and is still
//  reachable in DEBUG via the `-trendsV2Preview` launch argument in
//  `RunningLogApp`. See `outputs/trends-audit-2026-08-03.md` for the swap it
//  was made in, which this reverses.
//
//  The Signal Lab kept its door. It was reachable from v2's header and nowhere
//  else, so dropping v2 from the tab would have orphaned it; the `lab ›` chip
//  moved to v1's header unchanged.
//
//  This host exists for one reason beyond the swap: the tab must not fetch
//  until the athlete actually opens it. Every tab in `RunningLogApp` is
//  constructed at launch and merely hidden with `.opacity`, so a plain
//  `.task` on the content view would fire a timeline request for a tab that
//  was never visited. `TrendsLegacyTabView` carries that gate itself — it
//  checks the selected tab index before refreshing — so there is exactly one
//  fetch owner and this host does not add a second.
//

import SwiftUI

struct TrendsTabView: View {
    @State private var service = TrendsService.shared

    /// The Signal Lab, opened as a sheet from the Trends header. A sheet and
    /// not a tab, deliberately: the tab bar is the app's daily destinations,
    /// and the Lab is where you go when you want to look hard at one thing.
    @State private var showLab = false

    var body: some View {
        TrendsLegacyTabView(service: service, onOpenLab: { showLab = true })
            .background(Color.drip.background)
            .toolbar(.hidden, for: .navigationBar)
            // A sheet, not a fullScreenCover: a sheet can always be swiped
            // away, so a missing toolbar can never trap the athlete on this
            // screen again.
            .sheet(isPresented: $showLab) { SignalLabView(service: service) }
    }
}

#Preview("Trends tab") {
    NavigationStack {
        TrendsLegacyTabView(
            service: TrendsService(
                preview: TrendsSampleData.weeks,
                days: TrendsDay.previewMonthRich,
                keySessions: KeySession.previewLadder
            )
        )
    }
}
