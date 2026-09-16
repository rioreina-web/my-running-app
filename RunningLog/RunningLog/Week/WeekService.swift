//
//  WeekService.swift
//  RunningLog · Week
//
//  Builds the Week tab from the athlete's OWN data.
//
//  It does not fetch. Everything here is derived from `TrendsService`, which
//  already loads `trends-timeline` — and that payload already contains, per
//  day: deduped miles with doubles summed, the individual runs with clock
//  times, the full ten-zone minutes/miles/load breakdown, mood (nil when
//  unlogged), body mentions, `stress_load`, and the overnight biometrics.
//  Plus `paceBands`, which carries per-session heat-adjusted AND raw pace with
//  the correction between them.
//
//  So Week is a second reader of one fetch, not a second fetch. `TrendsService`
//  is already shared by two surfaces and joins an in-flight load rather than
//  duplicating it, so entering this tab costs nothing when Trends has been
//  opened, and warms Trends when it hasn't.
//
//  ── THE RULE ───────────────────────────────────────────────────────────────
//  If a number cannot be derived from the athlete's own rows, this file does
//  not produce it. There are no constants standing in for data, no rounded
//  "typical" values, no placeholder series. A section with no input returns
//  `.needsHistory` / `.notCaptured` / `.notWired` and the view renders prose
//  saying so. The first version of this tab shipped on invented numbers and
//  the athlete caught it in one question — "what's 48 miles from?" It was from
//  nothing. Everything below can answer that question.
//

import Foundation
import SwiftUI

@Observable
final class WeekService {
    static let shared = WeekService()
    private init() {}

    private(set) var read: WeekRead?
    private(set) var isLoading = false
    private(set) var lastError: Error?

    var failedWithNothingToShow: Bool { lastError != nil && read == nil }

    @MainActor
    func refresh(force: Bool = false) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        let trends = TrendsService.shared
        await trends.refresh(force: force)

        if let error = trends.lastError, trends.days.isEmpty {
            lastError = error
            return
        }
        lastError = nil
        read = WeekBuilder.build(days: trends.days,
                                 weeks: trends.weeks,
                                 paceBands: trends.paceBands)
    }
}

// MARK: - Builder

/// Pure mapping, so it can be unit-tested without a network or a service.
enum WeekBuilder {

    // Monday-first, matching `plan_weeks.start_date` and every other weekly
    // rollup in the product.
    //
    // ⚠️ UTC, AND IT HAS TO BE. `TrendsDay.date` is a UTC day key
    // ("yyyy-MM-dd (UTC day)" — see its doc comment) and `iso` below parses it
    // as UTC. If this calendar runs in the device timezone instead, every day
    // key west of Greenwich lands on the previous local day: at UTC−5,
    // `2026-08-17 00:00Z` is Aug 16, 7pm, which falls in the PREVIOUS week and
    // is filtered out of the current one entirely.
    //
    // That shipped, and the symptom was subtle enough to look like a design
    // choice rather than a bug: the week strip showed Tuesday's mileage in the
    // Monday cell and dropped Monday altogether, so a 20.3-mile week read as
    // 10.3. Both halves of the date math — the parser and the calendar — must
    // agree on a timezone, and UTC is the one the data is keyed in.
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }

    /// Display formatter, pinned to UTC for the same reason as `calendar` —
    /// otherwise a UTC day key renders as the day before.
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func build(days: [TrendsDay],
                      weeks: [TrendsWeek],
                      paceBands: PaceBands?) -> WeekRead? {

        guard !days.isEmpty else { return nil }

        let parsed: [(day: TrendsDay, date: Date)] = days.compactMap {
            guard let d = iso.date(from: $0.date) else { return nil }
            return ($0, d)
        }
        guard let latest = parsed.map(\.date).max() else { return nil }
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: latest)?.start
        else { return nil }

        let thisWeek = parsed
            .filter { $0.date >= weekStart }
            .sorted { $0.date < $1.date }

        let strip = weekStrip(weekStart: weekStart, entries: thisWeek)
        let totalMiles = thisWeek.reduce(0.0) { $0 + $1.day.miles }
        let runCount = thisWeek.reduce(0) { $0 + max($1.day.runs.count, $1.day.miles > 0 ? 1 : 0) }

        let loadSeries = weeklyLoad(parsed: parsed, upTo: weekStart)
        let spectrum = spectrumSlices(parsed: parsed, since: calendar.date(byAdding: .day, value: -28, to: latest))
        let recovery = recoveryRead(entries: thisWeek, allDays: parsed)

        return WeekRead(
            plateBlock: blockLabel(weeks: weeks),
            plateRange: rangeLabel(weekStart: weekStart),
            eyebrow: "The week ahead",
            title: "Week of \(monthDay(weekStart)).",
            subtitle: subtitleLine(totalMiles: totalMiles, runCount: runCount, days: thisWeek.count),

            days: strip,
            weekSummary: summaryLine(totalMiles: totalMiles, runCount: runCount),

            bands: bandSeries(paceBands),
            efficiency: nil,
            efficiencyUnavailable: .notWired(
                "Pace at a fixed heart rate is computed in the efficiency index, but it isn't plumbed to this tab yet."),
            fasterSentence: fasterSentence(paceBands),
            bandsUnavailable: paceBands == nil || (paceBands?.sessions.isEmpty ?? true)
                ? .needsHistory("No sessions have held a threshold band long enough to trend yet. This needs runs with laps inside HMP or MP.")
                : nil,

            load: loadSeries,
            recovery: recovery,
            overnightUnavailable: overnightState(entries: thisWeek),

            longRuns: longRuns(parsed: parsed),
            longRunSentence: "",
            spectrum: spectrum,
            spectrumNote: spectrumNote(spectrum),
            longThreshold: longThresholdStat(paceBands),
            volume: volumeStat(parsed: parsed, weekStart: weekStart, totalMiles: totalMiles),

            proposals: [],
            proposalsUnavailable: .notWired(
                "Nothing proposes yet. The signals above are yours; the change to the week is not written until there's an engine that can cite them.")
        )
    }

    // MARK: Week strip

    private static func weekStrip(weekStart: Date,
                                  entries: [(day: TrendsDay, date: Date)]) -> [WeekRead.Day] {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let match = entries.first { calendar.isDate($0.date, inSameDayAs: date) }

            guard let day = match?.day, day.miles > 0 else {
                // No row, or a row with no running. Both are honestly blank.
                return WeekRead.Day(name: names[offset], miles: nil,
                                    label: match == nil ? "—" : "Rest",
                                    isQuality: false)
            }

            let runs = day.runs
                .sorted { $0.startedAt < $1.startedAt }
                .map { WeekRead.DayRun(clock: $0.clockLabel,
                                       miles: $0.miles,
                                       label: runHeadline(for: $0.zoneMiles)) }

            return WeekRead.Day(
                name: names[offset],
                miles: day.miles,
                label: runs.count > 1 ? "\(runs.count) runs" : runHeadline(for: day.zoneMiles),
                isQuality: day.type == .key || day.type == .long,
                runs: runs
            )
        }
    }

    // A work zone has to be a real CHUNK of the run before it gets to name it:
    // at least a mile, and at least a tenth of the distance.
    private static let materialWorkMiles = 1.0
    private static let materialWorkShare = 0.10

    /// What the run mostly WAS, with the sharp end named only when it is
    /// material.
    ///
    /// ⚠️ THE BUG THIS REPLACED. The first version returned the sharpest zone
    /// with 0.3+ miles in it, which labelled a 17-mile steady long run "MP"
    /// because about a mile of it drifted into marathon pace. Worse, the
    /// provenance sheet showed that label directly under a header built by
    /// `compositionLabel` reading "11.0 Steady · 4.4 Easy" — two labelling
    /// rules disagreeing on one screen, about one run.
    ///
    /// A pace a run touched is not what the run was for. The bar is now a mile
    /// AND a tenth of the distance, so an interval day (2.5 mi at 10K inside
    /// 8.2) still names its work, and a long run that drifted for a mile does
    /// not.
    private static func runHeadline(for zoneMiles: [String: Double]?) -> String {
        guard let zoneMiles, !zoneMiles.isEmpty else { return "Run" }
        let total = zoneMiles.values.reduce(0, +)
        guard total > 0 else { return "Run" }

        let bar = max(materialWorkMiles, total * materialWorkShare)
        let workOrder: [(String, String)] = [
            ("mile", "Mile"), ("3k", "3K"), ("5k", "5K"), ("10k", "10K"),
            ("lt", "LT"), ("hmp", "HMP"), ("mp", "MP"), ("steady", "Steady")
        ]
        for (token, label) in workOrder where (zoneMiles[token] ?? 0) >= bar {
            return label
        }
        return dominantLabel(zoneMiles)
    }

    /// Whatever the run mostly was, by volume.
    private static func dominantLabel(_ zoneMiles: [String: Double]) -> String {
        guard let top = zoneMiles.max(by: { $0.value < $1.value })?.key,
              let zone = zone(for: top) else { return "Run" }
        return zone.label
    }

    // MARK: Load

    private static func weeklyLoad(parsed: [(day: TrendsDay, date: Date)],
                                   upTo weekStart: Date) -> WeekRead.Load {
        var buckets: [Date: [TrendsDay]] = [:]
        for entry in parsed {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start
            else { continue }
            buckets[start, default: []].append(entry.day)
        }

        let ordered = buckets.keys.sorted().suffix(9)
        let series: [WeekRead.LoadWeek] = ordered.map { start in
            let group = buckets[start] ?? []
            var minutes: [WeekZone: Double] = [:]
            for day in group {
                for (token, value) in (day.zoneLoad ?? [:]) {
                    guard let zone = zone(for: token) else { continue }
                    minutes[zone, default: 0] += value
                }
            }
            let sessions = group
                .filter { $0.miles > 0 }
                .sorted { $0.date < $1.date }
                .map { day in
                    WeekSourceRun(
                        date: shortLabel(day.date),
                        name: day.runs.count > 1 ? "\(day.runs.count) runs" : runHeadline(for: day.zoneMiles),
                        detail: String(format: "%.1f mi", day.miles),
                        value: day.stressLoad.map { String(Int($0.rounded())) } ?? "—",
                        secondary: day.stressLoad == nil ? "no load computed" : nil
                    )
                }
            return WeekRead.LoadWeek(label: shortLabel(iso.string(from: start)),
                                     minutes: minutes,
                                     sessions: sessions)
        }

        // Baseline: the 8 weeks BEFORE the current one, zero-running weeks held
        // out so a layoff can't reset it and make the comeback a false spike.
        let priors = series.dropLast().map(\.total).filter { $0 > 0 }
        let mean = priors.isEmpty ? 0 : priors.reduce(0, +) / Double(priors.count)
        let sd = standardDeviation(priors, mean: mean)
        let current = series.last?.total ?? 0

        let delta: String
        if mean > 0 {
            let pct = Int(((current / mean) - 1) * 100)
            delta = pct >= 0 ? "+\(pct)% vs your \(priors.count)-wk normal"
                             : "\(pct)% vs your \(priors.count)-wk normal"
        } else {
            delta = "No baseline yet"
        }

        return WeekRead.Load(
            current: current > 0 ? String(Int(current.rounded())) : "—",
            deltaText: delta,
            weeks: series,
            baselineAvg: mean,
            baselineLo: max(mean - sd, 0),
            baselineHi: mean + sd,
            baselineLabel: mean > 0 ? "Your normal · \(Int(mean.rounded()))" : "Baseline needs more weeks",
            spikeNote: "",
            method: "Every run's internal load, summed by week and split by the pace zone each lap sat in. The band behind is your own \(priors.count)-week average, plus or minus one standard deviation — weeks with no running are left out of it."
        )
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    // MARK: Spectrum

    private static func spectrumSlices(parsed: [(day: TrendsDay, date: Date)],
                                       since: Date?) -> [WeekRead.SpectrumSlice] {
        guard let since else { return [] }
        let window = parsed.filter { $0.date >= since }
        var totals: [WeekZone: Double] = [:]
        var sources: [WeekZone: [WeekSourceRun]] = [:]

        for entry in window {
            for (token, miles) in (entry.day.zoneMiles ?? [:]) {
                guard let zone = zone(for: token), miles > 0 else { continue }
                totals[zone, default: 0] += miles
                sources[zone, default: []].append(
                    WeekSourceRun(date: shortLabel(entry.day.date),
                                  name: runHeadline(for: entry.day.zoneMiles),
                                  detail: String(format: "%.1f mi total", entry.day.miles),
                                  value: String(format: "%.1f mi", miles),
                                  secondary: nil)
                )
            }
        }

        let grand = totals.values.reduce(0, +)
        guard grand > 0 else { return [] }

        return WeekZone.allCases.compactMap { zone in
            guard let miles = totals[zone], miles > 0 else { return nil }
            let share = miles / grand * 100
            return WeekRead.SpectrumSlice(
                zone: zone,
                share: share,
                flagged: false,
                miles: String(format: "%.1f mi", miles),
                sessions: (sources[zone] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    private static func spectrumNote(_ slices: [WeekRead.SpectrumSlice]) -> String {
        guard !slices.isEmpty else { return "" }
        let work: [WeekZone] = [.steady, .mp, .hmp, .tenK, .fiveK, .threeK]
        let present = slices.filter { work.contains($0.zone) }
        guard let thinnest = present.min(by: { $0.share < $1.share }) else { return "" }
        return "\(thinnest.zone.label) · \(String(format: "%.1f", thinnest.share))% — your least-visited work zone"
    }

    // MARK: Recovery

    private static func recoveryRead(entries: [(day: TrendsDay, date: Date)],
                                     allDays: [(day: TrendsDay, date: Date)]) -> WeekRead.Recovery {
        let window = allDays.sorted { $0.date < $1.date }.suffix(14)

        var niggles: [WeekRead.Niggle] = []
        var seen = Set<String>()
        for entry in window.reversed() {
            for niggle in entry.day.niggles {
                let key = [niggle.area, niggle.side ?? ""].joined(separator: "-")
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                niggles.append(WeekRead.Niggle(
                    name: [niggle.side?.capitalized, niggle.area.capitalized]
                        .compactMap { $0 }.joined(separator: " "),
                    status: niggle.severity?.capitalized ?? "Mentioned",
                    tint: Color.drip.tired,
                    resolved: false
                ))
            }
        }

        let dots = window.map { !$0.day.niggles.isEmpty }
        let moods: [Color?] = window.map { entry in
            guard let mood = entry.day.mood else { return nil }
            return moodColor(mood)
        }

        let logged = moods.compactMap { $0 }.count
        let summary = logged == 0
            ? "No moods logged in the last 14 days"
            : "Mood logged on \(logged) of \(window.count) days · niggles mentioned on \(dots.filter { $0 }.count)"

        return WeekRead.Recovery(
            niggles: niggles,
            niggleDots: dots,
            moods: moods,
            moodSummary: summary,
            overnight: overnightStats(entries: Array(window)),
            quadrantNote: "",
            sentence: recoverySentence(logged: logged, total: window.count, niggles: niggles)
        )
    }

    /// Deliberately does not interpret. It states what is there and what is
    /// missing, and stops — the convergence rules that would let it say more
    /// need the biometrics branch that isn't shipping data yet.
    private static func recoverySentence(logged: Int, total: Int, niggles: [WeekRead.Niggle]) -> String {
        var parts: [String] = []
        if logged == 0 {
            parts.append("Nothing was logged about how the running felt in the last two weeks, so the side of this that matters most is blank.")
        } else {
            parts.append("You logged how it felt on \(logged) of the last \(total) days.")
        }
        if niggles.isEmpty {
            parts.append("No body mentions in that window.")
        } else {
            let names = niggles.prefix(2).map(\.name).joined(separator: " and ")
            parts.append("\(names) came up in your own words.")
        }
        parts.append("The overnight numbers aren't flowing yet, so this is one side of the picture, not both.")
        return parts.joined(separator: " ")
    }

    private static func overnightStats(entries: [(day: TrendsDay, date: Date)]) -> [WeekRead.OvernightStat] {
        var out: [WeekRead.OvernightStat] = []
        let hrv = entries.compactMap { $0.day.hrvRmssd }
        let rhr = entries.compactMap { $0.day.restingHr }
        let sleep = entries.compactMap { $0.day.sleepTotalMin }

        if !rhr.isEmpty {
            out.append(.init(label: "HR · night",
                             value: String(Int((rhr.reduce(0,+) / Double(rhr.count)).rounded())),
                             baseline: nil, note: "\(rhr.count) nights",
                             noteTint: Color.drip.textSecondary))
        }
        if !hrv.isEmpty {
            out.append(.init(label: "HRV",
                             value: String(Int((hrv.reduce(0,+) / Double(hrv.count)).rounded())),
                             baseline: nil, note: "\(hrv.count) nights",
                             noteTint: Color.drip.textSecondary))
        }
        if !sleep.isEmpty {
            let mean = sleep.reduce(0,+) / sleep.count
            out.append(.init(label: "Sleep",
                             value: "\(mean / 60):\(String(format: "%02d", mean % 60))",
                             baseline: nil, note: "\(sleep.count) nights",
                             noteTint: Color.drip.textSecondary))
        }
        return out
    }

    private static func overnightState(entries: [(day: TrendsDay, date: Date)]) -> WeekRead.Unavailable? {
        let any = entries.contains { $0.day.hrvRmssd != nil || $0.day.restingHr != nil }
        guard !any else { return nil }
        return .notCaptured("No overnight data has arrived. `daily_biometrics` exists but nothing writes to it yet, so heart rate, HRV and sleep are blank rather than estimated.")
    }

    private static func moodColor(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "energized", "strong": Color.drip.energized
        case "positive", "good": Color.drip.positive
        case "neutral", "ok": Color.drip.neutral
        case "tired", "flat": Color.drip.tired
        case "struggling": Color.drip.struggling
        case "injured": Color.drip.injured
        default: Color.drip.neutral
        }
    }

    // MARK: Long runs

    private static func longRuns(parsed: [(day: TrendsDay, date: Date)]) -> [WeekRead.LongRun] {
        parsed
            .filter { $0.day.type == .long }
            .sorted { $0.date > $1.date }
            .prefix(4)
            .map { entry in
                WeekRead.LongRun(
                    date: shortLabel(entry.day.date),
                    distance: String(format: "%.1f", entry.day.miles),
                    inside: insideLabel(entry.day.zoneMiles),
                    durationLabel: entry.day.durationMin.map { "\($0 / 60)h \($0 % 60)m" } ?? "—",
                    // Composition, not headline — this row sits directly under a
                    // header built the same way, and the two must agree.
                    laps: entry.day.runs.sorted { $0.startedAt < $1.startedAt }.map {
                        WeekSourceRun(date: $0.clockLabel,
                                      name: insideLabel($0.zoneMiles),
                                      detail: String(format: "%.1f mi", $0.miles),
                                      value: String(format: "%.0f min", $0.durationSec / 60),
                                      secondary: nil)
                    }
                )
            }
    }

    /// "12.1 easy · 3.0 MP" — the real composition, never an inferred intent.
    private static func insideLabel(_ zoneMiles: [String: Double]?) -> String {
        guard let zoneMiles, !zoneMiles.isEmpty else { return "No lap breakdown" }
        let work = zoneMiles
            .compactMap { token, miles -> (WeekZone, Double)? in
                guard let zone = zone(for: token), miles >= 0.3 else { return nil }
                return (zone, miles)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
        guard !work.isEmpty else { return "No lap breakdown" }
        return work.map { String(format: "%.1f %@", $0.1, $0.0.label) }.joined(separator: " · ")
    }

    // MARK: Bands

    private static func bandSeries(_ paceBands: PaceBands?) -> [WeekRead.Band] {
        guard let paceBands else { return [] }
        return [PaceBandKey.hm, PaceBandKey.mp].compactMap { key in
            let summary = paceBands.summary(key)
            let sessions = paceBands.sessions(in: key)
            guard !sessions.isEmpty else { return nil }

            let points = sessions.map { session -> WeekRead.Point in
                let slice = session.slice(key)
                return WeekRead.Point(
                    weekLabel: session.dateLabel,
                    paceSec: slice?.paceAdjSec ?? summary.anchorSec,
                    sessions: [
                        WeekSourceRun(
                            date: session.dateLabel,
                            name: String(format: "%.1f mi session", session.sessionMi),
                            detail: String(format: "%.0f min in band", slice?.minutes ?? 0),
                            value: paceLabel(slice?.paceAdjSec),
                            secondary: (slice?.hasCorrection ?? false)
                                ? "\(paceLabel(slice?.paceRawSec)) raw · +\(slice?.correctionSec ?? 0)s heat"
                                : "no weather correction on file"
                        )
                    ]
                )
            }

            return WeekRead.Band(
                key: key.shortLabel,
                currentPace: paceLabel(summary.paceAdjSec),
                delta: deltaLabel(points),
                points: points,
                footnote: "Heat-adjusted · band \(paceLabel(summary.fastSec))–\(paceLabel(summary.slowSec)) · \(summary.sessionCount) sessions · \(paceBands.confidenceTier ?? "unrated") confidence",
                tint: key.color,
                method: "Every lap whose heat-adjusted pace landed inside the band, session by session. Membership is decided on the adjusted pace — what the conditions say the effort was worth — and the raw pace your watch recorded is shown beside it."
            )
        }
    }

    private static func deltaLabel(_ points: [WeekRead.Point]) -> String {
        guard let first = points.first?.paceSec, let last = points.last?.paceSec,
              points.count > 1 else { return "" }
        let change = last - first
        if change == 0 { return "Flat across \(points.count) sessions" }
        return change < 0 ? "−\(abs(change))s over \(points.count) sessions"
                          : "+\(change)s over \(points.count) sessions"
    }

    private static func fasterSentence(_ paceBands: PaceBands?) -> String {
        guard let overlap = paceBands?.overlap else { return "" }
        return "Your half and marathon targets sit \(overlap.gapSec)s apart, so the two bands share \(overlap.widthSec)s of pace and \(Int(overlap.minutesBoth)) minutes qualify for both. They read separately here; they are not independent."
    }

    private static func longThresholdStat(_ paceBands: PaceBands?) -> WeekRead.MiniStat {
        guard let paceBands else {
            return .init(eyebrow: "Threshold volume", value: "—", unit: "",
                         caption: "No band data", note: "", noteTint: Color.drip.textTertiary)
        }
        let hm = paceBands.summary(.hm)
        return .init(
            eyebrow: "Threshold volume",
            value: String(Int(hm.minutes.rounded())),
            unit: "min in HMP",
            caption: "\(hm.sessionCount) sessions in window",
            note: String(format: "%.1f mi", hm.miles),
            noteTint: Color.drip.textSecondary,
            method: "Minutes whose heat-adjusted pace landed inside the half-marathon band, across the whole window."
        )
    }

    private static func volumeStat(parsed: [(day: TrendsDay, date: Date)],
                                   weekStart: Date,
                                   totalMiles: Double) -> WeekRead.MiniStat {
        var buckets: [Date: Double] = [:]
        for entry in parsed {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start
            else { continue }
            buckets[start, default: 0] += entry.day.miles
        }
        let recent = buckets.keys.sorted().suffix(5).dropLast().map { buckets[$0] ?? 0 }
        return .init(
            eyebrow: "Volume",
            value: String(format: "%.1f", totalMiles),
            unit: "mi this week",
            caption: recent.map { String(format: "%.0f", $0) }.joined(separator: " · "),
            note: "Previous four weeks",
            noteTint: Color.drip.textSecondary,
            method: "Deduped running miles, doubles summed, for the week beginning \(monthDay(weekStart))."
        )
    }

    // MARK: Labels

    private static func summaryLine(totalMiles: Double, runCount: Int) -> String {
        totalMiles <= 0
            ? "Nothing logged yet this week"
            : String(format: "%.1f mi · %d runs", totalMiles, runCount)
    }

    private static func subtitleLine(totalMiles: Double, runCount: Int, days: Int) -> String {
        totalMiles <= 0
            ? "No runs logged yet this week."
            : String(format: "%.1f miles across %d runs so far. Three questions, then what's missing.", totalMiles, runCount)
    }

    private static func blockLabel(weeks: [TrendsWeek]) -> String {
        "\(weeks.count) weeks on file"
    }

    private static func rangeLabel(weekStart: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(monthDay(weekStart))–\(dayOnly(end))"
    }

    private static func zone(for token: String) -> WeekZone? {
        switch token.lowercased() {
        case "recovery", "easy": .easy
        case "moderate": .moderate
        case "steady": .steady
        case "mp": .mp
        case "hmp", "lt": .hmp
        case "10k": .tenK
        case "5k": .fiveK
        case "3k", "mile": .threeK
        default: nil
        }
    }

    private static func paceLabel(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static func shortLabel(_ isoDate: String) -> String {
        guard let date = iso.date(from: isoDate) else { return isoDate }
        return monthDay(date)
    }

    private static func monthDay(_ date: Date) -> String {
        formatter("MMM d").string(from: date)
    }

    private static func dayOnly(_ date: Date) -> String {
        formatter("d").string(from: date)
    }
}
