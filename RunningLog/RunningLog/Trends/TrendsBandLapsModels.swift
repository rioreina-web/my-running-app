//
//  TrendsBandLapsModels.swift
//  RunningLog · Trends
//
//  The substrate behind an *adjustable* pace band, and the settings that
//  adjust it.
//
//  **Why this exists alongside `TrendsPaceBandsModels`.** `PaceBands` arrives
//  pre-bucketed: the server decided membership at HM ±5% / MP ±5% and shipped
//  the answer. That is exactly right for a surface whose band is fixed, and
//  useless for one whose band is a control — you cannot widen a band when the
//  laps outside it were never sent, and you cannot re-anchor on LT or 10K when
//  the only anchors on the wire are HM and MP.
//
//  `band_laps` ships the question instead: every lap of every session, in the
//  order it was run, plus the full race-pace ladder that was in force that
//  week. Membership, width, minimum duration and the effort floor all become
//  decisions made here, on device, between frames. Source:
//  `supabase/functions/trends-timeline/bandLaps.ts`.
//
//  Two things the model deliberately preserves from the backend:
//
//    • **Order, including the breaks.** Rest laps and GPS fragments arrive
//      flagged rather than removed. A "longest unbroken block" gate is
//      meaningless without them — filter the recovery jogs out and four
//      separate three-minute touches read as one twelve-minute block, which is
//      the exact misread the gate exists to prevent.
//    • **Two paces per lap.** `adj` is the heat-neutral pace membership is
//      decided on; `raw` is what the watch said. Both travel, so the view can
//      draw the correction rather than silently applying it.
//

import Foundation
import SwiftUI

// MARK: - The anchor

/// What the band sits on.
///
/// The race-pace half of the canonical ten-zone taxonomy (CLAUDE.md), plus a
/// free-typed pace for a one-off boundary. Easy / Moderate / Steady are
/// deliberately absent: an Easy anchor with a skirt on it puts most of a
/// training week "in band", which is true and tells the athlete nothing.
///
/// `custom` is a fixed sec/mile the athlete typed. It does NOT move with
/// fitness — that's the trade for being able to ask an exact question, and the
/// controls say so.
enum BandAnchor: Hashable {
    case mp
    case hmp
    case lt
    case k10
    case k5
    case k3
    case mile
    case custom(Int)

    /// The zone chips, in taxonomy order — slowest anchor first.
    static let zones: [BandAnchor] = [.mp, .hmp, .lt, .k10, .k5, .k3, .mile]

    var isCustom: Bool { if case .custom = self { return true }; return false }

    /// Chip label.
    var label: String {
        switch self {
        case .mp: "MP"
        case .hmp: "HMP"
        case .lt: "LT"
        case .k10: "10K"
        case .k5: "5K"
        case .k3: "3K"
        case .mile: "MILE"
        case .custom(let sec): TrendsFormat.pace(sec)
        }
    }

    /// Sentence-case, for inline prose ("…inside the 1-hour race band").
    var proseLabel: String {
        switch self {
        case .mp: "marathon"
        case .hmp: "half marathon"
        case .lt: "1-hour race"
        case .k10: "10K"
        case .k5: "5K"
        case .k3: "3K"
        case .mile: "mile"
        case .custom(let sec): "\(TrendsFormat.pace(sec))"
        }
    }

    /// The one-line gloss under the chip row, so "LT" never has to be known.
    var gloss: String? {
        switch self {
        case .lt: "1-hour race pace, interpolated between 10K and half"
        case .custom: "a pace you set — it stays put as your fitness moves"
        default: nil
        }
    }

    /// This anchor's pace in a given week's ladder, sec/mile.
    func sec(in ladder: BandLadder) -> Int {
        switch self {
        case .mp: ladder.mp
        case .hmp: ladder.hmp
        case .lt: ladder.lt
        case .k10: ladder.k10
        case .k5: ladder.k5
        case .k3: ladder.k3
        case .mile: ladder.mile
        case .custom(let sec): sec
        }
    }

    /// Band colour from the canonical pace ramp — faster reads deeper. Blue is
    /// pace and only pace (three-palette rule). A typed pace is placed on the
    /// same ramp by where it falls in the athlete's own ladder, so a custom
    /// 10K-ish pace is the same blue as the 10K chip rather than a new hue.
    func color(in ladder: BandLadder?) -> Color {
        switch self {
        case .mp: return PaceSpectrum.mp
        case .hmp: return PaceSpectrum.hmp
        case .lt: return PaceSpectrum.lt
        case .k10: return PaceSpectrum.tenK
        case .k5: return PaceSpectrum.fiveK
        case .k3: return PaceSpectrum.threeK
        case .mile: return PaceSpectrum.mile
        case .custom(let sec):
            guard let ladder, ladder.mp > ladder.mile else { return PaceSpectrum.lt }
            return PaceSpectrum.color(
                forPaceSec: Double(sec),
                slowSec: Double(ladder.mp),
                fastSec: Double(ladder.mile)
            )
        }
    }
}

// MARK: Anchor · persistence token

extension BandAnchor: Codable {
    /// "lt" / "k10" / "custom:335". A flat string so the settings blob stays
    /// readable in UserDefaults and survives a case being added later.
    var token: String {
        switch self {
        case .mp: "mp"
        case .hmp: "hmp"
        case .lt: "lt"
        case .k10: "k10"
        case .k5: "k5"
        case .k3: "k3"
        case .mile: "mile"
        case .custom(let sec): "custom:\(sec)"
        }
    }

    init?(token: String) {
        if token.hasPrefix("custom:") {
            guard let sec = Int(token.dropFirst("custom:".count)), sec > 0 else { return nil }
            self = .custom(sec)
            return
        }
        switch token {
        case "mp": self = .mp
        case "hmp": self = .hmp
        case "lt": self = .lt
        case "k10": self = .k10
        case "k5": self = .k5
        case "k3": self = .k3
        case "mile": self = .mile
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // An unknown token is a settings blob from a newer build, not a reason
        // to lose every other setting alongside it.
        self = BandAnchor(token: raw) ?? .hmp
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(token)
    }
}

// MARK: - The ladder

/// One week's race-pace anchors, sec/mile. Fastest is `mile`, slowest is `mp`.
struct BandLadder: Equatable, Decodable {
    let mp: Int
    let hmp: Int
    let lt: Int
    let k10: Int
    let k5: Int
    let k3: Int
    let mile: Int
}

// MARK: - Laps and sessions

/// One lap, in the order it was run.
struct BandLap: Equatable {
    /// Moving seconds — the weight behind every average.
    let sec: Int
    let miles: Double
    /// Heat-neutral pace, sec/mile. What membership is decided on.
    let adjSec: Int
    /// What the watch recorded, sec/mile.
    let rawSec: Int
    let hr: Int?
    /// A recovery lap, a GPS fragment, or otherwise unable to hold a band.
    /// Never in band at any width — and it BREAKS a continuous block.
    let skip: Bool
}

/// One session, with its laps and the ladder in force the week it was run.
struct BandSession: Identifiable, Equatable {
    /// `training_log_id`, so a tap can open the workout.
    let id: String
    let date: String        // "2026-07-21"
    let dateLabel: String   // "Jul 21"
    /// The whole run, in band or not.
    let sessionMiles: Double
    let dewPointF: Int?
    let anchors: BandLadder
    /// `lap_index` order. Never re-sorted: the sequence IS the block structure.
    let laps: [BandLap]
}

/// The whole `band_laps` payload.
struct BandLaps: Equatable {
    /// Oldest → newest.
    let sessions: [BandSession]
    /// high | medium | low | nil, from the most recent fitness snapshot.
    let confidenceTier: String?
    let windowStart: String?
    let windowEnd: String?

    var isEmpty: Bool { sessions.isEmpty }

    /// The band is drawn with dashed edges when the prediction it rests on
    /// doesn't earn a hard line.
    var isLowConfidence: Bool { (confidenceTier ?? "").lowercased() == "low" }

    /// The ladder in force at the end of the window — the band the athlete is
    /// judged against *now*. Nil when the window holds nothing.
    var latestLadder: BandLadder? { sessions.last?.anchors }

    /// Narrowed to the trailing `days`. Pure filter — `trends-timeline` already
    /// returned the full 26 weeks, so changing the Trends range re-slices
    /// instantly and never refetches.
    func windowed(days: Int?, asOf: Date = Date()) -> BandLaps {
        guard let days, days > 0 else { return self }
        let cutoff = Self.isoDay(asOf.addingTimeInterval(-Double(days) * 86_400))
        let kept = sessions.filter { $0.date >= cutoff }
        if kept.count == sessions.count { return self }
        return BandLaps(
            sessions: kept,
            confidenceTier: confidenceTier,
            windowStart: kept.first?.date,
            windowEnd: kept.last?.date
        )
    }

    /// "yyyy-MM-dd" (UTC) — the same key space `date` uses, so the cutoff can
    /// be compared as a plain string.
    static func isoDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Wire format

/// The `band_laps` object from `trends-timeline`. Absent (or null) whenever the
/// athlete has no usable fitness anchor or no session carried a usable lap —
/// the section then falls back to the fixed-band read rather than offering
/// controls over nothing.
struct BandLapsDTO: Decodable {
    let sessions: [SessionDTO]
    let confidenceTier: String?
    let windowStart: String?
    let windowEnd: String?

    enum CodingKeys: String, CodingKey {
        case sessions
        case confidenceTier = "confidence_tier"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }

    struct LapDTO: Decodable {
        let sec: Double
        let mi: Double
        let adj: Int
        let raw: Int
        let hr: Int?
        let skip: Bool

        func toModel() -> BandLap {
            BandLap(
                sec: Int(sec.rounded()),
                miles: mi,
                adjSec: adj,
                rawSec: raw,
                hr: hr,
                skip: skip
            )
        }
    }

    struct SessionDTO: Decodable {
        let date: String
        let logId: String
        let sessionMi: Double
        let dewPointF: Double?
        let anchors: BandLadder
        let laps: [LapDTO]

        enum CodingKeys: String, CodingKey {
            case date, anchors, laps
            case logId = "log_id"
            case sessionMi = "session_mi"
            case dewPointF = "dew_point_f"
        }

        private static let monthAbbr = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]

        /// "2026-07-21" → "Jul 21". Falls back to the raw string rather than
        /// inventing a date.
        private var shortLabel: String {
            let p = date.split(separator: "-")
            guard p.count == 3, let m = Int(p[1]), (1...12).contains(m),
                  let d = Int(p[2]) else { return date }
            return "\(Self.monthAbbr[m - 1]) \(d)"
        }

        func toModel() -> BandSession {
            BandSession(
                id: logId,
                date: date,
                dateLabel: shortLabel,
                sessionMiles: sessionMi,
                dewPointF: dewPointF.map { Int($0.rounded()) },
                anchors: anchors,
                laps: laps.map { $0.toModel() }
            )
        }
    }

    func toModel() -> BandLaps {
        BandLaps(
            sessions: sessions.map { $0.toModel() },
            confidenceTier: confidenceTier,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }
}

// MARK: - Preview data

extension BandLaps {

    /// A window shaped like the live RunningAppMVP2 athlete's — HM 5:23, MP
    /// 5:38 — so `#Preview` and the tests exercise the real cases rather than
    /// a tidy one: continuous tempo blocks, interval sets broken by recovery,
    /// long runs that clip the slow edge at low heart rate, one session with
    /// no heart rate at all, and one three-minute drive-by that both minimums
    /// exist to hold out.
    static let preview: BandLaps = {
        let sessions: [BandSession] = [
            // A continuous tempo: 6 unbroken miles just inside the HM band.
            session("2026-04-04", "Apr 4", miles: 12.3, dew: 46, ladder: .previewLadder, laps: [
                (1.0, 400, 400, 148, false), // warm-up, well outside
                (1.0, 316, 316, 167, false),
                (1.0, 314, 314, 168, false),
                (1.0, 313, 313, 169, false),
                (1.0, 315, 315, 168, false),
                (1.0, 312, 312, 170, false),
                (1.0, 318, 318, 169, false),
                (1.2, 420, 420, 142, false), // cool-down
            ]),
            // Intervals: 5 × 1mi at 10K, recovery jogs between. Twelve minutes
            // of nothing longer than a rep — the block gate's whole point.
            session("2026-04-12", "Apr 12", miles: 9.8, dew: 45, ladder: .previewLadder, laps: [
                (1.5, 430, 430, 140, false),
                (1.0, 308, 308, 172, false),
                (0.4, 480, 480, 150, true),
                (1.0, 306, 306, 174, false),
                (0.4, 485, 485, 151, true),
                (1.0, 310, 310, 175, false),
                (0.4, 482, 482, 152, true),
                (1.0, 305, 305, 176, false),
                (0.4, 486, 486, 153, true),
                (1.0, 309, 309, 177, false),
                (1.4, 440, 440, 145, false),
            ]),
            // A long run clipping the slow edge four times, three minutes each.
            // Clears a twelve-minute total; fails a five-minute block.
            session("2026-04-28", "Apr 28", miles: 16.0, dew: 52, ladder: .previewLadder, laps: [
                (3.0, 420, 424, 143, false),
                (0.6, 334, 337, 152, false),
                (2.0, 415, 419, 145, false),
                (0.6, 336, 339, 153, false),
                (2.0, 418, 422, 146, false),
                (0.6, 335, 338, 154, false),
                (2.0, 416, 420, 147, false),
                (0.6, 337, 340, 155, false),
                (4.6, 425, 429, 148, false),
            ]),
            // A three-minute drive-by. Under both minimums, over none.
            session("2026-05-05", "May 5", miles: 9.9, dew: 55, ladder: .previewLadder, laps: [
                (2.0, 430, 434, 141, false),
                (0.55, 320, 324, 168, false),
                (7.3, 428, 432, 144, false),
            ]),
            // A hot tempo: 20 min, and the heat correction is worth 14 s/mi.
            session("2026-05-15", "May 15", miles: 11.7, dew: 68, ladder: .previewLadderMay, laps: [
                (2.0, 435, 449, 144, false),
                (1.0, 326, 340, 165, false),
                (1.0, 328, 342, 166, false),
                (1.0, 325, 339, 167, false),
                (1.0, 327, 341, 168, false),
                (5.6, 440, 454, 148, false),
            ]),
            // Cruise: in the band on pace, under the floor on effort.
            session("2026-05-28", "May 28", miles: 12.4, dew: 61, ladder: .previewLadderMay, laps: [
                (2.0, 420, 431, 140, false),
                (3.0, 333, 344, 149, false),
                (3.0, 335, 346, 151, false),
                (4.4, 425, 436, 145, false),
            ]),
            // No heart rate anywhere — ungradeable, and not guessed.
            session("2026-06-09", "Jun 9", miles: 9.2, dew: 65, ladder: .previewLadderJun, laps: [
                (1.5, 430, 442, nil, false),
                (2.0, 322, 334, nil, false),
                (2.0, 324, 336, nil, false),
                (3.7, 428, 440, nil, false),
            ]),
            session("2026-06-17", "Jun 17", miles: 14.4, dew: 66, ladder: .previewLadderJun, laps: [
                (2.0, 425, 438, 146, false),
                (1.0, 318, 331, 168, false),
                (1.0, 320, 333, 169, false),
                (1.0, 317, 330, 170, false),
                (9.4, 430, 443, 149, false),
            ]),
            session("2026-07-08", "Jul 8", miles: 12.5, dew: 69, ladder: .previewLadderJul, laps: [
                (2.0, 428, 442, 145, false),
                (1.2, 320, 334, 166, false),
                (9.3, 432, 446, 148, false),
            ]),
            // The best session of the block: 6 mi unbroken, and quickest.
            session("2026-07-21", "Jul 21", miles: 14.2, dew: 71, ladder: .previewLadderJul, laps: [
                (2.0, 430, 445, 146, false),
                (1.0, 314, 328, 165, false),
                (1.0, 312, 326, 166, false),
                (1.0, 313, 327, 167, false),
                (1.0, 311, 325, 167, false),
                (1.0, 315, 329, 168, false),
                (1.0, 316, 330, 168, false),
                (6.2, 435, 450, 149, false),
            ]),
            session("2026-08-01", "Aug 1", miles: 16.5, dew: 70, ladder: .previewLadderJul, laps: [
                (3.0, 432, 447, 147, false),
                (2.0, 313, 327, 164, false),
                (2.0, 315, 329, 165, false),
                (9.5, 436, 451, 150, false),
            ]),
        ]
        return BandLaps(
            sessions: sessions,
            confidenceTier: "medium",
            windowStart: sessions.first?.date,
            windowEnd: sessions.last?.date
        )
    }()

    /// `(miles, adjSec, rawSec, hr, isRestOrFragment)` → a session. Moving time
    /// is derived from distance and raw pace, so the fixture can't hold a lap
    /// whose clock contradicts its pace.
    static func session(
        _ date: String,
        _ label: String,
        miles: Double,
        dew: Int?,
        ladder: BandLadder,
        laps: [(Double, Int, Int, Int?, Bool)]
    ) -> BandSession {
        BandSession(
            id: "preview-\(date)",
            date: date,
            dateLabel: label,
            sessionMiles: miles,
            dewPointF: dew,
            anchors: ladder,
            laps: laps.map { mi, adj, raw, hr, skip in
                BandLap(
                    sec: Int((mi * Double(raw)).rounded()),
                    miles: mi,
                    adjSec: adj,
                    rawSec: raw,
                    hr: hr,
                    skip: skip
                )
            }
        )
    }
}

extension BandLadder {
    /// HM 5:23 / MP 5:38 — the live athlete's spring ladder. LT, 10K, 5K, 3K
    /// and mile are what `derivePaceTableFromGoal` returns for that half.
    static let previewLadder = BandLadder(
        mp: 339, hmp: 324, lt: 322, k10: 310, k5: 299, k3: 287, mile: 269
    )
    /// Mid-block, fitness dipped slightly.
    static let previewLadderMay = BandLadder(
        mp: 345, hmp: 330, lt: 328, k10: 316, k5: 304, k3: 292, mile: 274
    )
    static let previewLadderJun = BandLadder(
        mp: 340, hmp: 325, lt: 323, k10: 311, k5: 300, k3: 288, mile: 270
    )
    static let previewLadderJul = BandLadder(
        mp: 338, hmp: 323, lt: 321, k10: 309, k5: 298, k3: 286, mile: 268
    )
}
