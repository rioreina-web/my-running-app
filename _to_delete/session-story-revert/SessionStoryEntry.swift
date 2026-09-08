//
//  SessionStoryEntry.swift
//  RunningLog
//
//  The doorway into the Session Story sheet: a horizontal strip of the
//  window's key sessions (newest first), one card each — date, structure,
//  kind. Tap a card, get that session told whole (SessionStoryView), with
//  the previous comparable session as its ghost.
//
//  Lives inside the Key sessions section of TrendsTabView, under the grid
//  and the detail — the grid shows the rhythm, the detail shows the trend,
//  and this answers "now tell me about THAT day."
//
//  Honest degradation: no key sessions → the empty-state component
//  (never an em-dash, hard rule #8).
//

import SwiftUI

struct SessionStoryEntry: View {
    let sessions: [KeySession]

    @State private var selected: KeySession?

    /// Newest first — the session you just ran is the one you want told.
    private var ordered: [KeySession] {
        sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        if ordered.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "No stories yet",
                title: "Key sessions with lap data get a full story here — segments, drift, conditions, and your own words."
            )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ordered) { session in
                        card(session)
                    }
                }
            }
            .sheet(item: $selected) { session in
                SessionStoryView(keySession: session, allSessions: sessions)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func card(_ session: KeySession) -> some View {
        Button {
            selected = session
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.dateLabel.uppercased())
                    .font(.dripEyebrow(8)).tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary)
                Text(session.structure ?? session.zone.uppercased())
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1)
                Text(session.isLongRun ? "LONG RUN" : session.zone.uppercased())
                    .font(.dripEyebrow(8)).tracking(0.6)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .frame(width: 118, alignment: .leading)
            .padding(10)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
