//
//  WorkoutAnalysisLink.swift
//  RunningLog · Training › Analytics
//
//  Shared plumbing for deep-linking a session into the canonical per-workout
//  detail (WorkoutRepDetailSheet → WorkoutRepChart). Both the Volume detail
//  sheet and the Day analysis sheet present the same view the same way; this
//  gives them one target type and one presentation modifier.
//

import SwiftUI

/// A session to open in the canonical workout sheet. `id` is the
/// `training_logs` row id — the key `running_workout_laps` is joined on.
struct WorkoutAnalysisTarget: Identifiable {
    let id: UUID
    let workout: RunningWorkout
}

extension View {
    /// Presents the canonical `WorkoutRepDetailSheet` for the bound target.
    func workoutAnalysisSheet(_ item: Binding<WorkoutAnalysisTarget?>) -> some View {
        sheet(item: item) { target in
            WorkoutRepDetailSheet(workoutId: target.id)
        }
    }
}
