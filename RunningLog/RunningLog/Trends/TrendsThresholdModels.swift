//
//  TrendsThresholdModels.swift
//  RunningLog · Trends
//
//  The pure substrate for Trends section 04 — threshold work, read against the
//  athlete's own half-marathon pace band.
//
//  **Why this exists.** `PaceBands` already arrives on the wire with everything
//  needed: per-session minutes and miles inside the band, the heat-neutral pace
//  of those miles, the raw pace, the correction between them, average heart
//  rate over the in-band work and the session's dew point. Nothing here needs a
//  new endpoint or a new query. This file only decides what those numbers mean.
//
//  **The one decision it encodes — the slow-edge leak.** The band is the
//  anchor ±5%, and its slow edge sits close enough to long-run cruising pace
//  that steady miles inside a long run get counted as threshold work. The
//  2026-08-02 band audit found four such sessions in one block, worth 49
//  minutes of credit that was not threshold. Tightening the band edge would
//  fix it on a cool day and break it on a hot one, when genuine threshold work
//  legitimately slows. A heart-rate floor survives both, so that is the rule:
//  in-band minutes are **work** when the average heart rate over them clears
//  the floor, **cruise** when it does not, and **unclassed** when there is no
//  heart rate to ask. Unclassed is never quietly folded into either — a
//  session with no HR is a session we cannot grade, and the read says so.
//
//  No SwiftUI here. Everything is a value type or a pure function, so the
//  rules are testable without a renderer — see `TrendsThresholdTests`.
//

import Foundation

// MARK: - Grade

/// What a session's in-band minutes actually were.
enum ThresholdGrade: Equatable {
    /// Heart rate cleared the floor — this was threshold work.
    case work
    /// In the band on pace, under the floor on effort. Long-run cruising that
    /// the band's slow edge let in.
    case cruise
    /// No heart rate on the in-band miles. Not gradeable, and not guessed.
    case unclassed
}

// MARK: - One session

/// One session that spent time inside the band.
struct ThresholdPoint: Identifiable {
    /// `training_log_id`, so a tap can open the workout.
    let id: String
    /// "2026-07-21"
    let date: String
    /// "Jul 21"
    let dateLabel: String
    /// Minutes inside the band.
    let minutes: Double
    /// Miles inside the band.
    let miles: Double
    /// Heat-neutral pace of the in-band miles, sec/mi. This is the y value —
    /// a raw pace would draw the weather, not the athlete.
    let adjSec: Int
    /// What the watch said, sec/mi.
    let rawSec: Int
    /// `rawSec - adjSec`, the seconds the heat charged. 0 when there was no
    /// weather to correct for.
    let correctionSec: Int
    /// Average heart rate over the in-band work. `nil` when the session
    /// carries no heart-rate data.
    let hrAvg: Int?
    /// Dew point at the session, °F. `nil` when no weather was recorded.
    let dewPointF: Int?
    let grade: ThresholdGrade

    var isWork: Bool { grade == .work }
    var hasCorrection: Bool { correctionSec > 0 }
}

// MARK: - The read

/// Everything section 04 renders, computed once from a `PaceBands` payload.
struct ThresholdRead {
    /// Every session that touched the band, oldest → newest.
    let points: [ThresholdPoint]
    /// The band the read is against.
    let band: PaceBandKey
    /// The band's anchor and its two edges, sec/mi. `fast` is the lower
    /// number — faster pace, drawn higher.
    let anchorSec: Int
    let fastSec: Int
    let slowSec: Int
    /// The heart-rate floor applied, so the view can name it.
    let hrFloor: Int
    /// True when the prediction the band is built on is itself low-confidence.
    /// The view dashes the band edges rather than drawing a hard claim.
    let lowConfidence: Bool

    // MARK: Totals — counted, never carried over from the payload

    var workPoints: [ThresholdPoint] { points.filter { $0.grade == .work } }
    var cruisePoints: [ThresholdPoint] { points.filter { $0.grade == .cruise } }
    var unclassedPoints: [ThresholdPoint] { points.filter { $0.grade == .unclassed } }

    /// Minutes that graded as work. The headline figure.
    var workMinutes: Double { workPoints.reduce(0) { $0 + $1.minutes } }
    /// Minutes the slow edge let in.
    var cruiseMinutes: Double { cruisePoints.reduce(0) { $0 + $1.minutes } }
    var unclassedMinutes: Double { unclassedPoints.reduce(0) { $0 + $1.minutes } }
    var workMiles: Double { workPoints.reduce(0) { $0 + $1.miles } }

    var isEmpty: Bool { points.isEmpty }

    /// Mean minutes of band work per session that carried any. The number the
    /// growth read leans on — a session averaging under 20 minutes has room
    /// to lengthen without adding a mile of volume.
    var minutesPerWorkSession: Double? {
        guard !workPoints.isEmpty else { return nil }
        return workMinutes / Double(workPoints.count)
    }

    /// Mean heart rate over graded work, time-weighted by in-band minutes.
    var workHrAvg: Int? {
        let withHr = workPoints.filter { $0.hrAvg != nil }
        let mins = withHr.reduce(0.0) { $0 + $1.minutes }
        guard mins > 0 else { return nil }
        let weighted = withHr.reduce(0.0) { $0 + Double($1.hrAvg ?? 0) * $1.minutes }
        return Int((weighted / mins).rounded())
    }

    /// The fastest graded work session.
    var best: ThresholdPoint? { workPoints.min { $0.adjSec < $1.adjSec } }
    /// The most recent graded work session.
    var latest: ThresholdPoint? { workPoints.last }

    /// Mean heat correction across every session that had one, sec/mi.
    var meanCorrectionSec: Int? {
        let corrected = points.filter { $0.hasCorrection }
        guard !corrected.isEmpty else { return nil }
        let sum = corrected.reduce(0) { $0 + $1.correctionSec }
        return Int((Double(sum) / Double(corrected.count)).rounded())
    }

    // MARK: Trend

    /// Least-squares slope over graded work only, in **sec/mi per 30 days**.
    /// Negative is getting faster.
    ///
    /// Graded work only, deliberately: a trend fitted through cruising miles
    /// measures how many long runs happened to clip the slow edge, which is
    /// not a fitness claim.
    ///
    /// `nil` below three points — two points are a line through anything.
    var trendSecPerMonth: Double? {
        let pts = workPoints
        guard pts.count >= 3 else { return nil }
        let xs = pts.map { Double(ThresholdRead.dayNumber($0.date)) }
        let ys = pts.map { Double($0.adjSec) }
        guard let slope = ThresholdRead.slope(xs: xs, ys: ys) else { return nil }
        return slope * 30
    }

    /// Days since the epoch for an ISO day, so the fit is over real time
    /// rather than sample index — sessions are not evenly spaced.
    static func dayNumber(_ iso: String) -> Int {
        guard let date = isoDay.date(from: iso) else { return 0 }
        return Int(date.timeIntervalSince1970 / 86_400)
    }

    /// Ordinary least squares. `nil` when x has no spread.
    static func slope(xs: [Double], ys: [Double]) -> Double? {
        let n = Double(xs.count)
        guard n >= 2, xs.count == ys.count else { return nil }
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxx = zip(xs, xs).reduce(0) { $0 + $1.0 * $1.1 }
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 0.000_001 else { return nil }
        return (n * sxy - sx * sy) / denom
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Builder

enum ThresholdBuilder {

    /// The heart-rate floor for grading in-band minutes as work.
    ///
    /// 160 bpm comes from the 2026-08-02 audit: across nineteen band sessions
    /// every genuine workout cleared it and every long run that clipped the
    /// slow edge did not. It is a threshold on the athlete's own data, not a
    /// physiological constant — when the app carries per-athlete HR zones this
    /// wants to become zone-relative (roughly the floor of the athlete's
    /// threshold HR zone) rather than an absolute number.
    static let defaultHrFloor = 160

    /// Build the read for one band from the timeline's pace-bands payload.
    ///
    /// - Parameters:
    ///   - bands: `TrendsService.paceBands`, already fetched for the tab.
    ///   - band: which band to read against. `.hm` is the threshold band.
    ///   - windowDays: the tab's one time control. `nil` reads everything
    ///     loaded — the section never carries a second range of its own.
    ///   - hrFloor: overridable for tests.
    static func build(
        bands: PaceBands,
        band: PaceBandKey = .hm,
        windowDays: Int? = nil,
        hrFloor: Int = defaultHrFloor,
        asOf: Date = Date()
    ) -> ThresholdRead {
        let shown = windowDays.map { bands.windowed(days: $0, asOf: asOf) } ?? bands
        let summary = shown.summary(band)

        let points: [ThresholdPoint] = shown.sessions
            .compactMap { session in
                guard let slice = session.slice(band), slice.minutes > 0 else { return nil }
                return ThresholdPoint(
                    id: session.id,
                    date: session.date,
                    dateLabel: session.dateLabel,
                    minutes: slice.minutes,
                    miles: slice.miles,
                    adjSec: slice.paceAdjSec,
                    rawSec: slice.paceRawSec,
                    correctionSec: max(0, slice.correctionSec),
                    hrAvg: slice.hrAvg,
                    dewPointF: session.dewPointF,
                    grade: grade(hr: slice.hrAvg, floor: hrFloor)
                )
            }
            .sorted { $0.date < $1.date }

        return ThresholdRead(
            points: points,
            band: band,
            anchorSec: summary.anchorSec,
            fastSec: summary.fastSec,
            slowSec: summary.slowSec,
            hrFloor: hrFloor,
            lowConfidence: shown.isLowConfidence
        )
    }

    /// The grading rule, isolated so a test can state it in one line.
    static func grade(hr: Int?, floor: Int) -> ThresholdGrade {
        guard let hr, hr > 0 else { return .unclassed }
        return hr >= floor ? .work : .cruise
    }
}
