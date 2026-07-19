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

    var body: some View {
        NavigationStack {
            ScrollView {
                WorkoutRepReceiptView(workoutId: workoutId)
                    .padding(20)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("WORKOUT")
                        .font(.dripStat(10)).tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
