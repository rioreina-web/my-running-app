//
//  TrainingThreadModels.swift
//  RunningLog · Training / Analytics
//
//  Data layer for the 90-day thread: load, body and voice on one date axis.
//
//  WHY THREE REGISTERS AND NOT NINE LANES. Measured over Rio's last 90 days
//  (2026-09-08), the signals do not have nine independent densities — they
//  have three:
//
//    fitness/fatigue  90/90     resting HR   90/90     runs      82/90
//    authored memo    38/90     mood         37/90     felt_rpe  29/90
//    niggles           6/90     sleep         5/90     HRV        0/90
//
//  The load-bearing measurement: **days with an authored memo == days with
//  ANY qualitative signal == 38, exactly.** Mood, RPE, niggles and prose all
//  arrive on the same days because they all fall out of the same voice memo.
//  They are facets of ONE episodic channel, not independent lanes, and
//  `TrendsMoodLanes`' nine equal switchable lanes assert an independence the
//  data does not have.
//
//  So: two continuous registers (LOAD, modelled + BODY, measured) and one
//  episodic register (VOICE, authored). Niggles are 6 days in 90 — a lane
//  that is empty 93% of the time is a bad lane, but those are the most
//  important days in the window, so they draw as episode BANDS through all
//  three registers instead. That co-presence is the whole point: it shows
//  what the load and the resting HR were doing on the days the knee spoke.
//
//  NOTHING HERE COMPOSES. No index, no score, no 0-100 anything — see the
//  header of TrainingThreadView and project_recovery_score_model. Absent
//  channels are drawn as absent, never as zero and never as fine.
//

import Foundation
import PostgREST
import Supabase

// MARK: - Day

struct ThreadNiggle: Identifiable, Equatable {
    let id: String
    let bodyArea: String
    let side: String?
    let severityHint: String?
    /// The athlete's own words. Quoted verbatim, never paraphrased and never
    /// converted to a number (CLAUDE.md niggles rule 2).
    let verbatimQuote: String?

    var label: String {
        let s = side.map { "\($0) " } ?? ""
        return "\(s)\(bodyArea)"
    }

    /// The quote worth showing NEXT TO the memo it came from.
    ///
    /// The niggle extractor writes a truncated slice of the memo, lowercased
    /// and ellipsed, often starting mid-word ("...y tired, likely from
    /// saturday's run..."). Printed under the full memo it is both redundant
    /// and worse-looking than the sentence it was cut from. So: show it only
    /// when it adds something the memo on screen does not already say.
    /// Known extractor defect, defended here rather than trusted — see
    /// project_niggles_v2_timeline.
    func quote(besides memo: String?) -> String? {
        guard let raw = verbatimQuote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let core = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".… "))
        guard core.count > 3 else { return nil }
        if let memo, memo.range(of: core, options: .caseInsensitive) != nil { return nil }
        return raw
    }
}

/// One day on the axis. Every field is optional because absence is the
/// normal case for most of them, and absence has to survive to the drawing.
struct ThreadDay: Identifiable, Equatable {
    let dateString: String        // "2026-09-01", UTC calendar day
    let date: Date

    // LOAD — modelled, from daily_scores
    var fitness: Double?
    var fatigue: Double?
    var srpe: Double = 0
    var loadComponents: [ScoreComponent] = []
    var bodyComponents: [ScoreComponent] = []
    var recoveryConfidence: String = "none"

    // BODY — measured, from daily_biometrics
    var restingHR: Double?
    var hrv: Double?
    var sleepMinutes: Int?

    // VOICE — authored, from training_logs + body_mentions
    var mood: String?
    var feltRPE: Double?
    var pullQuote: String?
    var memo: String?
    var niggles: [ThreadNiggle] = []

    var id: String { dateString }

    /// Did a human say anything on this day. The 38/90 channel.
    var hasVoice: Bool {
        mood != nil || feltRPE != nil || memo != nil || !niggles.isEmpty
    }
}

/// A run of consecutive (or near-consecutive) days carrying niggles. Drawn as
/// a band through every register and listed at the foot of the screen.
struct NiggleEpisode: Identifiable, Equatable {
    let startIndex: Int
    let endIndex: Int
    let startDate: Date
    let endDate: Date
    let parts: [String]
    var id: String { "\(startIndex)-\(endIndex)" }

    /// Days apart that still count as one episode. Two, so a Thursday and a
    /// Saturday mention of the same knee read as one thing — which is how the
    /// athlete experienced it — while a month later starts a new band.
    static let joinGapDays = 2
}

/// The athlete's own baseline for a nightly channel: mean ± 0.5 SD over the
/// 28 days behind the window. Constants come from `TrendsBiometrics` rather
/// than being restated, so the band here and the nightly lanes in Trends
/// cannot disagree about what "usual" means.
struct ThreadBand: Equatable {
    let mean: Double
    let sd: Double
    let readings: Int

    var lower: Double { mean - 0.5 * sd }
    var upper: Double { mean + 0.5 * sd }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let v = values.sorted()
        let mid = v.count / 2
        return v.count % 2 == 0 ? (v[mid - 1] + v[mid]) / 2 : v[mid]
    }

    static func build(_ values: [Double]) -> ThreadBand? {
        guard values.count >= TrendsBiometrics.minBaselineNights else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let sd = TrendsBiometrics.stdev(values)
        guard sd > 0 else { return nil }
        return ThreadBand(mean: mean, sd: sd, readings: values.count)
    }
}

/// Everything the screen draws, plus what it must say is missing.
struct ThreadWindow: Equatable {
    var days: [ThreadDay] = []
    var restingHRBand: ThreadBand?
    /// The athlete's own median sleep, minutes. A reference line drawn from
    /// their own nights — never a 7- or 8-hour population norm, which would
    /// be the one hardcoded threshold on a screen built out of self-relative
    /// baselines.
    var sleepMedian: Double?
    var episodes: [NiggleEpisode] = []

    var hasHRV: Bool { days.contains { $0.hrv != nil } }
    var hasSleep: Bool { days.contains { $0.sleepMinutes != nil } }
    var voiceDays: Int { days.filter(\.hasVoice).count }
}

// MARK: - Authored-text filter

enum ThreadText {
    /// Strava and HealthKit stamp a title on every activity, so "has notes" is
    /// not the same as "the athlete said something". Over the measured window
    /// 87 of 136 logs were auto-titles; counting them as voice would draw a
    /// channel that looks 91% covered and is really 42%.
    ///
    /// Matched against the real titles in the data — "Morning Run",
    /// "Afternoon Run", "Evening Run", "Lunch Run", "Morning jog",
    /// "Treadmill" — and deliberately nothing cleverer. Short notes the
    /// athlete DID write ("7 mi fartlek", "4 mi - WU & CD", "Forgot to turn
    /// it off Ks again") stay in: the test is whether a human wrote it, not
    /// whether it was eloquent.
    static func authored(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let key = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if key == "treadmill" { return nil }
        let parts = key.split(separator: " ")
        if parts.count == 2,
           ["morning", "afternoon", "evening", "lunch", "night", "midday"].contains(String(parts[0])),
           ["run", "jog", "ride", "activity", "walk", "workout"].contains(String(parts[1])) {
            return nil
        }
        return text
    }
}

// MARK: - Service

enum ThreadError: LocalizedError {
    case notSignedIn
    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to see your thread."
        }
    }
}

enum TrainingThreadService {

    private struct ScoreRow: Decodable {
        let score_date: String
        let score_version: String
        let fitness: Double?
        let fatigue: Double?
        let srpe: Double?
        let recovery_confidence: String?
        let stress_components: [ScoreComponent]?
        let recovery_components: [ScoreComponent]?
    }

    private struct BioRow: Decodable {
        let date: String
        let resting_hr: Double?
        let hrv_rmssd: Double?
        let sleep_total_min: Int?
    }

    private struct LogRow: Decodable {
        let workout_date: String     // timestamptz
        let mood: String?
        let felt_rpe: Double?
        let rpe_pull_quote: String?
        let cleaned_notes: String?
        let notes: String?
    }

    private struct MentionRow: Decodable {
        let id: String
        let mentioned_at: String
        let body_area: String
        let side: String?
        let severity_hint: String?
        let verbatim_quote: String?
    }

    /// DATE columns are decoded as String and parsed by hand — the SDK's
    /// `.value` date path throws on them (feedback_supabase_swift_date_decoder).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `workout_date` is TIMESTAMPTZ while every other date here is DATE.
    /// It is bucketed by its **UTC** calendar day, because that is exactly
    /// what `compute_daily_scores()` does (`workout_date::date` under a
    /// UTC session). Bucketing it locally instead would slide the voice
    /// register off the load register by a day for evening runs.
    private static func utcDay(fromTimestamp raw: String) -> String? {
        String(raw.prefix(10))
    }

    static func fetchWindow(days: Int = 90) async throws -> ThreadWindow {
        // Throws rather than returning an empty window: "not signed in" and
        // "no runs yet" are different states, and the empty-state copy for
        // the second one ("it'll appear after the next nightly pass") is a
        // lie when the real problem is auth.
        guard let userId = AuthManager.shared.currentUserId else {
            throw ThreadError.notSignedIn
        }
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today),
              let baselineStart = cal.date(
                  byAdding: .day, value: -TrendsBiometrics.baselineDays, to: start)
        else { return ThreadWindow() }   // calendar maths cannot fail in practice
        let startString = dayFormatter.string(from: start)
        let baselineString = dayFormatter.string(from: baselineStart)

        // Four independent reads; no reason to serialise them.
        async let scoresTask = supabase
            .from("daily_scores")
            .select("score_date, score_version, fitness, fatigue, srpe, recovery_confidence, stress_components, recovery_components")
            .eq("user_id", value: userId)
            .gte("score_date", value: startString)
            .order("score_date", ascending: true)
            .limit(days * 4)
            .execute()

        // Reaches BEHIND the window: the resting-HR band needs 28 days of
        // history the screen never draws.
        async let bioTask = supabase
            .from("daily_biometrics")
            .select("date, resting_hr, hrv_rmssd, sleep_total_min")
            .eq("user_id", value: userId)
            .gte("date", value: baselineString)
            .order("date", ascending: true)
            .limit(days + TrendsBiometrics.baselineDays + 10)
            .execute()

        async let logsTask = supabase
            .from("training_logs")
            .select("workout_date, mood, felt_rpe, rpe_pull_quote, cleaned_notes, notes")
            .eq("user_id", value: userId)
            .gte("workout_date", value: startString)
            .order("workout_date", ascending: true)
            .limit(days * 3)
            .execute()

        async let mentionsTask = supabase
            .from("body_mentions")
            .select("id, mentioned_at, body_area, side, severity_hint, verbatim_quote")
            .eq("user_id", value: userId)
            .gte("mentioned_at", value: startString)
            .order("mentioned_at", ascending: true)
            .limit(400)
            .execute()

        let (scoresRes, bioRes, logsRes, mentionsRes) =
            try await (scoresTask, bioTask, logsTask, mentionsTask)

        let decoder = JSONDecoder()
        let scoreRows = try decoder.decode([ScoreRow].self, from: scoresRes.data)
        let bioRows = try decoder.decode([BioRow].self, from: bioRes.data)
        let logRows = try decoder.decode([LogRow].self, from: logsRes.data)
        let mentionRows = try decoder.decode([MentionRow].self, from: mentionsRes.data)

        // ── Spine: one slot per calendar day, so gaps stay gaps ──────────
        var index: [String: Int] = [:]
        var days_: [ThreadDay] = []
        for offset in 0..<days {
            guard let d = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = dayFormatter.string(from: d)
            index[key] = days_.count
            days_.append(ThreadDay(dateString: key, date: d))
        }

        // ── LOAD ─────────────────────────────────────────────────────────
        // Latest score_version wins ('1.2' > '1.1' lexically, by design); a
        // day can carry several rows because old versions are never
        // recomputed in place.
        if let latest = scoreRows.map({ $0.score_version }).max() {
            for row in scoreRows where row.score_version == latest {
                guard let i = index[row.score_date] else { continue }
                days_[i].fitness = row.fitness
                days_[i].fatigue = row.fatigue
                days_[i].srpe = row.srpe ?? 0
                days_[i].loadComponents = row.stress_components ?? []
                days_[i].bodyComponents = row.recovery_components ?? []
                days_[i].recoveryConfidence = row.recovery_confidence ?? "none"
            }
        }

        // ── BODY ─────────────────────────────────────────────────────────
        var baselineHR: [Double] = []
        for row in bioRows {
            if let i = index[row.date] {
                days_[i].restingHR = (row.resting_hr ?? 0) > 0 ? row.resting_hr : nil
                days_[i].hrv = (row.hrv_rmssd ?? 0) > 0 ? row.hrv_rmssd : nil
                days_[i].sleepMinutes = (row.sleep_total_min ?? 0) > 0 ? row.sleep_total_min : nil
            } else if row.date < startString, let hr = row.resting_hr, hr > 0 {
                baselineHR.append(hr)   // behind the window: baseline only
            }
        }

        // ── VOICE ────────────────────────────────────────────────────────
        for row in logRows {
            guard let key = utcDay(fromTimestamp: row.workout_date),
                  let i = index[key] else { continue }
            // A day can carry several logs. First non-nil wins for the
            // scalars; memo text concatenates so a double day doesn't
            // silently drop half of what was said.
            if days_[i].mood == nil { days_[i].mood = row.mood }
            if days_[i].feltRPE == nil { days_[i].feltRPE = row.felt_rpe }
            if days_[i].pullQuote == nil {
                days_[i].pullQuote = ThreadText.authored(row.rpe_pull_quote)
            }
            if let memo = ThreadText.authored(row.cleaned_notes)
                ?? ThreadText.authored(row.notes) {
                days_[i].memo = days_[i].memo.map { "\($0)\n\n\(memo)" } ?? memo
            }
        }

        for row in mentionRows {
            guard let i = index[row.mentioned_at] else { continue }
            days_[i].niggles.append(
                ThreadNiggle(
                    id: row.id,
                    bodyArea: row.body_area,
                    side: row.side,
                    severityHint: row.severity_hint,
                    verbatimQuote: row.verbatim_quote
                ))
        }

        return ThreadWindow(
            days: days_,
            restingHRBand: ThreadBand.build(baselineHR),
            sleepMedian: ThreadBand.median(days_.compactMap { $0.sleepMinutes.map(Double.init) }),
            episodes: episodes(in: days_)
        )
    }

    /// Consecutive-ish niggle days collapsed into bands.
    static func episodes(in days: [ThreadDay]) -> [NiggleEpisode] {
        let marked = days.indices.filter { !days[$0].niggles.isEmpty }
        guard !marked.isEmpty else { return [] }

        var out: [NiggleEpisode] = []
        var runStart = marked[0]
        var runEnd = marked[0]

        func close() {
            let parts = Array(
                Set(days[runStart...runEnd].flatMap { $0.niggles.map(\.bodyArea) })
            ).sorted()
            out.append(
                NiggleEpisode(
                    startIndex: runStart, endIndex: runEnd,
                    startDate: days[runStart].date, endDate: days[runEnd].date,
                    parts: parts))
        }

        for i in marked.dropFirst() {
            if i - runEnd <= NiggleEpisode.joinGapDays {
                runEnd = i
            } else {
                close()
                runStart = i
                runEnd = i
            }
        }
        close()
        return out
    }
}
