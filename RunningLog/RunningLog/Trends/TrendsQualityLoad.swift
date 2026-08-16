//
//  TrendsQualityLoad.swift
//  RunningLog
//
//  The effort score behind the Key Sessions grid, plus the calendar maths
//  the grid's y-axis needs. Pure — no view code, no IO — so the numbers can
//  be tested directly (see `TrendsQualityLoadTests`).
//
//  QUALITY LOAD
//  ------------
//  A session's effort is the SUM over its work bouts of
//  `seconds × zoneWeight`, expressed in weighted minutes. The weights are
//  the canonical 1–5 intensity scale that already exists in
//  `supabase/functions/_shared/workoutSegmentation.ts` (`ZONE_WEIGHTS`,
//  decision 2026-06-12) — this is a mirror of that table, not a new one.
//  Keep the two in sync; `TrendsQualityLoadTests` pins the values.
//
//  It is deliberately a SUM, not an average. The retired whole-workout
//  `intensity_score` divided the same weighted sum by total time, which
//  `_shared/quality-volume.ts` documents at length as broken: it booked a
//  rep session's warmup, floats and cooldown as quality, while a long run
//  with a 4-mile MP block scored zero because the easy miles dragged the
//  average under the cutoff. Integrating instead of averaging is the fix.
//
//  THE FLOOR
//  ---------
//  `floor` decides whether a session counts as a key session at all.
//  Calibrated 2026-07-27 against 23 real lap-scored sessions in prod:
//
//      stride sets            5.4, 6.4, 11.7, 13.1
//      ── nothing in between ──
//      smallest real session  42.1  (1K + 200/400s)
//      largest real session  103.5  (6×1mi @ 5:12)
//
//  The gap between 13.1 and 42.1 is empty, so any floor from 15 to 40
//  produces the identical split — 19 kept, 4 cut, all four unambiguously
//  strides, zero real sessions lost. 25 sits mid-gap.
//
//  Worth knowing before tuning it: across those sessions quality load
//  correlates 0.965 with plain work-duration, because the mp→mile weight
//  spread is only 2× while work duration spans 30×. For the GATE alone a
//  duration floor (≥ 5 min of work) gives the same answer. The weights
//  earn their keep on the grid, where dot size spans a visible 1.9× in
//  load-per-minute.
//

import Foundation

// MARK: - Intensity weights

/// The discrete zone anchors of `ZONE_WEIGHTS` in
/// `_shared/workoutSegmentation.ts`. NOTE: the backend now weights bouts on a
/// CONTINUOUS pace curve (`paceWeight`) that interpolates between these anchors
/// and extrapolates past mile; this grid keeps the discrete anchor lookup
/// (it has no per-bout pace), so it's a bounded approximation of the canonical
/// intensity_score. A minute at mile pace ≈ 8 easy minutes of mechanical load.
///
/// (2026-08-11) `steady` 1.5 → 2.15, `moderate` 1.25 → 1.40, mirroring the
/// backend reweight that removed the 9x slope cliff between steady and MP.
enum TrendsZoneWeight {
    static let table: [String: Double] = [
        "recovery": 1.0,
        "easy": 1.0,
        "moderate": 1.4,
        "steady": 2.15,
        "mp": 2.5,
        "hmp": 3.25,  // half-marathon / threshold / LT band
        "10k": 4.0,
        "5k": 5.5,   // (2026-07-30) keep in sync with ZONE_WEIGHTS in
        "3k": 6.75,  // _shared/workoutSegmentation.ts
        "mile": 8.0,
    ]

    /// Weight for a zone token. Unknown zones weigh 1.0 — an unrecognised
    /// zone must never inflate a score.
    static func weight(_ zone: String) -> Double {
        table[zone.lowercased()] ?? 1.0
    }
}

// MARK: - Quality load

enum QualityLoad {
    /// Weighted minutes below which a session is real work but not a key
    /// session. See the calibration note in this file's header.
    static let floor: Double = 25

    /// One work bout's contribution, in weighted minutes.
    static func score(workSeconds: Double, zone: String) -> Double {
        guard workSeconds > 0 else { return 0 }
        return workSeconds * TrendsZoneWeight.weight(zone) / 60
    }

    /// Sum over work bouts. The caller passes only bouts that are actually
    /// work — rest is excluded upstream by `segmentFromLaps`.
    static func total(_ bouts: [(seconds: Double, zone: String)]) -> Double {
        bouts.reduce(0) { $0 + score(workSeconds: $1.seconds, zone: $1.zone) }
    }

    /// Does this session clear the floor? A nil load (an older payload with
    /// no `quality_load` field) is treated as NOT qualifying, so a missing
    /// number can never silently promote a stride set to a key session.
    static func qualifies(_ load: Double?) -> Bool {
        guard let load else { return false }
        return load >= floor
    }
}

// MARK: - Calendar maths for the grid's y-axis

/// Mon-first weekday handling. The grid's rows are Mon→Sun because that is
/// how a training week is read; `Calendar.weekday` is Sun-first, so every
/// conversion goes through here rather than being open-coded per call site.
enum TrendsWeekday {
    /// Row labels, Mon→Sun. Two of them are "T" and two are "S"; that is the
    /// conventional calendar abbreviation and reads fine against the weekend
    /// wash the grid draws behind Sat/Sun.
    static let initials = ["M", "T", "W", "T", "F", "S", "S"]

    /// Full names, Mon→Sun — used in the readout, where ambiguity isn't OK.
    static let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private static let utc = TimeZone(secondsFromGMT: 0)!

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = utc
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = utc
        return c
    }

    /// "2026-06-23" or "2026-06-23T09:00:00Z" → a UTC-midnight `Date`.
    static func date(from isoDate: String) -> Date? {
        isoFormatter.date(from: String(isoDate.prefix(10)))
    }

    /// Mon = 0 … Sun = 6. `nil` when the date can't be parsed — the grid
    /// omits the mark rather than defaulting it onto Monday.
    static func index(from isoDate: String) -> Int? {
        guard let d = date(from: isoDate) else { return nil }
        // Calendar.weekday is Sun = 1 … Sat = 7.
        let weekday = utcCalendar.component(.weekday, from: d)
        return (weekday + 5) % 7
    }

    /// The Monday of this date's week, as "yyyy-MM-dd". Used to match a
    /// session onto a `TrendsWeek` column.
    static func weekStart(from isoDate: String) -> String? {
        guard let d = date(from: isoDate), let i = index(from: isoDate),
              let monday = utcCalendar.date(byAdding: .day, value: -i, to: d)
        else { return nil }
        return isoFormatter.string(from: monday)
    }
}
