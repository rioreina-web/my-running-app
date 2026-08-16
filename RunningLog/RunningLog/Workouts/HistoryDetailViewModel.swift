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
    /// True while `generateCoachInsight()` is in flight, so the "✦ READ THE
    /// INSIGHT" row can show "WRITING YOUR INSIGHT…" instead of looking dead
    /// for the several seconds the edge function takes.
    var isGeneratingInsight = false
    /// Why the last on-demand generation failed. Kept separate from
    /// `coachInsight` on purpose: an error stored as the insight would read as
    /// the coach's actual take, and would permanently block the retry path.
    var insightError: String?
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
                workoutNotes: currentEntry.workoutNotes,
                workoutPacePerMile: currentEntry.workoutPacePerMile,
                workoutType: currentEntry.workoutType,
                source: currentEntry.source,
                vitalWorkoutId: currentEntry.vitalWorkoutId,
                paceSegments: currentEntry.paceSegments,
                parsedStructure: currentEntry.parsedStructure,
                title: currentEntry.title
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
        title: String,
        mood: String,
        workoutType: String,
        distanceText: String,
        durationText: String,
        notesText: String
    ) async -> Bool {
        isSavingEdits = true

        var updateData: [String: AnyJSON] = [:]

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        if newTitle != currentEntry.displayTitle {
            updateData["title"] = newTitle.map { .string($0) } ?? .null
        }

        let newMood = mood.isEmpty ? nil : mood
        if newMood != currentEntry.mood {
            updateData["mood"] = newMood.map { .string($0) } ?? .null
        }

        // Normalized before the comparison so re-saving an entry the picker
        // loaded as "interval" doesn't write "interval" straight back.
        let newType = WorkoutLabel.normalize(workoutType.isEmpty ? nil : workoutType)
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

        // Trimmed before the comparison so a stray trailing newline off the
        // TextField doesn't read as an edit and write a row back over itself.
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let notesChanged = newNotes != (currentEntry.cleanedNotes ?? currentEntry.notes)
        if notesChanged {
            updateData["cleaned_notes"] = newNotes.map { .string($0) } ?? .null
        }

        // `workout_notes` deliberately absent (2026-08-10). Global edit mode
        // used to write it from a field seeded when the sheet opened, so
        // entering Edit and hitting Save would push a stale description back
        // over one just written in `TheWorkoutBlock` — the same silent
        // last-writer-wins this whole thread of work exists to remove. That
        // column has exactly one editor now.

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

            // A Strava-linked run is two rows, and the workout receipt renders
            // from the OTHER one — so an edit to any field the receipt reads
            // that lands only here saves cleanly and changes nothing the
            // athlete can see. Mirror those fields.
            //
            // `workout_type` joined `workout_notes` on 2026-08-07: the receipt
            // reads it via `WorkoutLapsService.fetchType` and writes it via
            // `setType`, both against the stream row, so the two pickers were
            // editing different rows with no reconciliation at all.
            //
            // (Patch; the real fix is one session identity per run.)
            let mirrored = updateData.filter { Self.streamRowMirroredFields.contains($0.key) }
            if !mirrored.isEmpty {
                await mirrorToStreamRow(mirrored)
            }

            currentEntry = TrainingLog(
                id: currentEntry.id,
                createdAt: currentEntry.createdAt,
                audioUrl: currentEntry.audioUrl,
                notes: currentEntry.notes,
                // Mirror what was WRITTEN, not what was typed. The old form —
                // `notesText.isEmpty ? currentEntry.cleanedNotes : notesText`
                // — special-cased empty to mean "keep the old value", but
                // empty is exactly how the athlete CLEARS the field: the
                // update above sends `.null`, and then this line put the old
                // text straight back on screen. The clear saved and looked
                // like it hadn't, until a refetch replaced it with the raw
                // transcript (`cleaned_notes` null → the reader falls through
                // to `notes`). Two different wrong answers for one edit, which
                // is what "sometimes my notes don't save" was.
                cleanedNotes: notesChanged ? newNotes : currentEntry.cleanedNotes,
                mood: newMood,
                workoutDate: currentEntry.workoutDate,
                workoutDistanceMiles: newDistance ?? currentEntry.workoutDistanceMiles,
                workoutDurationMinutes: newDuration ?? currentEntry.workoutDurationMinutes,
                processingStatus: currentEntry.processingStatus,
                processingError: currentEntry.processingError,
                processingAttempts: currentEntry.processingAttempts,
                transcriptUrl: currentEntry.transcriptUrl,
                coachInsight: coachInsight,
                workoutNotes: currentEntry.workoutNotes,
                workoutPacePerMile: currentEntry.workoutPacePerMile,
                workoutType: newType,
                source: currentEntry.source,
                vitalWorkoutId: currentEntry.vitalWorkoutId,
                paceSegments: currentEntry.paceSegments,
                parsedStructure: currentEntry.parsedStructure,
                title: newTitle
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

    // MARK: - Inline single-field edits (tap-to-edit on the header)
    //
    // The header's title and mood are editable by tapping them, without
    // entering the sheet's Cancel/Save mode. Each of these writes exactly ONE
    // column, which is the whole point: routing a one-word title fix through
    // `saveEdits` would carry five other fields along with it, seeded from
    // whatever the sheet held when it opened — the same stale-write shape the
    // `workout_notes` comment above exists to warn about.
    //
    // Neither field is in `streamRowMirroredFields`, so neither mirrors onto a
    // linked Strava row: `title` is the journal entry's own name, and `mood`
    // belongs to the note, not the run (see the mirroring note above).

    /// What an inline save actually did.
    ///
    /// Three states, not a `Bool`, because "nothing changed" and "saved" have
    /// different consequences at the call site: only a real write should
    /// refresh the journal feed behind the sheet, and only a real failure
    /// should tell the athlete something went wrong. Collapsing the first two
    /// into `true` made every stray tap on the headline refetch the feed.
    enum InlineSaveResult {
        case saved
        case unchanged
        case failed
    }

    /// Save the athlete's own entry title. Empty clears it, which drops the
    /// header back to the workout name and then the day-of-week.
    @MainActor
    func saveTitleInline(_ text: String) async -> InlineSaveResult {
        // Newlines flattened, not trimmed: the field wraps to three lines, so
        // Return inserts a break mid-title. Trimming only cleans the ends and
        // would leave "Bridge\nrepeats" to print as two lines in the journal
        // header and in every list that shows a title.
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmed.isEmpty ? nil : trimmed
        guard newTitle != currentEntry.displayTitle else { return .unchanged }

        do {
            let updateData: [String: AnyJSON] = [
                "title": newTitle.map { AnyJSON.string($0) } ?? .null,
            ]
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entryId.uuidString)
                .execute()
            // `title` is the one `var` on the model, so this needs no rebuild.
            currentEntry.title = newTitle
            return .saved
        } catch {
            Log.database.error("Failed to save inline title: \(error)")
            ErrorReporter.shared.report(error, context: "save inline title")
            return .failed
        }
    }

    /// Save how the session felt. Empty clears the mood.
    @MainActor
    func saveMoodInline(_ mood: String) async -> InlineSaveResult {
        let trimmed = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        let newMood = trimmed.isEmpty ? nil : trimmed
        guard newMood != currentEntry.mood else { return .unchanged }

        do {
            let updateData: [String: AnyJSON] = [
                "mood": newMood.map { AnyJSON.string($0) } ?? .null,
            ]
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: entryId.uuidString)
                .execute()
            currentEntry = currentEntry.replacingMood(newMood)
            return .saved
        } catch {
            Log.database.error("Failed to save inline mood: \(error)")
            ErrorReporter.shared.report(error, context: "save inline mood")
            return .failed
        }
    }

    // MARK: - Mirror workout notes onto the linked stream row

    /// Copy `workout_notes` onto the Strava import row when this entry is
    /// linked to one.
    ///
    /// A Strava-linked run occupies TWO `training_logs` rows: this journal
    /// entry (`entryId`), and the import that carries the GPS stream and laps
    /// (`linkedStreamLogId`). Every write in this view model targets
    /// `entryId`, but `WorkoutRepReceiptView` — the WORKOUT section embedded
    /// below, and the full-screen detail sheet — resolves its row as
    /// `linkedStreamLogId ?? entryId` and reads `workout_notes` off THAT row.
    /// So on a linked run the athlete's edit saved, returned 200, and the
    /// screen never changed. Silent, and indistinguishable from a broken app.
    ///
    /// Mirroring keeps both rows agreeing so no reader has to know which one
    /// it got. Best-effort by design: a failure here must never fail the save
    /// the athlete actually asked for — the journal row is already written and
    /// is the record of truth.
    ///
    /// This is a patch. The fix is one session identity shared by both rows so
    /// there is one place to write and one place to read — see
    /// `docs/specs/runs-and-notes-split.md`. Delete this when that lands.

    /// Columns the workout receipt reads off the STREAM row rather than the
    /// journal row. An edit to any of these that writes only to `entryId` is
    /// invisible on the receipt.
    ///
    /// Keep this list honest: adding a field to the journal's edit mode without
    /// adding it here recreates the silent-no-op bug in a new costume. The
    /// known remaining gaps are `mood` and `cleaned_notes` — deliberately NOT
    /// mirrored, because on a split pair those genuinely belong to the note,
    /// not the run, and overwriting the run's copy would be the merge decision
    /// `merge_voice_orphan_into_run` already makes differently.
    ///
    /// `workout_distance_miles` / `workout_duration_minutes` joined on
    /// 2026-08-07: `WorkoutRepChart.fetchSummary` reads both off the stream row
    /// and `wrDistanceMi` / `wrTimeSec` prefer them over the GPS stream and the
    /// summed laps, so they drive the receipt's headline distance, time AND the
    /// average pace derived from the pair. A distance correction typed in the
    /// journal was the loudest silent no-op left on the screen.
    private static let streamRowMirroredFields: Set<String> = [
        "workout_notes", "workout_type",
        "workout_distance_miles", "workout_duration_minutes",
    ]

    /// Copy an already-saved field set onto the linked stream row.
    ///
    /// Best-effort by design: a failure here must never fail the save the
    /// athlete actually asked for — the journal row is already written and is
    /// the record of truth. No-ops when there is no separate stream row, which
    /// since 2026-08-05 is the common case (a memo attaches to the run's row
    /// rather than creating a second one).
    @MainActor
    private func mirrorToStreamRow(_ fields: [String: AnyJSON]) async {
        guard let mirrorId = linkedStreamLogId, mirrorId != entryId, !fields.isEmpty else { return }
        do {
            try await supabase
                .from("training_logs")
                .update(fields)
                .eq("id", value: mirrorId.uuidString)
                .execute()
        } catch {
            Log.database.error("mirror \(fields.keys.sorted()) to linked stream row failed: \(error)")
        }
    }

    @MainActor
    private func mirrorWorkoutNotes(_ text: String?) async {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        await mirrorToStreamRow([
            "workout_notes": (trimmed?.isEmpty == false) ? .string(trimmed!) : .null,
        ])
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

            await mirrorWorkoutNotes(text)

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
                parsedStructure: currentEntry.parsedStructure,
                title: currentEntry.title
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
                    .select(TrainingLog.columns)
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

    /// How close a candidate has to be to count as the same session.
    ///
    /// These are `_shared/voiceOrphanMatch.ts`'s numbers on purpose. That is the
    /// ONE matcher `docs/specs/runs-and-notes-split.md` keeps when the other
    /// eight are deleted, so anything that still has to guess should converge on
    /// it rather than invent a tenth set of thresholds.
    private static let matchWindowSeconds: TimeInterval = 4 * 60 * 60
    private static let matchDistanceFloorMiles = 0.5
    private static let matchDistanceFraction = 0.08

    /// Is this candidate close enough to be the same run as this entry?
    ///
    /// Before 2026-08-07 there was no such test. Ranking ran through `min(by:)`
    /// over every candidate on the local calendar day, and `min` always returns
    /// a winner — so a run 23 hours away won simply by being the only one on the
    /// day. The `120` in `closer` below is a tie-break switch (rank by time, or
    /// by distance when two candidates are effectively simultaneous), never a
    /// match window. This is the match window.
    static func isPlausibleMatch(_ c: RunningWorkout,
                                 entryTime: TimeInterval,
                                 entryDist: Double?) -> Bool {
        guard abs(c.startDate.timeIntervalSince1970 - entryTime) <= matchWindowSeconds else {
            return false
        }
        // No distance on the entry → time has to carry it alone. (`hasLinkedWorkout`
        // requires a distance today, so this is defensive rather than live.)
        guard let d = entryDist else { return true }
        let tolerance = max(matchDistanceFloorMiles, matchDistanceFraction * c.distanceMiles)
        return abs(c.distanceMiles - d) <= tolerance
    }

    @MainActor
    func matchVitalWorkout() async {
        guard currentEntry.hasLinkedWorkout, let workoutDate = currentEntry.workoutDate else { return }

        // Pull from all wearable sources — Vital is stubbed, HealthKit covers Apple
        // Watch + Garmin-via-Apple-Health, and we add stream-carrying training_logs
        // rows mapped to RunningWorkout so parsed detail views can reach them.
        async let vital = VitalManager.shared.fetchRunningWorkouts(for: workoutDate)
        async let hk = HealthKitManager.shared.fetchRunningWorkouts(for: workoutDate)
        async let streams = Self.fetchStreamCarryingLogsForDate(workoutDate)

        // Keep the stream rows separately: they're real training_logs rows with a
        // GPS stream, so they're the ones "VIEW DETAIL" should open. The merged
        // list still drives the "LINKED · <source>" label.
        let streamRows = await streams
        let all = (await vital) + (await hk) + streamRows
        guard !all.isEmpty else { return }

        // Rank candidates by how well they match THIS entry — start time first,
        // then distance. Distance alone mislinks on a multi-run day: if the day
        // holds a warmup, the main workout, a cooldown, and an evening run, a
        // 7.5 mi interval memo and a 3.9 mi easy run are both "that day", and
        // closest-by-distance can grab the wrong run (and does grab an arbitrary
        // one when the entry has no distance). The memo's timestamp is copied
        // from the run it describes, so start time is the reliable key; distance
        // only breaks ties between runs at effectively the same time (e.g. the
        // same activity arriving from two sources).
        let entryTime = workoutDate.timeIntervalSince1970
        let entryDist = currentEntry.workoutDistanceMiles
        func closer(_ a: RunningWorkout, _ b: RunningWorkout) -> Bool {
            let at = abs(a.startDate.timeIntervalSince1970 - entryTime)
            let bt = abs(b.startDate.timeIntervalSince1970 - entryTime)
            // >2 min apart → time decides; otherwise fall back to distance.
            if abs(at - bt) > 120 { return at < bt }
            guard let d = entryDist else { return at < bt }
            return abs(a.distanceMiles - d) < abs(b.distanceMiles - d)
        }
        func best(_ xs: [RunningWorkout]) -> RunningWorkout? {
            xs.filter { Self.isPlausibleMatch($0, entryTime: entryTime, entryDist: entryDist) }
              .min(by: closer)
        }
        matchedVitalWorkout = best(all)
        // May resolve to `entryId` itself — see `fetchStreamCarryingLogsForDate`.
        // That's correct: the receipt then renders against this very row and
        // `workoutDetailId` collapses to `entry.id`, which is what it already
        // falls back to.
        linkedStreamLogId = best(streamRows)?.id
    }

    /// Every `training_logs` row for this day that actually carries a GPS stream.
    ///
    /// **Why this is a stream test and not a source allowlist (2026-08-07).**
    /// This query used to read `.in("source", ["garmin", "vital"])`. There has
    /// never been a `garmin` or a `vital` row in the database — Vital was never
    /// connected — so it returned `[]` on every call, `linkedStreamLogId` was
    /// permanently `nil`, and three things downstream had therefore never run on
    /// a live device: the inline WORKOUT receipt and the COMPARE row (both gated
    /// on `linkedStreamLogId != nil` in `HistoryDetailSheet+Editorial`), and
    /// `mirrorWorkoutNotes` below. The sibling query in
    /// `VoiceLogView.fetchStravaRunningWorkouts` carries the corrected source
    /// list and a comment about this exact failure mode; the two drifted apart.
    ///
    /// A source allowlist is the wrong shape for the question. What the caller
    /// needs is "a row with telemetry to chart," and every new source string
    /// (`strava`, `auto_sync`, `strava_backfill`, whatever comes next) silently
    /// breaks an allowlist while leaving the call site looking correct. So ask
    /// the real question: `external_streams IS NOT NULL`.
    ///
    /// The entry's own row is deliberately NOT excluded. Since the 2026-08-05
    /// picker fix, a memo recorded against a synced run attaches to that run's
    /// row instead of creating a second one — so for a session logged since
    /// then, the stream is on `entryId` itself and there is no sibling to find.
    /// Including it lets that row win on a zero time delta, which is what makes
    /// the receipt render for the modern (single-row) shape as well as the
    /// historical split-pair one.
    ///
    /// `external_streams` is filtered on but never selected: the blob is large
    /// and no caller here reads it.
    static func fetchStreamCarryingLogsForDate(_ date: Date) async -> [RunningWorkout] {
        struct Row: Decodable {
            let id: String
            let workout_date: Date?
            let workout_distance_miles: Double?
            let workout_duration_minutes: Double?
            let vital_workout_id: String?
            let source: String?
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let iso = ISO8601DateFormatter()
        do {
            let userId = AuthManager.shared.userId
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("id, workout_date, workout_distance_miles, workout_duration_minutes, vital_workout_id, source")
                .eq("user_id", value: userId)
                .not("external_streams", operator: .is, value: "null")
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
                    // Was hardcoded "Garmin", which was invisible while this
                    // query returned nothing and would now label every Strava
                    // run "LINKED · GARMIN". Mirrors VoiceLogView:1413.
                    sourceApp: Self.sourceAppLabel(r.source),
                    vitalWorkoutId: r.vital_workout_id
                )
            }
        } catch {
            Log.database.error("fetchStreamCarryingLogsForDate failed: \(error)")
            return []
        }
    }

    /// The `training_logs` row id for a workout that came from the DEVICE
    /// (HealthKit / Vital), whose `id` is a device sample UUID and not a row id
    /// at all.
    ///
    /// **Why this exists (2026-08-07, S2).** `WorkoutRepDetailSheet` documents
    /// `workoutId` as "the `training_logs` row id", and `WorkoutRepReceiptView`
    /// queries `training_logs` with it. But `DayDetailSheet` (the plan day
    /// sheet) fed it `RunningWorkout.id` straight off
    /// `VitalManager.fetchRunningWorkouts` — a device UUID. No row has that id,
    /// so every query returned nothing and the receipt opened blank. Nothing
    /// errored; the two id types are both `UUID`, so the compiler can't tell
    /// them apart. (A `TrainingLogID` wrapper type would make this
    /// uncompilable — worth doing where there's a compiler to check it.)
    ///
    /// Resolves through the same day query and the same plausibility test the
    /// journal uses, so this adds no new matcher — see
    /// `docs/specs/runs-and-notes-split.md` on why that matters.
    /// Returns nil when the device workout has no imported row yet, which is a
    /// real state: the run happened but Strava hasn't synced it.
    static func streamLogId(matching workout: RunningWorkout) async -> UUID? {
        let candidates = await fetchStreamCarryingLogsForDate(workout.startDate)
        let t = workout.startDate.timeIntervalSince1970
        let d = workout.distanceMiles
        return candidates
            .filter { isPlausibleMatch($0, entryTime: t, entryDist: d) }
            .min { abs($0.startDate.timeIntervalSince1970 - t) < abs($1.startDate.timeIntervalSince1970 - t) }?
            .id
    }

    /// `training_logs.source` → the label the LINKED row shows.
    private static func sourceAppLabel(_ source: String?) -> String {
        switch (source ?? "").lowercased() {
        case "strava", "strava_backfill": return "Strava"
        case "auto_sync": return "Apple Health"
        case "garmin": return "Garmin"
        case "vital": return "Vital"
        case "manual": return "Manual"
        default: return "Strava"
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
    // Wired to the "✦ READ THE INSIGHT" row in the journal entry sheet: when
    // no insight exists yet, tapping generates one on demand. (This function
    // sat orphaned for a while — the insight used to appear automatically and
    // nothing called this. The redesign moved the insight behind a tap, which
    // gave it a home again.)
    //
    // Calls the workout-specific `generate-workout-insight` by training_log_id.
    //
    // NOTE on cost: `process-training-memo` still generates an insight
    // server-side for every voice memo, so this on-demand path is usually a
    // no-op fallback rather than the primary source. If we want to actually
    // stop paying for insights nobody reads, drop the eager generation from
    // that edge function and let this be the only producer.

    @MainActor
    func generateCoachInsight() async {
        guard !isGeneratingInsight else { return }
        isGeneratingInsight = true
        defer { isGeneratingInsight = false }
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
            if text.isEmpty {
                // Failures go to `insightError`, never to `coachInsight` — an
                // error string stored as the insight would make `hasInsight`
                // true, so the retry path would keep re-showing the error and
                // could never call this function again.
                insightError = resp.error ?? "Couldn't generate an insight. Tap to try again."
            } else {
                coachInsight = text
                insightError = nil
                // Persist it. Without this, reopening the entry finds
                // `coach_insight` still null and pays for another generation.
                saveCoachInsight(text)
            }
        } catch {
            Log.coach.error("generateCoachInsight failed: \(error)")
            insightError = "Couldn't reach the coach. Tap to try again."
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

// MARK: - TrainingLog copy helpers

private extension TrainingLog {
    /// Copy of this row carrying a new mood.
    ///
    /// `mood` is a `let` on the model — deliberately, so nothing mutates a
    /// journal row in place — which means the inline mood save has to rebuild
    /// rather than assign. Every other field is carried through unchanged, so
    /// this can never quietly drop one the way a hand-written rebuild at the
    /// call site can.
    func replacingMood(_ newMood: String?) -> TrainingLog {
        TrainingLog(
            id: id,
            createdAt: createdAt,
            audioUrl: audioUrl,
            notes: notes,
            cleanedNotes: cleanedNotes,
            mood: newMood,
            workoutDate: workoutDate,
            workoutDistanceMiles: workoutDistanceMiles,
            workoutDurationMinutes: workoutDurationMinutes,
            processingStatus: processingStatus,
            processingError: processingError,
            processingAttempts: processingAttempts,
            transcriptUrl: transcriptUrl,
            coachInsight: coachInsight,
            workoutNotes: workoutNotes,
            workoutPacePerMile: workoutPacePerMile,
            workoutType: workoutType,
            source: source,
            vitalWorkoutId: vitalWorkoutId,
            paceSegments: paceSegments,
            parsedStructure: parsedStructure,
            title: title
        )
    }
}
