//
//  AskPullService.swift
//  RunningLog · Analysis · Ask
//
//  Fetches once, computes every metric, hands back series. One load per tab
//  appear rather than one query per pull — nine pulls over four tables would
//  otherwise be nine round trips to draw one screen.
//
//  WEEK BOUNDARIES. Weeks are Monday-start and only COMPLETE weeks are
//  returned. `workout_date` is a timestamptz with a known local-time skew
//  (an evening run can carry the next UTC day), so the date is bucketed on
//  its calendar-date prefix — the same thing `date_trunc('week', …)` does
//  server-side. Where that matters to a reading, it is stated in `caveat`
//  rather than silently corrected here.
//
//  DEDUPLICATION. `superseded_at` and `duplicate_of` are filtered client-side
//  after the fetch rather than in the query, because a null filter that
//  silently fails would quietly double the athlete's mileage, and a wrong
//  mileage figure is worse than a slow one.
//

import Foundation
import Supabase
import os

@Observable
@MainActor
final class AskPullService {
    static let shared = AskPullService()

    /// How many complete weeks a "whole block" reading covers.
    static let blockWeeks = 13

    private(set) var series: [AskMetric: AskMetricSeries] = [:]
    private(set) var isLoading = false
    private(set) var loadedAt: Date?
    /// The ledger under the masthead — what Ask can currently see.
    private(set) var coverage: String = "Reading your log"

    private let logger = Logger(subsystem: "com.postrundrip.app", category: "AskPulls")

    private init() {}

    // MARK: - Wire rows

    private struct TrainingRow: Decodable {
        let workout_date: String?
        let workout_distance_miles: Double?
        let superseded_at: String?
        let duplicate_of: String?
    }
    private struct FeatureRow: Decodable {
        let workout_date: String?
        let easy_seconds: Double?
        let moderate_seconds: Double?
        let threshold_seconds: Double?
        let hard_seconds: Double?
        let acwr: Double?
        let quality_load: Double?
        let quality_kind: String?
        let total_distance_miles: Double?
    }
    private struct BioRow: Decodable {
        let date: String?
        let sleep_total_min: Double?
        let resting_hr: Double?
        let hrv_rmssd: Double?
    }
    private struct BodyRow: Decodable {
        let body_area: String?
        let side: String?
        let mentioned_at: String?
    }

    // MARK: - Load

    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 120 { return }
        isLoading = true
        defer { isLoading = false }

        let weeks = Self.completeWeeks(count: Self.blockWeeks)
        guard let first = weeks.first else { return }
        let since = Self.dayString(first.start)

        async let logs: [TrainingRow] = fetch("training_logs",
            select: "workout_date, workout_distance_miles, superseded_at, duplicate_of",
            dateColumn: "workout_date", since: since)
        async let feats: [FeatureRow] = fetch("workout_features",
            select: "workout_date, easy_seconds, moderate_seconds, threshold_seconds, hard_seconds, acwr, quality_load, quality_kind, total_distance_miles",
            dateColumn: "workout_date", since: since)
        async let bios: [BioRow] = fetch("daily_biometrics",
            select: "date, sleep_total_min, resting_hr, hrv_rmssd",
            dateColumn: "date", since: since)
        async let bodies: [BodyRow] = fetch("body_mentions",
            select: "body_area, side, mentioned_at",
            dateColumn: "mentioned_at", since: since)

        let (l, f, b, n) = await (logs, feats, bios, bodies)
        // A superseded or merged row is a duplicate of a run already counted.
        let liveLogs = l.filter { $0.superseded_at == nil && $0.duplicate_of == nil }

        series = Self.build(weeks: weeks, logs: liveLogs, feats: f, bios: b, bodies: n)
        coverage = Self.coverageLine(logs: liveLogs, feats: f, bios: b, bodies: n)
        loadedAt = Date()
    }

    private func fetch<T: Decodable>(_ table: String,
                                     select: String,
                                     dateColumn: String,
                                     since: String) async -> [T] {
        do {
            return try await supabase
                .from(table)
                .select(select)
                .gte(dateColumn, value: since)
                .limit(4000)
                .execute()
                .value
        } catch {
            // A table that fails to load leaves its pulls empty rather than
            // taking the screen down. The block says so on its own face.
            logger.error("ask pull fetch \(table) failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Weeks

    struct Week {
        let start: Date
        let label: String
    }

    /// The last `count` COMPLETE Monday-start weeks, oldest first. This week
    /// is excluded: a partial week drawn beside full ones reads as a crash.
    static func completeWeeks(count: Int) -> [Week] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let thisMonday = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return (1...count).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisMonday) else { return nil }
            return Week(start: start, label: fmt.string(from: start))
        }
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: d)
    }

    /// Parses the calendar-date prefix of anything the API returns, whether
    /// that is `2026-08-29` or `2026-08-29T11:04:00+00:00`.
    private static func day(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: String(raw.prefix(10)))
    }

    private static func weekIndex(for date: Date, in weeks: [Week]) -> Int? {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
        return weeks.firstIndex { cal.isDate($0.start, inSameDayAs: start) }
    }

    // MARK: - Build

    private static func build(weeks: [Week],
                              logs: [TrainingRow],
                              feats: [FeatureRow],
                              bios: [BioRow],
                              bodies: [BodyRow]) -> [AskMetric: AskMetricSeries] {

        let n = weeks.count
        var miles = [Double](repeating: 0, count: n)
        var longest = [Double](repeating: 0, count: n)
        var runs = [Int](repeating: 0, count: n)
        for r in logs {
            guard let d = day(r.workout_date), let i = weekIndex(for: d, in: weeks),
                  let mi = r.workout_distance_miles else { continue }
            miles[i] += mi
            longest[i] = max(longest[i], mi)
            runs[i] += 1
        }

        var easy = [Double](repeating: 0, count: n)
        var zoneTotal = [Double](repeating: 0, count: n)
        var thrSec = [Double](repeating: 0, count: n)
        var acwrLast = [Double?](repeating: nil, count: n)
        var qualityScored = 0
        var qualitySessions: [(Date, Double)] = []
        for r in feats {
            guard let d = day(r.workout_date), let i = weekIndex(for: d, in: weeks) else { continue }
            let e = r.easy_seconds ?? 0, m = r.moderate_seconds ?? 0
            let t = r.threshold_seconds ?? 0, h = r.hard_seconds ?? 0
            easy[i] += e
            zoneTotal[i] += e + m + t + h
            thrSec[i] += t
            if let a = r.acwr { acwrLast[i] = a }
            if let ql = r.quality_load {
                qualityScored += 1
                if r.quality_kind == "quality" { qualitySessions.append((d, ql)) }
            }
        }

        var sleepSum = [Double](repeating: 0, count: n), sleepN = [Int](repeating: 0, count: n)
        var rhrSum = [Double](repeating: 0, count: n), rhrN = [Int](repeating: 0, count: n)
        for r in bios {
            guard let d = day(r.date), let i = weekIndex(for: d, in: weeks) else { continue }
            if let s = r.sleep_total_min { sleepSum[i] += s / 60.0; sleepN[i] += 1 }
            if let h = r.resting_hr { rhrSum[i] += h; rhrN[i] += 1 }
        }

        var mentions = [Double](repeating: 0, count: n)
        var sided = 0
        for r in bodies {
            if (r.side ?? "").isEmpty == false { sided += 1 }
            guard let d = day(r.mentioned_at), let i = weekIndex(for: d, in: weeks) else { continue }
            mentions[i] += 1
        }

        func pts(_ values: [Double?]) -> [AskMetricSeries.Point] {
            zip(weeks, values).compactMap { w, v in
                guard let v else { return nil }
                return AskMetricSeries.Point(label: w.label, value: v)
            }
        }

        var out: [AskMetric: AskMetricSeries] = [:]

        out[.weeklyMiles] = AskMetricSeries(
            points: pts(miles.map { $0 > 0 ? $0 : nil }),
            source: "\(logs.count) runs on file",
            caveat: runs.contains(where: { $0 > 14 })
                ? "One week here carries more than 14 runs, which is a duplicate-merge signature rather than a training week."
                : nil)

        out[.longRunShare] = AskMetricSeries(
            points: pts((0..<n).map { i in miles[i] > 0 ? longest[i] / miles[i] * 100 : nil }),
            source: "longest run ÷ week total",
            caveat: "Longest run is the largest single logged distance. A run split across two files understates it.")

        out[.acwr] = AskMetricSeries(
            points: pts(acwrLast),
            source: "workout_features.acwr",
            caveat: nil)

        out[.easyShare] = AskMetricSeries(
            points: pts((0..<n).map { i in zoneTotal[i] > 0 ? easy[i] / zoneTotal[i] * 100 : nil }),
            source: "share of weekly zone time",
            caveat: "Share of TIME in the easy zone, not a check against your own easy pace.")

        out[.thresholdMinutes] = AskMetricSeries(
            points: pts(thrSec.map { $0 / 60.0 }),
            source: "workout_features.threshold_seconds",
            caveat: "A zone classification, not a session label. Threshold-effort work classified moderate contributes nothing here.")

        let qs = qualitySessions.sorted { $0.0 < $1.0 }
        let qf = DateFormatter(); qf.dateFormat = "MMM d"
        out[.qualityLoad] = AskMetricSeries(
            points: qs.map { .init(label: qf.string(from: $0.0), value: $0.1) },
            source: "\(qualityScored) of \(feats.count) workouts scored",
            caveat: "One point per quality session, not per week. Long runs are scored under a different kind and excluded.")

        // Named the SOURCE, not a raw count. A bare "93 nights on file" reads
        // as an arbitrary, slightly alarming number with nothing to compare it
        // to — the provenance rule ("real counts, not a table name") is
        // satisfied just as well by naming where the reading comes from.
        out[.sleepHours] = AskMetricSeries(
            points: pts((0..<n).map { i in sleepN[i] > 0 ? sleepSum[i] / Double(sleepN[i]) : nil }),
            source: "Reading from your sleep data",
            caveat: sleepN.contains(where: { $0 > 0 && $0 < 6 })
                ? "Some weeks average fewer than 6 nights, so a weekly mean can be carried by a couple of readings."
                : nil)

        out[.restingHR] = AskMetricSeries(
            points: pts((0..<n).map { i in rhrN[i] > 0 ? rhrSum[i] / Double(rhrN[i]) : nil }),
            source: "Reading from your resting HR data",
            caveat: "A few beats across a block is close to the noise floor for a wrist reading. Read the shape, not the week.")

        out[.bodyMentions] = AskMetricSeries(
            points: pts(mentions),
            source: "\(bodies.count) mentions on file",
            caveat: bodies.isEmpty ? nil
                : "Only \(sided) of \(bodies.count) mentions carry a side, so left and right cannot be separated.")

        return out
    }

    private static func coverageLine(logs: [TrainingRow],
                                     feats: [FeatureRow],
                                     bios: [BioRow],
                                     bodies: [BodyRow]) -> String {
        let withDistance = logs.filter { $0.workout_distance_miles != nil }.count
        let nights = bios.filter { $0.resting_hr != nil }.count
        return "Reading \(withDistance) runs · \(feats.count) scored · \(nights) nights"
    }

    // MARK: - Chat context

    /// The context handed to `coaching-agent` with a typed question.
    ///
    /// This replaces the ~200 lines of string-building that `CoachView` does
    /// on every turn. It is shorter on purpose: figures the athlete's own
    /// screen is showing, so a reply that contradicts the screen is visible
    /// immediately rather than plausible.
    func contextBlock() -> String {
        var lines: [String] = ["Computed from this athlete's own rows. Use ONLY these figures; do not calculate your own."]
        func describe(_ metric: AskMetric, _ name: String) {
            guard let s = series[metric], let last = s.points.last else { return }
            let vals = s.points.map(\.value)
            let mean = vals.reduce(0, +) / Double(vals.count)
            let lo = vals.min() ?? last.value, hi = vals.max() ?? last.value
            let d = metric.decimals
            lines.append("  \(name): latest \(AskPullReading.format(last.value, decimals: d))\(metric.unit)"
                + " · mean \(AskPullReading.format(mean, decimals: d))"
                + " · range \(AskPullReading.format(lo, decimals: d))–\(AskPullReading.format(hi, decimals: d))"
                + " (\(s.source))")
        }
        lines.append("")
        lines.append("Last \(Self.blockWeeks) complete weeks:")
        describe(.weeklyMiles, "Weekly miles")
        describe(.acwr, "Acute:chronic")
        describe(.easyShare, "Easy share of zone time (%)")
        describe(.thresholdMinutes, "Threshold minutes/week")
        describe(.longRunShare, "Long-run share (%)")
        describe(.qualityLoad, "Quality load per session")
        describe(.sleepHours, "Sleep hours/night")
        describe(.restingHR, "Resting HR")
        describe(.bodyMentions, "Niggle mentions/week")
        if series[.sleepHours]?.points.isEmpty == false {
            lines.append("")
            lines.append("HRV is NOT on file — say so plainly if asked, and never estimate it.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Reading

    func reading(for pull: AskPull) -> AskPullReading {
        let s = series[pull.metric] ?? .empty
        let windowed = Array(s.points.suffix(pull.window.weeks))
        let values = windowed.map(\.value)
        let latest = values.last
        let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        var ghost: Double?
        var delta = ""
        var diff: Double = 0

        if let latest {
            switch pull.compare {
            case .none:
                delta = "\(windowed.count) \(windowed.count == 1 ? "point" : "points")"
            case .start:
                diff = latest - (values.first ?? latest)
                delta = Self.deltaText(diff, metric: pull.metric)
                    + (windowed.first.map { " since \($0.label)" } ?? "")
            case .mean:
                diff = latest - mean
                ghost = mean
                delta = abs(diff) < 0.05 ? "on the mean"
                    : Self.deltaText(diff, metric: pull.metric) + " vs mean"
            }
        } else {
            delta = "nothing on file"
        }

        let tone: AskPullReading.Tone
        if pull.compare == .none || pull.metric.better == .none || latest == nil || diff == 0 {
            tone = .flat
        } else {
            let improving = pull.metric.better == .down ? diff < 0 : diff > 0
            tone = improving ? .good : .watch
        }

        return AskPullReading(pull: pull, points: windowed, latest: latest, mean: mean,
                              ghost: ghost, deltaText: delta, tone: tone,
                              source: s.source, caveat: s.caveat)
    }

    private static func deltaText(_ diff: Double, metric: AskMetric) -> String {
        let sign = diff > 0 ? "+" : "−"
        return sign + AskPullReading.format(abs(diff), decimals: metric.decimals) + metric.unit
    }
}
