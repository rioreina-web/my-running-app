//
//  WeekModels.swift
//  RunningLog · Week
//
//  The data the Week tab renders. One value type for the whole surface, so
//  the view stays a dumb renderer and the wiring happens in one place later.
//
//  STATUS 2026-08-19 — EVERY VALUE HERE IS A FIXTURE. `WeekRead.preview` is
//  hand-built so the surface can be reviewed on device before any service is
//  wired. Nothing in this file reads from Supabase, TrendsService, AskService
//  or the store. See WEEK-TAB-APPLY.md §"Wiring" for which analyzer feeds
//  which field — most already exist and are a WRAP, not a BUILD.
//
//  ONE FIELD HAS NO DATA PATH AT ALL: `LongRun.fuel`. Carbohydrate intake is
//  not captured anywhere in the schema (no column, no field, no classifier).
//  It stays in the fixture because it is the most decision-relevant column on
//  the long-run ledger, and it is flagged here so nobody mistakes it for a
//  wiring job. It is a capture job first.
//

import SwiftUI

// MARK: - Zones

/// The pace spectrum, slow to sharp. Mirrors `PaceSpectrum` stops so a bar in
/// this tab is the same blue as the same zone anywhere else in the app.
/// `lt` and `mile` are deliberately absent: the backend classifier folds LT
/// into HMP, and no week in a marathon block carries mile-pace volume worth a
/// visible segment.
enum WeekZone: String, CaseIterable, Identifiable {
    case easy, moderate, steady, mp, hmp, tenK, fiveK, threeK

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy:     "Easy"
        case .moderate: "Mod"
        case .steady:   "Steady"
        case .mp:       "MP"
        case .hmp:      "HMP"
        case .tenK:     "10K"
        case .fiveK:    "5K"
        case .threeK:   "3K"
        }
    }

    var color: Color {
        switch self {
        case .easy:     PaceSpectrum.easy
        case .moderate: PaceSpectrum.moderate
        case .steady:   PaceSpectrum.steady
        case .mp:       PaceSpectrum.mp
        case .hmp:      PaceSpectrum.hmp
        case .tenK:     PaceSpectrum.tenK
        case .fiveK:    PaceSpectrum.fiveK
        case .threeK:   PaceSpectrum.threeK
        }
    }
}

// MARK: - Anchors

/// Scroll targets. An evidence chip on a proposal jumps to the card the claim
/// came from — that jump is the whole glass-box promise, so the anchors are a
/// typed enum rather than loose strings.
enum WeekAnchor: String, Hashable {
    case threshold, efficiency, load, recovery, longRuns, spectrum
}

// MARK: - Provenance

/// One source row behind a number: a session, or a lap inside one.
///
/// THE RULE THIS TYPE EXISTS TO ENFORCE. Every value this tab shows is
/// derived from imported activity data — laps from Strava, or the standard
/// splits when the watch recorded no laps. Nothing is estimated, rounded to a
/// nice number, or generated to fill a row. If a datum cannot name the runs it
/// came from, it must not offer a provenance sheet at all; an empty sheet is a
/// bug, not an empty state.
struct WeekSourceRun: Identifiable {
    let id = UUID()
    var date: String
    var name: String
    /// What of this run went into the number — "4 laps", "2.1 mi", "38 min".
    var detail: String
    /// The value this run contributed, in the parent number's units.
    var value: String
    /// The uncorrected value, when a correction was applied. Heat-adjusted
    /// paces always show their raw pace here so the athlete can see the
    /// correction being made on their behalf.
    var secondary: String?
}

/// What a tapped chart element opens. Built at the tap site from the datum,
/// so the sheet can never show rows the chart didn't actually use.
struct WeekProvenance: Identifiable {
    let id = UUID()
    var eyebrow: String
    var title: String
    var subtitle: String
    /// Plain-language description of the computation. Not a formula — the
    /// sentence an athlete would accept as an answer to "where did that come
    /// from?"
    var method: String
    var rows: [WeekSourceRun]
    var coverage: String
    var tint: Color
    /// Column heading for `WeekSourceRun.value`.
    var valueHeader: String
}

// MARK: - WeekRead

struct WeekRead {

    // ---- Header ----
    var plateBlock: String
    var plateRange: String
    var eyebrow: String
    var title: String
    var subtitle: String

    // ---- The week ----
    var days: [Day]
    var weekSummary: String

    // ---- 01 · faster ----
    var bands: [Band]
    /// `nil` when this athlete has no pace-band data in the window — a new
    /// account, or one whose runs predate the lap ingest.
    var efficiency: Efficiency?
    var efficiencyUnavailable: Unavailable?
    var fasterSentence: String
    var bandsUnavailable: Unavailable?

    // ---- 02 · absorbing ----
    var load: Load
    var recovery: Recovery
    /// Set whenever the biometrics row cannot speak. `daily_biometrics` is
    /// migrated, RLS'd and indexed but EMPTY until `vital-webhook` grows its
    /// daily-sleep branch, so this is the expected state today.
    var overnightUnavailable: Unavailable?

    // ---- 03 · the marathon ----
    var longRuns: [LongRun]
    var longRunSentence: String
    var spectrum: [SpectrumSlice]
    var spectrumNote: String
    var longThreshold: MiniStat
    var volume: MiniStat


    // ---- the call ----
    var proposals: [Proposal]
    /// Set while no proposal engine exists. There is no `proposed_actions`
    /// anywhere in the repo; until there is, this section states that plainly
    /// instead of showing invented advice.
    var proposalsUnavailable: Unavailable?

    // MARK: Nested

    struct Day: Identifiable {
        let id = UUID()
        var name: String
        /// `nil` renders as a rest day — never 0.0, which reads as a logged
        /// zero-mile run.
        var miles: Double?
        var label: String
        var isQuality: Bool
        /// The individual runs on this day, in clock order.
        ///
        /// THIS IS WHY THE FIELD EXISTS: the athlete this was first built
        /// against runs 8–16 times a week and doubles most days (Mon 17 Aug
        /// was 6.0 + 4.0; Tue was 2.1 + 6.2 + 2.0). A day cell holding one
        /// number cannot represent that. `miles` is the deduped day total —
        /// the sum of these — and the cell shows the count when there is more
        /// than one.
        var runs: [DayRun] = []
    }

    struct DayRun: Identifiable {
        let id = UUID()
        /// "6:12 AM" — from `TrendsDay.Run.clockLabel`.
        var clock: String
        var miles: Double
        var label: String
    }

    struct Point: Identifiable {
        let id = UUID()
        var weekLabel: String
        var paceSec: Int
        /// The sessions whose laps produced this week's value.
        var sessions: [WeekSourceRun] = []
    }

    struct Band: Identifiable {
        let id = UUID()
        var key: String
        var currentPace: String
        var delta: String
        var points: [Point]
        var footnote: String
        var tint: Color
        var method: String = ""
    }

    struct Efficiency {
        var pace: String
        var atHR: String
        var delta: String
        var points: [Point]
        var footnote: String
        var method: String = ""
    }

    struct LoadWeek: Identifiable {
        let id = UUID()
        var label: String
        var minutes: [WeekZone: Double]
        /// The runs that make up this week's bar.
        var sessions: [WeekSourceRun] = []
        var total: Double { minutes.values.reduce(0, +) }
        /// Share of the week's load from MP and faster — the number the
        /// readout states on tap.
        var sharpShare: Double {
            let sharp: [WeekZone] = [.mp, .hmp, .tenK, .fiveK, .threeK]
            let s = sharp.reduce(0.0) { $0 + (minutes[$1] ?? 0) }
            return total > 0 ? s / total : 0
        }
    }

    struct Load {
        var current: String
        var deltaText: String
        var weeks: [LoadWeek]
        var baselineAvg: Double
        var baselineLo: Double
        var baselineHi: Double
        var baselineLabel: String
        var spikeNote: String
        var method: String = ""
    }

    struct Niggle: Identifiable {
        let id = UUID()
        var name: String
        var status: String
        var tint: Color
        var resolved: Bool
    }

    struct OvernightStat: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        var baseline: String?
        var note: String
        var noteTint: Color
    }

    struct Recovery {
        var niggles: [Niggle]
        /// One entry per day, oldest first. `true` = the niggle was mentioned.
        var niggleDots: [Bool]
        /// One entry per day, oldest first. `nil` = NOTHING WAS LOGGED that
        /// day, and it renders as an empty ring, never a colour.
        ///
        /// The first fixture drew fourteen filled dots. The real account logs
        /// a mood on 1-5 runs a week out of 8-16 — so most days are honestly
        /// blank, and a filled row was inventing the athlete's own words back
        /// at them. `TrendsDay.mood` is nil on an unlogged day by contract
        /// ("never fabricated"); this field preserves that all the way to the
        /// pixel.
        var moods: [Color?]
        var moodSummary: String
        var overnight: [OvernightStat]
        var quadrantNote: String
        /// The one sentence that does the interpreting. Everything above it is
        /// evidence; this is the only place the surface speaks.
        var sentence: String
    }

    struct LongRun: Identifiable {
        let id = UUID()
        var date: String
        var distance: String
        /// What was actually inside it, from the day's zone breakdown —
        /// "12.1 easy · 3.0 MP", not a guess at intent.
        var inside: String
        var durationLabel: String
        /// The runs that made up this day. A long run that was actually a
        /// double says so.
        var laps: [WeekSourceRun] = []
    }

    /// Why a section is dark. Every one of these is a real state of the data,
    /// and each renders as plain prose — never a placeholder number, never a
    /// dash where a value would go.
    enum Unavailable {
        /// The computation exists but this athlete has too little history.
        case needsHistory(String)
        /// The data is not captured anywhere in the product yet.
        case notCaptured(String)
        /// Built, but not wired to this surface.
        case notWired(String)

        var message: String {
            switch self {
            case .needsHistory(let m), .notCaptured(let m), .notWired(let m): m
            }
        }
    }

    struct SpectrumSlice: Identifiable {
        let id = UUID()
        var zone: WeekZone
        var share: Double
        var flagged: Bool
        var miles: String = ""
        /// The runs that put miles in this zone.
        var sessions: [WeekSourceRun] = []
    }

    struct MiniStat {
        var eyebrow: String
        var value: String
        var unit: String
        var caption: String
        var note: String
        var noteTint: Color
        var method: String = ""
        var sessions: [WeekSourceRun] = []
    }

    struct Evidence: Identifiable {
        let id = UUID()
        var label: String
        var tint: Color
        var anchor: WeekAnchor
    }

    /// What applying a proposal does to the week strip. Kept as data, not a
    /// closure, so an applied proposal is inspectable and reversible.
    struct DayChange {
        var dayName: String
        var miles: Double?
        var label: String
    }

    struct Proposal: Identifiable {
        var id: Int
        var day: String
        var headline: String
        /// Struck through in the diff. `nil` when the proposal adds a
        /// constraint rather than replacing a session.
        var fromText: String?
        var toText: String
        var why: String
        var evidence: [Evidence]
        var change: DayChange?
        var appliedNote: String
    }
}
