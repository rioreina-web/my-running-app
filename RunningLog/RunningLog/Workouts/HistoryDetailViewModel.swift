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
                paceSegments: currentEntry.paceSegments,
                parsedStructure: currentEntry.parsedStructure
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

        let newWorkoutNotes = workoutNotesText.isEmpty ? nil : workoutNotesText
        if newWorkoutNotes != currentEntry.workoutNotes {
            updateData["workout_notes"] = newWorkoutNotes.map { .string($0) } ?? .null
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
                paceSegments: currentEntry.paceSegments,
                parsedStructure: currentEntry.parsedStructure
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

            currentEntry = TrainingLog(
                id: currentEntry.id,
                createdAt: currentEntry.createdAt,
                audioUrl: currentEntry.audioUrl,
                notes: currentEntry.notes,
                cleanedNotes: currentEntry.cleanedNotes,
                mood: currentEntry.mood,
                workoutDate: currentEntry.workoutDate,
                workoutDistanceMiles: currentEntry.workoutDistanceMiles,
                workoutDurationMinutes: currentEntry.workoutDurationMinutes,
                processingStatus: currentEntry.processingStatus,
                processingError: currentEntry.processingError,
                processingAttempts: currentEntry.processingAttempts,
                transcriptUrl: currentEntry.transcriptUrl,
                coachInsight: currentEntry.coachInsight,
                workoutNotes: text,
                workoutPacePerMile: currentEntry.workoutPacePerMile,
                workoutType: currentEntry.workoutType,
                source: currentEntry.source,
                vitalWorkoutId: currentEntry.vitalWorkoutId,
                paceSegments: currentEntry.paceSegments,
                parsedStructure: currentEntry.parsedStructure
            )

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

        // Pull from all wearable sources — Vital is stubbed, HealthKit covers Apple
        // Watch + Garmin-via-Apple-Health, and we add Strava-imported training_logs
        // mapped to RunningWorkout so parsed detail views can reach them.
        async let vital = VitalManager.shared.fetchRunningWorkouts(for: workoutDate)
        async let hk = HealthKitManager.shared.fetchRunningWorkouts(for: workoutDate)
        async let strava = Self.fetchStravaRunningWorkoutsForDate(workoutDate)

        let all = (await vital) + (await hk) + (await strava)
        guard !all.isEmpty else { return }

        if let entryDist = currentEntry.workoutDistanceMiles {
            matchedVitalWorkout = all.min(by: {
                abs($0.distanceMiles - entryDist) < abs($1.distanceMiles - entryDist)
            })
        } else {
            matchedVitalWorkout = all.first
        }
    }

    /// Fetch Strava-imported workouts for a specific date (same pattern as
    /// TrainingTabView.fetchStravaRunningWorkouts but filtered by date).
    private static func fetchStravaRunningWorkoutsForDate(_ date: Date) async -> [RunningWorkout] {
        struct Row: Decodable {
            let id: String
            let workout_date: Date?
            let workout_distance_miles: Double?
            let workout_duration_minutes: Double?
            let vital_workout_id: String?
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let iso = ISO8601DateFormatter()
        do {
            let userId = AuthManager.shared.userId
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("id, workout_date, workout_distance_miles, workout_duration_minutes, vital_workout_id")
                .eq("user_id", value: userId)
                .eq("source", value: "strava")
                .gte("workout_date", value: iso.string(from: start))
                .lt("workout_date", value: iso.string(from: end))
                .execute()
                .value
            return rows.compactMap { r -> RunningWorkout? in
                guard let s = r.workout_date,
                      let dist = r.workout_distance_miles, dist > 0,
                      let dur = r.workout_duration_minutes, dur > 0,
                      let uuid = UUID(uuidString: r.id) else { return nil }
                return RunningWorkout(
                    id: uuid,
                    startDate: s,
                    endDate: s.addingTimeInterval(dur * 60),
                    distanceMiles: dist,
                    durationMinutes: dur,
                    pacePerMile: dur / dist,
                    calories: 0,
                    sourceApp: "Strava",
                    vitalWorkoutId: r.vital_workout_id
                )
            }
        } catch {
            return []
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

    // MARK: - Generate Coach Insight
    //
    // Lifted from `CoachInsightSection.getCoachInsight` / `callCoachingAgent`
    // so the editorial body's `DripTextLink` "Ask the coach →" can call it
    // directly. The legacy card view keeps working — it still owns its own
    // copy until that surface is removed.

    @MainActor
    func generateCoachInsight() async {
        let entry = currentEntry
        Log.coach.debug("generateCoachInsight() called")

        // Build structured workout context.
        var workoutDetails = ""
        if entry.hasLinkedWorkout {
            var parts: [String] = []
            if let distance = entry.formattedWorkoutDistance { parts.append(distance) }
            if let duration = entry.formattedWorkoutDuration { parts.append(duration) }
            if let pace = entry.formattedWorkoutPace { parts.append("\(pace)/mi") }
            workoutDetails = "Workout: " + parts.joined(separator: " | ")
        }

        var notesContext = ""
        if let cleaned = entry.cleanedNotes, !cleaned.isEmpty {
            notesContext = "Notes: \(cleaned)"
        } else if let notes = entry.notes, !notes.isEmpty {
            notesContext = "Notes: \(notes)"
        }

        var moodContext = ""
        if let mood = entry.mood, !mood.isEmpty {
            moodContext = "Mood: \(mood)"
        }

        let allNotes = (entry.cleanedNotes ?? "") + (entry.notes ?? "")
        let isHarderEffort = Self.isQualityWorkout(notes: allNotes, distanceMiles: entry.workoutDistanceMiles)

        let hasRecoveryConcern = allNotes.lowercased().containsAny([
            "sore", "tight", "pain", "ache", "hurt", "tired", "fatigue", "heavy",
        ])
        let hasMoodData = entry.mood.map { !$0.isEmpty } ?? false

        let contextParts = [workoutDetails, notesContext, moodContext].filter { !$0.isEmpty }
        let context = contextParts.joined(separator: "\n")

        var focusHints: [String] = []
        if hasRecoveryConcern { focusHints.append("note any recovery/fatigue signals") }
        if hasMoodData { focusHints.append("connect effort to how they felt") }
        if isHarderEffort { focusHints.append("training stimulus and adaptation") }

        let goalsInstruction = isHarderEffort
            ? "[GOALS] Reflect on how this workout connects to their upcoming goal race. Vary phrasing naturally (e.g., 'This type of effort builds the strength you'll need for...', 'Sessions like this are what prepare you for race day...', 'This is the work that'll pay off when...')."
            : ""

        let message = """
        [COACH INSIGHT REQUEST]

        \(context.isEmpty ? "Training log from \(entry.displayDate.shortDateString)" : context)

        Give thoughtful coaching feedback (4-5 sentences). Be conversational and supportive.
        Observations to consider: \(focusHints.isEmpty ? "effort, execution, pacing" : focusHints.joined(separator: ", "))
        \(goalsInstruction)
        """

        Log.coach.debug("Coach insight request message: \(message)")
        await callCoachingAgent(message: message)
    }

    private static func isQualityWorkout(notes: String, distanceMiles: Double?) -> Bool {
        let lowercased = notes.lowercased()
        let qualityKeywords = [
            "tempo", "interval", "speed", "fast", "hard",
            "long run", "longrun", "race", "threshold",
            "fartlek", "repeat", "workout", "track",
            "progressive", "negative split", "pr", "pb",
        ]
        if qualityKeywords.contains(where: { lowercased.contains($0) }) { return true }
        if let miles = distanceMiles, miles >= 8.0 { return true }
        return false
    }

    private func callCoachingAgent(message: String) async {
        Log.coach.debug("callCoachingAgent() starting...")

        guard let url = URL(string: "\(supabaseURL)/functions/v1/coaching-agent") else {
            Log.coach.error("Invalid URL")
            await MainActor.run {
                self.coachInsight = "Error: Invalid URL configuration"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let payload: [String: Any] = ["message": message]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            Log.coach.debug("Making API request to coaching-agent...")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                Log.coach.debug("HTTP status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "No body"
                    Log.coach.error("Response body: \(errorBody)")
                    throw NSError(
                        domain: "CoachError",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode)): \(errorBody)"]
                    )
                }
            }

            struct CoachResponse: Codable {
                let response: String?
                let conversationId: String?
                let error: String?
                let details: String?
                let model: String?
            }

            let coachResponse = try JSONDecoder().decode(CoachResponse.self, from: data)
            Log.coach.info("Successfully decoded response, model: \(coachResponse.model ?? "unknown")")

            await MainActor.run {
                if let error = coachResponse.error {
                    self.coachInsight = "Error: \(error)"
                    if let details = coachResponse.details {
                        Log.coach.error("Error details: \(details)")
                    }
                } else if let response = coachResponse.response {
                    self.coachInsight = response
                    self.saveCoachInsight(response)
                } else {
                    self.coachInsight = "No response received from coach."
                }
            }
        } catch let urlError as URLError {
            Log.coach.error("URLError: \(urlError.localizedDescription), code: \(urlError.code.rawValue)")
            await MainActor.run {
                if urlError.code == .timedOut {
                    self.coachInsight = "Error: Request timed out. Please try again."
                } else if urlError.code == .notConnectedToInternet {
                    self.coachInsight = "Error: No internet connection."
                } else {
                    self.coachInsight = "Error: Network error - \(urlError.localizedDescription)"
                }
            }
        } catch {
            Log.coach.error("General error: \(error)")
            await MainActor.run {
                self.coachInsight = "Couldn't get coach feedback: \(error.localizedDescription)"
            }
        }
    }
}
