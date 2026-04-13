import Foundation
import os
import Supabase
import SwiftUI

@Observable
final class HistoryDetailViewModel {
    var currentEntry: TrainingLog
    var coachInsight: String?
    var isDeleting = false
    var isLinkingWorkout = false
    var isSavingEdits = false
    var isSavingWorkoutNotes = false
    var matchedVitalWorkout: RunningWorkout?

    private let entryId: UUID

    init(entry: TrainingLog) {
        self.entryId = entry.id
        self.currentEntry = entry
        self.coachInsight = entry.coachInsight
    }

    // MARK: - Delete

    @MainActor
    func deleteEntry() async -> Bool {
        isDeleting = true
        do {
            try await supabase
                .from("training_logs")
                .delete()
                .eq("id", value: entryId.uuidString)
                .execute()
            return true
        } catch {
            Log.database.error("Failed to delete entry: \(error)")
            ErrorReporter.shared.report(error, context: "delete log entry")
            isDeleting = false
            return false
        }
    }

    // MARK: - Link Workout

    @MainActor
    func linkWorkout(_ workout: RunningWorkout, workoutNotesText: String) async -> Bool {
        isLinkingWorkout = true
        do {
            let updateData: [String: AnyJSON] = [
                "workout_date": .string(ISO8601DateFormatter().string(from: workout.startDate)),
                "workout_distance_miles": .double(workout.distanceMiles),
                "workout_duration_minutes": .double(workout.durationMinutes),
            ]

            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entryId.uuidString)
                .execute()

            currentEntry = TrainingLog(
                id: currentEntry.id,
                createdAt: currentEntry.createdAt,
                audioUrl: currentEntry.audioUrl,
                notes: currentEntry.notes,
                cleanedNotes: currentEntry.cleanedNotes,
                mood: currentEntry.mood,
                workoutDate: workout.startDate,
                workoutDistanceMiles: workout.distanceMiles,
                workoutDurationMinutes: workout.durationMinutes,
                processingStatus: currentEntry.processingStatus,
                processingError: currentEntry.processingError,
                processingAttempts: currentEntry.processingAttempts,
                transcriptUrl: currentEntry.transcriptUrl,
                coachInsight: coachInsight,
                workoutNotes: workoutNotesText.isEmpty ? nil : workoutNotesText,
                workoutPacePerMile: currentEntry.workoutPacePerMile,
                workoutType: currentEntry.workoutType,
                source: currentEntry.source,
                vitalWorkoutId: currentEntry.vitalWorkoutId,
                paceSegments: currentEntry.paceSegments
            )
            isLinkingWorkout = false
            return true
        } catch {
            Log.database.error("Failed to link workout: \(error)")
            ErrorReporter.shared.report(error, context: "link workout")
            isLinkingWorkout = false
            return false
        }
    }

    // MARK: - Save Coach Insight

    func saveCoachInsight(_ insight: String) {
        Task {
            do {
                let updateData: [String: AnyJSON] = [
                    "coach_insight": .string(insight),
                ]
                try await supabase
                    .from("training_logs")
                    .update(updateData)
                    .eq("id", value: entryId.uuidString)
                    .execute()
                Log.database.info("Coach insight saved to database")
            } catch {
                Log.database.error("Failed to save coach insight: \(error)")
                ErrorReporter.shared.report(error, context: "save coach insight")
            }
        }
    }

    // MARK: - Save Edits

    @MainActor
    func saveEdits(
        mood: String,
        workoutType: String,
        distanceText: String,
        durationText: String,
        notesText: String,
        workoutNotesText: String
    ) async -> Bool {
        isSavingEdits = true

        var updateData: [String: AnyJSON] = [:]

        let newMood = mood.isEmpty ? nil : mood
        if newMood != currentEntry.mood {
            updateData["mood"] = newMood.map { .string($0) } ?? .null
        }

        let newType = workoutType.isEmpty ? nil : workoutType
        if newType != currentEntry.workoutType {
            updateData["workout_type"] = newType.map { .string($0) } ?? .null
        }

        let newDistance = Double(distanceText)
        if newDistance != currentEntry.workoutDistanceMiles {
            updateData["workout_distance_miles"] = newDistance.map { .double($0) } ?? .null
        }

        let newDuration = parseDurationToMinutes(durationText)
        if newDuration != currentEntry.workoutDurationMinutes {
            updateData["workout_duration_minutes"] = newDuration.map { .double($0) } ?? .null
        }

        let newNotes = notesText.isEmpty ? nil : notesText
        if newNotes != (currentEntry.cleanedNotes ?? currentEntry.notes) {
            updateData["cleaned_notes"] = newNotes.map { .string($0) } ?? .null
        }

        guard !updateData.isEmpty else {
            isSavingEdits = false
            return true
        }

        do {
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entryId.uuidString)
                .execute()

            currentEntry = TrainingLog(
                id: currentEntry.id,
                createdAt: currentEntry.createdAt,
                audioUrl: currentEntry.audioUrl,
                notes: currentEntry.notes,
                cleanedNotes: notesText.isEmpty ? currentEntry.cleanedNotes : notesText,
                mood: newMood,
                workoutDate: currentEntry.workoutDate,
                workoutDistanceMiles: newDistance ?? currentEntry.workoutDistanceMiles,
                workoutDurationMinutes: newDuration ?? currentEntry.workoutDurationMinutes,
                processingStatus: currentEntry.processingStatus,
                processingError: currentEntry.processingError,
                processingAttempts: currentEntry.processingAttempts,
                transcriptUrl: currentEntry.transcriptUrl,
                coachInsight: coachInsight,
                workoutNotes: workoutNotesText.isEmpty ? nil : workoutNotesText,
                workoutPacePerMile: currentEntry.workoutPacePerMile,
                workoutType: newType,
                source: currentEntry.source,
                vitalWorkoutId: currentEntry.vitalWorkoutId,
                paceSegments: currentEntry.paceSegments
            )
            isSavingEdits = false
            return true
        } catch {
            Log.database.error("Failed to save edits: \(error)")
            ErrorReporter.shared.report(error, context: "save edits")
            isSavingEdits = false
            return false
        }
    }

    // MARK: - Save Workout Notes

    @MainActor
    func saveWorkoutNotes(_ text: String) async -> Bool {
        guard !text.isEmpty else { return false }
        isSavingWorkoutNotes = true

        do {
            let updateData: [String: AnyJSON] = [
                "workout_notes": .string(text),
            ]
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entryId.uuidString)
                .execute()

            isSavingWorkoutNotes = false
            Log.database.info("Workout notes saved to database")
            return true
        } catch {
            Log.database.error("Failed to save workout notes: \(error)")
            ErrorReporter.shared.report(error, context: "save workout notes")
            isSavingWorkoutNotes = false
            return false
        }
    }

    // MARK: - Match Vital Workout

    @MainActor
    func matchVitalWorkout() async {
        guard currentEntry.hasLinkedWorkout, let workoutDate = currentEntry.workoutDate else { return }

        let workouts = await VitalManager.shared.fetchRunningWorkouts(for: workoutDate)
        if let entryDist = currentEntry.workoutDistanceMiles {
            matchedVitalWorkout = workouts.min(by: {
                abs($0.distanceMiles - entryDist) < abs($1.distanceMiles - entryDist)
            })
        } else {
            matchedVitalWorkout = workouts.first
        }
    }

    // MARK: - Helpers

    func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: return parts[0] + parts[1] / 60.0
        case 1: return parts[0]
        default: return nil
        }
    }

    func formatMinutesForEdit(_ minutes: Double) -> String {
        let totalSeconds = Int(minutes * 60)
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}
