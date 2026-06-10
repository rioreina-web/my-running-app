//
//  TodayPlate18.swift
//  RunningLog
//
//  Plate 18 (Today · Diary + Charts) — data fetchers and view components.
//
//  See design/PLATE_18_DATA.md for the full data contract.
//
//  Sections:
//    1. Date heading + race countdown        (data: client-side + activePlan)
//    2. Today's mood prompt                  (degraded substitute via training_logs.mood)
//    3. Yesterday's journal entry            (data: TodayLastLog — already loaded)
//    4. Tomorrow's prescription              (data: TodayTomorrowWorkout — new fetch)
//    5. Fitness · 12-week trend chart        (data: TodayFitnessTrend — new fetch)
//    6. Zone shifts · week vs 4-week avg     (data: TodayZoneShifts — new fetch)
//    7. Race predictions · 5 distances       (data: TodayRacePredictions — new fetch)
//

import os
import Supabase
import SwiftUI

// MARK: - Data types

/// Tomorrow's scheduled workout, as the Today tab needs to display it.
struct TodayTomorrowWorkout {
    let date: Date
    let workoutType: String       // raw enum string from scheduled_workouts
    let totalDistanceMiles: Double?
    let structureLine: String?    // e.g. "2 mi WU · 5 mi at 7:00/mi · 1 mi CD"
    let notes: String?            // freeform notes if any

    var displayName: String { CoachIntent.displayName(for: workoutType) }
    var coachIntent: String? {
        // Empty-string notes from the DB shouldn't beat the static fallback —
        // `??` only swaps on nil, not on "". Trim and treat blank as absent.
        if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return CoachIntent.forType(workoutType)
    }
    var isRest: Bool { workoutType.lowercased() == "rest" }

    static func fetchTomorrow() async -> TodayTomorrowWorkout? {
        struct Row: Decodable {
            let id: String?
            let date: String
            let workout_type: String?
            let workout_data: WorkoutData?
            let notes: String?

            struct WorkoutData: Decodable {
                let total_distance_miles: Double?
                let totalDistanceMiles: Double?
                let summary: String?
            }
        }

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let dayAfter = cal.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        let tomorrowStr = f.string(from: tomorrow)
        let dayAfterStr = f.string(from: dayAfter)

        do {
            let rows: [Row] = try await supabase
                .from("scheduled_workouts")
                .select("id, date, workout_type, workout_data, notes")
                .gte("date", value: tomorrowStr)
                .lt("date", value: dayAfterStr)
                .order("date", ascending: true)
                .limit(1)
                .execute()
                .value
            guard let r = rows.first else { return nil }
            let parsedDate = f.date(from: r.date) ?? tomorrow
            let miles = r.workout_data?.total_distance_miles ?? r.workout_data?.totalDistanceMiles
            return TodayTomorrowWorkout(
                date: parsedDate,
                workoutType: r.workout_type ?? "easy",
                totalDistanceMiles: miles,
                structureLine: r.workout_data?.summary,
                notes: r.notes
            )
        } catch {
            Log.coach.error("TodayTomorrowWorkout fetch failed: \(error)")
            return nil
        }
    }
}

/// Twelve weekly samples of predicted marathon time + the current value
/// and a 12-week-ago value for the headline.
struct TodayFitnessTrend {
    let weeklySamples: [WeeklySample]   // oldest → newest, up to 12
    struct WeeklySample {
        let weekStart: Date
        let predictedMarathonSeconds: Int?
    }

    var latestSeconds: Int? { weeklySamples.last?.predictedMarathonSeconds }
    var twelveWeeksAgoSeconds: Int? { weeklySamples.first?.predictedMarathonSeconds }

    /// Negative = fitness improving (predicted time dropping).
    var deltaSeconds: Int? {
        guard let a = latestSeconds, let b = twelveWeeksAgoSeconds else { return nil }
        return a - b
    }

    static func fetch() async -> TodayFitnessTrend {
        struct Row: Decodable {
            let created_at: String
            let predicted_marathon_seconds: Int?
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -84, to: Date()) ?? Date()
        let cutoffStr = ISO8601DateFormatter().string(from: cutoffDate)

        do {
            let rows: [Row] = try await supabase
                .from("fitness_snapshots")
                .select("created_at, predicted_marathon_seconds")
                .gte("created_at", value: cutoffStr)
                .order("created_at", ascending: true)
                .execute()
                .value

            // Bucket by ISO week (Monday-first), take latest snapshot per week
            var byWeek: [Date: (Date, Int?)] = [:]
            for r in rows {
                let date = f.date(from: r.created_at) ?? f2.date(from: r.created_at) ?? Date()
                let weekStart = isoMondayWeekStart(for: date)
                if let existing = byWeek[weekStart] {
                    if date > existing.0 {
                        byWeek[weekStart] = (date, r.predicted_marathon_seconds)
                    }
                } else {
                    byWeek[weekStart] = (date, r.predicted_marathon_seconds)
                }
            }
            let samples = byWeek
                .sorted { $0.key < $1.key }
                .map { (weekStart, value) in
                    WeeklySample(weekStart: weekStart, predictedMarathonSeconds: value.1)
                }
                .suffix(12)
            return TodayFitnessTrend(weeklySamples: Array(samples))
        } catch {
            Log.coach.error("TodayFitnessTrend fetch failed: \(error)")
            return TodayFitnessTrend(weeklySamples: [])
        }
    }
}

/// Zone shifts — this week's % distribution and the 4-week-avg %, plus
/// the delta. Four zones (easy / moderate / threshold / hard).
struct TodayZoneShifts {
    let zones: [Zone]
    struct Zone {
        let label: String
        let thisWeekPct: Int
        let fourWeekAvgPct: Int
        var deltaPct: Int { thisWeekPct - fourWeekAvgPct }
    }

    var hasData: Bool {
        zones.contains { $0.thisWeekPct > 0 || $0.fourWeekAvgPct > 0 }
    }

    static func fetch() async -> TodayZoneShifts {
        struct Row: Decodable {
            let workout_date: String?
            let easy_seconds: Double?
            let moderate_seconds: Double?
            let threshold_seconds: Double?
            let hard_seconds: Double?
        }
        let cal = Calendar.current
        let now = Date()
        let thisWeekStart = isoMondayWeekStart(for: now)
        guard let fourWeeksAgo = cal.date(byAdding: .day, value: -28, to: thisWeekStart) else {
            return TodayZoneShifts(zones: emptyZones())
        }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        let cutoffStr = f.string(from: fourWeeksAgo)

        do {
            let rows: [Row] = try await supabase
                .from("workout_features")
                .select("workout_date, easy_seconds, moderate_seconds, threshold_seconds, hard_seconds")
                .gte("workout_date", value: cutoffStr)
                .execute()
                .value

            var thisWeek = ZoneSums()
            var prior = ZoneSums()  // last 4 weeks before this week
            for r in rows {
                let date = (r.workout_date.flatMap { f.date(from: $0) }) ?? Date()
                let easy = r.easy_seconds ?? 0
                let mod = r.moderate_seconds ?? 0
                let thr = r.threshold_seconds ?? 0
                let hard = r.hard_seconds ?? 0
                if date >= thisWeekStart {
                    thisWeek.add(easy: easy, mod: mod, thr: thr, hard: hard)
                } else {
                    prior.add(easy: easy, mod: mod, thr: thr, hard: hard)
                }
            }
            let priorAvg = prior.dividedBy(4)
            let zones: [Zone] = [
                Zone(label: "EASY",
                     thisWeekPct: thisWeek.pct(of: \.easy),
                     fourWeekAvgPct: priorAvg.pct(of: \.easy)),
                Zone(label: "MODERATE",
                     thisWeekPct: thisWeek.pct(of: \.mod),
                     fourWeekAvgPct: priorAvg.pct(of: \.mod)),
                Zone(label: "THRESHOLD",
                     thisWeekPct: thisWeek.pct(of: \.thr),
                     fourWeekAvgPct: priorAvg.pct(of: \.thr)),
                Zone(label: "HARD",
                     thisWeekPct: thisWeek.pct(of: \.hard),
                     fourWeekAvgPct: priorAvg.pct(of: \.hard)),
            ]
            return TodayZoneShifts(zones: zones)
        } catch {
            Log.coach.error("TodayZoneShifts fetch failed: \(error)")
            return TodayZoneShifts(zones: emptyZones())
        }
    }

    private static func emptyZones() -> [Zone] {
        ["EASY", "MODERATE", "THRESHOLD", "HARD"].map {
            Zone(label: $0, thisWeekPct: 0, fourWeekAvgPct: 0)
        }
    }

    private struct ZoneSums {
        var easy: Double = 0
        var mod: Double = 0
        var thr: Double = 0
        var hard: Double = 0

        mutating func add(easy: Double, mod: Double, thr: Double, hard: Double) {
            self.easy += easy
            self.mod += mod
            self.thr += thr
            self.hard += hard
        }

        var total: Double { easy + mod + thr + hard }

        func dividedBy(_ d: Double) -> ZoneSums {
            ZoneSums(easy: easy / d, mod: mod / d, thr: thr / d, hard: hard / d)
        }

        func pct(of keyPath: KeyPath<ZoneSums, Double>) -> Int {
            guard total > 0 else { return 0 }
            return Int((self[keyPath: keyPath] / total * 100).rounded())
        }
    }
}

/// Race predictions across 5 distances + 4-week-ago deltas.
struct TodayRacePredictions {
    let mile: Distance?
    let fiveK: Distance?
    let tenK: Distance?
    let half: Distance?
    let marathon: Distance?
    let confidence: String?    // "high" / "medium" / "low"

    struct Distance {
        let nowSeconds: Int
        let fourWeeksAgoSeconds: Int?
        var deltaSeconds: Int? {
            guard let prev = fourWeeksAgoSeconds else { return nil }
            return nowSeconds - prev
        }
    }

    var ordered: [(label: String, distance: Distance?)] {
        [("MILE", mile), ("5K", fiveK), ("10K", tenK), ("HALF", half), ("FULL", marathon)]
    }

    static func fetch() async -> TodayRacePredictions {
        struct Row: Decodable {
            let created_at: String
            let predicted_mile_seconds: Int?
            let predicted_5k_seconds: Int?
            let predicted_10k_seconds: Int?
            let predicted_half_seconds: Int?
            let predicted_marathon_seconds: Int?
            let confidence: String?
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -35, to: Date()) ?? Date()
        let cutoffStr = ISO8601DateFormatter().string(from: cutoffDate)

        do {
            let rows: [Row] = try await supabase
                .from("fitness_snapshots")
                .select("created_at, predicted_mile_seconds, predicted_5k_seconds, predicted_10k_seconds, predicted_half_seconds, predicted_marathon_seconds, confidence")
                .gte("created_at", value: cutoffStr)
                .order("created_at", ascending: false)
                .execute()
                .value

            guard let latest = rows.first else { return empty() }
            // Find the row closest to (today − 28 days)
            let target = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            let prior = rows.min { lhs, rhs in
                let ld = (f.date(from: lhs.created_at) ?? f2.date(from: lhs.created_at)) ?? Date()
                let rd = (f.date(from: rhs.created_at) ?? f2.date(from: rhs.created_at)) ?? Date()
                return abs(ld.timeIntervalSince(target)) < abs(rd.timeIntervalSince(target))
            }

            func dist(now: Int?, prev: Int?) -> Distance? {
                guard let n = now else { return nil }
                return Distance(nowSeconds: n, fourWeeksAgoSeconds: prev)
            }

            return TodayRacePredictions(
                mile:     dist(now: latest.predicted_mile_seconds, prev: prior?.predicted_mile_seconds),
                fiveK:    dist(now: latest.predicted_5k_seconds, prev: prior?.predicted_5k_seconds),
                tenK:     dist(now: latest.predicted_10k_seconds, prev: prior?.predicted_10k_seconds),
                half:     dist(now: latest.predicted_half_seconds, prev: prior?.predicted_half_seconds),
                marathon: dist(now: latest.predicted_marathon_seconds, prev: prior?.predicted_marathon_seconds),
                confidence: latest.confidence
            )
        } catch {
            Log.coach.error("TodayRacePredictions fetch failed: \(error)")
            return empty()
        }
    }

    private static func empty() -> TodayRacePredictions {
        TodayRacePredictions(mile: nil, fiveK: nil, tenK: nil, half: nil, marathon: nil, confidence: nil)
    }
}

// MARK: - Helpers

/// ISO 8601 (Monday-first) start of the week containing `date`.
func isoMondayWeekStart(for date: Date) -> Date {
    var cal = Calendar(identifier: .iso8601)
    cal.firstWeekday = 2
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? cal.startOfDay(for: date)
}

func formatPaceSecondsHMS(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d", h, m) }
    return String(format: "%d:%02d", m, s)
}

func formatRaceTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d", h, m) }
    return String(format: "%d:%02d", m, s)
}

func formatDeltaSeconds(_ seconds: Int) -> String {
    if seconds == 0 { return "—" }
    let abs_s = abs(seconds)
    let sign = seconds < 0 ? "−" : "+"
    if abs_s < 60 {
        return "\(sign)\(abs_s)s"
    }
    let m = abs_s / 60
    let s = abs_s % 60
    return "\(sign)\(m):\(String(format: "%02d", s))"
}

// MARK: - View — TodayJournalEntry

/// Yesterday's journal entry — full prose with mood-color rule on the
/// left. Reads from the existing TodayLastLog data shape.
struct TodayJournalEntry: View {
    let log: TodayLastLog

    private var moodColor: Color {
        let m = (log.mood ?? "").lowercased()
        switch m {
        case "energized": return Color.drip.energized
        case "positive":  return Color.drip.positive
        case "neutral":   return Color.drip.neutral
        case "tired":     return Color.drip.tired
        case "struggling":return Color.drip.struggling
        case "injured":   return Color.drip.injured
        default:          return Color.drip.textTertiary
        }
    }

    private var dayDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE  ·  MMM d"
        return f.string(from: log.workoutDate).uppercased()
    }

    private var bodyText: String? {
        let raw = log.cleanedNotes ?? log.rawNotes
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t = trimmed, !t.isEmpty else { return nil }
        return "\u{201C}\(t)\u{201D}"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(moodColor)
                .frame(width: 2)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(dayDateLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)

                HStack(alignment: .firstTextBaseline) {
                    Text(headlineLine)
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                }

                if let meta = metaLine {
                    Text(meta)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                if let body = bodyText {
                    Text(body)
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(4)
                        .lineLimit(4)
                        .padding(.top, 6)
                }

                if let insight = log.coachInsight, !insight.isEmpty {
                    Text("—— coach: \(insight)")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Color.drip.coral)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var headlineLine: String {
        let typeName = CoachIntent.displayName(for: log.typeKey)
        if let m = log.distanceMiles, m > 0 {
            return "\(typeName), \(formatMiles(m)) mi."
        }
        return "\(typeName)."
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let p = log.pacePerMile { parts.append("\(p) / mi") }
        if let dur = log.durationMinutes, dur > 0 {
            parts.append("\(Int(dur.rounded())) min")
        }
        if let mood = log.mood, !mood.isEmpty {
            parts.append(mood.uppercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: "   ·   ")
    }

    private func formatMiles(_ m: Double) -> String {
        if m == m.rounded() { return String(format: "%.0f", m) }
        return String(format: "%.1f", m)
    }
}

// MARK: - View — TodayTomorrowSection

struct TodayTomorrowSection: View {
    let workout: TodayTomorrowWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TOMORROW")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("FROM YOUR COACH")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }

            if workout.isRest {
                Text("Rest day.")
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.drip.textPrimary)
            } else {
                Text(headlineLine)
                    .font(.dripDisplay(22))
                    .foregroundStyle(Color.drip.textPrimary)
                if let s = workout.structureLine {
                    Text(s)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            if let intent = workout.coachIntent {
                Text("\u{201C}\(intent)\u{201D}")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private var headlineLine: String {
        let name = workout.displayName
        if let m = workout.totalDistanceMiles, m > 0 {
            let str = m == m.rounded() ? String(format: "%.0f", m) : String(format: "%.1f", m)
            return "\(name), \(str) mi."
        }
        return "\(name)."
    }
}

// MARK: - View — TodayMoodPrompt

/// Capsule radio pills for the daily mood check-in. Each mood is a
/// tracked uppercase label with a dot in the mood color, sitting in a
/// 12% wash capsule. Selected pill fills solid in the mood color with
/// white text. Per the spec's "tracked uppercase pills + dot color,
/// not faces" rule. v1 stores in @AppStorage keyed by today's date.
struct TodayMoodPrompt: View {
    @AppStorage("todayMoodCheckIn") private var todayMoodKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TODAY")
                    .font(.dripEyebrow(10))
                    .tracking(1.0)  // 0.10em caption tracking at 10pt
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if currentSelection != nil {
                    Text("CHECKED IN")
                        .font(.dripEyebrow(10))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.energized)
                }
            }

            Text("How are you feeling?")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moodChoices, id: \.label) { choice in
                        let isSelected = currentSelection == choice.label
                        Button {
                            select(choice.label)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isSelected ? .white : choice.color)
                                    .frame(width: 5, height: 5)
                                Text(choice.label)
                                    .font(.dripEyebrow(11))
                                    .tracking(1.1)  // 0.10em caption tracking at 11pt
                            }
                            .foregroundStyle(isSelected ? .white : choice.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? choice.color : choice.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var moodChoices: [(label: String, color: Color)] {
        [
            ("ENERGIZED",  Color.drip.energized),
            ("POSITIVE",   Color.drip.positive),
            ("NEUTRAL",    Color.drip.neutral),
            ("TIRED",      Color.drip.tired),
            ("STRUGGLING", Color.drip.struggling),
        ]
    }

    /// Today's mood, decoded from the @AppStorage key "YYYY-MM-DD:MOOD".
    private var currentSelection: String? {
        let parts = todayMoodKey.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              parts[0] == todayDateKey
        else { return nil }
        return String(parts[1])
    }

    private var todayDateKey: Substring {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return Substring(f.string(from: Date()))
    }

    private func select(_ mood: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        todayMoodKey = "\(f.string(from: Date())):\(mood)"
        // V2: also write to a `daily_check_ins` table via Supabase. The
        // current persistence is local-only — the DCO and downstream
        // analyses still read mood from `training_logs.mood`, which only
        // attaches to logged runs. Closing that gap requires the new
        // table per design/PLATE_18_DATA.md §2.
    }
}

// MARK: - View — TodayFitnessTrendChart

struct TodayFitnessTrendChart: View {
    let trend: TodayFitnessTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FITNESS  ·  12 WEEKS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                Text("PREDICTED MARATHON")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
            }

            if trend.weeklySamples.count < 2 {
                Text("Building baseline — need more weeks of training data.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.vertical, 14)
            } else {
                if let latest = trend.latestSeconds {
                    HStack(spacing: 6) {
                        Text(formatRaceTime(latest))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.drip.textPrimary)
                        if let delta = trend.deltaSeconds, delta != 0 {
                            Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(delta < 0 ? Color.drip.energized : Color.drip.coral)
                            Text(delta < 0 ? "fitness up" : "fitness down")
                                .font(.system(size: 11, design: .serif).italic())
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                }
                FitnessTrendCanvas(samples: trend.weeklySamples)
                    .frame(height: 100)
            }
        }
    }
}

private struct FitnessTrendCanvas: View {
    let samples: [TodayFitnessTrend.WeeklySample]

    var body: some View {
        GeometryReader { geo in
            let values = samples.compactMap { $0.predictedMarathonSeconds }
            if values.count < 2 {
                Color.clear
            } else {
                let mn = Double(values.min() ?? 0)
                let mx = Double(values.max() ?? 1)
                let range = max(mx - mn, 1)
                let pad: CGFloat = 8
                let n = samples.count
                let pts: [CGPoint] = samples.enumerated().compactMap { (i, s) in
                    guard let v = s.predictedMarathonSeconds else { return nil }
                    let x = pad + (CGFloat(i) / CGFloat(n - 1)) * (geo.size.width - 2 * pad)
                    // Lower seconds = higher fitness = visually higher (lower y)
                    let y = pad + CGFloat(1 - (Double(v) - mn) / range) * (geo.size.height - 2 * pad)
                    return CGPoint(x: x, y: y)
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.drip.textPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let last = pts.last {
                    Circle()
                        .fill(Color.drip.coral)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - View — TodayZoneShiftsRow

struct TodayZoneShiftsRow: View {
    let shifts: TodayZoneShifts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ZONE SHIFTS  ·  WEEK vs 4 WK AVG")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
            }

            if !shifts.hasData {
                Text("No volume to compare yet — log a few runs.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
            } else {
                HStack(spacing: 0) {
                    ForEach(shifts.zones, id: \.label) { zone in
                        VStack(spacing: 4) {
                            Text(zone.label)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(zoneColor(zone.label))
                            Text("\(zone.thisWeekPct)%")
                                .font(.dripDisplay(20))
                                .foregroundStyle(Color.drip.textPrimary)
                                .monospacedDigit()
                            Text(deltaString(zone.deltaPct))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(deltaColor(zone.deltaPct))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func zoneColor(_ label: String) -> Color {
        switch label {
        case "EASY": return Color.drip.energized
        case "MODERATE": return Color.drip.textSecondary
        case "THRESHOLD": return Color.drip.coral
        case "HARD": return Color.drip.textPrimary
        default: return Color.drip.textTertiary
        }
    }

    private func deltaString(_ d: Int) -> String {
        if d == 0 { return "0" }
        return d > 0 ? "+\(d)" : "\(d)"
    }

    private func deltaColor(_ d: Int) -> Color {
        if d > 0 { return Color.drip.energized }
        if d < 0 { return Color.drip.coral }
        return Color.drip.textTertiary
    }
}

// MARK: - View — TodayRacePredictionsStrip

struct TodayRacePredictionsStrip: View {
    let predictions: TodayRacePredictions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RACE PREDICTIONS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let conf = predictions.confidence {
                    Text("\(conf.uppercased()) CONFIDENCE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(confidenceColor(conf))
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(predictions.ordered.enumerated()), id: \.offset) { idx, item in
                    VStack(spacing: 4) {
                        Text(item.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textSecondary)
                        if let dist = item.distance {
                            Text(formatRaceTime(dist.nowSeconds))
                                .font(.dripDisplay(18))
                                .foregroundStyle(Color.drip.textPrimary)
                                .monospacedDigit()
                            if let delta = dist.deltaSeconds {
                                Text(formatDeltaSeconds(delta))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(delta < 0 ? Color.drip.energized
                                                     : (delta > 0 ? Color.drip.coral
                                                                  : Color.drip.textTertiary))
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        } else {
                            Text("—")
                                .font(.dripDisplay(18))
                                .foregroundStyle(Color.drip.textTertiary)
                                .monospacedDigit()
                            Text("no data")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.drip.divider)
                                .frame(width: 1)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private func confidenceColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "high": return Color.drip.energized
        case "medium": return Color.drip.textSecondary
        default: return Color.drip.textTertiary
        }
    }
}
