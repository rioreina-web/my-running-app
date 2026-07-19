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
    /// The training_logs row id of the linked Strava import (if any). Strava runs
    /// are stored as their own training_logs row carrying the GPS stream + laps —
    /// separate from this (voice/manual) entry, which has none. "VIEW DETAIL" opens
    /// this id so the rep-by-rep sheet has telemetry to chart. Derived ONLY from
    /// Strava-sourced training_logs rows, so it's always a valid row id (unlike
    /// `matchedVitalWorkout.id`, which for a HealthKit/Vital match is a device id).
    var linkedStreamLogId: UUID?

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

            // The athlete just corrected the notes — re-derive the workout
            // structure so the parsed rep chart reflects their typed truth.
            // The parser treats typed workout_notes as the TOP source for
            // structure/intent (above the GPS guess), so e.g. "2 sets of 2k,
            // 2 x 1k w/ 2'/1' recovery" overrides whatever the stream inferred.
            // Fire-and-forget; re-fetch the row when it returns so the chart
            // updates in place.
            let reparseId = entryId.uuidString
            let reparseUserId = AuthManager.shared.userId
            Task { [weak self] in
                _ = try? await callEdgeFunction(
                    name: "parse-workout-structure",
                    body: ["training_log_id": reparseId, "user_id": reparseUserId]
                )
                let refreshed: [TrainingLog]? = try? await supabase
                    .from("training_logs")
                    .select()
                    .eq("id", value: reparseId)
                    .limit(1)
                    .execute()
                    .value
                if let row = refreshed?.first {
                    await MainActor.run { self?.currentEntry = row }
                }
            }
            return true
        } catch {
            Log.database.error("Failed to save workout notes: \(error)")
            ErrorReporter.shared.report(error, context: "save workout notes")
            isSavingWorkoutNotes = false
            return false
        }
    }

    /// Latest `workout_notes` for this row, straight from the DB. The note is
    /// often written server-side (process-training-memo / parse-workout-structure)
    /// AFTER the detail sheet opened, so the initially-passed entry had none. The
    /// sheet polls this to fill the field once the note lands.
    @MainActor
    func latestWorkoutNotes() async -> String? {
        struct Row: Decodable { var workout_notes: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("workout_notes")
                .eq("id", value: entryId.uuidString).limit(1).execute().value
            return rows.first?.workout_notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Log.database.error("latestWorkoutNotes failed: \(error)")
            return nil
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

        // Keep the Strava rows separately: they're real training_logs rows (with
        // the stream), so they're the ones "VIEW DETAIL" should open. The merged
        // list still drives the "LINKED · <source>" label + closest-by-distance
        // display match, unchanged.
        let stravaRows = await strava
        let all = (await vital) + (await hk) + stravaRows
        guard !all.isEmpty else { return }

        if let entryDist = currentEntry.workoutDistanceMiles {
            matchedVitalWorkout = all.min(by: {
                abs($0.distanceMiles - entryDist) < abs($1.distanceMiles - entryDist)
            })
            linkedStreamLogId = stravaRows.min(by: {
                abs($0.distanceMiles - entryDist) < abs($1.distanceMiles - entryDist)
            })?.id
        } else {
            matchedVitalWorkout = all.first
            linkedStreamLogId = stravaRows.first?.id
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

    // MARK: - Coach Insight (auto-appear)

    /// Poll for the server-generated coach insight and slot it in once it lands,
    /// so an entry opened mid-processing shows the insight the moment it's ready —
    /// no manual tap. Mirrors `fillWorkoutNotesWhenReady` (the note is written by
    /// `process-training-memo` shortly after the voice memo is processed). No-op
    /// once an insight is already present.
    @MainActor
    func refreshCoachInsightWhenReady() async {
        if let c = coachInsight, !c.isEmpty { return }
        struct Row: Decodable { var coach_insight: String? }
        for _ in 0..<8 {
            do {
                let rows: [Row] = try await supabase
                    .from("training_logs").select("coach_insight")
                    .eq("id", value: entryId.uuidString).limit(1).execute().value
                if let text = rows.first?.coach_insight?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    coachInsight = text
                    return
                }
            } catch {
                Log.database.error("refreshCoachInsightWhenReady failed: \(error)")
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Generate Coach Insight
    //
    // Retained as a reusable capability (e.g. a future manual "regenerate"),
    // but no longer wired to a button: the entry-level AI Insight now appears
    // automatically once `process-training-memo` has written `coach_insight`
    // (see `refreshCoachInsightWhenReady`). Calls the workout-specific
    // `generate-workout-insight` by training_log_id.

    @MainActor
    func generateCoachInsight() async {
        let id = currentEntry.id
        Log.coach.debug("generateCoachInsight() → generate-workout-insight for \(id)")

        // The workout AI Insight is the context-rich, workout-specific read
        // produced by `generate-workout-insight` (athlete state: volume / fitness
        // ranges / pace zones, plus this run's splits + conditions + parsed
        // structure). It is NOT the general conversational `coaching-agent`.
        //
        // Previously this built a short text message (distance | duration | pace
        // + notes + mood) and POSTed it to `coaching-agent`. With almost no
        // quantitative context, that chat agent followed its ask-vs-answer design
        // and kept defaulting to "I need more info — what's your weekly mileage?".
        // Call the purpose-built function by training_log_id instead — the same
        // path the rep-chart screen uses — so the insight reads the real workout.
        struct Req: Encodable { let training_log_id: String }
        struct Resp: Decodable { let insight: String?; let error: String? }
        do {
            let resp: Resp = try await supabase.functions.invoke(
                "generate-workout-insight",
                options: .init(body: Req(training_log_id: id.uuidString))
            )
            let text = resp.insight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run {
                self.coachInsight = text.isEmpty
                    ? (resp.error ?? "Couldn't generate insight. Try again.")
                    : text
            }
        } catch {
            Log.coach.error("generateCoachInsight failed: \(error)")
            await MainActor.run {
                self.coachInsight = "Couldn't reach the coach. Try again."
            }
        }
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
        // coaching-agent requires a real user JWT (the anon-key + body-userId
        // fallback was removed as an impersonation hole). Send the session
        // access token; fall back to anon only when signed out (will 401).
        let bearerToken = (try? await supabase.auth.session)?.accessToken ?? supabaseAnonKey
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
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
