//
//  WorkoutRepDetailSheet.swift
//  RunningLog
//
//  THE single canonical workout-detail sheet.
//
//  Every "tap a completed run" entry point routes here: the history log
//  (HistoryDetailSheet), the workouts list (WorkoutsView), the day sheet
//  (DayDetailSheet), and the analytics deep-links (WorkoutAnalysisLink).
//  It wraps `WorkoutRepReceiptView` (Direction A "Rep Receipt") — the hero
//  rep chart, HR/pace/cadence/elevation telemetry, time-in-zone, per-rep
//  recovery, the prescribed-workout notes block, ANALYSIS, and the
//  diverging SPLITS-vs-target table — in standard sheet chrome.
//
//  This replaced a sprawl of parallel detail surfaces (WorkoutAnalystView,
//  WorkoutAnalysisView, the Plate-23 VitalWorkoutDetailView). RepChart reads
//  the clean rep-level `running_workout_laps` table rather than the
//  external_streams blob, so it doesn't depend on the stream parser at all.
//
//  `workoutId` is the `training_logs` row id for the run (the same id
//  WorkoutsAndRepsSection and CoachReadView already hand to RepChart).
//

import SwiftUI

struct WorkoutRepDetailSheet: View {
    let workoutId: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                WorkoutRepReceiptView(workoutId: workoutId)
                    .padding(20)
            }
            .background(Color.drip.background.ignoresSafeArea())
            // Without an opaque nav bar the 34pt headline scrolls UNDER it and
            // clips — the artefact in the 2026-08-06 screenshot.
            // `HistoryDetailSheet` and `EditWorkoutNotesSheet` both set this;
            // this sheet was the one that didn't. (2026-08-07)
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("WORKOUT")
                        .font(.dripStat(10)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                }
                // Drag-to-dismiss was the only way out. Every other sheet in
                // the app offers an explicit exit.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
