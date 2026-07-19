//
//  WorkoutRepChart.swift
//  RunningLog
//
//  The per-workout rep visualization (Training Analysis headline feature).
//  Reads rep-level `running_workout_laps` for one workout and draws it
//  split-by-split: rep bars (faster = taller), HR overlay, rest markers,
//  pace-zone reference lines, a stat row, and a heat-adjustment toggle.
//
//  Design: outputs/workout-detail-viz.html + weather-adjustment-viz.html.
//  Post Run Drip. Hand-drawn (GeometryReader/Path) — no chart dependency.
//
//  Use: `WorkoutRepChart(workoutId: log.id)` from any workout tap-through.
//  Preview-able offline via the #Preview at the bottom.
//

import SwiftUI
import Supabase
import os

// MARK: - Data

struct WorkoutLapRow: Decodable, Identifiable {
    var id: Int { lap_index ?? 0 }
    var lap_index: Int?
    var distance_meters: Double?
    var moving_time_seconds: Int?
    var avg_pace_sec_per_mile: Double?
    var avg_heart_rate: Int?
    var is_rest: Bool?
    var temp_f: Double?
    var dew_point_f: Double?
    var heat_adjusted_pace_sec_per_mile: Double?
}

/// Pace zones (sec/mi) used for the dashed reference lines.
struct RepChartZones {
    var fiveK: Double?
    var tenK: Double?
    var threshold: Double?   // HMP / LT
    var mp: Double?          // marathon pace (sec/mi) — anchors the recovery-grey threshold
    static let none = RepChartZones(fiveK: nil, tenK: nil, threshold: nil, mp: nil)
}

/// What the workout *was* — surfaced on every screen that renders the chart.
/// `pattern` is the parsed-structure headline ("6×1600m @ threshold");
/// `notes` is the athlete/coach free text carrying recoveries and paces.
struct WorkoutPrescription {
    var notes: String?
    var pattern: String?
    var hasContent: Bool {
        (notes?.isEmpty == false) || (pattern?.isEmpty == false)
    }
}

/// One past same-type session reduced to its average WORK-rep pace (and HR),
/// for the Rep Receipt's "vs recent" comparison strip. Built from
/// `parsed_structure.blocks` so it's the same quantity the receipt's
/// "AVG WORK" stat shows — apples-to-apples.
struct RecentSimilarWorkout: Identifiable {
    let id = UUID()
    var dateLabel: String   // "6/12"
    var avgPaceSec: Double  // sec/mi, mean of non-recovery blocks
    var avgHR: Int?
}

enum WorkoutLapsService {
    /// The athlete's observed max heart rate — the highest per-lap max HR across
    /// all their recorded laps. Used as the stable ceiling for HR-zone scaling so
    /// a single sub-maximal workout doesn't compress the zones into Z5. Real data
    /// only (no hardcoded max); nil when no lap HR exists. `gte 1` drops nulls so
    /// the DESC order returns a genuine max, not a NULL row.
    static func fetchObservedMaxHR(userId: String) async -> Int? {
        struct Row: Decodable { let max_heart_rate: Int? }
        do {
            let rows: [Row] = try await supabase
                .from("running_workout_laps")
                .select("max_heart_rate")
                .eq("user_id", value: userId.lowercased())
                .gte("max_heart_rate", value: 1)
                .order("max_heart_rate", ascending: false)
                .limit(1)
                .execute().value
            return rows.first?.max_heart_rate
        } catch {
            Log.coach.error("WorkoutLapsService.fetchObservedMaxHR failed: \(error)")
            return nil
        }
    }

    static func fetchLaps(workoutId: UUID) async -> [WorkoutLapRow] {
        do {
            return try await supabase
                .from("running_workout_laps")
                .select("lap_index,distance_meters,moving_time_seconds,avg_pace_sec_per_mile,avg_heart_rate,is_rest,temp_f,dew_point_f,heat_adjusted_pace_sec_per_mile")
                .eq("workout_id", value: workoutId.uuidString)
                .order("lap_index", ascending: true)
                .execute().value
        } catch {
            Log.coach.error("WorkoutLapsService.fetchLaps failed: \(error)")
            return []
        }
    }

    /// Build clean rep geometry from the raw `running_workout_laps` table, which
    /// already carries GPS-measured distance/time/pace per bout. Consecutive work
    /// laps with no rest between them are ONE rep — e.g. a 1200m that the watch
    /// auto-split at 1000m (a 1000m lap + a 204m lap) becomes a single 1204m rep.
    /// Rest laps pass through between reps so the recovery/slot logic still works.
    /// Deterministic and trustworthy, unlike the LLM `parse_structure`, which can
    /// bleed recovery into work reps and corrupt the distances and paces.
    static func mergeWorkBouts(_ raw: [WorkoutLapRow]) -> [WorkoutLapRow] {
        let ordered = raw.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) }
        var out: [WorkoutLapRow] = []
        var i = 0
        var idx = 0
        while i < ordered.count {
            if ordered[i].is_rest == true {
                var rest = ordered[i]; rest.lap_index = idx
                out.append(rest); idx += 1; i += 1
                continue
            }
            var dist = 0.0, time = 0.0, hrWeighted = 0.0, hrTime = 0.0
            var temp: Double? = nil, dew: Double? = nil
            var j = i
            while j < ordered.count, ordered[j].is_rest != true {
                let w = ordered[j]
                let d = w.distance_meters ?? 0
                let t = Double(w.moving_time_seconds ?? 0)
                dist += d; time += t
                if let hr = w.avg_heart_rate { hrWeighted += Double(hr) * max(t, 1); hrTime += max(t, 1) }
                if let tf = w.temp_f { temp = max(temp ?? tf, tf) }
                if let df = w.dew_point_f { dew = max(dew ?? df, df) }
                j += 1
            }
            let miles = dist / 1609.344
            out.append(WorkoutLapRow(
                lap_index: idx,
                distance_meters: dist > 0 ? dist : nil,
                moving_time_seconds: time > 0 ? Int(time) : nil,
                avg_pace_sec_per_mile: miles > 0 ? time / miles : nil,
                avg_heart_rate: hrTime > 0 ? Int((hrWeighted / hrTime).rounded()) : nil,
                is_rest: false,
                temp_f: temp,
                dew_point_f: dew,
                heat_adjusted_pace_sec_per_mile: nil
            ))
            idx += 1
            i = j
        }
        return out
    }

    /// True when the raw watch laps are uniform distance auto-laps — a
    /// continuous run lapped every km/mile, with at most the occasional pause.
    /// These are the athlete's OWN recorded splits and must be shown as-is: a
    /// steady / long run must never be merged or LLM-parsed into fake "reps".
    ///
    /// Distinguished from an interval session (where short work laps alternate
    /// with a recovery after nearly every rep) by requiring the rest / pause
    /// laps to be SPARSE relative to the work laps. A 24 km run auto-lapped
    /// every km with two water-break pauses is continuous; 6×1k with a jog
    /// after each rep is not.
    static func isContinuousAutoLap(_ raw: [WorkoutLapRow]) -> Bool {
        let ordered = raw.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) }
        let work = ordered.filter {
            $0.is_rest != true
            && ($0.distance_meters ?? 0) >= 150
            && ($0.moving_time_seconds ?? 0) >= 20
        }
        // Need enough splits to be a "run", not a short quality session.
        guard work.count >= 5 else { return false }
        // Pauses are rare in a continuous run; interval recoveries land after
        // nearly every rep. Cap rests well below one-per-rep.
        let rests = ordered.filter {
            $0.is_rest == true || ($0.distance_meters ?? 0) < 150
        }
        guard rests.count <= max(2, work.count / 6) else { return false }
        // Laps must be a uniform length near 1 km or 1 mile (a real auto-lap
        // cadence), with ≥70% of them within 20% of that median length.
        let dists = work.compactMap { $0.distance_meters }.sorted()
        guard !dists.isEmpty else { return false }
        let median = dists[dists.count / 2]
        let nearKm = abs(median - 1000) < 120
        let nearMi = abs(median - 1609.344) < 200
        guard nearKm || nearMi else { return false }
        let regular = work.filter { abs(($0.distance_meters ?? 0) - median) < median * 0.2 }
        return Double(regular.count) >= Double(work.count) * 0.7
    }

    /// Result of reading the recovery-segmented execution from parse-workout-structure.
    struct ParsedReps {
        var laps: [WorkoutLapRow]   // work_rep + recovery blocks, mapped to lap rows
        var intentPattern: String?  // "2k + 2×1k, repeated twice" — what was actually run
        var edited: Bool = false    // athlete hand-corrected the structure → authoritative
    }

    /// Reps from `parsed_structure.blocks` — the recovery-segmented EXECUTION
    /// (continuous efforts already merged: a 2k is ONE rep, not two 1ks). This is
    /// the true rep structure and must win over raw `running_workout_laps`, which
    /// lap every mile/km and re-split a continuous rep. Returns empty laps when
    /// there's no parsed structure (caller falls back to the lap table).
    static func fetchParsedReps(workoutId: UUID) async -> ParsedReps {
        struct Block: Decodable {
            var role: String?
            var rep_num: Int?
            var distance_miles: Double?
            var duration_s: Double?
            var avg_pace_per_mile: String?
            var avg_hr: Int?
        }
        struct Parsed: Decodable { var intent_pattern: String?; var blocks: [Block]?; var edited_by_user: Bool? }
        struct Row: Decodable { var parsed_structure: Parsed? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("parsed_structure")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            let parsed = rows.first?.parsed_structure
            guard let blocks = parsed?.blocks, !blocks.isEmpty else {
                return ParsedReps(laps: [], intentPattern: parsed?.intent_pattern, edited: parsed?.edited_by_user == true)
            }
            var out: [WorkoutLapRow] = []
            for (i, b) in blocks.enumerated() {
                let role = (b.role ?? "").lowercased()
                let meters = (b.distance_miles ?? 0) * 1609.344
                let paceSec: Double? = {
                    guard let p = b.avg_pace_per_mile else { return nil }
                    let parts = p.split(separator: ":")
                    guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
                    return Double(m * 60 + s)
                }()
                out.append(WorkoutLapRow(
                    lap_index: i,
                    distance_meters: meters > 0 ? meters : nil,
                    moving_time_seconds: b.duration_s.map { Int($0) },
                    avg_pace_sec_per_mile: paceSec,
                    avg_heart_rate: b.avg_hr,
                    is_rest: role == "recovery",
                    temp_f: nil,
                    dew_point_f: nil,
                    heat_adjusted_pace_sec_per_mile: nil
                ))
            }
            return ParsedReps(laps: out, intentPattern: parsed?.intent_pattern, edited: parsed?.edited_by_user == true)
        } catch {
            Log.coach.error("WorkoutLapsService.fetchParsedReps failed: \(error)")
            return ParsedReps(laps: [], intentPattern: nil)
        }
    }

    /// One-shot detail read: parsed reps, prescription (notes + pattern),
    /// coach insight and workout type in a SINGLE `training_logs` round-trip.
    ///
    /// Replaces five separate single-column reads of the SAME row that the
    /// detail/receipt screens used to fire in parallel — `parsed_structure`
    /// (twice), `coach_insight`, `workout_notes`, `workout_type`. Same data,
    /// one request, far less network churn on a phone. The individual fetch*
    /// methods are kept for other callers; this just collapses the hot path.
    struct DetailBundle {
        var parsedReps: ParsedReps
        var insight: String?
        var workoutType: String?
        var prescription: WorkoutPrescription
        var edited: Bool = false   // athlete hand-corrected the structure
    }

    static func fetchDetailBundle(workoutId: UUID) async -> DetailBundle {
        struct Block: Decodable {
            var role: String?
            var rep_num: Int?
            var distance_miles: Double?
            var duration_s: Double?
            var avg_pace_per_mile: String?
            var avg_hr: Int?
        }
        struct Parsed: Decodable {
            var intent_pattern: String?
            var pattern: String?
            var blocks: [Block]?
            var edited_by_user: Bool?
        }
        struct Row: Decodable {
            var parsed_structure: Parsed?
            var coach_insight: String?
            var workout_notes: String?
            var workout_type: String?
        }
        let empty = DetailBundle(
            parsedReps: ParsedReps(laps: [], intentPattern: nil),
            insight: nil, workoutType: nil,
            prescription: WorkoutPrescription(notes: nil, pattern: nil)
        )
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("parsed_structure,coach_insight,workout_notes,workout_type")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            guard let row = rows.first else { return empty }
            let parsed = row.parsed_structure

            // Reps from parsed_structure.blocks — mirrors fetchParsedReps exactly.
            var lapsOut: [WorkoutLapRow] = []
            if let blocks = parsed?.blocks {
                for (i, b) in blocks.enumerated() {
                    let role = (b.role ?? "").lowercased()
                    let meters = (b.distance_miles ?? 0) * 1609.344
                    let paceSec: Double? = {
                        guard let p = b.avg_pace_per_mile else { return nil }
                        let parts = p.split(separator: ":")
                        guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
                        return Double(m * 60 + s)
                    }()
                    lapsOut.append(WorkoutLapRow(
                        lap_index: i,
                        distance_meters: meters > 0 ? meters : nil,
                        moving_time_seconds: b.duration_s.map { Int($0) },
                        avg_pace_sec_per_mile: paceSec,
                        avg_heart_rate: b.avg_hr,
                        is_rest: role == "recovery",
                        temp_f: nil,
                        dew_point_f: nil,
                        heat_adjusted_pace_sec_per_mile: nil
                    ))
                }
            }
            let parsedReps = ParsedReps(laps: lapsOut, intentPattern: parsed?.intent_pattern)

            // Prescription pattern: the parsed intent wins over the structure
            // pattern (matches the old fetchPrescription + .task override).
            let intent = parsed?.intent_pattern
            let patternRaw = (intent?.isEmpty == false) ? intent : parsed?.pattern
            let prescription = WorkoutPrescription(
                notes: row.workout_notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                pattern: patternRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            return DetailBundle(
                parsedReps: parsedReps,
                insight: row.coach_insight,
                workoutType: row.workout_type,
                prescription: prescription,
                edited: parsed?.edited_by_user == true
            )
        } catch {
            Log.coach.error("WorkoutLapsService.fetchDetailBundle failed: \(error)")
            return empty
        }
    }

    /// The run's identity + qualitative signal, for the detail screen's Act 1
    /// (date / source line) and Act 2 (mood + the athlete's own words).
    /// Everything is optional: a voice-logged run has no laps but still has a
    /// date, a mood and a quote, and the screen must still compose.
    struct WorkoutSummary {
        var date: Date?
        var source: String?          // raw column: "strava" | "healthkit" | "manual" | …
        var mood: String?            // closed vocabulary — see MoodBadge
        var quote: String?           // the athlete's own words, verbatim
        var distanceMi: Double?      // logged distance — the fallback when there are no laps
        var durationMin: Double?
        /// Run-level weather from `training_logs.weather_actual`. Fallback for
        /// the HEAT-ADJ toggle when the per-lap rows carry no temp/dew — e.g. a
        /// run enriched by open-meteo-backfill, which writes only the run
        /// summary, not per-lap `running_workout_laps.temp_f/dew_point_f`.
        var weatherTempF: Double?
        var weatherDewF: Double?

        /// Display name for the italic source line. Unknown sources render as
        /// themselves rather than a guess.
        var sourceLabel: String? {
            guard let s = source?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            switch s.lowercased() {
            case "strava":            return "Strava"
            case "healthkit", "apple": return "HealthKit"
            case "manual":            return "Manual"
            case "voice", "voice_log": return "Voice"
            case "garmin":            return "Garmin"
            default:                  return s.capitalized
            }
        }
    }

    static func fetchSummary(workoutId: UUID) async -> WorkoutSummary {
        // `workout_date` is decoded as a STRING, not a Date. The Supabase Swift
        // SDK's `.value` decoder only parses ISO-8601 timestamps and throws on a
        // bare DATE column — and a throw here would cost us the whole row (mood,
        // quote, source), not just the date. Parse it ourselves instead.
        struct WeatherActual: Decodable { var temp_f: Double?; var dew_point_f: Double? }
        struct Row: Decodable {
            var workout_date: String?
            var source: String?
            var mood: String?
            var cleaned_notes: String?
            var notes: String?
            var workout_distance_miles: Double?
            var workout_duration_minutes: Double?
            var weather_actual: WeatherActual?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("workout_date,source,mood,cleaned_notes,notes,workout_distance_miles,workout_duration_minutes,weather_actual")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            guard let r = rows.first else { return WorkoutSummary() }
            // Cleaned notes win over the raw transcript, but both are the
            // athlete's own words — we never paraphrase them.
            let quote = [r.cleaned_notes, r.notes]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return WorkoutSummary(
                date: parseWorkoutDate(r.workout_date),
                source: r.source,
                mood: r.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
                quote: quote,
                distanceMi: r.workout_distance_miles,
                durationMin: r.workout_duration_minutes,
                weatherTempF: r.weather_actual?.temp_f,
                weatherDewF: r.weather_actual?.dew_point_f
            )
        } catch {
            Log.coach.error("WorkoutLapsService.fetchSummary failed: \(error)")
            return WorkoutSummary()
        }
    }

    /// Tolerant date parse — the column has been both a timestamptz and a bare
    /// DATE across migrations, so accept either rather than losing the header.
    private static func parseWorkoutDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(raw.prefix(10)))
    }

    static func fetchInsight(workoutId: UUID) async -> String? {
        struct Row: Decodable { var coach_insight: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("coach_insight")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            return rows.first?.coach_insight
        } catch { return nil }
    }

    /// The prescribed-workout context the athlete cares about on every screen:
    /// what the session was (parsed structure headline), plus the free-text
    /// `workout_notes` that carry recoveries and target paces. Two tolerant
    /// reads — a `parsed_structure` schema mismatch never costs us the notes.
    static func fetchPrescription(workoutId: UUID) async -> WorkoutPrescription {
        var notes: String?
        var pattern: String?
        struct NotesRow: Decodable { var workout_notes: String? }
        struct ParsedRow: Decodable { var parsed_structure: ParsedStructure? }
        do {
            let rows: [NotesRow] = try await supabase
                .from("training_logs").select("workout_notes")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            notes = rows.first?.workout_notes
        } catch { Log.coach.error("fetchPrescription notes failed: \(error)") }
        do {
            let rows: [ParsedRow] = try await supabase
                .from("training_logs").select("parsed_structure")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            pattern = rows.first?.parsed_structure?.pattern
        } catch { /* parsed_structure is optional — ignore decode misses */ }
        return WorkoutPrescription(
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines),
            pattern: pattern?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func fetchType(workoutId: UUID) async -> String? {
        struct Row: Decodable { var workout_type: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("workout_type")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            return rows.first?.workout_type
        } catch { return nil }
    }

    /// Manual override of the detected workout type. compute-workout-features
    /// only fills workout_type when it's null, so a manual value persists.
    static func setType(workoutId: UUID, type: String) async {
        do {
            try await supabase
                .from("training_logs")
                .update(["workout_type": type])
                .eq("id", value: workoutId.uuidString)
                .execute()
        } catch {
            Log.coach.error("WorkoutLapsService.setType failed: \(error)")
        }
    }

    static func fetchZones() async -> RepChartZones {
        struct Row: Decodable { var pace_zones: [String: Double]? }
        do {
            let rows: [Row] = try await supabase
                .from("athlete_state").select("pace_zones").limit(1).execute().value
            let z = rows.first?.pace_zones
            return RepChartZones(fiveK: z?["fiveK"], tenK: z?["tenK"], threshold: z?["hm"], mp: z?["mp"])
        } catch {
            return .none
        }
    }

    /// Recent completed sessions of the same `workout_type`, each reduced to its
    /// average WORK-rep pace (mean of non-recovery `parsed_structure` blocks) —
    /// the same quantity the receipt's "AVG WORK" stat shows, so the comparison
    /// strip is apples-to-apples. Rows with no parsed structure (no computable
    /// work pace) are skipped. Returned oldest→newest for left-to-right plotting.
    static func fetchRecentSimilar(type: String, excluding currentId: UUID, limit: Int = 6) async -> [RecentSimilarWorkout] {
        struct Block: Decodable { var role: String?; var avg_pace_per_mile: String?; var avg_hr: Int? }
        struct Parsed: Decodable { var blocks: [Block]? }
        struct Row: Decodable { var workout_date: String?; var parsed_structure: Parsed? }
        func paceSec(_ s: String?) -> Double? {
            guard let s else { return nil }
            let parts = s.split(separator: ":")
            guard parts.count == 2, let m = Int(parts[0]), let sec = Int(parts[1]) else { return nil }
            return Double(m * 60 + sec)
        }
        let skip: Set<String> = ["recovery", "warmup", "warm_up", "cooldown", "cool_down", "rest"]
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("workout_date,parsed_structure")
                .eq("workout_type", value: type)
                .neq("id", value: currentId.uuidString)
                .order("workout_date", ascending: false)
                .limit(24)
                .execute().value
            var out: [RecentSimilarWorkout] = []
            for r in rows {
                guard let blocks = r.parsed_structure?.blocks else { continue }
                let work = blocks.filter { !skip.contains(($0.role ?? "").lowercased()) }
                let paces = work.compactMap { paceSec($0.avg_pace_per_mile) }
                guard !paces.isEmpty else { continue }
                let hrs = work.compactMap { $0.avg_hr }
                out.append(RecentSimilarWorkout(
                    dateLabel: shortDate(r.workout_date),
                    avgPaceSec: paces.reduce(0, +) / Double(paces.count),
                    avgHR: hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count
                ))
                if out.count >= limit { break }
            }
            return out.reversed()   // oldest → newest
        } catch {
            Log.coach.error("WorkoutLapsService.fetchRecentSimilar failed: \(error)")
            return []
        }
    }

    private static func shortDate(_ raw: String?) -> String {
        guard let raw else { return "" }
        let iso = String(raw.prefix(10))   // "2026-06-12"
        let comps = iso.split(separator: "-")
        if comps.count == 3, let mo = Int(comps[1]), let d = Int(comps[2]) { return "\(mo)/\(d)" }
        return iso
    }
}

// MARK: - View

struct WorkoutRepChart: View {
    let workoutId: UUID?
    private let injectedLaps: [WorkoutLapRow]?
    private let injectedZones: RepChartZones?

    init(workoutId: UUID) {
        self.workoutId = workoutId
        self.injectedLaps = nil
        self.injectedZones = nil
    }
    /// Preview / test seam.
    init(laps: [WorkoutLapRow], zones: RepChartZones) {
        self.workoutId = nil
        self.injectedLaps = laps
        self.injectedZones = zones
    }

    @State private var laps: [WorkoutLapRow] = []
    @State private var zones: RepChartZones = .none
    @State private var loaded = false
    @State private var heatOn = false
    @State private var insight: String?
    @State private var workoutType: String?
    @State private var showTypePicker = false
    @State private var prescription: WorkoutPrescription?
    @State private var parsedIntent: String?
    @State private var insightLoading = false
    @State private var insightError: String?
    @State private var structureEdited = false
    @State private var showStructureEditor = false

    private let metersPerMile = 1609.344
    static let typeOptions = ["intervals", "threshold", "tempo", "fartlek", "progression", "easy", "long_run", "recovery", "race"]

    // Work reps = non-rest laps faster than ~steady and long enough to be a rep.
    private var reps: [WorkoutLapRow] {
        laps.filter { lap in
            guard lap.is_rest != true,
                  let p = lap.avg_pace_sec_per_mile, p > 0,
                  let d = lap.distance_meters, d >= 150,
                  let s = lap.moving_time_seconds, s >= 20 else { return false }
            // faster than ~6:10/mi (steady-ish) counts as work
            return p <= 370
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loaded && reps.isEmpty {
                emptyState
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                headerStats
                prescriptionCard
                analysisCard
                chartPanel
                splitsCard
                heatChip
            }
        }
        .task {
            if let injectedLaps {
                laps = injectedLaps; zones = injectedZones ?? .none; loaded = true; return
            }
            await reload()
        }
        .sheet(isPresented: $showStructureEditor) {
            if let workoutId {
                EditWorkoutStructureSheet(
                    workoutId: workoutId,
                    initialLaps: laps,
                    initialIntent: parsedIntent ?? prescription?.pattern,
                    onSaved: { Task { await reload() } }
                )
            }
        }
    }

    /// Load the workout's reps + zones + detail. Re-run after a structure
    /// correction so the chart reflects the athlete's fix immediately.
    @MainActor
    private func reload() async {
        guard let workoutId else { loaded = true; return }
        // Three parallel reads, each hitting a DIFFERENT table: laps
        // (running_workout_laps), zones (athlete_state), and one combined
        // training_logs read that returns parsed reps + insight + type +
        // prescription in a single round-trip — was five separate reads of
        // the same row.
        async let l = WorkoutLapsService.fetchLaps(workoutId: workoutId)
        async let z = WorkoutLapsService.fetchZones()
        async let bundle = WorkoutLapsService.fetchDetailBundle(workoutId: workoutId)
        let lapRows = await l
        let detail = await bundle
        let parsed = detail.parsedReps
        // Prefer the recovery-segmented execution (continuous 2ks merged into
        // one rep) over raw mile/km laps, which would re-split it into 8×1k.
        let parsedWorkCount = parsed.laps.filter { $0.is_rest != true }.count
        laps = parsedWorkCount >= 2 ? parsed.laps : lapRows
        parsedIntent = parsed.intentPattern
        zones = await z
        insight = detail.insight
        workoutType = detail.workoutType
        prescription = detail.prescription
        structureEdited = detail.edited
        loaded = true
    }

    // MARK: Header + stats

    private var headerStats: some View {
        let paces = reps.compactMap { $0.avg_pace_sec_per_mile }
        let hrs = reps.compactMap { $0.avg_heart_rate }
        let avgPace = paces.isEmpty ? 0 : paces.reduce(0, +) / Double(paces.count)
        let workMi = reps.compactMap { $0.distance_meters }.reduce(0, +) / metersPerMile
        let spread = (paces.max() ?? 0) - (paces.min() ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Button { showTypePicker = true } label: {
                HStack(spacing: 6) {
                    Text((workoutType.map(prettyType) ?? zoneTag(avgPace)).uppercased())
                        .font(.dripStat(10)).tracking(1.3)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.drip.coral)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.drip.coralWash)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .confirmationDialog("Change workout type", isPresented: $showTypePicker, titleVisibility: .visible) {
                ForEach(Self.typeOptions, id: \.self) { t in
                    Button(prettyType(t)) { updateType(t) }
                }
                Button("Cancel", role: .cancel) {}
            }
            Text(repHeadline)
                .font(.dripDisplay(24))
                .foregroundStyle(Color.drip.textPrimary)
            HStack(spacing: 18) {
                stat("AVG WORK", fmt(avgPace) + "/mi")
                stat("WORK", String(format: "%.1f mi", workMi))
                if let hi = hrs.max() { stat("HR", "\(avg(hrs)) · \(hi) max") }
                stat("SPREAD", "\(Int(spread))s")
            }
        }
    }

    /// Manual workout-type override — updates immediately on screen and persists.
    private func updateType(_ t: String) {
        workoutType = t
        guard let workoutId else { return }
        Task { await WorkoutLapsService.setType(workoutId: workoutId, type: t) }
    }

    private func prettyType(_ t: String) -> String {
        switch t {
        case "long_run": return "Long run"
        case "intervals", "interval": return "Intervals"
        default: return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.dripStat(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
            Text(v).font(.dripStat(13)).foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: Prescription / notes

    // What the workout was — the parsed-structure headline plus the free-text
    // workout notes (recoveries, target paces). Hidden when neither exists so
    // we never show an empty card. Lives inside the chart so it travels to
    // every surface that renders WorkoutRepChart (detail sheet, Coach Read,
    // Trends), per "workout notes should live on every screen."
    @ViewBuilder
    private var prescriptionCard: some View {
        if let p = prescription, p.hasContent {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE WORKOUT")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
                if let pattern = p.pattern, !pattern.isEmpty {
                    Text(pattern)
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notes = p.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.dripBody(14)).lineSpacing(2)
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
        }
    }

    // MARK: Chart

    /// True when a substantial AI insight is already stored.
    private var hasAIInsight: Bool {
        (insight?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) >= 40
    }

    // AI analysis of the session — generated on demand by a button so it runs
    // AFTER the voice memo + parsed workout exist and can reason over the full
    // picture (notes, structure, splits, HR, training context). Until the
    // athlete taps Generate, we show a deterministic computed read as a preview.
    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ANALYSIS")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
                Spacer()
            }

            if insightLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.drip.coral)
                    Text("Analyzing your workout…")
                        .font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
                }
            } else if hasAIInsight {
                Text(insight!.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.dripBody(15)).lineSpacing(3)
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(computedRead)
                    .font(.dripBody(14)).lineSpacing(3)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if workoutId != nil {
                    Button { Task { await generateInsight() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                            Text("Generate AI insight").font(.dripLabel(13))
                        }
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.drip.coralWash)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            if let err = insightError {
                Text(err)
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.struggling)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    /// Call the on-demand insight generator. Fires once per workout — the
    /// server returns the existing insight if one was already generated.
    /// Rate-limited + monthly-capped server-side.
    @MainActor
    private func generateInsight() async {
        guard let workoutId else { return }
        insightLoading = true
        insightError = nil
        struct Req: Encodable { let training_log_id: String }
        struct Resp: Decodable { let insight: String?; let error: String? }
        do {
            let resp: Resp = try await supabase.functions.invoke(
                "generate-workout-insight",
                options: .init(body: Req(training_log_id: workoutId.uuidString))
            )
            let text = resp.insight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                insight = text
            } else {
                insightError = resp.error ?? "Couldn't generate insight. Try again."
            }
        } catch {
            insightError = "Couldn't reach the coach. Try again."
            Log.coach.error("generateInsight failed: \(error)")
        }
        insightLoading = false
    }

    private var computedRead: String {
        let n = reps.count
        let dist = repDistanceLabel()
        let avg = repPacesArr.isEmpty ? "—" : fmt(repPacesArr.reduce(0, +) / Double(repPacesArr.count))
        let zone = workoutType.map { prettyType($0).lowercased() }
            ?? (repPacesArr.isEmpty ? "quality" : zoneTag(repPacesArr.reduce(0, +) / Double(repPacesArr.count)))
        let shapeRead: String
        switch shapeString {
        case "negative": shapeRead = "and you got stronger through the set"
        case "faded":    shapeRead = "but drifted slower over the reps"
        default:         shapeRead = "and held it even"
        }
        var drift = ""
        if let f = repHRArr.first, let l = repHRArr.last, f > 0 {
            let pct = Double(l - f) / Double(f) * 100
            if pct >= 6 { drift = " HR climbed \(Int(pct))% across the reps — normal fatigue for the effort." }
            else if pct >= 0 { drift = " HR held steady, a sign you stayed in control." }
        }
        return "\(n)×\(dist) at \(avg)/mi (\(zone)) \(shapeRead).\(drift)"
    }

    // Per-rep splits + durability — the deeper analysis under the chart.
    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SPLITS")
                .font(.dripStat(10)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 12)
            HStack(spacing: 18) {
                stat("FADE", fadeString)
                stat("HR DRIFT", driftString)
                stat("SHAPE", shapeString)
            }
            .padding(.bottom, 10)
            ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                HStack {
                    Text("REP \(i + 1)")
                        .font(.dripStat(11)).foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    if let p = rep.avg_pace_sec_per_mile {
                        Text(fmt(p) + "/mi")
                            .font(.dripBody(14)).foregroundStyle(Color.drip.textPrimary)
                    }
                    if let hr = rep.avg_heart_rate {
                        Text("\(hr) bpm")
                            .font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                .padding(.vertical, 9)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var repPacesArr: [Double] { reps.compactMap { $0.avg_pace_sec_per_mile } }
    private var repHRArr: [Int] { reps.compactMap { $0.avg_heart_rate } }
    private var fadeString: String {
        guard let f = repPacesArr.first, let l = repPacesArr.last, f > 0 else { return "—" }
        return String(format: "%+.0f%%", (l - f) / f * 100)
    }
    private var driftString: String {
        guard let f = repHRArr.first, let l = repHRArr.last, f > 0 else { return "—" }
        return String(format: "%+.0f%%", Double(l - f) / Double(f) * 100)
    }
    private var shapeString: String {
        guard let f = repPacesArr.first, let l = repPacesArr.last, f > 0 else { return "even" }
        let pct = (l - f) / f * 100
        if pct < -1.5 { return "negative" }
        if pct > 1.5 { return "faded" }
        return "even"
    }

    // Chart wrapped in a panel card to match workout-detail-viz.html.
    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("REP-BY-REP")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                if structureEdited {
                    Text("EDITED")
                        .font(.dripStat(8)).tracking(1.0)
                        .foregroundStyle(Color.drip.coral)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.drip.coralWash)
                        .clipShape(Capsule())
                }
                Spacer()
                if workoutId != nil {
                    Button { showStructureEditor = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold))
                            Text(structureEdited ? "Edit" : "Fix reps").font(.dripLabel(12))
                        }
                        .foregroundStyle(Color.drip.coral)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Each bar is a rep — taller = faster. Line = HR. Dashed lines are your pace zones.")
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chart
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padTop: CGFloat = 16, padBottom: CGFloat = 20
            let plotH = h - padTop - padBottom
            let n = max(reps.count, 1)
            let slot = w / CGFloat(n)
            let barW = slot * 0.5

            // pace scale (faster = top). Pad the rep range a touch.
            let paces = reps.compactMap { $0.avg_pace_sec_per_mile }
            let pMin = (paces.min() ?? 300) - 6
            let pMax = (paces.max() ?? 320) + 6
            let yPace: (Double) -> CGFloat = { p in
                padTop + CGFloat((p - pMin) / max(pMax - pMin, 1)) * plotH
            }
            // HR scale on upper band
            let hrs = reps.compactMap { $0.avg_heart_rate }.map(Double.init)
            let hMin = (hrs.min() ?? 140) - 4
            let hMax = (hrs.max() ?? 175) + 4
            let yHR: (Double) -> CGFloat = { v in
                padTop + (1 - CGFloat((v - hMin) / max(hMax - hMin, 1))) * plotH
            }
            let xC: (Int) -> CGFloat = { i in slot * CGFloat(i) + slot / 2 }

            ZStack(alignment: .topLeading) {
                // zone reference lines
                ForEach(Array(zoneLines().enumerated()), id: \.offset) { _, line in
                    let name = line.0, pace = line.1, color = line.2
                    let y = yPace(pace)
                    if y >= padTop && y <= padTop + plotH {
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w - 30, y: y)) }
                            .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        Text(name).font(.dripStat(8)).foregroundStyle(color)
                            .position(x: w - 16, y: y)
                    }
                }
                // bars + labels
                ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                    if let p = rep.avg_pace_sec_per_mile {
                        let y = yPace(p)
                        let barH = padTop + plotH - y
                        Rectangle().fill(Color.drip.coral)
                            .frame(width: barW, height: max(barH, 1))
                            .position(x: xC(i), y: y + barH / 2)
                        Text(fmt(p)).font(.dripStat(8)).foregroundStyle(Color.drip.textPrimary)
                            .position(x: xC(i), y: y - 8)
                        // cool-air equivalent marker when heat toggle on
                        if heatOn, let adj = adjustedPace(rep) {
                            let ya = yPace(adj)
                            Path { pa in pa.move(to: CGPoint(x: xC(i) - barW/2, y: ya)); pa.addLine(to: CGPoint(x: xC(i) + barW/2, y: ya)) }
                                .stroke(Color.drip.coralLight, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        }
                        Text("\(i + 1)").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                            .position(x: xC(i), y: padTop + plotH + 10)
                    }
                }
                // HR polyline + dots
                if hrs.count >= 2 {
                    Path { path in
                        for (i, rep) in reps.enumerated() {
                            guard let hr = rep.avg_heart_rate else { continue }
                            let pt = CGPoint(x: xC(i), y: yHR(Double(hr)))
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.drip.textSecondary, lineWidth: 1.5)
                    ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                        if let hr = rep.avg_heart_rate {
                            Circle().fill(Color.drip.textSecondary).frame(width: 5, height: 5)
                                .position(x: xC(i), y: yHR(Double(hr)))
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Color.drip.coral, "rep pace")
            legendItem(Color.drip.textSecondary, "avg HR")
            Text("dashed = your 5K / 10K / threshold")
                .font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary)
        }
    }
    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(t).font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var heatChip: some View {
        let conds = heatConditions()
        return Group {
            if let c = conds {
                Button { withAnimation(.easeOut(duration: 0.2)) { heatOn.toggle() } } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Color.drip.tired).frame(width: 7, height: 7)
                        Text(heatOn
                             ? "Heat-adjusted — cool-air equivalent shown ‹"
                             : "Hot & humid — \(c). Tap for cool-air splits ›")
                            .font(.dripBody(12.5))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(heatOn ? Color.drip.coral : Color.drip.tired)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background((heatOn ? Color.drip.coral : Color.drip.tired).opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No rep-level splits for this run — it reads as a steady effort.")
                .font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
            if workoutId != nil {
                Button { showStructureEditor = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .semibold))
                        Text("This was a workout — fix the reps").font(.dripLabel(13))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.drip.coralWash)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: Helpers

    private func zoneLines() -> [(String, Double, Color)] {
        var out: [(String, Double, Color)] = []
        if let v = zones.fiveK { out.append(("5K \(fmt(v))", v, Color.drip.coral)) }
        if let v = zones.tenK { out.append(("10K \(fmt(v))", v, Color.drip.textTertiary)) }
        if let v = zones.threshold { out.append(("Thr \(fmt(v))", v, Color.drip.tired)) }
        return out
    }
    private func adjustedPace(_ lap: WorkoutLapRow) -> Double? {
        if let a = lap.heat_adjusted_pace_sec_per_mile, a > 0 { return a }
        return nil
    }
    private func heatConditions() -> String? {
        guard let t = reps.compactMap({ $0.temp_f }).max(),
              let d = reps.compactMap({ $0.dew_point_f }).max(),
              d >= PaceCalculator.heatDewPointFloorF else { return nil }
        return "\(Int(t))°F, \(Int(d))° dew"
    }
    private func label(forMeters m: Double) -> String {
        let miles = m / metersPerMile
        if abs(miles - miles.rounded()) / max(miles, 1) < 0.08 && miles >= 1 { return "\(Int(miles.rounded()))mi" }
        for r in [400.0, 600, 800, 1000, 1200, 1600, 2000, 3000] where abs(m - r) / r < 0.08 {
            return r.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(r/1000))K" : "\(Int(r))m"
        }
        return "\(Int((m/100).rounded()*100))m"
    }

    private func repDistanceLabel() -> String {
        guard let m = reps.compactMap({ $0.distance_meters }).first else { return "rep" }
        return label(forMeters: m)
    }

    /// True when the reps aren't all the same distance (e.g. a 2k then 1ks).
    private var isMixedReps: Bool {
        Set(reps.compactMap { $0.distance_meters }.map { label(forMeters: $0) }).count > 1
    }

    /// Headline: "8×1K" when uniform; a compact "2K·1K·1K·2K·1K·1K" when the
    /// session is mixed (so the real structure shows, not a false "6×2K").
    private var repHeadline: String {
        if reps.isEmpty { return "—" }
        if !isMixedReps { return "\(reps.count)×\(repDistanceLabel())" }
        let seq = reps.compactMap { $0.distance_meters }.map { label(forMeters: $0) }
        return seq.count <= 8 ? seq.joined(separator: "·") : "\(reps.count) reps"
    }
    private func zoneTag(_ p: Double) -> String {
        if let v = zones.fiveK, p <= v + 6 { return "5K pace" }
        if let v = zones.tenK, p <= v + 6 { return "10K pace" }
        if let v = zones.threshold, p <= v + 8 { return "threshold" }
        return "quality"
    }
    private func fmt(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t/60):\(String(format: "%02d", t%60))"
    }
    private func avg(_ xs: [Int]) -> Int { xs.isEmpty ? 0 : xs.reduce(0,+)/xs.count }
}

// MARK: - Preview (renders in Xcode canvas, no app run)

#Preview {
    // Real-shaped May 20 9×1K @ ~5:07 with rests, plus warmup/cooldown.
    func lap(_ i: Int, _ m: Double, _ s: Int, _ p: Double, _ hr: Int, _ rest: Bool = false, _ t: Double = 67, _ dew: Double = 67, _ adj: Double? = nil) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s,
                   avg_pace_sec_per_mile: p, avg_heart_rate: hr, is_rest: rest,
                   temp_f: t, dew_point_f: dew, heat_adjusted_pace_sec_per_mile: adj)
    }
    let laps: [WorkoutLapRow] = [
        lap(0, 1609, 480, 480, 132),                 // warmup
        lap(1, 1000, 307, 307, 162, false, 67, 67, 301),
        lap(2, 64, 63, 1579, 167, true),
        lap(3, 1000, 309, 309, 168, false, 67, 67, 303),
        lap(4, 60, 63, 1900, 158, true),
        lap(5, 1000, 306, 306, 166, false, 67, 67, 300),
        lap(6, 60, 63, 1900, 169, true),
        lap(7, 1000, 307, 307, 168, false, 67, 67, 301),
        lap(8, 60, 63, 1900, 170, true),
        lap(9, 1000, 309, 309, 169, false, 67, 67, 303),
        lap(10, 60, 63, 1900, 169, true),
        lap(11, 1000, 307, 307, 170, false, 67, 67, 301),
        lap(12, 60, 63, 1900, 169, true),
        lap(13, 1000, 309, 309, 169, false, 67, 67, 303),
        lap(14, 60, 63, 1900, 169, true),
        lap(15, 1000, 307, 307, 169, false, 67, 67, 301),
        lap(16, 60, 63, 1900, 168, true),
        lap(17, 1000, 306, 306, 166, false, 67, 67, 300),
        lap(18, 1200, 540, 540, 140),                // cooldown
    ]
    let zones = RepChartZones(fiveK: 302, tenK: 314, threshold: 328)
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("INTERVALS · MAY 20")
                .font(.dripStat(10)).tracking(1.4).foregroundStyle(Color.drip.coral)
            WorkoutRepChart(laps: laps, zones: zones)
        }
        .padding(20)
    }
    .background(Color.drip.background.ignoresSafeArea())
}
