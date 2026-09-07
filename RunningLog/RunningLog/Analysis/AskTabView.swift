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
        // 2026-08-19: Ask now lands on TIPS, not the chat. Three or four
        // things that would move the athlete's goal, derived from training
        // they have actually done — see `AskTipsView`. The free-text chat is
        // one tap down from there.
        //
        // This also makes the lazy-mount flag in `MainTabView` redundant:
        // `CoachView` is no longer constructed until the athlete taps through,
        // so its HealthKit authorisation prompt cannot fire on tab entry, let
        // alone at launch. The flag is harmless and stays for now.
        AskTipsView()
    }
}
