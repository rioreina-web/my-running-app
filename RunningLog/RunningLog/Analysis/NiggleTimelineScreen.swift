//
//  NiggleTimelineScreen.swift
//  RunningLog
//
//  The niggle timeline as its own destination, reachable from the menu.
//
//  The timeline first shipped as a card buried on the injuries screen, below
//  the active-ache list. That made it effectively undiscoverable: nothing in
//  the app named it, and you had to already know to open Injuries and scroll.
//  Aches are the thing runners go looking for by name, so the timeline gets
//  its own door.
//
//  Same component as the card on the injuries screen — one implementation,
//  two entry points. Here it mounts expanded, because arriving on a screen
//  called "Niggles" and finding a collapsed row would be silly.
//

import SwiftUI
import Supabase

struct NiggleTimelineScreen: View {
    @State private var injuryService = InjuryService()
    /// The run being read. Set by `openRun`, presented as the same
    /// `HistoryDetailSheet` the journal and Trends use — one workout sheet,
    /// reached from a new place.
    @State private var openWorkoutLog: TrainingLog?

    @Environment(\.openGoalEditor) private var openGoalEditor

    private var timeline: NiggleTimeline { injuryService.niggleTimeline }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PlateStrip(
                        surface: "NIGGLES  ·  MENTION TIMELINE",
                        fig: TrainingDateline.string(for: ActiveGoalStore.shared.soonestActiveGoal),
                        onFigTap: openGoalEditor
                    )
                        .padding(.top, 16)

                    header

                    if timeline.isEmpty {
                        emptyState
                    } else {
                        EditorialRule()
                        NiggleTimelineCard(
                            timeline: timeline,
                            startExpanded: true,
                            onResolve: { thread in
                                Task {
                                    _ = await injuryService.resolveNiggle(
                                        bodyArea: thread.bodyArea,
                                        side: thread.dominantSide == .unspecified
                                            ? "" : thread.dominantSide.rawValue
                                    )
                                }
                            },
                            onOpenRun: { logId in openRun(logId) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $openWorkoutLog) { log in
            HistoryDetailSheet(entry: log, onUpdate: {})
        }
        .task { await injuryService.fetchAll() }
        .task { await ActiveGoalStore.shared.loadIfNeeded() }
    }

    /// Loads the run a mention was recorded on and opens its sheet. Same
    /// fetch-by-id `SignalLabView` uses for its scrubbed points.
    private func openRun(_ id: UUID) {
        Task {
            let rows: [TrainingLog] = (try? await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .eq("id", value: id.uuidString.lowercased())
                .limit(1)
                .execute()
                .value) ?? []
            guard let log = rows.first else { return }
            await MainActor.run { openWorkoutLog = log }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text("What you've mentioned")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Every ache you've said out loud, when you said it, and what the training was doing that week. Counts only — not a diagnosis.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        timeline.activeCount > 0
            ? "TRACKING NOW  ·  \(timeline.activeCount)"
            : "NOTHING ACTIVE"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing mentioned yet")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Mention an ache in a voice memo — \u{201C}left achilles was tight this morning\u{201D} — and it lands here on its own.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
        .padding(.top, 32)
    }
}
