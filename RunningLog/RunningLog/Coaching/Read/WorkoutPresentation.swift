//
//  WorkoutPresentation.swift
//  RunningLog
//
//  The SINGLE source of truth for how a logged run is labelled, titled,
//  and summarized on the Coach Read surface. Replaces four divergent
//  functions that disagreed within one card:
//
//    - EvidenceChip.coachReadTypeLabel   (legacy TEMPO/THRESHOLD switch)
//    - EvidenceChip.coachReadDisplayTitle(first line of workout_notes —
//                                          often a parsed plan string)
//    - CoachReadView.workoutTitle        (distance + workout_type)
//    - TrainingLog.workoutTypeLabel      (yet another switch)
//
//  Design rules (see outputs/coach-read-effectiveness-plan-2026-06-12.md):
//
//  1. Labels come from the 10-zone taxonomy (CLAUDE.md 2026-05-28), NOT
//     the retired tempo/threshold/interval vocabulary. The zone is the
//     label.
//  2. Zone assignment is a COMPARISON against engine-provided zones
//     (PaceZonesService) — never on-device pace math. If zones are
//     unavailable we degrade to a neutral, non-misleading label rather
//     than re-asserting retired vocabulary.
//  3. Titles are NEVER sourced from workout_notes (those carry parsed
//     plan structure strings / km splits). Title = distance + zone.
//  4. The meta line reuses TrainingLog's own formatted accessors.
//

import Foundation

/// Canonical presentation of a logged run for the Coach Read.
struct WorkoutPresentation {
    /// Short uppercase eyebrow label, e.g. "MP", "EASY", "LT", "LONG".
    let label: String
    /// Display-cased card / sheet title, e.g. "6.6 mi · MP".
    let title: String
    /// Mono meta line: "6.6mi · 7:30/mi · 1h02m". Nil when nothing to show.
    let metaLine: String?
    /// The zone the run's average pace was classified into, if any. Nil
    /// when zones were unavailable or the run had no usable pace.
    let zone: CoachReadZone?

    /// Build a presentation for `log`, classifying against `zones` when
    /// available. Pass `PaceZonesService.shared.zones`.
    init(log: TrainingLog, zones: PaceZonesEngine?) {
        let avgPaceSec = WorkoutPresentation.averagePaceSeconds(for: log)
        let durationMin = log.workoutDurationMinutes
        let distance = log.workoutDistanceMiles

        let resolvedZone = WorkoutPresentation.classify(
            paceSeconds: avgPaceSec,
            distanceMiles: distance,
            durationMinutes: durationMin,
            zones: zones
        )
        self.zone = resolvedZone

        let label = resolvedZone?.shortLabel
            ?? WorkoutPresentation.neutralLabel(for: log)
        self.label = label

        if let d = distance {
            self.title = String(format: "%.1f mi · %@", d, label.capitalizedZone)
        } else {
            self.title = label.capitalizedZone
        }

        self.metaLine = WorkoutPresentation.metaLine(for: log)
    }

    // MARK: - Average pace

    /// Average pace in sec/mi. Prefers the stored `workout_pace_per_mile`
    /// string; falls back to distance ÷ duration. This is display-level
    /// arithmetic (already done by TrainingLog.formattedWorkoutPace), not
    /// pace-zone math.
    static func averagePaceSeconds(for log: TrainingLog) -> Double? {
        if let raw = log.workoutPacePerMile, let parsed = parsePaceString(raw) {
            return parsed
        }
        guard let miles = log.workoutDistanceMiles,
              let minutes = log.workoutDurationMinutes,
              miles > 0 else { return nil }
        return (minutes / miles) * 60.0
    }

    /// Parse "M:SS" → seconds. Returns nil for km-unit or malformed input.
    static func parsePaceString(_ raw: String) -> Double? {
        // Reject anything that looks like a km pace or carries units — the
        // Read must never echo plan-parsed km splits.
        let lowered = raw.lowercased()
        if lowered.contains("km") || lowered.contains("/k") { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let s = Int(parts[1].prefix(2)) else { return nil }
        return Double(m * 60 + s)
    }

    // MARK: - Classification

    /// Classify an average pace into the 10-zone taxonomy by COMPARING it
    /// against the athlete's engine-computed zones. Race-pace zones use
    /// midpoints between adjacent anchors as boundaries; effort zones use
    /// the engine ranges. Long runs are detected by duration/distance and
    /// take precedence over an Easy/Moderate classification (a long run is
    /// a long run regardless of how easy the pace).
    static func classify(
        paceSeconds: Double?,
        distanceMiles: Double?,
        durationMinutes: Double?,
        zones: PaceZonesEngine?
    ) -> CoachReadZone? {
        // Long-run override: ≥ 90 min or ≥ 13 mi reads as LONG.
        let isLong = (durationMinutes ?? 0) >= 90 || (distanceMiles ?? 0) >= 13.0
        if isLong { return .long }

        guard let pace = paceSeconds, let z = zones else { return nil }

        // Assemble the race-pace anchors we have, fastest → slowest.
        // (sec/mi ascending = faster pace first.)
        var anchors: [(zone: CoachReadZone, pace: Double)] = []
        if let p = z.mile?.pace { anchors.append((.mile, p)) }
        if let p = z.threeK?.pace { anchors.append((.threeK, p)) }
        if let p = z.fiveK?.pace { anchors.append((.fiveK, p)) }
        if let p = z.tenK?.pace { anchors.append((.tenK, p)) }
        if let p = z.thresholdPace { anchors.append((.lt, p)) }
        if let p = z.halfMarathon?.pace { anchors.append((.hmp, p)) }
        if let p = z.marathon?.pace { anchors.append((.mp, p)) }
        anchors.sort { $0.pace < $1.pace }

        // Effort-band fast bound (fastest of steady) — paces slower than
        // marathon pace fall into steady / moderate / easy by range.
        if let mp = z.marathon?.pace {
            // Faster than MP → race-pace classification by nearest-boundary.
            if pace < mp - 1 {
                return nearestRacePace(pace: pace, anchors: anchors) ?? .mp
            }
        }

        // Effort bands (slower end). Each is a closed range in sec/mi.
        if let steady = z.steady, pace <= steady.paceSlow + tolerance,
           pace >= steady.paceFast - tolerance {
            return .steady
        }
        if let moderate = z.moderate, pace <= moderate.paceSlow + tolerance,
           pace >= moderate.paceFast - tolerance {
            return .moderate
        }
        if let easy = z.easy {
            if pace >= easy.paceFast - tolerance { return .easy }
        }

        // Between MP and steady, or no effort band matched: nearest race
        // pace if we have anchors, else MP as the closest structured target.
        if pace < (z.steady?.paceFast ?? .greatestFiniteMagnitude) {
            return nearestRacePace(pace: pace, anchors: anchors) ?? .mp
        }
        return .easy
    }

    private static let tolerance: Double = 6.0 // sec/mi slack on band edges

    /// Nearest race-pace zone to `pace` using midpoints between adjacent
    /// anchors as decision boundaries.
    private static func nearestRacePace(
        pace: Double,
        anchors: [(zone: CoachReadZone, pace: Double)]
    ) -> CoachReadZone? {
        guard !anchors.isEmpty else { return nil }
        var best = anchors[0]
        var bestDelta = abs(pace - anchors[0].pace)
        for a in anchors.dropFirst() {
            let d = abs(pace - a.pace)
            if d < bestDelta { best = a; bestDelta = d }
        }
        return best.zone
    }

    // MARK: - Neutral fallback (zones unavailable)

    /// When we can't classify, never re-assert retired vocabulary. Use a
    /// neutral, honest label derived from duration/distance only.
    static func neutralLabel(for log: TrainingLog) -> String {
        if (log.workoutDurationMinutes ?? 0) >= 90 || (log.workoutDistanceMiles ?? 0) >= 13 {
            return CoachReadZone.long.shortLabel
        }
        // Non-running types we still recognize structurally.
        switch log.workoutType?.lowercased() {
        case "race": return "RACE"
        case "rest": return "REST"
        case "cross_train", "cross-train", "crosstrain": return "CROSS-TRAIN"
        case "strength": return "STRENGTH"
        default: return "RUN"
        }
    }

    // MARK: - Meta line

    static func metaLine(for log: TrainingLog) -> String? {
        var parts: [String] = []
        if let mi = log.workoutDistanceMiles {
            parts.append(String(format: "%.1fmi", mi))
        }
        if let sec = averagePaceSeconds(for: log) {
            let total = Int(sec.rounded())
            parts.append(String(format: "%d:%02d/mi", total / 60, total % 60))
        }
        if let min = log.workoutDurationMinutes {
            let total = Int(min.rounded())
            let h = total / 60
            let m = total % 60
            parts.append(h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - CoachReadZone

/// The canonical 10-zone taxonomy (CLAUDE.md 2026-05-28) plus the
/// structural Long label, as used by the Coach Read surface. Race-pace
/// zones are exact targets; effort zones are ranges. "Tempo" and
/// "Threshold" are intentionally absent — the zone IS the workout label.
///
/// Named distinctly from the chart-side `PaceZone` (an Int-based velocity
/// classifier in `WorkoutsView.swift`) because this taxonomy adds the
/// `lt` and `long` labels the chart enum doesn't carry.
enum CoachReadZone: String, CaseIterable {
    case easy, moderate, steady, long
    case mp, hmp, lt, tenK, fiveK, threeK, mile

    /// Uppercase eyebrow label.
    var shortLabel: String {
        switch self {
        case .easy: return "EASY"
        case .moderate: return "MODERATE"
        case .steady: return "STEADY"
        case .long: return "LONG"
        case .mp: return "MP"
        case .hmp: return "HMP"
        case .lt: return "LT"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        case .threeK: return "3K"
        case .mile: return "MILE"
        }
    }
}

private extension String {
    /// Title-case for effort words, but keep race-pace zone codes
    /// (MP, HMP, LT, 10K…) upper. "EASY" → "Easy"; "MP" → "MP".
    var capitalizedZone: String {
        switch self {
        case "EASY", "MODERATE", "STEADY", "LONG", "RUN", "RACE", "REST",
             "CROSS-TRAIN", "STRENGTH":
            return prefix(1) + dropFirst().lowercased()
        default:
            return self // MP, HMP, LT, 10K, 5K, 3K, MILE stay upper
        }
    }
}
