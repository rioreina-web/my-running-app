//
//  TrendsModels.swift
//  RunningLog
//
//  Data model for the **Trends** tab — the chart-centric "show me what I
//  can't see" surface (revived from the retired Trends tab; see the
//  tombstone history in this folder). One shared timeline fuses five
//  streams the athlete can't easily correlate from inside a block:
//  mileage, intensity, key-session pace, mood, and niggles.
//
//  V1 ships with `TrendsSampleData` so the surface is fully designed and
//  reviewable. The real wiring is a follow-up:
//    • miles / qualityMiles → `_shared/dataAnalysis.ts` weekly volume +
//      the quality-mile split (HealthKit-synced training_logs).
//    • keyPaceSec           → the week's hardest quality session pace.
//    • mood                 → dominant voice-log mood for the week
//      (vocabulary: energized | positive | neutral | tired | struggling
//      | injured — see CLAUDE.md).
//    • niggles / voiceQuote → `body_mentions` (verbatim, surface-not-
//      diagnose). Quotes are the athlete's own words; never coerced.
//

import Foundation

// MARK: - Range window

/// The timeframe segmenter at the top of the chart. Raw value == number of
/// weeks shown (also used to slice the sample tail).
enum TrendsRange: Int, CaseIterable, Identifiable {
    case fourWeek = 4
    case twelveWeek = 12
    case sixMonth = 26

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fourWeek: "4 wk"
        case .twelveWeek: "12 wk"
        case .sixMonth: "6 mo"
        }
    }

    /// The same window expressed in days, for the day-grained surfaces
    /// (the pace spectrum) that hang off this one control. Trends ships ONE
    /// time control; anything embedded in the tab reads its window from here
    /// rather than carrying a second, independently-set range of its own.
    var days: Int { rawValue * 7 }
}

// MARK: - Week model

/// One week on the unified timeline. All five tracks read off the same row,
/// so a vertical scrub lines up volume, the key session, how she felt, and
/// any body-part mentions for that week.
struct TrendsWeek: Identifiable {
    let id = UUID()
    /// Short month tag for the x-axis ("May"). Drawn only when the month
    /// changes across the window.
    let month: String
    /// Full label shown in the readout ("May 26").
    let dateLabel: String
    /// Weekly mileage.
    let miles: Double
    /// Quality (non-easy) miles inside `miles` — rendered as the darker bar
    /// cap so intensity rides inside volume rather than needing its own chart.
    let qualityMiles: Double
    /// Pace of the week's key quality session, sec/mile. `nil` for weeks
    /// with no quality session (e.g. a down week).
    let keyPaceSec: Int?
    /// Dominant voice-log mood for the week (closed vocabulary).
    let mood: String
    /// Body parts mentioned this week, verbatim labels. Surface, never
    /// diagnose.
    let niggles: [String]
    /// An optional verbatim voice-log line to surface in an insight.
    var voiceQuote: String? = nil
    /// Monday of this week, "yyyy-MM-dd". Used to align a week row with the
    /// sessions that fall inside it. Empty for monthly rollups, which have no
    /// single week — callers skip those rather than guessing a Monday.
    /// (Was the session grid's column key until the grid came out, 2026-08-17.)
    var weekStart: String = ""
}

// MARK: - Day model (Trends-v2 calendar substrate)

/// One calendar day on the Trends-v2 grid. The daily substrate the Month/Block
/// calendar renders on — **dense** (one entry per day in the window, rest days
/// included) so the weekday layout needs no gap-filling on device.
///
/// Source: `trends-timeline` → `days[]` (`buildDailyTimeline`). Shares the
/// weekly builder's dedup / quality / mood logic, so a day can never disagree
/// with the week it sums into.
struct TrendsDay: Identifiable {
    let id = UUID()
    /// "yyyy-MM-dd" (UTC day).
    let date: String
    /// Deduped running miles that day (doubles summed). 0 on a rest day.
    let miles: Double
    /// The coarse session channel the calendar colours by.
    let type: SessionChannel
    /// Dominant mood that day (closed vocabulary), or `nil` when no feeling was
    /// logged — a true rest day carries no mood, and it is never fabricated.
    let mood: String?
    /// Body mentions that landed on this day, verbatim. Surface, never diagnose.
    let niggles: [DayNiggle]

    // Sleep + overnight biometrics (additive, 2026-08-05). All optional with
    // nil defaults: a day with no watch data and no check-in carries none, and
    // it is never fabricated — same contract as `mood`. Source:
    // `trends-timeline` → `days[]`, decorated from `daily_biometrics` +
    // `daily_checkins`.

    /// Nocturnal HRV (rmssd, ms) from `daily_biometrics`, or nil. Context —
    /// never read on its own or on a single night (recovery-trend-v2 §2c).
    var hrvRmssd: Double? = nil
    /// Nocturnal resting HR (bpm) from `daily_biometrics`, or nil. The HRV
    /// disambiguator.
    var restingHr: Double? = nil
    /// Total sleep minutes from `daily_biometrics`, or nil. Tier-3 annotation
    /// only — never sleep stages or scores (recovery-trend-v2 §7.4).
    var sleepTotalMin: Int? = nil
    /// Self-reported sleep quality for the night, closed vocab
    /// ('rough' | 'ok' | 'good'), or nil when unrated. The Tier-1 signal.
    var sleepQuality: String? = nil

    // Load inputs for the recovery-need DEMAND term (2026-08-06,
    // `outputs/recovery-need-model-2026-08-06.md` §2).

    /// Total running minutes that day, paused-watch artifacts already
    /// re-imputed server-side. 0 on a rest day.
    var durationMin: Int? = nil
    /// The real per-workout internal-load unit, summed over the day's runs.
    /// `nil` until the `20260731120000` backfill runs — which is why
    /// `TrendsRecoveryDemand` carries a fallback ladder rather than assuming
    /// this is present. Never 0-for-missing: a zero-load day and an
    /// unmeasured day are different facts.
    var stressLoad: Double? = nil

    // Per-zone breakdown of the day (additive, 2026-08-10). Source:
    // `trends-timeline` → `days[].zone_minutes` / `zone_miles`, built from
    // every `Bout` that `segmentFromLaps` returns.
    //
    // This is the only surface carrying the FULL ten-zone taxonomy per day.
    // `keyVolume` (`quality_volume`) is weekly and filters to work zones, so
    // it reports nothing at all for a 12-mile easy day; `type` above is one
    // coarse channel for the calendar. Neither answers "where did this day's
    // volume actually sit on the pace spectrum".
    //
    // Keyed by the raw zone token, so the vocabulary stays owned by
    // `workoutSegmentation.ts` and this model never has to be edited when a
    // zone is added. Zones with no volume are absent, not zero — `.keys` is
    // the list of zones actually run.

    /// Minutes per pace zone, or nil when the day carries no breakdown.
    var zoneMinutes: [String: Double]? = nil
    /// Miles per pace zone, paired with `zoneMinutes` so a caller can derive a
    /// real average pace per zone (Σ time ÷ Σ distance) instead of averaging
    /// per-run averages.
    var zoneMiles: [String: Double]? = nil
    /// Weighted minutes (TLS) per zone, summed per BOUT off the backend's
    /// continuous `paceWeight` curve. Prefer this over multiplying `zoneMinutes`
    /// by `TrendsZoneWeight` — the table is ten steps, the curve is what those
    /// steps sample, and it keeps climbing past the mile anchor. nil against a
    /// payload predating the field; callers fall back to the table.
    var zoneLoad: [String: Double]? = nil

    /// True when this day has a per-zone breakdown to render.
    ///
    /// The three states a caller must tell apart, because they read very
    /// differently to an athlete:
    ///   • `miles == 0`                        → a rest day. Nothing to show.
    ///   • `miles > 0 && !hasZoneBreakdown`    → ran, but the run arrived with
    ///     no laps (manual entry, or an import without splits). We cannot say
    ///     how it was distributed, and must not guess.
    ///   • `miles > 0 && hasZoneBreakdown`     → the real thing.
    var hasZoneBreakdown: Bool { !(zoneMinutes?.isEmpty ?? true) }

    // The same day, unrolled (additive, 2026-08-11). Source:
    // `trends-timeline` → `days[].runs`. Everything above is this day summed;
    // this is what it was summed from. Empty on a rest day, AND on any payload
    // from a deploy predating the field — so a caller must treat "no runs" as
    // "cannot say", never as "did not run", and fall back to `miles`.

    /// This day's runs, chronological by start time. These are UPLOADS, one per
    /// watch activity — a track session logged as warm-up / reps / cool-down is
    /// three of them. Most display surfaces want `sessions(from:)` instead.
    var runs: [Run] = []

    /// Fold uploads into the runs a person would say they did.
    ///
    /// An athlete who stops their watch between the warm-up, the session and
    /// the cool-down has done ONE run and uploaded three. Drawn literally that
    /// is three bars a few minutes apart, which is both visually crowded and
    /// factually misleading — the 6:29am "run" was 40 minutes, not the 12 the
    /// middle upload claims.
    ///
    /// The gap threshold is `SessionRollup.sessionGapMinutes`, NOT a new
    /// constant: The Sheet already had to answer "what is one session", and two
    /// surfaces disagreeing about it is worse than either answer being slightly
    /// off. It is measured from the END of the previous piece, so a long warm-up
    /// does not eat the allowance, and at 90 minutes a genuine double (a
    /// morning and an evening run, hours apart) still splits.
    static func sessions(from runs: [Run]) -> [Run] {
        let ordered = runs.sorted { $0.startedAt < $1.startedAt }
        var out: [Run] = []
        for run in ordered {
            guard var last = out.last else { out.append(run); continue }
            let prevEnd = last.startedAt.addingTimeInterval(last.durationSec)
            let gapMin = run.startedAt.timeIntervalSince(prevEnd) / 60
            guard gapMin <= SessionRollup.sessionGapMinutes else {
                out.append(run); continue
            }
            // Merge into the piece already there. The session keeps the FIRST
            // piece's id and start — the id so selection survives a refetch
            // (same convention as `TrainingSession`), the start because that is
            // when the athlete began running.
            last.durationSec += run.durationSec   // running time, so the gaps
            last.miles += run.miles               // are excluded, as they should be
            last.pieceCount += run.pieceCount
            last.zoneMinutes = Self.merge(last.zoneMinutes, run.zoneMinutes)
            last.zoneMiles = Self.merge(last.zoneMiles, run.zoneMiles)
            last.zoneLoad = Self.merge(last.zoneLoad, run.zoneLoad)
            out[out.count - 1] = last
        }
        return out
    }

    /// Sum two optional zone maps. Nil + nil stays nil — "no breakdown" must
    /// not become "an empty breakdown", which the client renders differently.
    private static func merge(_ a: [String: Double]?,
                              _ b: [String: Double]?) -> [String: Double]? {
        guard a != nil || b != nil else { return nil }
        var out = a ?? [:]
        for (k, v) in b ?? [:] { out[k, default: 0] += v }
        return out
    }

    /// One run inside a day. Carries the two things the day rollup destroys:
    /// **when it started**, and **which zones belong to which run**.
    struct Run: Identifiable {
        /// `training_logs.id`. Stable across fetches, so it is also the
        /// selection key for a view that opens one run at a time.
        let id: UUID
        /// The run's start time as an instant. Time-of-day must be read from
        /// this with `minuteOfDay`, never with a shared `Calendar.current` —
        /// see that property.
        let startedAt: Date
        /// The offset the payload actually stated, in seconds — and **nil when
        /// it stated nothing usable**, which is the common case: `TIMESTAMPTZ`
        /// flattens everything to `+00:00` on write, so a zero offset is
        /// Postgres, not a fact about the athlete.
        ///
        /// Deliberately NOT pre-resolved to "the offset to use". Baking the
        /// fallback in at decode time meant changing the Settings timezone left
        /// every already-decoded run at its old position until the next fetch —
        /// the setting appeared not to work. Storing only what was stated, and
        /// resolving in `minuteOfDay`, makes the whole app follow the setting
        /// the instant it changes.
        let statedOffsetSeconds: Int?
        // `var` from here down because `sessions(from:)` accumulates a session
        // into its first piece. `id`, `startedAt` and the offset stay `let`:
        // those are the session's identity and are taken from the first upload,
        // never summed.
        /// Wall-clock SECONDS. Seconds rather than minutes because a run is
        /// 42:13 and an athlete checks that against their watch — rounding to
        /// the minute throws away the only digits they would verify.
        var durationSec: Double
        var miles: Double
        var zoneMinutes: [String: Double]? = nil
        var zoneMiles: [String: Double]? = nil
        /// See `TrendsDay.zoneLoad`.
        var zoneLoad: [String: Double]? = nil
        /// How many uploads were folded into this one. 1 for a plain run; 3 for
        /// the everyday warm-up / session / cool-down trio. See
        /// `TrendsDay.sessions(from:)`.
        var pieceCount: Int = 1

        var hasZoneBreakdown: Bool { !(zoneMinutes?.isEmpty ?? true) }

        /// Minutes past local midnight, 0...1439 — the run's position on a
        /// 24-hour day.
        ///
        /// A stated offset wins; otherwise the athlete's Settings timezone,
        /// falling back to the device. `AthleteTimeZone` owns that ladder — do
        /// not reach for `TimeZone.current` at a call site, or the Settings
        /// choice silently stops applying to whatever you are building.
        ///
        /// Where no offset was stated this is a resolved best guess, not a
        /// recorded fact. Prefer `partOfDay` over `clockLabel` anywhere the app
        /// would be asserting something it cannot stand behind.
        var minuteOfDay: Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = statedOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) }
                ?? AthleteTimeZone.resolved
            let c = cal.dateComponents([.hour, .minute], from: startedAt)
            return min(1439, max(0, (c.hour ?? 0) * 60 + (c.minute ?? 0)))
        }

        /// The calendar day this run belongs to, in the athlete's own timezone.
        /// Resolved through the SAME ladder as `minuteOfDay`, so the day a run
        /// is filed under and the position it takes inside that day can never
        /// disagree.
        ///
        /// The payload's `days[].date` key is a UTC date (`dayUTC` in
        /// `trends-timeline/timeline.ts`), which is a different question from
        /// the one the strip asks. A run started 7:26pm in Chicago is 00:26Z
        /// the NEXT day: it arrived filed under tomorrow while `minuteOfDay`
        /// correctly read 19:26, so it drew late in the evening of the wrong
        /// slot — and the day totals disagreed with the list above the chart,
        /// which buckets locally via `TrainingAnalyticsViewModel.split(forDay:)`.
        /// Anything that files a run under a DAY must use this, not the key it
        /// arrived under.
        var localDay: Date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = statedOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) }
                ?? AthleteTimeZone.resolved
            return cal.startOfDay(for: startedAt)
        }

        /// What the strip's x-position actually claims. The chart has no hour
        /// axis, so anywhere the app says *when* in words, it says this and
        /// not a clock reading estimated off the picture.
        var partOfDay: String {
            switch minuteOfDay {
            case ..<(5 * 60):   return "Night"
            case ..<(11 * 60):  return "Morning"
            case ..<(14 * 60):  return "Midday"
            case ..<(18 * 60):  return "Afternoon"
            case ..<(20 * 60):  return "Evening"
            default:            return "Night"
            }
        }

        /// "6:05am". The exact time, for the panel — where it is read rather
        /// than measured.
        var clockLabel: String {
            let m = minuteOfDay
            let h24 = m / 60
            let h = h24 % 12 == 0 ? 12 : h24 % 12
            return "\(h):" + String(format: "%02d", m % 60) + (h24 < 12 ? "am" : "pm")
        }
    }

    /// The session channel the calendar colours by — **not** a pace zone. Per
    /// the calendar encoding: `key` gets the coral accent, `long` its own dark-
    /// grey channel (precedence over key), `easy` light grey, `rest` no run.
    enum SessionChannel: String {
        case key, long, easy, rest

        /// Unknown/absent tokens degrade to `rest`, never a faked session.
        init(token: String?) {
            self = SessionChannel(rawValue: (token ?? "").lowercased()) ?? .rest
        }
    }

    /// One body mention on a day, verbatim. `severity` is the raw
    /// `body_mentions.severity_hint` (tight | sore | pain | sharp); the view
    /// maps it to an opacity ramp — the model never interprets it.
    struct DayNiggle: Identifiable {
        let id = UUID()
        let area: String
        let side: String?
        let severity: String?
        let quote: String
    }
}

// MARK: - Key session (Section A of the redesigned Key Sessions chart)

/// One quality session on the honest pace chart. Unlike `TrendsWeek.keyPaceSec`
/// (one whole-workout average per week), this is a single session's **work-bout
/// pace** — rest excluded, classified to the athlete's own pace zone, with the
/// heat-adjusted pace carried alongside the raw one (never replacing it).
///
/// Source: `trends-timeline` → `quality_sessions[]` (see
/// `supabase/functions/trends-timeline/keySessions.ts`). Missing lap data means
/// a session simply isn't here — the surface degrades, it never fakes a dot.
struct KeySession: Identifiable {
    let id: String          // training_log_id
    let date: String        // "2026-06-23" (UTC day)
    let dateLabel: String   // "Jun 23"
    /// Zone token from the shared classifier: mile | 3k | 5k | 10k | hmp | mp.
    /// NB: the backend classifier folds LT/threshold into `hmp`, so LT is
    /// surfaced as HMP here — the honest label given the current zone table.
    let zone: String
    let workPaceSec: Int
    let workPaceAdjSec: Int?
    let heatCategory: String?  // ideal | warm | hot | very_hot | dangerous | nil
    let workHrAvg: Int?
    let structure: String?     // "5K 5×1km · 6.0 mi"
    let distanceMi: Double?
    /// Weighted minutes of work — Σ(work-bout seconds × zone weight) — from
    /// `trends-timeline`. Drives dot size on the session grid and the gate
    /// that decides whether this counts as a key session at all. Optional so
    /// an older payload still decodes; a nil load never clears the floor.
    /// See `QualityLoad` in `TrendsQualityLoad.swift`.
    var qualityLoad: Double? = nil
    /// `"quality"` = a rep/threshold session, classified by its work bouts.
    /// `"long_run"` = an aerobic anchor session with no MP-or-faster work,
    /// admitted on the classifier's label. Their paces are NOT comparable —
    /// a long run's is the whole run's mean, a quality session's is its work
    /// bouts — so the grid colours and labels them apart and never plots them
    /// on one scale.
    var kind: String = "quality"

    /// Convenience for the grid and the readout.
    var isLongRun: Bool { kind == "long_run" }

    /// The heat model applied only when conditions weren't ideal AND an
    /// adjusted number exists. Drives the hollow-dot rendering.
    var isHeatAdjusted: Bool {
        guard workPaceAdjSec != nil, let c = heatCategory?.lowercased() else { return false }
        return c != "ideal"
    }

    /// Pace the dot is plotted at: adjusted when heat mattered, else raw.
    var effectivePaceSec: Int { isHeatAdjusted ? (workPaceAdjSec ?? workPaceSec) : workPaceSec }
}

/// Zone display + ordering for the chip row and chart. Fast → slow, matching
/// the work zones the classifier emits.
enum KeyZone {
    /// Canonical fast→slow order of the work zones.
    static let order = ["mile", "3k", "5k", "10k", "hmp", "mp"]

    nonisolated static func label(_ token: String) -> String {
        switch token.lowercased() {
        case "mile": "Mile"
        case "3k": "3K"
        case "5k": "5K"
        case "10k": "10K"
        case "hmp": "HMP"
        case "mp": "MP"
        default: token.uppercased()
        }
    }

    /// Sort index for chips; unknown zones sort last.
    static func rank(_ token: String) -> Int {
        order.firstIndex(of: token.lowercased()) ?? order.count
    }
}

// MARK: - Quality volume (Section B: the work behind it)

/// One week of time-at-quality-pace, keyed by work zone. Backs the Section-B
/// stacked bars. A down week comes back with an empty `zoneSeconds` — a real
/// zero, drawn as a gap in the bar row, never faked.
///
/// Source: `trends-timeline` → `quality_volume[]`
/// (`buildQualityVolume` in `keySessions.ts`), aggregated from the same laps
/// as Section A so the two surfaces never disagree.
struct QualityVolumeWeek: Identifiable {
    let id = UUID()
    let weekStart: String       // "2026-06-08"
    let dateLabel: String       // "Jun 8"
    let zoneSeconds: [String: Int]  // work zone token → seconds

    /// Total quality seconds this week (all work zones summed).
    var total: Int { zoneSeconds.values.reduce(0, +) }
}

// MARK: - Pace formatting

enum TrendsFormat {
    /// 401 → "6:41". Returns "—" for nil (callers should prefer the
    /// empty-state component for real empty cells; this is for inline stats).
    static func pace(_ sec: Int?) -> String {
        guard let sec else { return "—" }
        return "\(sec / 60):\(String(format: "%02d", sec % 60))"
    }
}

// MARK: - Sample data

/// 26 weeks of base-phase data ending "this" Monday, mirroring the approved
/// HTML prototype (`trends-tab-prototype.html`). Tail-sliced by `TrendsRange`.
///
/// NB: deliberately static + synchronous for V1. Replace `weeks` with a
/// data-service load when wiring real streams; the views depend only on the
/// `[TrendsWeek]` shape.
enum TrendsSampleData {
    static let weeks: [TrendsWeek] = [
        TrendsWeek(month: "Dec", dateLabel: "Dec 16", miles: 32, qualityMiles: 5,  keyPaceSec: 438, mood: "positive",   niggles: []),
        TrendsWeek(month: "Dec", dateLabel: "Dec 23", miles: 30, qualityMiles: 4,  keyPaceSec: nil, mood: "neutral",    niggles: []),
        TrendsWeek(month: "Dec", dateLabel: "Dec 30", miles: 34, qualityMiles: 6,  keyPaceSec: 440, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 6",  miles: 36, qualityMiles: 6,  keyPaceSec: 436, mood: "energized",  niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 13", miles: 35, qualityMiles: 7,  keyPaceSec: 434, mood: "tired",      niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 20", miles: 38, qualityMiles: 8,  keyPaceSec: 432, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jan", dateLabel: "Jan 27", miles: 37, qualityMiles: 7,  keyPaceSec: 430, mood: "positive",   niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 3",  miles: 40, qualityMiles: 9,  keyPaceSec: 431, mood: "tired",      niggles: ["L hip"]),
        TrendsWeek(month: "Feb", dateLabel: "Feb 10", miles: 39, qualityMiles: 8,  keyPaceSec: 428, mood: "positive",   niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 17", miles: 42, qualityMiles: 10, keyPaceSec: 427, mood: "energized",  niggles: []),
        TrendsWeek(month: "Feb", dateLabel: "Feb 24", miles: 41, qualityMiles: 9,  keyPaceSec: 426, mood: "neutral",    niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 3",  miles: 44, qualityMiles: 11, keyPaceSec: 425, mood: "tired",      niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 10", miles: 43, qualityMiles: 10, keyPaceSec: 423, mood: "positive",   niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 17", miles: 46, qualityMiles: 12, keyPaceSec: 422, mood: "positive",   niggles: []),
        // ---- last 12 weeks (default window) ----
        TrendsWeek(month: "Mar", dateLabel: "Mar 24", miles: 38, qualityMiles: 8,  keyPaceSec: 418, mood: "positive",   niggles: []),
        TrendsWeek(month: "Mar", dateLabel: "Mar 31", miles: 41, qualityMiles: 9,  keyPaceSec: 416, mood: "positive",   niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 7",  miles: 43, qualityMiles: 10, keyPaceSec: 414, mood: "tired",      niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 14", miles: 40, qualityMiles: 9,  keyPaceSec: 415, mood: "positive",   niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 21", miles: 46, qualityMiles: 12, keyPaceSec: 410, mood: "energized",  niggles: []),
        TrendsWeek(month: "Apr", dateLabel: "Apr 28", miles: 48, qualityMiles: 13, keyPaceSec: 408, mood: "tired",      niggles: []),
        TrendsWeek(month: "May", dateLabel: "May 5",  miles: 44, qualityMiles: 10, keyPaceSec: 407, mood: "struggling", niggles: ["R achilles"], voiceQuote: "Achilles grumbled on the warm-up, eased off after a mile."),
        TrendsWeek(month: "May", dateLabel: "May 12", miles: 50, qualityMiles: 14, keyPaceSec: 405, mood: "positive",   niggles: []),
        TrendsWeek(month: "May", dateLabel: "May 19", miles: 52, qualityMiles: 15, keyPaceSec: 404, mood: "energized",  niggles: ["R achilles"]),
        TrendsWeek(month: "May", dateLabel: "May 26", miles: 49, qualityMiles: 13, keyPaceSec: 403, mood: "positive",   niggles: []),
        TrendsWeek(month: "Jun", dateLabel: "Jun 2",  miles: 53, qualityMiles: 16, keyPaceSec: 402, mood: "tired",      niggles: ["R achilles", "L hip"]),
        TrendsWeek(month: "Jun", dateLabel: "Jun 9",  miles: 53, qualityMiles: 16, keyPaceSec: 401, mood: "energized",  niggles: ["R achilles"], voiceQuote: "Heavy and short on patience today — nothing in the legs."),
    ]

    /// The most recent `range.rawValue` weeks, oldest → newest.
    static func window(_ range: TrendsRange) -> [TrendsWeek] {
        Array(weeks.suffix(range.rawValue))
    }
}
