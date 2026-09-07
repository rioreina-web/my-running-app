//
//  AskTabView.swift
//  RunningLog · Analysis
//
//  Ask as its own destination — tab 10, in the slot Charts held until
//  2026-08-19.
//
//  WHAT THIS IS: the free-text chat. You type anything, `coaching-agent`
//  answers in prose, the thread stays. It is deliberately NOT the analyzer
//  chip rail — a fixed catalog of pre-written questions answering in cards
//  is a narrower surface than the athlete's actual questions, and the cards
//  it produced were under-developed. Both the rail (`AskBar`) and the card
//  (`AskAnswerCard`) stay in the repo, unlinked, along with the sheet that
//  hosted them (`CoachAskSheet`). Nothing presents them as of 2026-08-19.
//
//  REPLACED 2026-08-31. The tab now renders `AskWildHomeView` — the
//  composer-first Ask surface on Direction I. `AskTipsView` stays in the
//  repo, unlinked, as `AskBar`, `AskAnswerCard` and `WelcomeCard` did before
//  it. See `AskWildHomeView` for why the tips lost the landing slot.
//
//  LAZY MOUNT — READ BEFORE MOVING THIS INTO THE ZSTACK EAGERLY. Every
//  other tab is mounted at launch and hidden with `.opacity`, which is free
//  because none of them do anything on appear. `CoachView` is different: its
//  `.task` calls `healthKitManager.requestAuthorization()`, loads the active
//  plan and runs a fitness prediction. Mounted eagerly that fires the
//  HealthKit permission prompt at app launch, in front of an athlete who
//  never opened Ask. `MainTabView` therefore holds it behind a
//  first-visit flag; once opened it stays mounted, so the thread survives
//  tab switches.
//

import SwiftUI

struct AskTabView: View {
    var body: some View {
        // 2026-08-31: the tab lands on the composer. Tips were a landing
        // page in front of a question box; they are now suggested pulls
        // inside the one screen.
        //
        // The lazy-mount flag in `MainTabView` stays redundant and harmless:
        // `CoachView` is not constructed here at all any more, so its
        // HealthKit authorisation prompt cannot fire on tab entry.
        AskWildHomeView()
    }
}
