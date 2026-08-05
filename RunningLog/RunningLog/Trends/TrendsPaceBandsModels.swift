//
//  TrendsPaceBandsModels.swift
//  RunningLog · Trends
//
//  The Pace Bands surface's model + wire format. Spec:
//  `outputs/pace-band-surface-spec-2026-08-02.md`; prototype
//  `band-toggle-prototype.html`.
//
//  The question this surface answers: *"am I doing the work at the pace I'm
//  supposed to be doing it at, and what is it costing me?"* — one band at a
//  time. The athlete picks HM or MP; the whole surface re-renders against
//  that anchor.
//
//  Source: `trends-timeline` → `pace_bands`
//  (`supabase/functions/trends-timeline/paceBands.ts`). Two things the model
//  deliberately preserves from the backend:
//
//    • **Membership was decided on heat-adjusted pace.** `paceAdjSec` is what
//      put a lap in the band; `paceRawSec` is what the watch recorded. Both
//      travel, so the view can draw the correction being applied to her
//      rather than silently applying it.
//    • **The two bands can share pace.** `overlapMin` is per session and
//      `PaceBandOverlap` is the window total. The toggle makes the bands
//      legible separately; it does not make them independent, and the surface
//      says so out loud.
//
//  Observation, never prescription: nothing here grades a number, and nothing
//  suggests what to do next.
//

import Foundation
import SwiftUI

// MARK: - Which band

/// The two anchors the surface toggles between.
enum PaceBandKey: String, CaseIterable, Identifiable, Codable {
    case hm
    case mp

    var id: String { rawValue }

    /// Segmented-control label.
    var label: String {
        switch self {
        case .hm: "Half marathon"
        case .mp: "Marathon"
        }
    }

    /// Sentence-case, for inline prose ("Per session · half marathon").
    var proseLabel: String {
        switch self {
        case .hm: "half marathon"
        case .mp: "marathon"
        }
    }

    /// Uppercase token for eyebrows and empty states ("NO HM WORK YET").
    var shortLabel: String {
        switch self {
        case .hm: "HM"
        case .mp: "MP"
        }
    }

    /// Band colour from the canonical pace ramp — HM deeper than MP, because
    /// faster reads deeper. Blue is pace and only pace (three-palette rule).
    ///
    /// NB: the prototype used two off-ramp hexes (`#12294F` / `#4E80AB`) for a
    /// wider gap between the toggle states. We take the canonical
    /// `PaceSpectrum` stops instead — only one band renders at a time, so the
    /// inter-band contrast the prototype was buying isn't load-bearing, and
    /// new hexes outside the ramp are exactly the drift the design system
    /// warns about. Revisit only with a `PaceSpectrum` change.
    var color: Color {
        switch self {
        case .hm: PaceSpectrum.hmp
        case .mp: PaceSpectrum.mp
        }
    }

    var other: PaceBandKey { self == .hm ? .mp : .hm }
}

// MARK: - Models

/// One band's slice of one session — the minutes that landed inside it.
struct PaceBandSlice {
    let minutes: Double
    let miles: Double
    /// The heat-adjusted pace membership was decided on.
    let paceAdjSec: Int
    /// What the watch recorded over the same laps.
    let paceRawSec: Int
    /// `paceRawSec - paceAdjSec`, never negative. Zero when no weather was on
    /// file — the chart then draws no correction stem at all rather than a
    /// zero-length one.
    let correctionSec: Int
    let hrAvg: Int?

    var hasCorrection: Bool { correctionSec > 0 }
}

/// One session on the shared x-axis. Present only when it held at least one
/// of the two bands for more than two minutes.
struct PaceBandSession: Identifiable {
    let id: String          // training_log_id
    let date: String        // "2026-07-21"
    let dateLabel: String   // "Jul 21"
    let longDateLabel: String // "JUL 21 · 2026"
    /// The whole run, in band or not — the constant the in-band bar reads against.
    let sessionMi: Double
    let hm: PaceBandSlice?
    let mp: PaceBandSlice?
    /// Minutes qualifying for BOTH bands. The honesty number.
    let overlapMin: Double
    let dewPointF: Int?
    /// The anchors in force that week — the band steps, it doesn't curve.
    let hmAnchorSec: Int
    let mpAnchorSec: Int

    func slice(_ band: PaceBandKey) -> PaceBandSlice? { band == .hm ? hm : mp }
    func anchorSec(_ band: PaceBandKey) -> Int { band == .hm ? hmAnchorSec : mpAnchorSec }
}

/// Window totals for one band.
struct PaceBandSummary {
    let anchorSec: Int
    let fastSec: Int
    let slowSec: Int
    let sessionCount: Int
    let minutes: Double
    let miles: Double
    let paceAdjSec: Int?
    let hrAvg: Int?

    var isEmpty: Bool { sessionCount == 0 }
}

/// How much pace the two bands share. Non-nil whenever they touched in any
/// week of the window; the note it drives is required and persistent.
struct PaceBandOverlap {
    /// MP anchor − HM anchor, sec/mile. How close the two targets sit.
    let gapSec: Int
    /// Seconds of pace both bands claim at the current anchors.
    let widthSec: Int
    /// Minutes across the window qualifying for both.
    let minutesBoth: Double
    let weeksOverlapping: Int
    let weeksTotal: Int
}

/// The whole surface's data.
struct PaceBands {
    let hm: PaceBandSummary
    let mp: PaceBandSummary
    /// Oldest → newest. The x order for all three lanes; never re-sorted
    /// per-lane, because the vertical alignment IS the point.
    let sessions: [PaceBandSession]
    let overlap: PaceBandOverlap?
    /// high | medium | low | nil, from the most recent fitness snapshot.
    let confidenceTier: String?
    let windowStart: String?
    let windowEnd: String?

    func summary(_ band: PaceBandKey) -> PaceBandSummary { band == .hm ? hm : mp }

    /// Sessions holding work in `band`, oldest → newest. The table and the
    /// marks read this; the x-axis still spans every session, so a session
    /// that's empty in this band keeps its column.
    func sessions(in band: PaceBandKey) -> [PaceBandSession] {
        sessions.filter { $0.slice(band) != nil }
    }

    /// The band is drawn with a dashed outer edge and a LOW CONFIDENCE chip
    /// when the underlying prediction doesn't earn a hard line.
    var isLowConfidence: Bool { (confidenceTier ?? "").lowercased() == "low" }

    /// "23 Mar – 2 Aug", for the eyebrow. Empty when the window is unknown.
    var windowLabel: String {
        guard let s = windowStart, let e = windowEnd,
              let a = Self.shortDate(s), let b = Self.shortDate(e) else { return "" }
        return "\(a) – \(b)"
    }

    private static let monthAbbr = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// "2026-03-23" → "23 Mar".
    private static func shortDate(_ iso: String) -> String? {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), (1...12).contains(m), let d = Int(p[2]) else { return nil }
        return "\(d) \(monthAbbr[m - 1])"
    }
}

// MARK: - Windowing

extension PaceBands {
    /// The same payload narrowed to the trailing `days` window, with **every**
    /// aggregate recomputed over what's left — minutes and miles in band, the
    /// adjusted pace, average HR, session counts, and the overlap minutes.
    ///
    /// Why this is client-side: `trends-timeline` already returns every
    /// qualifying session in its 26-week fetch, so narrowing is a filter, not
    /// a round trip. Changing the Trends range re-slices instantly and never
    /// refetches.
    ///
    /// The anchor is NOT recomputed — it's read off the most recent session in
    /// the window. The band she is judged against is the one in force now; a
    /// shorter window looks at less running, it doesn't change her fitness.
    func windowed(days: Int, asOf: Date = Date()) -> PaceBands {
        guard days > 0 else { return self }
        let cutoff = Self.isoDay(asOf.addingTimeInterval(-Double(days) * 86_400))
        let kept = sessions.filter { $0.date >= cutoff }
        // Nothing dropped — hand back the original rather than rebuilding it.
        if kept.count == sessions.count { return self }
        return PaceBands(
            hm: Self.summarize(.hm, kept, fallback: hm),
            mp: Self.summarize(.mp, kept, fallback: mp),
            sessions: kept,
            overlap: Self.recomputeOverlap(kept, fallback: overlap),
            confidenceTier: confidenceTier,
            windowStart: kept.first?.date,
            windowEnd: kept.last?.date
        )
    }

    /// One band's totals over an arbitrary set of sessions.
    ///
    /// Time-weighted, like the backend: a slice's `minutes` IS its weight, so a
    /// 32-minute tempo can't be averaged against a 3-minute brush as if they
    /// were equal. HR averages only over the slices that carry one, so a
    /// session with no heart-rate data doesn't drag the mean toward zero.
    private static func summarize(
        _ band: PaceBandKey,
        _ sessions: [PaceBandSession],
        fallback: PaceBandSummary
    ) -> PaceBandSummary {
        // The band in force at the end of the window.
        let anchor = sessions.last?.anchorSec(band) ?? fallback.anchorSec
        let fast = Int((Double(anchor) * 0.95).rounded())
        let slow = Int((Double(anchor) * 1.05).rounded())

        let slices = sessions.compactMap { $0.slice(band) }
        guard !slices.isEmpty else {
            return PaceBandSummary(
                anchorSec: anchor, fastSec: fast, slowSec: slow,
                sessionCount: 0, minutes: 0, miles: 0,
                paceAdjSec: nil, hrAvg: nil
            )
        }

        let minutes = slices.reduce(0.0) { $0 + $1.minutes }
        let miles = slices.reduce(0.0) { $0 + $1.miles }
        let paceWeighted = slices.reduce(0.0) { $0 + Double($1.paceAdjSec) * $1.minutes }

        let withHR = slices.compactMap { s -> (Int, Double)? in
            guard let hr = s.hrAvg else { return nil }
            return (hr, s.minutes)
        }
        let hrMinutes = withHR.reduce(0.0) { $0 + $1.1 }
        let hrWeighted = withHR.reduce(0.0) { $0 + Double($1.0) * $1.1 }

        return PaceBandSummary(
            anchorSec: anchor, fastSec: fast, slowSec: slow,
            sessionCount: slices.count,
            minutes: minutes,
            miles: miles,
            paceAdjSec: minutes > 0 ? Int((paceWeighted / minutes).rounded()) : nil,
            hrAvg: hrMinutes > 0 ? Int((hrWeighted / hrMinutes).rounded()) : nil
        )
    }

    /// Overlap for the window: the double-counted minutes are re-summed, and
    /// the gap and shared width are measured at the window's latest anchors.
    ///
    /// Computed symmetrically (min/max rather than assuming MP is the slower
    /// anchor), matching `paceBands.ts` — a stale half prediction can invert
    /// the usual order, and assuming it reports a fat overlap between two
    /// bands that share nothing.
    private static func recomputeOverlap(
        _ sessions: [PaceBandSession],
        fallback: PaceBandOverlap?
    ) -> PaceBandOverlap? {
        guard let fallback, let last = sessions.last else { return nil }
        let minutes = sessions.reduce(0.0) { $0 + $1.overlapMin }
        let hm = Double(last.hmAnchorSec), mp = Double(last.mpAnchorSec)
        let width = min(hm, mp) * 1.05 - max(hm, mp) * 0.95
        // Bands apart now AND no double-counted minutes in the window: there's
        // nothing to warn about, so the note doesn't render at all.
        if width < 0 && minutes <= 0 { return nil }
        return PaceBandOverlap(
            gapSec: last.mpAnchorSec - last.hmAnchorSec,
            widthSec: max(0, Int(width.rounded())),
            minutesBoth: minutes,
            weeksOverlapping: fallback.weeksOverlapping,
            weeksTotal: fallback.weeksTotal
        )
    }

    /// "yyyy-MM-dd" (UTC) — the same key space the payload's `date` uses, so
    /// the cutoff can be compared as a plain string.
    private static func isoDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Wire format

/// The `pace_bands` object from `trends-timeline`. Absent (or null) whenever
/// the athlete has no usable fitness anchor or nothing cleared the in-band
/// gate — the surface hides itself rather than rendering a guessed band.
struct PaceBandsDTO: Decodable {
    let hm: SummaryDTO
    let mp: SummaryDTO
    let sessions: [SessionDTO]
    let overlap: OverlapDTO?
    let confidenceTier: String?
    let windowStart: String?
    let windowEnd: String?

    enum CodingKeys: String, CodingKey {
        case hm, mp, sessions, overlap
        case confidenceTier = "confidence_tier"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }

    struct SummaryDTO: Decodable {
        let anchorSec: Int
        let fastSec: Int
        let slowSec: Int
        let sessions: Int
        let minutes: Double
        let miles: Double
        let paceAdjSec: Int?
        let hrAvg: Int?

        enum CodingKeys: String, CodingKey {
            case anchorSec = "anchor_sec"
            case fastSec = "fast_sec"
            case slowSec = "slow_sec"
            case sessions, minutes, miles
            case paceAdjSec = "pace_adj_sec"
            case hrAvg = "hr_avg"
        }

        func toModel() -> PaceBandSummary {
            PaceBandSummary(
                anchorSec: anchorSec, fastSec: fastSec, slowSec: slowSec,
                sessionCount: sessions, minutes: minutes, miles: miles,
                paceAdjSec: paceAdjSec, hrAvg: hrAvg
            )
        }
    }

    struct SliceDTO: Decodable {
        let minutes: Double
        let miles: Double
        let paceAdjSec: Int
        let paceRawSec: Int
        let correctionSec: Int
        let hrAvg: Int?

        enum CodingKeys: String, CodingKey {
            case minutes, miles
            case paceAdjSec = "pace_adj_sec"
            case paceRawSec = "pace_raw_sec"
            case correctionSec = "correction_sec"
            case hrAvg = "hr_avg"
        }

        func toModel() -> PaceBandSlice {
            PaceBandSlice(
                minutes: minutes, miles: miles,
                paceAdjSec: paceAdjSec, paceRawSec: paceRawSec,
                correctionSec: max(0, correctionSec), hrAvg: hrAvg
            )
        }
    }

    struct SessionDTO: Decodable {
        let date: String
        let logId: String
        let sessionMi: Double
        let hm: SliceDTO?
        let mp: SliceDTO?
        let overlapMin: Double
        let dewPointF: Double?
        let hmAnchorSec: Int
        let mpAnchorSec: Int

        enum CodingKeys: String, CodingKey {
            case date
            case logId = "log_id"
            case sessionMi = "session_mi"
            case hm, mp
            case overlapMin = "overlap_min"
            case dewPointF = "dew_point_f"
            case hmAnchorSec = "hm_anchor_sec"
            case mpAnchorSec = "mp_anchor_sec"
        }

        private static let monthAbbr = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]

        /// "2026-07-21" → ("Jul 21", "JUL 21 · 2026"). Falls back to the raw
        /// string rather than inventing a date.
        private var labels: (String, String) {
            let p = date.split(separator: "-")
            guard p.count == 3, let m = Int(p[1]), (1...12).contains(m),
                  let d = Int(p[2]) else { return (date, date.uppercased()) }
            let mon = Self.monthAbbr[m - 1]
            return ("\(mon) \(d)", "\(mon.uppercased()) \(d) · \(p[0])")
        }

        func toModel() -> PaceBandSession {
            let (short, long) = labels
            return PaceBandSession(
                id: logId, date: date, dateLabel: short, longDateLabel: long,
                sessionMi: sessionMi,
                hm: hm?.toModel(), mp: mp?.toModel(),
                overlapMin: overlapMin,
                dewPointF: dewPointF.map { Int($0.rounded()) },
                hmAnchorSec: hmAnchorSec, mpAnchorSec: mpAnchorSec
            )
        }
    }

    struct OverlapDTO: Decodable {
        let gapSec: Int
        let widthSec: Int
        let minutesBoth: Double
        let weeksOverlapping: Int
        let weeksTotal: Int

        enum CodingKeys: String, CodingKey {
            case gapSec = "gap_sec"
            case widthSec = "width_sec"
            case minutesBoth = "minutes_both"
            case weeksOverlapping = "weeks_overlapping"
            case weeksTotal = "weeks_total"
        }

        func toModel() -> PaceBandOverlap {
            PaceBandOverlap(
                gapSec: gapSec, widthSec: widthSec, minutesBoth: minutesBoth,
                weeksOverlapping: weeksOverlapping, weeksTotal: weeksTotal
            )
        }
    }

    func toModel() -> PaceBands {
        PaceBands(
            hm: hm.toModel(), mp: mp.toModel(),
            sessions: sessions.map { $0.toModel() },
            overlap: overlap?.toModel(),
            confidenceTier: confidenceTier,
            windowStart: windowStart, windowEnd: windowEnd
        )
    }
}

// MARK: - Preview data

extension PaceBands {
    /// The 19 qualifying sessions from the live RunningAppMVP2 window
    /// (23 Mar – 2 Aug 2026) the spec was built and validated against. Used by
    /// `#Preview` so the surface is reviewable in Xcode without a network
    /// call. Raw paces and dew points here are the prototype's illustrative
    /// corrections, not measured values — the live payload carries the real
    /// ones.
    static let preview = PaceBands(
        hm: PaceBandSummary(anchorSec: 323, fastSec: 307, slowSec: 339,
                            sessionCount: 14, minutes: 239.5, miles: 45.15,
                            paceAdjSec: 318, hrAvg: 165),
        mp: PaceBandSummary(anchorSec: 338, fastSec: 321, slowSec: 355,
                            sessionCount: 8, minutes: 79.4, miles: 13.51,
                            paceAdjSec: 353, hrAvg: 166),
        sessions: previewSessions,
        overlap: PaceBandOverlap(gapSec: 15, widthSec: 18, minutesBoth: 46.9,
                                 weeksOverlapping: 20, weeksTotal: 20),
        confidenceTier: "medium",
        windowStart: "2026-03-31", windowEnd: "2026-08-01"
    )

    /// The same window with the MP band emptied out — exercises the
    /// band-empty state without inventing a second athlete.
    static let previewEmptyMP = PaceBands(
        hm: preview.hm,
        mp: PaceBandSummary(anchorSec: 338, fastSec: 321, slowSec: 355,
                            sessionCount: 0, minutes: 0, miles: 0,
                            paceAdjSec: nil, hrAvg: nil),
        sessions: previewSessions.map {
            PaceBandSession(id: $0.id, date: $0.date, dateLabel: $0.dateLabel,
                            longDateLabel: $0.longDateLabel, sessionMi: $0.sessionMi,
                            hm: $0.hm, mp: nil, overlapMin: 0, dewPointF: $0.dewPointF,
                            hmAnchorSec: $0.hmAnchorSec, mpAnchorSec: $0.mpAnchorSec)
        },
        // No MP minutes anywhere in this fixture, so no overlap either — the
        // note must not contradict the data it sits under.
        overlap: nil,
        confidenceTier: "low",
        windowStart: "2026-03-31", windowEnd: "2026-08-01"
    )

    private static let previewSessions: [PaceBandSession] = [
        .init(id: "s-03-31", date: "2026-03-31", dateLabel: "Mar 31", longDateLabel: "MAR 31 · 2026",
              sessionMi: 10.3, hm: .init(minutes: 15.9, miles: 3.05, paceAdjSec: 313, paceRawSec: 313, correctionSec: 0, hrAvg: 168), mp: nil,
              overlapMin: 0, dewPointF: 44, hmAnchorSec: 324, mpAnchorSec: 339),
        .init(id: "s-04-04", date: "2026-04-04", dateLabel: "Apr 4", longDateLabel: "APR 4 · 2026",
              sessionMi: 12.3, hm: .init(minutes: 32.2, miles: 6.15, paceAdjSec: 314, paceRawSec: 314, correctionSec: 0, hrAvg: 168), mp: nil,
              overlapMin: 0, dewPointF: 46, hmAnchorSec: 324, mpAnchorSec: 339),
        .init(id: "s-04-07", date: "2026-04-07", dateLabel: "Apr 7", longDateLabel: "APR 7 · 2026",
              sessionMi: 12.1, hm: .init(minutes: 15.2, miles: 2.89, paceAdjSec: 316, paceRawSec: 316, correctionSec: 0, hrAvg: 164), mp: nil,
              overlapMin: 0, dewPointF: 48, hmAnchorSec: 324, mpAnchorSec: 339),
        .init(id: "s-04-12", date: "2026-04-12", dateLabel: "Apr 12", longDateLabel: "APR 12 · 2026",
              sessionMi: 9.8, hm: .init(minutes: 31.7, miles: 6.12, paceAdjSec: 311, paceRawSec: 311, correctionSec: 0, hrAvg: 158), mp: nil,
              overlapMin: 0, dewPointF: 45, hmAnchorSec: 324, mpAnchorSec: 339),
        .init(id: "s-04-28", date: "2026-04-28", dateLabel: "Apr 28", longDateLabel: "APR 28 · 2026",
              sessionMi: 8.0, hm: .init(minutes: 18.1, miles: 3.32, paceAdjSec: 327, paceRawSec: 330, correctionSec: 3, hrAvg: 168), mp: nil,
              overlapMin: 3.0, dewPointF: 52, hmAnchorSec: 330, mpAnchorSec: 345),
        .init(id: "s-05-05", date: "2026-05-05", dateLabel: "May 5", longDateLabel: "MAY 5 · 2026",
              sessionMi: 9.9, hm: .init(minutes: 5.4, miles: 1.01, paceAdjSec: 320, paceRawSec: 324, correctionSec: 4, hrAvg: 168), mp: nil,
              overlapMin: 0, dewPointF: 55, hmAnchorSec: 330, mpAnchorSec: 345),
        .init(id: "s-05-15", date: "2026-05-15", dateLabel: "May 15", longDateLabel: "MAY 15 · 2026",
              sessionMi: 11.7, hm: .init(minutes: 13.8, miles: 2.54, paceAdjSec: 326, paceRawSec: 331, correctionSec: 5, hrAvg: 149), mp: nil,
              overlapMin: 0, dewPointF: 57, hmAnchorSec: 340, mpAnchorSec: 356),
        .init(id: "s-05-16", date: "2026-05-16", dateLabel: "May 16", longDateLabel: "MAY 16 · 2026",
              sessionMi: 15.0, hm: nil, mp: .init(minutes: 6.2, miles: 1.02, paceAdjSec: 364, paceRawSec: 370, correctionSec: 6, hrAvg: 166),
              overlapMin: 0, dewPointF: 58, hmAnchorSec: 340, mpAnchorSec: 356),
        .init(id: "s-05-24", date: "2026-05-24", dateLabel: "May 24", longDateLabel: "MAY 24 · 2026",
              sessionMi: 14.0, hm: nil, mp: .init(minutes: 3.7, miles: 0.63, paceAdjSec: 354, paceRawSec: 360, correctionSec: 6, hrAvg: 173),
              overlapMin: 0, dewPointF: 60, hmAnchorSec: 340, mpAnchorSec: 356),
        .init(id: "s-05-28", date: "2026-05-28", dateLabel: "May 28", longDateLabel: "MAY 28 · 2026",
              sessionMi: 12.4, hm: nil, mp: .init(minutes: 18.2, miles: 3.10, paceAdjSec: 352, paceRawSec: 359, correctionSec: 7, hrAvg: 169),
              overlapMin: 0, dewPointF: 61, hmAnchorSec: 340, mpAnchorSec: 356),
        .init(id: "s-06-02", date: "2026-06-02", dateLabel: "Jun 2", longDateLabel: "JUN 2 · 2026",
              sessionMi: 7.6, hm: .init(minutes: 6.6, miles: 1.24, paceAdjSec: 320, paceRawSec: 328, correctionSec: 8, hrAvg: 176), mp: nil,
              overlapMin: 3.4, dewPointF: 62, hmAnchorSec: 335, mpAnchorSec: 351),
        .init(id: "s-06-06", date: "2026-06-06", dateLabel: "Jun 6", longDateLabel: "JUN 6 · 2026",
              sessionMi: 11.4, hm: nil, mp: .init(minutes: 14.7, miles: 2.49, paceAdjSec: 354, paceRawSec: 363, correctionSec: 9, hrAvg: 169),
              overlapMin: 0, dewPointF: 64, hmAnchorSec: 335, mpAnchorSec: 351),
        .init(id: "s-06-09", date: "2026-06-09", dateLabel: "Jun 9", longDateLabel: "JUN 9 · 2026",
              sessionMi: 9.2, hm: .init(minutes: 16.5, miles: 3.00, paceAdjSec: 330, paceRawSec: 339, correctionSec: 9, hrAvg: 164),
              mp: .init(minutes: 6.0, miles: 1.01, paceAdjSec: 358, paceRawSec: 367, correctionSec: 9, hrAvg: 165),
              overlapMin: 5.6, dewPointF: 65, hmAnchorSec: 335, mpAnchorSec: 351),
        .init(id: "s-06-17", date: "2026-06-17", dateLabel: "Jun 17", longDateLabel: "JUN 17 · 2026",
              sessionMi: 14.4, hm: .init(minutes: 9.9, miles: 1.86, paceAdjSec: 320, paceRawSec: 330, correctionSec: 10, hrAvg: 168), mp: nil,
              overlapMin: 0, dewPointF: 66, hmAnchorSec: 330, mpAnchorSec: 345),
        .init(id: "s-06-23", date: "2026-06-23", dateLabel: "Jun 23", longDateLabel: "JUN 23 · 2026",
              sessionMi: 15.7, hm: .init(minutes: 3.5, miles: 0.63, paceAdjSec: 331, paceRawSec: 342, correctionSec: 11, hrAvg: 166),
              mp: .init(minutes: 3.7, miles: 0.64, paceAdjSec: 345, paceRawSec: 356, correctionSec: 11, hrAvg: 155),
              overlapMin: 7.2, dewPointF: 67, hmAnchorSec: 330, mpAnchorSec: 345),
        .init(id: "s-07-08", date: "2026-07-08", dateLabel: "Jul 8", longDateLabel: "JUL 8 · 2026",
              sessionMi: 12.5, hm: .init(minutes: 6.2, miles: 1.16, paceAdjSec: 320, paceRawSec: 332, correctionSec: 12, hrAvg: 165), mp: nil,
              overlapMin: 0, dewPointF: 69, hmAnchorSec: 325, mpAnchorSec: 340),
        .init(id: "s-07-21", date: "2026-07-21", dateLabel: "Jul 21", longDateLabel: "JUL 21 · 2026",
              sessionMi: 14.2, hm: .init(minutes: 32.8, miles: 6.15, paceAdjSec: 320, paceRawSec: 334, correctionSec: 14, hrAvg: 166), mp: nil,
              overlapMin: 16.6, dewPointF: 71, hmAnchorSec: 325, mpAnchorSec: 340),
        .init(id: "s-07-28", date: "2026-07-28", dateLabel: "Jul 28", longDateLabel: "JUL 28 · 2026",
              sessionMi: 13.9, hm: .init(minutes: 31.7, miles: 6.04, paceAdjSec: 315, paceRawSec: 328, correctionSec: 13, hrAvg: 166),
              mp: .init(minutes: 2.9, miles: 0.52, paceAdjSec: 335, paceRawSec: 348, correctionSec: 13, hrAvg: 163),
              overlapMin: 11.1, dewPointF: 70, hmAnchorSec: 325, mpAnchorSec: 340),
        .init(id: "s-08-01", date: "2026-08-01", dateLabel: "Aug 1", longDateLabel: "AUG 1 · 2026",
              sessionMi: 16.5, hm: nil, mp: .init(minutes: 24.0, miles: 4.10, paceAdjSec: 351, paceRawSec: 364, correctionSec: 13, hrAvg: 163),
              overlapMin: 0, dewPointF: 70, hmAnchorSec: 323, mpAnchorSec: 338),
    ]
}
