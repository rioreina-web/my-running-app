//
//  CoachNoteSection.swift
//  RunningLog
//
//  The coach-note beat on the WEEK view. Sits between two EditorialRules
//  so it reads as its own block, not as a card.
//
//      FROM YOUR COACH
//      "Hold splits, don't chase them — negative is fine, positive is not."
//
//  Coral discipline: coral eyebrow ("FROM YOUR COACH") plus the 2pt
//  coral-at-50% left bar on CoachQuote — the one sanctioned coral
//  left-border in the design system. Per the redesign handoff, this
//  cluster earns its coral because the surrounding section is otherwise
//  neutral.
//
//  Data source: `weekly_coaching_reports.coaching_narrative` for the
//  current week. The parent falls back to a locally-assembled narrative
//  (lifted from the retired TrainingDashboardView) when the server row
//  isn't there yet.
//

import SwiftUI

struct CoachNoteSection: View {
    let quote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FROM YOUR COACH")
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            CoachQuote(text: quote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
