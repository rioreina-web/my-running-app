//
//  TrendsThresholdModels.swift
//  RunningLog · Trends
//
//  The pure substrate for Trends section 04 — threshold work, read against a
//  pace band the athlete controls.
//
//  **What changed on 2026-08-05.** This file used to read `PaceBands`, which
//  arrives pre-bucketed at HM ±5% / MP ±5%. Every number in it was therefore a
//  server decision, and none of them could be questioned from the app. It now
//  reads `BandLaps` — the raw laps plus the week's full race-pace ladder — and
//  makes those decisions here, from `BandSettings`. Four constants became
//  controls: the anchor (any race-pace zone, or a typed pace), the two band
//  edges (independent, because the leak was only ever on the slow one), and the
//  minimum a session must hold before it counts.
//
//  **The two rules it encodes.**
//
//  *The slow-edge leak.* A band's slow edge sits close enough to long-run
//  cruising pace that steady miles inside a long run get counted as threshold
//  work. The 2026-08-02 audit found four such sessions in one block, worth 49
//  minutes of credit that was not threshold. A heart-rate floor survives what
//  a tighter edge cannot — genuine threshold work legitimately slows on a hot
//  day — so in-band minutes are **work** when the average heart rate over them
//  clears the floor, **cruise** when it does not, and **unclassed** when there
//  is no heart rate to ask. Unclassed is never quietly folded into either.
//
//  *The drive-by.* Three minutes at 10K pace during a long run is a pace the
//  athlete passed through, not work she did. Two gates hold it out, and they
//  catch different things: a **total** across the session, and a **longest
//  unbroken block**. Four separate three-minute touches clear a twelve-minute
//  total and fail a five-minute block, which is the correct verdict and the
//  reason both exist. Sessions the gates exclude are COUNTED and reported —
//  a filter that silently deletes running is a filter that lies.
//
//  No SwiftUI layout here; everything is a value type or a pure function, so
//  the rules are testable without a renderer — see `TrendsThresholdTests`.
//

import Foundation
import SwiftUI

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
struct ThresholdPoint: Identifiable, Equatable {
    /// `training_log_id`, so a tap can open the workout.
    let id: String
    /// "2026-07-21"
    let date: String
    /// "Jul 21"
    let dateLabel: String
    /// Minutes inside the band, summed across the session.
    let minutes: Double
    /// Minutes of the longest UNBROKEN stretch inside it. Never greater than
    /// `minutes`; equal to it when the work was one continuous block.
    let blockMinutes: Double
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
    /// The band's anchor the week this session was run, sec/mi. The band steps
    /// weekly; the chart draws the latest one, and this is how a point knows
    /// which band it was actually judged against.
    let anchorSec: Int
    let grade: ThresholdGrade

    var isWork: Bool { grade == .work }
    var hasCorrection: Bool { correctionSec > 0 }
    /// True when the in-band time came in pieces rather than one stretch.
    var isFragmented: Bool { blockMinutes + 0.05 < minutes }
}

// MARK: - The read

/// Everything section 04 renders, computed once from a `BandLaps` payload and
/// one `BandSettings`.
struct ThresholdRead {
    /// Every session that cleared the minimums, oldest → newest.
    let points: [ThresholdPoint]
    /// The settings this read was built under. Carried so the view can state
    /// the band it drew rather than restate the rule from its own constants.
    let settings: BandSettings
    /// The anchor, resolved to a colour once — the view never re-derives it.
    let anchorColor: Color
    /// The band's anchor and its two edges at the END of the window, sec/mi.
    /// `fast` is the lower number — faster pace, drawn higher.
    ///
    /// One band is drawn even though the anchor steps weekly: it is the band
    /// she is judged against now. Each point keeps its own `anchorSec` so a
    /// session run against an older, slower anchor is still honestly placed.
    let anchorSec: Int
    let fastSec: Int
    let slowSec: Int
    /// True when the prediction the band is built on is itself low-confidence.
    /// The view dashes the band edges rather than drawing a hard claim.
    let lowConfidence: Bool

    /// Sessions that held time in the band but failed a minimum, and the
    /// minutes they were holding. Reported, never silently dropped.
    let excludedSessions: Int
    let excludedMinutes: Double

    var anchor: BandAnchor { settings.anchor }
    var hrFloor: Int { settings.hrFloor }
    /// True when the athlete is looking at her own band rather than the
    /// shipped one.
    var isAdjusted: Bool { !settings.isDefault }

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

    /// An empty read that still knows what band was asked for — so a section
    /// with no qualifying sessions can say which band found nothing.
    static func empty(settings: BandSettings, ladder: BandLadder? = nil) -> ThresholdRead {
        let anchorSec = ladder.map { settings.anchor.sec(in: $0) } ?? 0
        let edges = settings.edges(anchorSec: anchorSec)
        return ThresholdRead(
            points: [],
            settings: settings,
            anchorColor: settings.anchor.color(in: ladder),
            anchorSec: anchorSec,
            fastSec: edges.fast,
            slowSec: edges.slow,
            lowConfidence: false,
            excludedSessions: 0,
            excludedMinutes: 0
        )
    }
}

// MARK: - Builder

enum ThresholdBuilder {

    /// The heart-rate floor the app ships with.
    ///
    /// 160 bpm comes from the 2026-08-02 audit: across nineteen band sessions
    /// every genuine workout cleared it and every long run that clipped the
    /// slow edge did not. It is a threshold on one athlete's own data, not a
    /// physiological constant — which is precisely why it is now a setting
    /// (`BandSettings.hrFloor`) rather than a constant anyone has to live with.
    /// When the app carries per-athlete HR zones this default wants to become
    /// zone-relative rather than absolute.
    static let defaultHrFloor = BandSettings.default.hrFloor

    // MARK: The adjustable path

    /// Build the read from the raw laps under one set of settings.
    ///
    /// - Parameters:
    ///   - lab: `TrendsService.bandLaps` — every lap of every session in the
    ///     26-week fetch, with each week's race-pace ladder.
    ///   - settings: the athlete's band. Clamped on the way in, so a caller
    ///     cannot ask for a band of negative width.
    ///   - windowDays: the tab's one time control. `nil` reads everything
    ///     loaded — the section never carries a second range of its own.
    static func build(
        lab: BandLaps,
        settings rawSettings: BandSettings,
        windowDays: Int? = nil,
        asOf: Date = Date()
    ) -> ThresholdRead {
        let settings = rawSettings.clamped()
        let shown = lab.windowed(days: windowDays, asOf: asOf)

        guard let latest = shown.latestLadder else {
            return .empty(settings: settings, ladder: lab.latestLadder)
        }

        var points: [ThresholdPoint] = []
        var excludedSessions = 0
        var excludedMinutes = 0.0

        for session in shown.sessions {
            let anchorSec = settings.anchor.sec(in: session.anchors)
            guard anchorSec > 0 else { continue }
            guard let slice = inBand(session: session, settings: settings, anchorSec: anchorSec)
            else { continue }

            // Both gates, and they catch different things — see the file note.
            let clearsTotal = slice.minutes + 0.001 >= settings.minTotalMinutes
            let clearsBlock = slice.blockMinutes + 0.001 >= settings.minBlockMinutes
            guard clearsTotal && clearsBlock else {
                excludedSessions += 1
                excludedMinutes += slice.minutes
                continue
            }

            points.append(
                ThresholdPoint(
                    id: session.id,
                    date: session.date,
                    dateLabel: session.dateLabel,
                    minutes: slice.minutes,
                    blockMinutes: slice.blockMinutes,
                    miles: slice.miles,
                    adjSec: slice.adjSec,
                    rawSec: slice.rawSec,
                    correctionSec: max(0, slice.rawSec - slice.adjSec),
                    hrAvg: slice.hrAvg,
                    dewPointF: session.dewPointF,
                    anchorSec: anchorSec,
                    grade: grade(hr: slice.hrAvg, floor: settings.hrFloor)
                )
            )
        }

        let anchorSec = settings.anchor.sec(in: latest)
        let edges = settings.edges(anchorSec: anchorSec)

        return ThresholdRead(
            points: points,
            settings: settings,
            anchorColor: settings.anchor.color(in: latest),
            anchorSec: anchorSec,
            fastSec: edges.fast,
            slowSec: edges.slow,
            lowConfidence: shown.isLowConfidence,
            excludedSessions: excludedSessions,
            excludedMinutes: excludedMinutes
        )
    }

    /// One session's in-band totals. `nil` when nothing landed in the band at
    /// all — which is a different thing from landing and failing a minimum,
    /// and only the latter is worth reporting as excluded.
    private struct Slice {
        let minutes: Double
        let blockMinutes: Double
        let miles: Double
        let adjSec: Int
        let rawSec: Int
        let hrAvg: Int?
    }

    /// Walk the laps IN ORDER, accumulating the in-band ones and measuring the
    /// longest unbroken run of them.
    ///
    /// Anything that is not in band breaks the block — an out-of-band lap, a
    /// recovery jog, a GPS fragment. That is why the payload ships those laps
    /// flagged instead of removing them: without the breaks in the sequence,
    /// four three-minute touches are indistinguishable from one twelve-minute
    /// effort, and the block gate would pass both.
    private static func inBand(
        session: BandSession,
        settings: BandSettings,
        anchorSec: Int
    ) -> Slice? {
        var seconds = 0.0
        var meters = 0.0
        var adjWeighted = 0.0
        var rawWeighted = 0.0
        var hrWeighted = 0.0
        var hrSeconds = 0.0
        var blockSeconds = 0.0
        var longestBlock = 0.0

        for lap in session.laps {
            let inside = !lap.skip
                && lap.sec > 0
                && settings.contains(paceSec: lap.adjSec, anchorSec: anchorSec)
            guard inside else {
                longestBlock = max(longestBlock, blockSeconds)
                blockSeconds = 0
                continue
            }

            let s = Double(lap.sec)
            seconds += s
            meters += lap.miles
            adjWeighted += Double(lap.adjSec) * s
            rawWeighted += Double(lap.rawSec) * s
            if let hr = lap.hr, hr > 0 {
                hrWeighted += Double(hr) * s
                hrSeconds += s
            }
            blockSeconds += s
        }
        longestBlock = max(longestBlock, blockSeconds)

        guard seconds > 0 else { return nil }
        return Slice(
            minutes: seconds / 60,
            blockMinutes: longestBlock / 60,
            miles: meters,
            adjSec: Int((adjWeighted / seconds).rounded()),
            rawSec: Int((rawWeighted / seconds).rounded()),
            hrAvg: hrSeconds > 0 ? Int((hrWeighted / hrSeconds).rounded()) : nil
        )
    }

    /// The grading rule, isolated so a test can state it in one line.
    ///
    /// A floor of 0 is the athlete saying "I don't train with a strap" — every
    /// in-band minute then counts, including the ones with no reading, because
    /// under that setting the absence of a heart rate is not a missing answer.
    static func grade(hr: Int?, floor: Int) -> ThresholdGrade {
        guard floor > 0 else { return .work }
        guard let hr, hr > 0 else { return .unclassed }
        return hr >= floor ? .work : .cruise
    }

    // MARK: The fixed-band fallback

    /// Build the read from the pre-bucketed `PaceBands` payload.
    ///
    /// Kept for the window between shipping this build and deploying the
    /// `band_laps` half of `trends-timeline`: without it the section goes blank
    /// against an older backend. The band is whatever the server decided, so
    /// the controls are inert on this path and the section says so.
    ///
    /// Delete this, and `PaceBandKey`'s role here, once `band_laps` is live.
    static func build(
        bands: PaceBands,
        band: PaceBandKey = .hm,
        windowDays: Int? = nil,
        hrFloor: Int = defaultHrFloor,
        asOf: Date = Date()
    ) -> ThresholdRead {
        let shown = windowDays.map { bands.windowed(days: $0, asOf: asOf) } ?? bands
        let summary = shown.summary(band)
        let anchor: BandAnchor = band == .hm ? .hmp : .mp
        // The server band, restated as settings so the read has one shape.
        var settings = BandSettings.default
        settings.anchor = anchor
        settings.hrFloor = hrFloor
        settings.minTotalMinutes = 0
        settings.minBlockMinutes = 0

        let points: [ThresholdPoint] = shown.sessions
            .compactMap { session in
                guard let slice = session.slice(band), slice.minutes > 0 else { return nil }
                return ThresholdPoint(
                    id: session.id,
                    date: session.date,
                    dateLabel: session.dateLabel,
                    minutes: slice.minutes,
                    // Un-knowable from a bucketed payload — the laps that would
                    // reveal the block structure are exactly what it dropped.
                    // Reported as the total rather than a guess, and the block
                    // gate is off on this path so nothing is judged on it.
                    blockMinutes: slice.minutes,
                    miles: slice.miles,
                    adjSec: slice.paceAdjSec,
                    rawSec: slice.paceRawSec,
                    correctionSec: max(0, slice.correctionSec),
                    hrAvg: slice.hrAvg,
                    dewPointF: session.dewPointF,
                    anchorSec: session.anchorSec(band),
                    grade: grade(hr: slice.hrAvg, floor: hrFloor)
                )
            }
            .sorted { $0.date < $1.date }

        return ThresholdRead(
            points: points,
            settings: settings,
            anchorColor: anchor.color(in: nil),
            anchorSec: summary.anchorSec,
            fastSec: summary.fastSec,
            slowSec: summary.slowSec,
            lowConfidence: shown.isLowConfidence,
            excludedSessions: 0,
            excludedMinutes: 0
        )
    }
}
