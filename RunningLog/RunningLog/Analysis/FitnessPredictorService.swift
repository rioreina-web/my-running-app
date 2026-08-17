//
//  FitnessPredictorService.swift
//  RunningLog
//
//  Service for AI-powered race predictions.
//

import Foundation
import HealthKit
import os
import Supabase

// MARK: - FitnessPredictorService

@Observable
final class FitnessPredictorService {
    var isAnalyzing = false
    var predictions: FitnessPrediction?
    var lastUpdated: Date?
    var errorMessage: String?
    var snapshotHistory: [FitnessSnapshot] = []
    var isLoadingHistory = false

    // 2026-07-17 race gathering
    // Pending server-tagged race candidates awaiting the athlete's call, and
    // lifetime PRs keyed by the view's distance labels ("MILE", "5K", "10K",
    // "HALF", "MARATHON").
    var raceCandidates: [RaceCandidate] = []
    var lifetimePRs: [String: (seconds: Int, date: Date)] = [:]
    /// Full `extracted_data` per fetched candidate — kept so confirm/dismiss
    /// can read-modify-write the JSON (PostgREST cannot deep-merge).
    private var candidateExtractedData: [UUID: [String: AnyJSON]] = [:]
    /// Last plan passed to `predictFitness` — lets a candidate confirmation
    /// refresh the prediction the same way the view does.
    private var lastPlan: TrainingPlan?

    private let healthStore = HKHealthStore()
    private let workoutSources: [WorkoutDataSource]
    private let auth: AuthProvider

    init(
        workoutSources: [WorkoutDataSource]? = nil,
        auth: AuthProvider? = nil
    ) {
        self.workoutSources = workoutSources ?? [HealthKitManager.shared, VitalManager.shared]
        self.auth = auth ?? AuthManager.shared
    }

    // MARK: - Predict Fitness

    @MainActor
    func predictFitness(
        plan: TrainingPlan?
    ) async {
        Log.coach.info("Starting fitness prediction...")
        isAnalyzing = true
        errorMessage = nil

        // 2026-07-17 race gathering: remember the plan so a candidate
        // confirmation can re-run the prediction with the same inputs.
        lastPlan = plan

        let userId = AuthManager.shared.userId
        Log.coach.info("Using userId: \(userId)")

        // Fetch workouts from all sources (30 days)
        Log.coach.info("Fetching workouts from \(self.workoutSources.count) sources...")
        let sourceWorkouts = await fetchFromAllSources(days: 30)
        Log.coach.info("Found \(sourceWorkouts.count) workouts from all sources")

        // Fetch voice logs from Supabase (includes linked workout data)
        Log.coach.info("Fetching training logs...")
        let voiceLogs = await fetchTrainingLogs(days: 30)
        Log.coach.info("Found \(voiceLogs.count) training logs")

        // 2026-07-17 race gathering: pending candidates + lifetime PRs load
        // alongside the rest of the read.
        await fetchRaceCandidates()
        await fetchLifetimePRs()

        // No data → bail out. We do NOT synthesize a fake fitness profile from
        // a hardcoded pace default (violates feedback_no_hardcoded_paces and
        // feedback_no_ai_hallucination). The view renders EmptyPredictionState
        // when predictions stays nil.
        if sourceWorkouts.isEmpty && voiceLogs.isEmpty {
            errorMessage = "No workout data found. Connect Apple Health or record a voice log to get predictions."
            predictions = nil
            isAnalyzing = false
            Log.coach.warning("No data from any source — userId=\(userId)")
            return
        }

        // Extract linked workouts from training logs (this is where race data often lives!)
        let linkedWorkouts = extractLinkedWorkouts(from: voiceLogs)
        Log.coach.info("Found \(linkedWorkouts.count) linked workouts in training logs")

        // Merge all workouts (linked + sources, avoiding duplicates by date+distance)
        let allWorkouts = mergeWorkouts(linkedWorkouts, sourceWorkouts)
        Log.coach.info("Total workouts after merge: \(allWorkouts.count)")

        // Load snapshot history early so the predictor can use it as a baseline
        if snapshotHistory.isEmpty {
            await fetchHistory()
        }

        // ONE PREDICTOR (2026-08-17). There is no on-device model any more.
        //
        // The app used to run `generateLocalPrediction` — an 851-line Swift
        // twin of the server's predictor — and render whichever answer was
        // handy. The device sees no laps, no weather, no HR efficiency and no
        // damped curve, so it was never the same answer: on 2026-08-17 it put
        // a 2:37 marathon on screen against the server's 2:29:13. Keeping a
        // second model "as a fallback" meant the app could silently show a
        // number no other surface agreed with.
        //
        // So: the server's row or nothing. When the nightly job hasn't reached
        // an athlete yet, an honest empty state beats a rival estimate — the
        // whole point of one source is that there is no second opinion to fall
        // back to.
        let prediction: FitnessPrediction? = await fetchCanonicalFitness()
            .flatMap { canonicalPrediction(from: $0) }

        predictions = prediction
        lastUpdated = Date()
        isAnalyzing = false

        guard let prediction else {
            errorMessage = "Not enough quality training data to project race times yet. Log a hard effort, race, or structured workout."
            Log.coach.info("No canonical fitness row — refusing to fabricate a second estimate.")
            return
        }
        Log.coach.info("Fitness read from canonical snapshot: \(prediction.dataSource)")

        Log.coach.info("Fitness prediction completed with \(prediction.races.count) races")

        await saveSnapshot(prediction: prediction)
    }

    // MARK: - Fetch Workouts (Protocol-based)

    private func fetchFromAllSources(days: Int) async -> [WorkoutData] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var all: [WorkoutData] = []
        for source in workoutSources {
            let workouts = await source.fetchRunningWorkouts(startDate: startDate, endDate: endDate)
            let mapped = workouts.compactMap { rw -> WorkoutData? in
                guard rw.distanceMiles > 0.5 else { return nil }
                let durationSeconds = rw.durationMinutes * 60
                let paceSecondsPerMile = rw.distanceMiles > 0 ? durationSeconds / rw.distanceMiles : 0
                return WorkoutData(
                    date: dateFormatter.string(from: rw.startDate),
                    distanceMiles: rw.distanceMiles,
                    durationMinutes: rw.durationMinutes,
                    paceSecondsPerMile: paceSecondsPerMile,
                    heartRateAvg: nil,
                    type: classifyWorkout(distance: rw.distanceMiles, pace: paceSecondsPerMile)
                )
            }
            all.append(contentsOf: mapped)
        }
        return all
    }

    /// Merge workouts, deduplicating by date + distance proximity
    func mergeWorkouts(_ base: [WorkoutData], _ additions: [WorkoutData]) -> [WorkoutData] {
        var merged = base
        for workout in additions {
            let isDuplicate = merged.contains { existing in
                existing.date == workout.date &&
                abs(existing.distanceMiles - workout.distanceMiles) < 0.2
            }
            if !isDuplicate {
                merged.append(workout)
            }
        }
        return merged
    }

    func classifyWorkout(distance: Double, pace: Double) -> String {
        if distance >= 10 { return "Long Run" }
        if pace > 0 && pace < 420 { return "Speed Work" }
        if pace > 0 && pace < 480 { return "Tempo" }
        if distance < 4 { return "Recovery" }
        return "Easy Run"
    }

    // MARK: - Fetch Training Logs (Voice Logs + Linked Workouts)

    private func fetchTrainingLogs(days: Int) async -> [VoiceLogData] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        do {
            // Select only columns in the TrainingLog model to avoid decoding issues
            // with extra DB columns (extracted_data, last_processing_attempt, etc.)
            let columns = "id, created_at, audio_url, notes, cleaned_notes, mood, workout_date, workout_distance_miles, workout_duration_minutes, processing_status, processing_error, processing_attempts, transcript_url, coach_insight, workout_notes, workout_pace_per_mile, workout_type, source, vital_workout_id, pace_segments, parsed_structure"
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select(columns)
                .gte("created_at", value: ISO8601DateFormatter().string(from: startDate))
                .order("created_at", ascending: false)
                .limit(1000)
                .execute()
                .value

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            return logs.compactMap { log -> VoiceLogData? in
                let notes = log.cleanedNotes ?? log.notes ?? ""

                // Extract pace mentions from notes
                let paces = extractPaces(from: notes)

                // Parse structured workout data from notes (intervals, tempo, etc.)
                let extractedWorkout = WorkoutTextParser.shared.parse(notes)
                if extractedWorkout.hasStructuredData {
                    Log.coach.info("Extracted structured workout: \(extractedWorkout.summary)")
                }

                return VoiceLogData(
                    date: log.workoutDate.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date()),
                    notes: notes,
                    mood: log.mood,
                    pacesMentioned: paces,
                    linkedWorkoutDistanceMiles: log.workoutDistanceMiles,
                    linkedWorkoutDurationMinutes: log.workoutDurationMinutes,
                    extractedWorkout: extractedWorkout,
                    paceSegments: log.paceSegments,
                    parsedStructure: log.parsedStructure
                )
            }
        } catch {
            Log.coach.error("Failed to fetch training logs: \(error)")
            // Surface decoding errors — these are the #1 silent killer
            if let decodingError = error as? DecodingError {
                Log.coach.error("Decoding error detail: \(decodingError)")
            }
            return []
        }
    }

    /// Extract workouts from training logs that have linked workout data
    private func extractLinkedWorkouts(from voiceLogs: [VoiceLogData]) -> [WorkoutData] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return voiceLogs.compactMap { log -> WorkoutData? in
            guard let distance = log.linkedWorkoutDistanceMiles,
                  let duration = log.linkedWorkoutDurationMinutes,
                  distance > 0.5 else { return nil }

            let paceSecondsPerMile = (duration * 60) / distance

            return WorkoutData(
                date: log.date,
                distanceMiles: distance,
                durationMinutes: duration,
                paceSecondsPerMile: paceSecondsPerMile,
                heartRateAvg: nil,
                type: classifyWorkout(distance: distance, pace: paceSecondsPerMile)
            )
        }
    }

    func extractPaces(from text: String) -> [String] {
        var paces: [String] = []

        // Pattern: "X:XX" or "XX:XX" format (1-2 digit minutes, 2 digit seconds)
        let pattern = #"(\d{1,2}):(\d{2})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                if let minuteRange = Range(match.range(at: 1), in: text),
                   let secondRange = Range(match.range(at: 2), in: text),
                   let minutes = Int(text[minuteRange]),
                   let seconds = Int(text[secondRange]) {
                    let totalSeconds = minutes * 60 + seconds
                    // Only include reasonable running paces (4:00-15:00/mi)
                    if totalSeconds >= 240 && totalSeconds <= 900 {
                        paces.append("\(minutes):\(String(format: "%02d", seconds))/mi")
                    }
                }
            }
        }

        return paces
    }

    // MARK: - Local Prediction (DELETED 2026-08-17)
    //
    // `generateLocalPrediction` lived here: 853 lines that re-derived race
    // predictions on-device from HealthKit workouts and training logs — a
    // Swift twin of _shared/fitnessPrediction.ts that drifted from it.
    //
    // It could not agree with the server and never will: the device has no
    // laps, so no per-rep heat or grade normalization; no weather, so no
    // conditions-normalized race anchor; no HR efficiency signal; and no
    // damped fitness curve. It picked its anchor race by a different rule.
    // On 2026-08-17 it showed a 2:37 marathon while the server held 2:29:13.
    //
    // It survived this long as a 'fallback' supplying three context fields
    // the canonical row didn't carry. `summary` and `supporting_training`
    // (migration 20260817220000) carry them now, so there is nothing left
    // for it to do. When no canonical row exists the screen shows its empty
    // state — one predictor means there is no second opinion to fall back
    // to, and that is the point.

    // MARK: - Canonical Fitness (server-owned)

    /// Read the server's canonical answer. Returns nil when there is no row
    /// yet (new athlete, or the nightly job hasn't run) — the caller then
    /// falls back to the on-device estimate rather than showing nothing.
    private func fetchCanonicalFitness() async -> CanonicalFitnessRow? {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return nil }
        do {
            let rows: [CanonicalFitnessRow] = try await supabase
                .from("fitness_snapshots")
                .select(
                    "predicted_mile_seconds, predicted_5k_seconds, predicted_10k_seconds,"
                    + "predicted_half_seconds, predicted_marathon_seconds,"
                    + "estimated_10k_pace_seconds, confidence, confidence_tier, data_source,"
                    + "workout_count, range_mile_seconds, range_5k_seconds, range_10k_seconds,"
                    + "range_half_seconds, range_marathon_seconds,"
                    + "anchor_distance_key, anchor_raw_seconds, anchor_neutral_seconds,"
                    + "anchor_date, anchor_weeks_ago, summary, supporting_training"
                )
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            Log.coach.error("canonical fitness read failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Build the screen's model from the canonical row — every field of it.
    ///
    /// This used to take a `local:` estimate alongside the row, because the
    /// server carried the numbers but not the summary line or the log counts.
    /// Producing those three values was the last job of the on-device model,
    /// and it cost 851 lines plus a 180-day workout fetch on every launch.
    /// `summary` and `supporting_training` (migration 20260817220000) carry
    /// them now, so there is exactly one predictor and this reads it.
    private func canonicalPrediction(from row: CanonicalFitnessRow) -> FitnessPrediction? {
        guard let tenK = row.predicted10kSeconds, tenK > 0,
              let paceSec = row.estimated10kPaceSeconds, paceSec > 0 else { return nil }

        func item(_ label: String, _ seconds: Int?, _ miles: Double, _ range: Int?) -> RacePredictionItem? {
            guard let seconds, seconds > 0 else { return nil }
            return RacePredictionItem(
                distance: label,
                time: formatTime(seconds: seconds),
                pace: formatPaceLocal(Double(seconds) / miles),
                pointSeconds: seconds,
                // The server computes the honest band (hard rule #7). A missing
                // one is left at 0 rather than invented here.
                rangeSeconds: range ?? 0
            )
        }

        let races = [
            item("MILE", row.predictedMileSeconds, 1.0, row.rangeMileSeconds),
            item("5K", row.predicted5kSeconds, RaceDistanceConstants.fiveKMiles, row.range5kSeconds),
            item("10K", row.predicted10kSeconds, RaceDistanceConstants.tenKMiles, row.range10kSeconds),
            item("HALF", row.predictedHalfSeconds, RaceDistanceConstants.halfMarathonMiles, row.rangeHalfSeconds),
            item("MARATHON", row.predictedMarathonSeconds, RaceDistanceConstants.marathonMiles, row.rangeMarathonSeconds),
        ].compactMap { $0 }
        guard !races.isEmpty else { return nil }

        // Zones from the canonical 10K — the Swift twin of the server's
        // derivePaceTableFromGoal, so app and backend share one ladder.
        let eqPaces = EquivalentPaces(raceDistance: .tenK, goalTimeSeconds: tenK)
        func aerobicRange(_ zone: NamedPace, single: Double) -> String {
            if let r = zone.displayPaceRange(base: single, marathonPace: eqPaces.mpPace) {
                return formatPaceRange(low: r.low, high: r.high)
            }
            return formatPaceLocal(single)
        }
        let trainingPaces = TrainingPacesSummary(
            easyPace: aerobicRange(.easy, single: eqPaces.easyPace),
            moderatePace: aerobicRange(.moderate, single: eqPaces.moderatePace),
            steadyPace: aerobicRange(.steady, single: eqPaces.steadyPace),
            marathonPace: formatPaceLocal(eqPaces.mpPace),
            hmpPace: formatPaceLocal(eqPaces.hmPace),
            tenKPace: formatPaceLocal(eqPaces.tenKPace),
            fiveKPace: formatPaceLocal(eqPaces.fiveKPace),
            thresholdPace: formatPaceLocal(eqPaces.thresholdPace),
            intervalPace: formatPaceLocal(eqPaces.fiveKPace),
            longRunPace: formatPaceLocal(eqPaces.longRunPace)
        )

        // The anchor as the server chose it. RAW is displayed — a normalized
        // time is never shown as a time she ran — even though the estimate
        // itself rests on the neutral equivalent.
        var raceAnchor: RaceAnchorInfo? = nil
        if let key = row.anchorDistanceKey, let raw = row.anchorRawSeconds, raw > 0 {
            let inFmt = DateFormatter()
            inFmt.dateFormat = "yyyy-MM-dd"
            inFmt.timeZone = TimeZone(identifier: "UTC")
            let outFmt = DateFormatter()
            outFmt.dateFormat = "MMM d, yyyy"
            let displayDate = row.anchorDate.flatMap { inFmt.date(from: $0) }.map { outFmt.string(from: $0) }
                ?? (row.anchorDate ?? "")
            raceAnchor = RaceAnchorInfo(
                raceType: key.uppercased() == "TENK" ? "10K"
                    : key.uppercased() == "FIVEK" ? "5K"
                    : key.uppercased(),
                time: formatTime(seconds: raw),
                date: displayDate,
                weeksAgo: Int((row.anchorWeeksAgo ?? 0).rounded())
            )
        }

        let tier = ConfidenceTier(rawValue: (row.confidenceTier ?? "").lowercased()) ?? .medium
        return FitnessPrediction(
            races: races,
            fitnessSummary: row.summary,
            dataSources: DataSources(
                workoutCount: row.workoutCount ?? 0,
                // The sessions the estimate actually rests on, and the ones it
                // read and set aside — the server's own accounting, not a
                // second model's guess at it.
                voiceLogCount: row.supportingTraining?.readButNotUsed?.count ?? 0,
                hardEffortCount: row.supportingTraining?.used?.count ?? 0,
                confidence: row.confidence ?? tier.rawValue.capitalized,
                confidenceTier: tier
            ),
            estimated10kPaceSeconds: paceSec,
            dataSource: row.dataSource ?? "server",
            trainingPaces: trainingPaces,
            raceAnchor: raceAnchor,
            // The server does not compute a training-stimulus block, so this is
            // nil rather than a device-derived one. The views already guard on
            // it (`trainingPaces != nil || trainingStimulus != nil`), so the
            // paces section still renders. If this is wanted back, it belongs
            // on the snapshot alongside `supporting_training` — not in a second
            // model on the phone.
            trainingStimulus: nil
        )
    }

    private func parsePaceString(_ pace: String) -> Double? {
        // Parse "M:SS/mi" format
        let cleaned = pace.replacingOccurrences(of: "/mi", with: "")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let mins = Int(parts[0]),
              let secs = Int(parts[1]) else { return nil }
        return Double(mins * 60 + secs)
    }

    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

    private func formatPaceLocal(_ secondsPerMile: Double) -> String {
        PaceCalculator.formatPaceWithUnit(secondsPerMile)
    }

    // MARK: - Race Gathering (2026-07-17 race gathering)
    //
    // The nightly server job tags race-like runs on their own training_logs
    // row: extracted_data.race_candidate = { race_type, race_label,
    // finish_time_seconds, detected_at, status }. The athlete owns the call —
    // we surface the candidate; confirming writes workout_type = "race" plus a
    // race_result payload and the predictor re-reads. Dismissing only flips
    // the status so the card never returns.

    /// Row shape for candidate + PR queries. `extracted_data` / `race_result`
    /// decode as AnyJSON so a malformed payload can never fail the whole list.
    private struct RaceCandidateRow: Decodable {
        let id: UUID
        let workoutDate: Date?
        let extractedData: AnyJSON?

        enum CodingKeys: String, CodingKey {
            case id
            case workoutDate = "workout_date"
            case extractedData = "extracted_data"
        }
    }

    @MainActor
    func fetchRaceCandidates() async {
        let userId = AuthManager.shared.userId
        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            let rows: [RaceCandidateRow] = try await supabase
                .from("training_logs")
                .select("id, workout_date, extracted_data")
                .eq("user_id", value: userId)
                .eq("extracted_data->race_candidate->>status", value: "pending")
                .order("workout_date", ascending: false)
                .limit(20)
                .execute()
                .value

            var candidates: [RaceCandidate] = []
            var extractedById: [UUID: [String: AnyJSON]] = [:]
            for row in rows {
                // Defensive decode — any malformed candidate is skipped, never a crash.
                guard let date = row.workoutDate,
                      let extracted = row.extractedData?.objectValue,
                      let rc = extracted["race_candidate"]?.objectValue,
                      let raceLabel = rc["race_label"]?.stringValue,
                      let raceType = rc["race_type"]?.stringValue,
                      let finishSeconds = rc["finish_time_seconds"]?.intValue
                          ?? rc["finish_time_seconds"]?.doubleValue.map({ Int($0) }),
                      finishSeconds > 0
                else {
                    Log.coach.warning("Skipping malformed race candidate row")
                    continue
                }

                candidates.append(RaceCandidate(
                    id: row.id,
                    date: date,
                    raceLabel: raceLabel,
                    raceType: raceType,
                    finishTimeSeconds: finishSeconds
                ))
                extractedById[row.id] = extracted
            }

            raceCandidates = candidates
            candidateExtractedData = extractedById
            Log.coach.info("Fetched \(candidates.count) pending race candidates")
        } catch {
            Log.coach.error("Failed to fetch race candidates: \(error)")
        }
    }

    /// Confirm a candidate: workout_type = "race", race_result written, and
    /// race_candidate.status flipped to "confirmed" via read-modify-write of
    /// the fetched extracted_data. Then refresh the prediction — a confirmed
    /// race is new anchor evidence.
    @MainActor
    func confirmRaceCandidate(_ candidate: RaceCandidate) async {
        // Never clobber extracted_data with a partial object — the full JSON
        // from the fetch is required for the read-modify-write.
        guard var extracted = candidateExtractedData[candidate.id] else {
            Log.coach.error("No fetched extracted_data for candidate \(candidate.id) — skipping confirm")
            return
        }
        var rc = extracted["race_candidate"]?.objectValue ?? [:]
        rc["status"] = .string("confirmed")
        extracted["race_candidate"] = .object(rc)

        let updateData: [String: AnyJSON] = [
            "workout_type": .string("race"),
            "race_result": .object([
                "distance": .string(Self.raceResultDistance(forRaceType: candidate.raceType)),
                "finish_time_seconds": .integer(candidate.finishTimeSeconds),
            ]),
            "extracted_data": .object(extracted),
        ]

        do {
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: candidate.id.uuidString)
                .execute()

            raceCandidates.removeAll { $0.id == candidate.id }
            candidateExtractedData[candidate.id] = nil
            Log.coach.info("Confirmed race candidate: \(candidate.raceLabel) (\(candidate.finishTimeSeconds)s)")

            // Refresh the read — predictFitness re-fetches candidates and
            // lifetime PRs alongside the prediction itself.
            await predictFitness(plan: lastPlan)
        } catch {
            Log.coach.error("Failed to confirm race candidate: \(error)")
        }
    }

    /// Dismiss a candidate: only race_candidate.status flips to "dismissed".
    /// The run itself is untouched.
    @MainActor
    func dismissRaceCandidate(_ candidate: RaceCandidate) async {
        guard var extracted = candidateExtractedData[candidate.id] else {
            Log.coach.error("No fetched extracted_data for candidate \(candidate.id) — skipping dismiss")
            return
        }
        var rc = extracted["race_candidate"]?.objectValue ?? [:]
        rc["status"] = .string("dismissed")
        extracted["race_candidate"] = .object(rc)

        let updateData: [String: AnyJSON] = [
            "extracted_data": .object(extracted),
        ]

        do {
            try await supabase
                .from("training_logs")
                .update(updateData)
                .eq("id", value: candidate.id.uuidString)
                .execute()

            raceCandidates.removeAll { $0.id == candidate.id }
            candidateExtractedData[candidate.id] = nil
            Log.coach.info("Dismissed race candidate: \(candidate.raceLabel)")
        } catch {
            Log.coach.error("Failed to dismiss race candidate: \(error)")
        }
    }

    /// Server race_type key → race_result.distance vocabulary.
    private static func raceResultDistance(forRaceType raceType: String) -> String {
        switch raceType {
        case "tenK":     return "10K"
        case "fiveK":    return "5K"
        case "half":     return "half"
        case "marathon": return "marathon"
        case "mile":     return "mile"
        default:         return raceType
        }
    }

    // MARK: - Lifetime PRs (2026-07-17 race gathering)

    /// Fetch every race row on file and compute the fastest finish per
    /// distance. Keyed by the view's row labels so the prediction rows can
    /// show the demonstrated mark beside the modeled one.
    @MainActor
    func fetchLifetimePRs() async {
        let userId = AuthManager.shared.userId
        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        struct RaceResultRow: Decodable {
            let workoutDate: Date?
            let raceResult: AnyJSON?

            enum CodingKeys: String, CodingKey {
                case workoutDate = "workout_date"
                case raceResult = "race_result"
            }
        }

        do {
            let rows: [RaceResultRow] = try await supabase
                .from("training_logs")
                .select("workout_date, race_result")
                .eq("user_id", value: userId)
                .eq("workout_type", value: "race")
                .limit(1000)
                .execute()
                .value

            var prs: [String: (seconds: Int, date: Date)] = [:]
            for row in rows {
                // Client-side filter for non-null, well-formed race_result.
                guard let date = row.workoutDate,
                      let result = row.raceResult?.objectValue,
                      let distanceRaw = result["distance"]?.stringValue,
                      let label = Self.prLabel(forDistance: distanceRaw),
                      let seconds = result["finish_time_seconds"]?.intValue
                          ?? result["finish_time_seconds"]?.doubleValue.map({ Int($0) }),
                      seconds > 0
                else { continue }

                if let existing = prs[label], existing.seconds <= seconds { continue }
                prs[label] = (seconds: seconds, date: date)
            }

            lifetimePRs = prs
            Log.coach.info("Lifetime PRs on file for \(prs.count) distances")
        } catch {
            Log.coach.error("Failed to fetch lifetime PRs: \(error)")
        }
    }

    /// race_result.distance (case-insensitive) → prediction-row label.
    private static func prLabel(forDistance distance: String) -> String? {
        switch distance.lowercased() {
        case "mile":                  return "MILE"
        case "5k":                    return "5K"
        case "10k":                   return "10K"
        case "half", "half marathon": return "HALF"
        case "marathon":              return "MARATHON"
        default:                      return nil
        }
    }

    /// "PR 31:21 · Feb 2026" for a prediction-row distance label, or nil when
    /// no race is on file at that distance (the row renders nothing).
    func prLine(forDistance distance: String) -> String? {
        guard let pr = lifetimePRs[distance.uppercased()] else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return "PR \(formatTime(seconds: pr.seconds)) · \(f.string(from: pr.date))"
    }

    /// "10K · 33:00 · Jul 4" summary line for a pending candidate.
    func candidateSummary(_ candidate: RaceCandidate) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(candidate.raceLabel) · \(formatTime(seconds: candidate.finishTimeSeconds)) · \(f.string(from: candidate.date))"
    }

    // MARK: - Snapshot Persistence

    /// DISABLED 2026-08-17 — the device no longer writes `fitness_snapshots`.
    ///
    /// WHY. There were two writers with different models. The server
    /// (`compute-fitness-snapshot`, nightly) reads per-lap data this device
    /// never sees: heat- and grade-normalized rep paces, conditions-normalized
    /// race anchors, HR-derived efficiency, and since 2026-08-16 a damped
    /// fitness curve. The on-device predictor has none of that, so it produced
    /// a materially different answer and persisted it to the same table.
    ///
    /// That was cosmetic while every night overwrote the last. It stopped being
    /// cosmetic when the server curve landed: a smoother trusts its own history
    /// by design, so a device-written row becomes the prior the server damps
    /// away FROM. Two such rows (2026-08-15 15:03 and 2026-08-16 20:46, both
    /// 33:44 against the server's 32:00) dragged the athlete's estimate off by
    /// ~100 s, and at a 21-day time constant it would have taken six weeks to
    /// crawl back.
    ///
    /// The local prediction is still computed and still drives this screen —
    /// only the PERSIST is gone. `fitness_snapshots` now has exactly one
    /// writer. Read the server's answer from `athlete_state.fitness_prediction`
    /// when this screen should agree with Trends.
    /// Single switch rather than deleted code: the write path is still correct
    /// and still the only reference for what a snapshot row looks like. If the
    /// device ever becomes the writer again, this flips — it does not get
    /// rewritten from memory.
    private static let deviceWritesSnapshots = false

    @MainActor
    private func saveSnapshot(prediction: FitnessPrediction) async {
        guard Self.deviceWritesSnapshots else {
            Log.coach.info(
                "saveSnapshot skipped — fitness_snapshots is server-owned (compute-fitness-snapshot)")
            return
        }

        let userId = AuthManager.shared.userId

        // Never write a snapshot with an empty user_id. AuthManager.userId
        // returns "" when accessed before auth resolves; persisting that
        // produces orphaned rows owned by nobody (invisible to the user and to
        // server-side reads). Skip and let the next prediction (post-auth) write.
        // See outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md.
        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else {
            Log.coach.warning("saveSnapshot skipped — userId empty (not yet authenticated)")
            return
        }

        // Write the EXACT numbers the athlete saw (2026-07-16). The old code
        // recomputed times from the raw ratio table here, silently bypassing the
        // mile speed-shading and marathon volume adjustment — and it never wrote
        // confidence_tier or the range columns at all (tier arrived NULL in the
        // DB and server-side readers fell back to defaults).
        let pace10k = prediction.estimated10kPaceSeconds
        func item(_ name: String) -> RacePredictionItem? {
            prediction.races.first(where: { $0.distance == name })
        }
        let tenKSeconds = item("10K")?.pointSeconds ?? Int((pace10k * RaceDistanceConstants.tenKMiles).rounded())

        let snapshotData = FitnessSnapshotInsert(
            userId: userId,
            predictedMileSeconds: item("MILE")?.pointSeconds ?? PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "mile"),
            predicted5kSeconds: item("5K")?.pointSeconds ?? PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "5K"),
            predicted10kSeconds: tenKSeconds,
            predictedHalfSeconds: item("HALF")?.pointSeconds ?? PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "half"),
            predictedMarathonSeconds: item("MARATHON")?.pointSeconds ?? PaceCalculator.getEquivalentTime(fromDistance: "10K", fromSeconds: tenKSeconds, toDistance: "marathon"),
            estimated10kPaceSeconds: pace10k,
            confidence: prediction.dataSources.confidence,
            dataSource: prediction.dataSource,
            workoutCount: prediction.dataSources.workoutCount,
            confidenceTier: prediction.dataSources.confidenceTier.rawValue,
            rangeMileSeconds: item("MILE")?.rangeSeconds,
            range5kSeconds: item("5K")?.rangeSeconds,
            range10kSeconds: item("10K")?.rangeSeconds,
            rangeHalfSeconds: item("HALF")?.rangeSeconds,
            rangeMarathonSeconds: item("MARATHON")?.rangeSeconds
        )

        // Upsert: update today's existing row if there is one, otherwise insert.
        let today = Calendar.current.startOfDay(for: Date())
        let todaysSnapshotId: UUID? = snapshotHistory
            .first(where: { Calendar.current.isDate($0.createdAt, inSameDayAs: today) })?
            .id

        do {
            if let id = todaysSnapshotId {
                try await supabase
                    .from("fitness_snapshots")
                    .update(snapshotData)
                    .eq("id", value: id.uuidString)
                    .execute()
                Log.coach.info("Updated today's fitness snapshot (10K pace: \(self.formatPaceLocal(pace10k)))")
            } else {
                try await supabase
                    .from("fitness_snapshots")
                    .insert(snapshotData)
                    .execute()
                Log.coach.info("Saved new fitness snapshot (10K pace: \(self.formatPaceLocal(pace10k)))")
            }

            // Refresh history to include the new/updated snapshot
            await fetchHistory()
        } catch {
            Log.coach.error("Failed to save fitness snapshot: \(error.localizedDescription)")
        }
    }

    @MainActor
    func fetchHistory() async {
        isLoadingHistory = true

        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        let userId = AuthManager.shared.userId

        do {
            let snapshots: [FitnessSnapshot] = try await supabase
                .from("fitness_snapshots")
                .select()
                .eq("user_id", value: userId)
                .gte("created_at", value: ISO8601DateFormatter().string(from: ninetyDaysAgo))
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value

            snapshotHistory = snapshots
            Log.coach.info("Fetched \(snapshots.count) fitness snapshots")
        } catch {
            Log.coach.error("Failed to fetch fitness history: \(error.localizedDescription)")
        }

        isLoadingHistory = false
    }

    // MARK: - Trend Helpers

    /// Change in predicted 10K time (seconds) vs previous snapshot. Negative = improvement.
    var tenKChangeFromPrevious: Int? {
        guard snapshotHistory.count >= 2 else { return nil }
        return snapshotHistory[0].predicted10kSeconds - snapshotHistory[1].predicted10kSeconds
    }

    /// Date of the previous snapshot for comparison labeling
    var previousSnapshotDate: Date? {
        guard snapshotHistory.count >= 2 else { return nil }
        return snapshotHistory[1].createdAt
    }

    // MARK: - Race Detection

    enum RaceType: String {
        case mile = "Mile"
        case fiveK = "5K"
        case tenK = "10K"
        case half = "Half Marathon"
        case marathon = "Marathon"

        var distanceMiles: Double {
            switch self {
            case .mile: return 1.0
            case .fiveK: return 3.107
            case .tenK: return 6.214
            case .half: return 13.109
            case .marathon: return 26.219
            }
        }

        var tolerance: Double {
            // Allow for GPS drift - races often read short due to tangent running
            // 10K might show as 6.15mi instead of 6.21mi
            switch self {
            case .mile: return 0.08      // ±0.08mi (~8%)
            case .fiveK: return 0.20     // ±0.20mi (~6%)
            case .tenK: return 0.40      // ±0.40mi (~6%) - 5.81 to 6.61
            case .half: return 0.50      // ±0.50mi (~4%)
            case .marathon: return 1.0   // ±1.0mi (~4%)
            }
        }
    }

    struct DetectedRace {
        let raceType: RaceType
        let paceSecondsPerMile: Double
        let date: String
        let totalTimeSeconds: Int
    }

    /// A high-quality training effort that can serve as a fitness anchor when no
    /// recent race exists. Less reliable than a declared race (lower confidence)
    /// but captures current fitness far better than a 3-month-old race decayed forward.
    struct TrainingAnchor {
        enum Kind: String {
            case tempoSustained      // ≥2mi labeled tempo/threshold segment
            case intervalSession     // summed interval efforts, ≥3mi total
            case racePaceEffort      // labeled race_pace segment ≥2mi
            case longRunFinish       // last 3mi of a long run, labeled moderate+
        }
        let kind: Kind
        let paceSecondsPerMile: Double       // avg pace across the effort
        let distanceMiles: Double            // total distance of the qualifying effort
        let equivalentTenKPace: Double       // converted to 10K equivalent for anchoring
        let date: String
        let confidence: Double               // 0.0 - 1.0, vs 1.0 for a declared race
    }

    /// Detraining signal — captures whether a runner has stopped training in ways
    /// that would actually erode fitness. Gate on the snapshot-baseline decay so
    /// a runner who keeps training isn't penalized for an old snapshot.
    ///
    /// Triggers (any one contributes to severity):
    ///   - lowVolume:   weekly miles in last 2 weeks < 50% of 4-week baseline,
    ///                  OR < 15 mi/wk in absolute terms
    ///   - zeroQuality: no parsed_structure workouts of type tempo/interval/race/
    ///                  progression in the last 3 weeks
    ///   - layoff:      gap ≥ 7 days between consecutive workouts in the last 4 weeks
    ///
    /// Severity:
    ///   - 3 triggers → 1.0 (full 0.3%/wk decay rate)
    ///   - 2 triggers → 0.7
    ///   - 1 trigger  → 0.4
    ///   - 0 triggers → no signal returned (nil → no decay applied)
    struct DetrainingSignal {
        let lowVolume: Bool
        let zeroQuality: Bool
        let layoff: Bool
        let reasons: [String]
        var severity: Double {
            let count = [lowVolume, zeroQuality, layoff].filter { $0 }.count
            switch count {
            case 3: return 1.0
            case 2: return 0.7
            case 1: return 0.4
            default: return 0.0
            }
        }
    }

    /// Surface training efforts that can ground the fitness estimate when a recent
    /// race isn't available.
    ///
    /// Primary signal: `parsed_structure` from the Observer-layer AI parse — it
    /// computes equivalent race pace from total work distance + avg work pace
    /// (e.g. 8×800m @ 2:30 → 5K @ ~15:30). That pace goes straight in as an anchor.
    ///
    /// Fallback: labeled pace_segments (tempo/threshold/interval/race_pace) when
    /// the Observer hasn't run yet. Never infers from raw pace — prevents the
    /// same class of false positives the race detector had.
    func detectTrainingAnchors(voiceLogs: [VoiceLogData]) -> [TrainingAnchor] {
        var anchors: [TrainingAnchor] = []

        // ── Primary: Observer parsed_structure ──
        for log in voiceLogs {
            guard let parsed = log.parsedStructure,
                  parsed.confidence >= 0.6,
                  let eqRace = parsed.equivalentRacePace else { continue }

            let paceSec = Self.paceStringToSeconds(eqRace.pacePerMile)
            guard paceSec > 0 else { continue }
            let tenK = Self.convert(pace: paceSec, from: eqRace.distanceKey, to: "tenK")
            let workDist = parsed.workSummary?.totalDistanceMi ?? 0

            // Pick anchor kind from workout type.
            //
            // INTERVAL sessions are deliberately excluded as race anchors: an
            // equivalent_race_pace derived from short reps equates rep pace with
            // race pace (reps are run FASTER than you can race), which produced
            // near-elite fitness estimates — e.g. 400m reps @ 4:50/mi read as a
            // 15:00 5K. The Observer prompt no longer emits these, but old rows
            // still carry them, so we also drop them here. Interval fitness still
            // reaches the estimate through the calibrated pace-segment signal
            // below (distance-aware, volume-gated), not a fabricated race.
            let kind: TrainingAnchor.Kind
            switch parsed.type.lowercased() {
            case "tempo": kind = .tempoSustained
            case "race", "race_pace": kind = .racePaceEffort
            case "progression", "long_run": kind = .longRunFinish
            default: continue  // skip interval / easy / unclear
            }

            anchors.append(TrainingAnchor(
                kind: kind,
                paceSecondsPerMile: paceSec,
                distanceMiles: max(workDist, 2.0),
                equivalentTenKPace: tenK,
                date: log.date,
                // Observer-parsed anchors carry the model's confidence, capped at 0.85
                // (a declared race is still a stronger signal at 1.0).
                confidence: min(0.85, parsed.confidence)
            ))
        }

        // Sort Observer anchors by date desc, confidence desc
        let observerAnchors = anchors.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.confidence > rhs.confidence
        }

        // Segment-label fallback DISABLED. The existing classifier's "race_pace"
        // / "tempo" labels are unreliable (labels get applied to easy long runs
        // etc.), which produced false anchors like "7:38/mi = race_pace effort"
        // on a runner whose actual 10K pace is 5:03. Only the Observer's
        // parsed_structure + equivalent_race_pace is trustworthy.
        //
        // Note: removing this fallback means workouts without a parsed_structure
        // contribute no training anchor — the predictor falls back to its race
        // anchor, which correctly decays over time. Better false negative than
        // corrupt fitness estimate.
        return observerAnchors
    }

    /// Retained for future use if a stricter segment-label fallback is re-enabled.
    /// Currently unused.
    private func _legacySegmentAnchors(voiceLogs: [VoiceLogData], existing: [TrainingAnchor]) -> [TrainingAnchor] {
        var anchors = existing
        for log in voiceLogs {
            if anchors.contains(where: { $0.date == log.date }) { continue }
            guard let segments = log.paceSegments, !segments.isEmpty else { continue }

            // Sustained tempo/threshold — one segment ≥ 2mi, labeled tempo/threshold
            for seg in segments {
                let effort = seg.effort.lowercased()
                let distance = seg.distanceMiles
                let paceSec = Self.paceStringToSeconds(seg.pacePerMile)
                guard paceSec > 0 else { continue }

                if (effort == "tempo" || effort == "threshold") && distance >= 2.0 {
                    // Tempo ≈ HMP. Convert to 10K using PaceCalculator.
                    let tenK = Self.convert(
                        pace: paceSec, from: "halfMarathon", to: "tenK"
                    )
                    anchors.append(TrainingAnchor(
                        kind: .tempoSustained,
                        paceSecondsPerMile: paceSec,
                        distanceMiles: distance,
                        equivalentTenKPace: tenK,
                        date: log.date,
                        confidence: min(0.75, 0.55 + (distance - 2.0) * 0.05)
                    ))
                } else if effort == "race_pace" && distance >= 2.0 {
                    // race_pace is already goal pace — scale to 10K based on distance
                    let tenK = Self.convert(
                        pace: paceSec, from: distance < 5.0 ? "fiveK" : "tenK", to: "tenK"
                    )
                    anchors.append(TrainingAnchor(
                        kind: .racePaceEffort,
                        paceSecondsPerMile: paceSec,
                        distanceMiles: distance,
                        equivalentTenKPace: tenK,
                        date: log.date,
                        confidence: 0.7
                    ))
                }
            }

            // Interval session — sum all interval segments in this log
            let intervalSegs = segments.filter { $0.effort.lowercased() == "interval" }
            let intervalDist = intervalSegs.reduce(0.0) { $0 + $1.distanceMiles }
            if intervalDist >= 2.0 {
                let totalSec = intervalSegs.reduce(0.0) { sum, s in
                    sum + Self.paceStringToSeconds(s.pacePerMile) * s.distanceMiles
                }
                let avgPace = totalSec / intervalDist
                // Intervals ≈ 5K pace. Convert to 10K.
                let tenK = Self.convert(pace: avgPace, from: "fiveK", to: "tenK")
                anchors.append(TrainingAnchor(
                    kind: .intervalSession,
                    paceSecondsPerMile: avgPace,
                    distanceMiles: intervalDist,
                    equivalentTenKPace: tenK,
                    date: log.date,
                    confidence: min(0.7, 0.5 + (intervalDist - 2.0) * 0.05)
                ))
            }
        }

        // Sort by date (most recent first), then confidence
        return anchors.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.confidence > rhs.confidence
        }
    }

    private static func paceStringToSeconds(_ pace: String) -> Double {
        let parts = pace.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]), let s = Int(parts[1]) else { return 0 }
        return Double(m * 60 + s)
    }

    /// The Observer's `distance_key` vocabulary ("fiveK" / "tenK" /
    /// "halfMarathon") does NOT match `PaceCalculator.distances`' keys
    /// ("5K" / "10K" / "half"). Without this mapping every lookup missed and
    /// `convert` silently returned the pace UNCHANGED — so a 5K-equivalent pace
    /// was used directly as a 10K pace (etc.) with no distance slowdown, which
    /// is part of why predictions ran elite. Map before lookup.
    private static func paceCalcKey(_ key: String) -> String {
        switch key {
        case "fiveK":        return "5K"
        case "tenK":         return "10K"
        case "halfMarathon": return "half"
        default:             return key   // "mile" / "marathon" already match
        }
    }

    /// Convert a pace from one distance to another using PaceCalculator's equivalence.
    /// Keys accepted: "mile", "fiveK", "tenK", "halfMarathon", "marathon".
    /// `internal` (not private) so a regression test can prove the distance-key
    /// mapping actually converts instead of silently no-opping (the elite-
    /// prediction bug, 2026-07-16).
    static func convert(pace: Double, from: String, to: String) -> Double {
        let fromKey = paceCalcKey(from)
        let toKey = paceCalcKey(to)
        guard
            let fromDist = PaceCalculator.distances[fromKey],
            let toDist = PaceCalculator.distances[toKey]
        else { return pace }
        let fromTime = Int(pace * fromDist)
        let toTime = PaceCalculator.getEquivalentTime(
            fromDistance: fromKey, fromSeconds: fromTime, toDistance: toKey
        )
        return toTime > 0 ? Double(toTime) / toDist : pace
    }

    /// Detect race efforts from workouts and voice logs.
    /// Voice log text parsing runs FIRST — "10k race: 31:24" is the strongest signal.
    func detectRaces(workouts: [WorkoutData], voiceLogs: [VoiceLogData]) -> [DetectedRace] {
        var races: [DetectedRace] = []

        // ── PHASE 1: Parse explicit race results from training log notes ──
        // This is the most reliable source — the user explicitly wrote "10k race: 31:24"
        let raceKeywords = ["race", "raced", "pr ", "pr:", "pb ", "pb:", "personal best", "personal record", "finish time"]
        let distancePatterns: [(String, RaceType)] = [
            ("marathon", .marathon), ("half marathon", .half), ("half", .half),
            ("10k", .tenK), ("10K", .tenK),
            ("5k", .fiveK), ("5K", .fiveK),
            ("mile", .mile),
        ]

        // Workout-context patterns — when these appear, the log is describing
        // training, not a race. The race keyword is almost always a forward-looking
        // reference ("leading up to the race", "racing in 2 weeks"). Skip race
        // detection on these logs entirely.
        let workoutContextPatterns = [
            "tempo run", "workout:", "workout today", "interval session", "fartlek",
            "mile repeat", "mile repeats", "k repeat", "kilometer repeat",
            "x 400", "x 800", "x 1000", "x 1k", "x 200", "x 600", "x 1200",
            "x400", "x800", "x1000", "x1k", "x200", "x600", "x1200",
            "threshold intervals", "threshold work", "track session",
            "warm-up:", "warm up:", "cool-down:", "cool down:"
        ]
        // Forward-looking race phrases — talking about a future race, not a past one.
        let forwardLookingRacePhrases = [
            "leading up to", "looking forward to", "next race", "upcoming race",
            "before the race", "race coming up", "race next", "racing in",
            "preparing for the race"
        ]
        // Past-tense race signals — strong evidence a race actually happened.
        let pastRaceSignals = [
            "raced", "race today", "race result", "finish time",
            "for the race", "ran the", "finished the", "completed the race",
            "race report", "race recap", "ran my"
        ]

        for log in voiceLogs {
            let notes = log.notes.lowercased()
            guard raceKeywords.contains(where: { notes.contains($0) }) else { continue }

            // Filter 1: workout context overrides race detection entirely.
            if workoutContextPatterns.contains(where: { notes.contains($0) }) {
                continue
            }

            // Filter 2: if the only race mention is forward-looking AND there's no
            // past-tense race signal, this isn't a race report — it's anticipation.
            let hasForwardLooking = forwardLookingRacePhrases.contains(where: { notes.contains($0) })
            let hasPastTense = pastRaceSignals.contains(where: { notes.contains($0) })
            if hasForwardLooking && !hasPastTense {
                continue
            }

            for (pattern, raceType) in distancePatterns {
                guard notes.contains(pattern) else { continue }
                // Already have this exact race (same date AND distance)? Skip.
                // We dedupe by (date, raceType) — not by raceType alone — so multiple
                // races at the same distance months apart (e.g. a Feb 10K and an Apr
                // 10K) are both retained. The anchor selection picks the best one.
                if races.contains(where: { $0.raceType == raceType && $0.date == log.date }) { break }

                // Parse time: H:MM:SS or MM:SS patterns
                let originalNotes = log.notes
                let timePattern = #"(\d{1,2}):(\d{2}):(\d{2})|(\d{1,2}):(\d{2})"#
                guard let regex = try? NSRegularExpression(pattern: timePattern) else { break }
                let range = NSRange(originalNotes.startIndex..., in: originalNotes)
                let matches = regex.matches(in: originalNotes, range: range)

                for match in matches {
                    var totalSeconds: Int?

                    // H:MM:SS format
                    if let hRange = Range(match.range(at: 1), in: originalNotes),
                       let mRange = Range(match.range(at: 2), in: originalNotes),
                       let sRange = Range(match.range(at: 3), in: originalNotes),
                       let h = Int(originalNotes[hRange]),
                       let m = Int(originalNotes[mRange]),
                       let s = Int(originalNotes[sRange]) {
                        totalSeconds = h * 3600 + m * 60 + s
                    }
                    // MM:SS format
                    else if let mRange = Range(match.range(at: 4), in: originalNotes),
                            let sRange = Range(match.range(at: 5), in: originalNotes),
                            let m = Int(originalNotes[mRange]),
                            let s = Int(originalNotes[sRange]) {
                        totalSeconds = m * 60 + s
                    }

                    if let seconds = totalSeconds, seconds > 60, seconds < 36000 {
                        let pace = Double(seconds) / raceType.distanceMiles
                        if pace >= 180 && pace <= 900 {
                            races.append(DetectedRace(
                                raceType: raceType,
                                paceSecondsPerMile: pace,
                                date: log.date,
                                totalTimeSeconds: seconds
                            ))
                            Log.coach.info("Parsed \(raceType.rawValue) race from notes on \(log.date): \(self.formatTime(seconds: seconds)) (\(self.formatPaceLocal(pace)))")
                            break
                        }
                    }
                }
                break // Only match the first distance pattern per log
            }
        }

        // ── PHASE 2: Detect race efforts from workout data — STRICT ──
        // Old heuristic auto-tagged easy runs as races (e.g. single 3mi jog @ 8:32/mi → "5K race").
        // Correct rule: only auto-infer a race when the workout clearly matches BOTH:
        //   (a) explicit race keyword in the linked log's notes on that date, AND
        //   (b) pace is meaningfully faster than the user's recent training average (≥15% faster)
        // Workouts without a user-declared race keyword are never auto-tagged.
        let raceDates = Set(voiceLogs.filter { log in
            let notes = log.notes.lowercased()
            return raceKeywords.contains(where: { notes.contains($0) })
        }.map { $0.date })

        for workout in workouts {
            // Only workouts on dates the user explicitly mentioned as a race qualify for Phase 2.
            guard raceDates.contains(workout.date) else { continue }

            for raceType in [RaceType.mile, .fiveK, .tenK, .half, .marathon] {
                // Already found this race type from voice logs? Skip.
                if races.contains(where: { $0.raceType == raceType }) { continue }

                let minDist = raceType.distanceMiles - raceType.tolerance
                let maxDist = raceType.distanceMiles + raceType.tolerance

                if workout.distanceMiles >= minDist && workout.distanceMiles <= maxDist {
                    // Pace must be at least 15% faster than the user's recent training average
                    // to count as a race effort. Prevents slow runs on race-mention days (e.g.
                    // "recovery after race") from being mis-tagged.
                    let minComparisonDist = min(4.0, raceType.distanceMiles * 0.8)
                    let otherWorkouts = workouts.filter {
                        ($0.date != workout.date || abs($0.distanceMiles - workout.distanceMiles) > 0.1) &&
                        $0.distanceMiles >= minComparisonDist
                    }
                    guard !otherWorkouts.isEmpty else { continue }

                    let avgPace = otherWorkouts.map { $0.paceSecondsPerMile }.reduce(0, +) / Double(otherWorkouts.count)
                    let isRaceEffort = workout.paceSecondsPerMile < avgPace * 0.85

                    if isRaceEffort {
                        // Adjust race time from GPS-measured distance to the standard race distance.
                        // GPS commonly reads short (tangent running, tunnel signal loss) — a 10K
                        // race showing 5.9mi on the watch is still a 10K. Use the actual finish
                        // time as the race time when GPS is short. Only scale up when GPS is
                        // long (extra warm-up distance, wrong start/stop).
                        let actualTimeSeconds = workout.durationMinutes * 60
                        let actualDistanceMiles = workout.distanceMiles
                        let targetKey = raceTypeToPCKey(raceType)
                        let targetDistanceMiles = PaceCalculator.distances[targetKey] ?? raceType.distanceMiles

                        let adjustedTimeSeconds: Int
                        let distanceRatio = actualDistanceMiles / targetDistanceMiles

                        if distanceRatio >= 0.92 && distanceRatio <= 1.02 {
                            // GPS shows the race distance (or slightly short due to GPS error).
                            // Trust the actual finish time as the true race time.
                            adjustedTimeSeconds = Int(actualTimeSeconds)
                        } else if distanceRatio > 1.02 && distanceRatio < 1.08 {
                            // GPS reads longer (extra distance from warm-up, wrong cut-off).
                            // Scale down proportionally.
                            adjustedTimeSeconds = Int(actualTimeSeconds / distanceRatio)
                        } else {
                            // Significantly different distance — use PaceCalculator equivalence
                            let pcKey = closestPaceCalculatorKey(distanceMiles: actualDistanceMiles)
                            let converted = PaceCalculator.getEquivalentTime(
                                fromDistance: pcKey, fromSeconds: Int(actualTimeSeconds), toDistance: targetKey
                            )
                            adjustedTimeSeconds = converted > 0 ? converted : Int(actualTimeSeconds)
                        }
                        let adjustedPace = Double(adjustedTimeSeconds) / raceType.distanceMiles

                        races.append(DetectedRace(
                            raceType: raceType,
                            paceSecondsPerMile: adjustedPace,
                            date: workout.date,
                            totalTimeSeconds: adjustedTimeSeconds
                        ))
                        Log.coach.info("Detected \(raceType.rawValue) race on \(workout.date): \(self.formatPaceLocal(workout.paceSecondsPerMile)) (\(String(format: "%.2f", actualDistanceMiles))mi) → \(self.formatTime(seconds: adjustedTimeSeconds))")
                        break
                    }
                }
            }
        }

        // Sort by date (most recent first)
        return races.sorted { $0.date > $1.date }
    }

    /// Detect whether the runner has stopped training in ways that actually erode
    /// fitness. Returns nil when no detraining evidence is present — meaning the
    /// snapshot baseline should hold flat (no decay applied).
    ///
    /// Coach intuition: fitness doesn't vanish from a single slow week. It vanishes
    /// when volume and quality both collapse for a sustained period, or when
    /// there's been a real layoff. Anything short of that holds.
    func detectDetraining(workouts: [WorkoutData], voiceLogs: [VoiceLogData]) -> DetrainingSignal? {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: now) ?? now
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now
        let sixWeeksAgo = Calendar.current.date(byAdding: .day, value: -42, to: now) ?? now

        // ── Low volume detection ──
        // Recent (last 2wk) miles/wk vs prior 4-week baseline (6wk → 2wk back).
        // Trigger if recent < 50% of baseline, OR absolute recent < 15 mi/wk.
        var recentMiles: Double = 0
        var baselineMiles: Double = 0
        for workout in workouts {
            guard let workoutDate = dateFmt.date(from: workout.date) else { continue }
            if workoutDate >= twoWeeksAgo {
                recentMiles += workout.distanceMiles
            } else if workoutDate >= sixWeeksAgo && workoutDate < twoWeeksAgo {
                baselineMiles += workout.distanceMiles
            }
        }
        let recentMilesPerWeek = recentMiles / 2.0
        // Divide by the weeks the data actually COVERS (2026-07-16). Workouts
        // arrive on a ~30-day window, so the "6wk→2wk back" baseline held at
        // most ~16 days of data — dividing by a fixed 4.0 understated baseline
        // mi/wk, inflated the recent:baseline ratio, and suppressed the
        // low-volume detraining trigger.
        let earliestWorkoutDate = workouts.compactMap { dateFmt.date(from: $0.date) }.min() ?? sixWeeksAgo
        let baselineWindowStart = max(sixWeeksAgo, earliestWorkoutDate)
        let baselineCoveredWeeks = max(twoWeeksAgo.timeIntervalSince(baselineWindowStart) / (7 * 86400.0), 0.5)
        let baselineMilesPerWeek = baselineMiles / min(baselineCoveredWeeks, 4.0)
        let ratio = baselineMilesPerWeek > 0 ? recentMilesPerWeek / baselineMilesPerWeek : 1.0
        let lowVolume = (baselineMilesPerWeek > 0 && ratio < 0.5) || recentMilesPerWeek < 15.0

        // ── Zero quality detection ──
        // No parsed_structure workouts of qualifying types in the last 3 weeks.
        let qualifyingTypes: Set<String> = ["tempo", "interval", "race", "progression", "race_pace"]
        let recentQuality = voiceLogs.contains { log in
            guard let logDate = dateFmt.date(from: log.date),
                  logDate >= threeWeeksAgo,
                  let parsed = log.parsedStructure else { return false }
            return qualifyingTypes.contains(parsed.type.lowercased())
        }
        let zeroQuality = !recentQuality

        // ── Layoff detection ──
        // Gap of ≥ 7 days between consecutive workouts in the last 4 weeks.
        // Also: fewer than 2 workouts in 4 weeks counts as layoff.
        let recentWorkoutDates = workouts.compactMap { dateFmt.date(from: $0.date) }
            .filter { $0 >= fourWeeksAgo }
            .sorted()
        var layoff = false
        if recentWorkoutDates.count < 2 {
            layoff = true
        } else {
            for i in 1..<recentWorkoutDates.count {
                let gap = recentWorkoutDates[i].timeIntervalSince(recentWorkoutDates[i-1]) / 86400.0
                if gap >= 7.0 {
                    layoff = true
                    break
                }
            }
        }

        // Assemble signal
        let triggerCount = [lowVolume, zeroQuality, layoff].filter { $0 }.count
        guard triggerCount > 0 else { return nil }

        var reasons: [String] = []
        if lowVolume {
            if recentMilesPerWeek < 15.0 {
                reasons.append("low volume (\(String(format: "%.0f", recentMilesPerWeek)) mi/wk)")
            } else {
                reasons.append("volume drop to \(String(format: "%.0f%%", ratio * 100)) of baseline")
            }
        }
        if zeroQuality { reasons.append("no quality work in 3wk") }
        if layoff      { reasons.append("layoff (7+ day gap)") }

        return DetrainingSignal(
            lowVolume: lowVolume,
            zeroQuality: zeroQuality,
            layoff: layoff,
            reasons: reasons
        )
    }

    /// Map the public RaceDistance enum to the internal RaceType
    private func planRaceType(_ distance: RaceDistance) -> RaceType {
        switch distance {
        case .mile1500: return .mile
        case .fiveK: return .fiveK
        case .tenK: return .tenK
        case .halfMarathon: return .half
        case .marathon: return .marathon
        }
    }

    /// Convert pace from one race distance to another using PaceCalculator equivalence tables.
    /// This matches the pace chart system exactly.
    func convert(racePace: Double, from source: RaceType, to target: RaceType) -> Double {
        let sourceKey = raceTypeToPCKey(source)
        let targetKey = raceTypeToPCKey(target)
        let sourceMiles = PaceCalculator.distances[sourceKey] ?? source.distanceMiles
        let targetMiles = PaceCalculator.distances[targetKey] ?? target.distanceMiles

        guard let fromRatio = PaceCalculator.performanceRatios[sourceKey],
              let toRatio = PaceCalculator.performanceRatios[targetKey] else { return racePace }

        // Use doubles throughout to avoid Int truncation errors
        let sourceTimeSeconds = racePace * sourceMiles
        let targetTimeSeconds = sourceTimeSeconds * (toRatio / fromRatio)
        guard targetTimeSeconds > 0 else { return racePace }
        return targetTimeSeconds / targetMiles
    }

    /// Map RaceType to PaceCalculator distance key
    private func raceTypeToPCKey(_ type: RaceType) -> String {
        switch type {
        case .mile: return "mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "half"
        case .marathon: return "marathon"
        }
    }

    /// Find the closest PaceCalculator distance key for a given distance in miles
    private func closestPaceCalculatorKey(distanceMiles: Double) -> String {
        let keys: [(String, Double)] = [
            ("mile", 1.0),
            ("5K", 3.10686),
            ("10K", 6.21371),
            ("half", 13.1094),
            ("marathon", 26.2188),
        ]
        return keys.min(by: { abs($0.1 - distanceMiles) < abs($1.1 - distanceMiles) })?.0 ?? "10K"
    }
}


