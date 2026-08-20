import Foundation

// MARK: - Weather on a row
//
// `training_logs.weather_actual` is already written by `fetch-workout-weather`
// and is populated on 90 of the last 91 rows. It carries the temperature, the
// dew point, and — importantly — `adjustment_pct`, the heat penalty the backend
// already computed. Do NOT recompute it on the client: two heat models that
// disagree by a tenth of a percent is a bug report waiting to happen.
struct RunWeather: Codable, Equatable {
    let tempF: Double?
    let dewPointF: Double?
    let humidity: Double?
    /// Fractional pace penalty, e.g. 0.0472 for 4.72%. Server-computed.
    let adjustmentPct: Double?
    let heatCategory: String?
    let beyondChart: Bool?

    enum CodingKeys: String, CodingKey {
        case tempF = "temp_f"
        case dewPointF = "dew_point_f"
        case humidity
        case adjustmentPct = "adjustment_pct"
        case heatCategory = "heat_category"
        case beyondChart = "beyond_chart"
    }

    /// Ink tick glyphs, never a colour. Blue is pace, warm is mood, coral is
    /// alert — heat is a condition and gets none of the three.
    var loadTicks: String {
        switch heatCategory {
        case "ideal", nil:  return ""
        case "warm":        return "·"
        case "hot":         return "· ·"
        case "very_hot":    return "· · ·"
        case "dangerous":   return "· · · ·"
        default:            return ""
        }
    }
}

// MARK: - Session

/// One training session. Not a day and not an upload: five Strava files on
/// Aug 4 are two sessions, a track workout and an evening double.
struct ConditionsSession: Identifiable {
    let id: UUID
    let date: Date
    let rows: [TodayLogRow]

    let miles: Double
    let durationMinutes: Double
    /// Derived, never read from `workout_pace_per_mile` — that column is
    /// populated on ~12% of rows and must not be trusted as a display source.
    let paceSeconds: Double?

    let mood: String?
    let rpe: Int?
    /// The workout as the athlete described it into the voice memo. The only
    /// record of intent anywhere in the system: `scheduled_workouts` has no rows.
    let plannedWorkout: String?
    let hasAudio: Bool

    let weather: RunWeather?
    let splits: [PaceSegment]
    let fastSegments: [PaceSegment]
    let label: String

    var avgHeartRate: Int? {
        let hr = splits.compactMap(\.avgHeartRate)
        guard !hr.isEmpty else { return nil }
        return hr.reduce(0, +) / hr.count
    }

    var fastAvgHeartRate: Int? {
        let hr = fastSegments.compactMap(\.avgHeartRate)
        guard !hr.isEmpty else { return nil }
        return hr.reduce(0, +) / hr.count
    }

    var fastMiles: Double { fastSegments.reduce(0) { $0 + $1.distanceMiles } }

    /// Cool-weather equivalent. Shown beside the recorded pace, never instead
    /// of it, and never fed into training load.
    var adjustedPaceSeconds: Double? {
        guard let p = paceSeconds, let pct = weather?.adjustmentPct, pct > 0 else { return nil }
        return p / (1 + pct)
    }

    var heatCostSeconds: Int? {
        guard let p = paceSeconds, let a = adjustedPaceSeconds else { return nil }
        return Int((p - a).rounded())
    }

    /// A manual/treadmill upload has no GPS, so outdoor weather cannot be
    /// attributed to it. Attributing 78°/75° air to a treadmill run is not a
    /// rounding error, it is a wrong number.
    var isIndoor: Bool { weather == nil || weather?.tempF == nil }
}

// MARK: - Rollup

enum ConditionsRollup {

    /// A fast segment is anything held at or under the athlete's fast cut.
    /// Derived from the zone table when there is one; the fallback exists so
    /// a new athlete still sees something, and is deliberately conservative.
    static func fastCutSeconds(zones: PaceZonesEngine?) -> Double {
        if let lt = zones?.thresholdPace { return lt * 1.06 }
        return 375   // 6:15/mi
    }

    /// Group by LOCAL day, dedupe voice against GPS, then split the day into
    /// sessions on a 90-minute clock gap. The order matters: the dedupe has to
    /// be at day level because a voice memo and its run can be five hours apart.
    static func sessions(from rows: [TodayLogRow],
                         calendar: Calendar = .current,
                         fastCut: Double = 375) -> [ConditionsSession] {

        let deduped = rows.dedupedByPhysicalWorkout()
        let byDay = Dictionary(grouping: deduped) { calendar.startOfDay(for: $0.date) }

        var out: [ConditionsSession] = []
        for (_, dayRows) in byDay {
            let sorted = dayRows.sorted { $0.date < $1.date }
            var groups: [[TodayLogRow]] = []
            for row in sorted {
                if var last = groups.last, let prev = last.last {
                    let prevEnd = prev.date.addingTimeInterval((prev.durationMinutes ?? 0) * 60)
                    if row.date.timeIntervalSince(prevEnd) <= 90 * 60 {
                        last.append(row)
                        groups[groups.count - 1] = last
                        continue
                    }
                }
                groups.append([row])
            }
            out.append(contentsOf: groups.compactMap { make($0, fastCut: fastCut) })
        }
        return out.sorted { $0.date > $1.date }
    }

    private static func make(_ rows: [TodayLogRow], fastCut: Double) -> ConditionsSession? {
        guard let first = rows.first else { return nil }

        let miles = rows.compactMap(\.miles).reduce(0, +)
        let minutes = rows.compactMap(\.durationMinutes).reduce(0, +)
        let pace = derivedPaceSeconds(miles: miles, minutes: minutes)

        let splits = rows.flatMap { $0.paceSegments ?? [] }
        let fast = splits.filter {
            guard let s = paceSeconds(from: $0.pacePerMile) else { return false }
            return s <= fastCut && $0.durationSeconds >= 25 && $0.distanceMiles >= 0.09
        }

        // Walk every piece including warm-ups and cooldowns: on Aug 4 the memo
        // on the cooldown reads RPE 3 and the one on the session reads RPE 7.
        // Rank by RPE so the session's own memo leads.
        let lead = rows.max { ($0.feltRPE ?? 0) < ($1.feltRPE ?? 0) }

        return ConditionsSession(
            id: first.id,
            date: first.date,
            rows: rows,
            miles: miles,
            durationMinutes: minutes,
            paceSeconds: pace,
            mood: rows.compactMap(\.mood).first,
            rpe: lead?.feltRPE,
            plannedWorkout: rows.compactMap(\.workoutNotes)
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            hasAudio: rows.contains { $0.audioUrl != nil },
            weather: rows.compactMap(\.weather).first,
            splits: splits,
            fastSegments: fast,
            label: label(rows: rows, miles: miles, pace: pace, fastCount: fast.count)
        )
    }

    /// Pace in seconds per mile, derived. `workout_pace_per_mile` is populated
    /// on ~12% of rows and must not be trusted as a display source.
    static func derivedPaceSeconds(miles: Double?, minutes: Double?) -> Double? {
        guard let mi = miles, mi > 0.05, let min = minutes, min > 0 else { return nil }
        return min * 60 / mi
    }

    /// "5:19" -> 319. Returns nil rather than 0 on a malformed string.
    static func paceSeconds(from mmss: String?) -> Double? {
        guard let s = mmss else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return m * 60 + sec
    }

    /// Round the total seconds FIRST, then split. Flooring minutes and rounding
    /// the remainder separately prints "7:60" for anything in [59.5, 60).
    static func mmss(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s > 0 else { return "" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func label(rows: [TodayLogRow], miles: Double,
                              pace: Double?, fastCount: Int) -> String {
        // A 19:24/mi outing is a walk, not a steady run. Guard first, or a long
        // walk containing one fast span labels itself "Steady".
        if let p = pace, p > 11 * 60, fastCount < 3 { return "Walk" }
        if let stored = rows.compactMap(\.typeKey).first {
            let display = WorkoutLabel.display(stored)
            if display != "Run" { return display }
        }
        if miles >= 13 { return "Long run" }
        if fastCount >= 4 { return "Intervals" }
        if fastCount > 0 { return "Threshold" }
        return miles < 3 ? "Recovery" : "Easy"
    }
}

// MARK: - Weeks

struct ConditionsWeek: Identifiable {
    var id: Date { start }
    let start: Date
    let miles: Double
    let daysRun: Int
    let sessions: Int
    let quality: Int
    let fastMiles: Double
    let hours: Double
    /// A week the range cut in half. Rendered hatched, so a 6-mile bar beside a
    /// 77-mile bar does not read as a collapse in fitness.
    let isPartial: Bool

    static func build(_ sessions: [ConditionsSession],
                      calendar: Calendar = .current) -> [ConditionsWeek] {
        var cal = calendar
        cal.firstWeekday = 2   // Monday
        let grouped = Dictionary(grouping: sessions) { s -> Date in
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.date)) ?? s.date
        }
        return grouped.map { start, group in
            let days = Set(group.map { cal.startOfDay(for: $0.date) })
            return ConditionsWeek(
                start: start,
                miles: group.reduce(0) { $0 + $1.miles },
                daysRun: days.count,
                sessions: group.count,
                quality: group.filter { !$0.fastSegments.isEmpty }.count,
                fastMiles: group.reduce(0) { $0 + $1.fastMiles },
                hours: group.reduce(0) { $0 + $1.durationMinutes } / 60,
                isPartial: days.count < 5
            )
        }.sorted { $0.start > $1.start }
    }
}
