//
//  WorkoutAnalysisLink.swift
//  RunningLog · Training › Analytics
//
//  Shared plumbing for deep-linking a session into the full per-workout
//  stream analysis (WorkoutAnalystView). Both the Volume detail sheet and
//  the Day analysis sheet present the same view the same way; this gives
//  them one target type and one presentation modifier instead of three
//  near-identical private copies.
//

import SwiftUI

/// A session to open in `WorkoutAnalystView`. `id` is the `training_logs`
/// row id — also the stream-bearing row for Strava imports (path 1).
struct WorkoutAnalysisTarget: Identifiable {
    let id: UUID
    let workout: RunningWorkout
}

extension View {
    /// Presents `WorkoutAnalystView` for the bound target as a large sheet.
    func workoutAnalysisSheet(_ item: Binding<WorkoutAnalysisTarget?>) -> some View {
        sheet(item: item) { target in
            WorkoutAnalystView(workout: target.workout, trainingLogId: target.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
