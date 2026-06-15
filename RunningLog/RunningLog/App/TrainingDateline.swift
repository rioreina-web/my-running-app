import Foundation

// ============================================================================
// TrainingDateline
//
// The plate strip's trailing slot used to print a fake magazine figure number
// ("FIG. 09") — decoration pretending to be information. This replaces it with
// a real one: the runner's *training dateline*, the same way a magazine prints
// its issue date on every page.
//
// Rule (deliberately minimal — see the 2026-06-15 design note): if a goal race
// exists, show a countdown to it; otherwise show NOTHING. No fake fallback, no
// block-week placeholder. A dateline is only printed when it's true.
//
// Pure, deterministic, no I/O — the value derivation lives here so it can be
// reasoned about and unit-tested; the views just render the string.
// ============================================================================

enum TrainingDateline {

    /// The trailing dateline for a goal, or nil when there's no upcoming goal.
    /// `now` is injectable for testing. Past-dated goals return nil (the slot
    /// goes empty rather than counting up from a race that already happened).
    static func string(goalTitle: String, targetDate: Date, now: Date = Date()) -> String? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let target = cal.startOfDay(for: targetDate)
        guard let days = cal.dateComponents([.day], from: start, to: target).day else { return nil }
        if days < 0 { return nil } // goal is in the past — show nothing

        let label = raceLabel(from: goalTitle)
        if days == 0 { return "\(label) · TODAY" }
        if days == 1 { return "\(label) −1D" }
        if days < 100 { return "\(label) −\(days)D" }
        // Beyond ~3 months, weeks read cleaner than a big day count.
        let weeks = Int((Double(days) / 7.0).rounded())
        return "\(label) −\(weeks)W"
    }

    /// Convenience over the app's `UserGoal`. Pass the soonest active goal (or
    /// nil). Returns nil when there's nothing honest to print.
    static func string(for goal: UserGoal?, now: Date = Date()) -> String? {
        guard let goal else { return nil }
        return string(goalTitle: goal.goalTitle, targetDate: goal.targetDate, now: now)
    }

    // ── Label derivation ──
    // Turn a freeform goal title into a short, uppercase dateline token.
    // Priority: a named race/place > a distance keyword > "GOAL".
    //   "Sub-3:16 Berlin Marathon" → "BERLIN"
    //   "BQ attempt (marathon)"    → "MARATHON"   (no proper-noun place)
    //   "break 1:30 half"          → "HALF"
    //   "Boston"                   → "BOSTON"
    static func raceLabel(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "GOAL" }

        // 1. A proper-noun place/event name (a capitalized word that isn't a
        //    filler/qualifier or a distance word) reads best as the dateline.
        let fillers: Set<String> = [
            "sub", "break", "under", "goal", "race", "attempt", "bq",
            "qualifier", "qualify", "pr", "pb", "target", "the", "a", "for",
            "marathon", "half", "10k", "5k", "mile", "10-k", "5-k",
            // Common opening verbs / determiners so a sentence-initial word
            // ("Run a 10K…", "Fall marathon…") isn't mistaken for a place name.
            "run", "runner", "complete", "completed", "finish", "finished",
            "do", "my", "our", "big", "new", "first", "next", "day", "get",
            "hit", "beat", "go", "going", "train", "training", "prep", "build",
            "season", "fall", "spring", "summer", "winter", "autumn",
        ]
        let words = trimmed.split { $0 == " " || $0 == "-" || $0 == "(" || $0 == ")" }
            .map(String.init)
        for w in words {
            let bare = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;'\""))
            guard let first = bare.first else { continue }
            let isCapitalized = first.isUppercase && bare.dropFirst().contains { $0.isLowercase }
            let hasDigit = bare.contains { $0.isNumber }
            if isCapitalized, !hasDigit, !fillers.contains(bare.lowercased()) {
                return clamp(bare.uppercased())
            }
        }

        // 2. A distance keyword.
        let lower = trimmed.lowercased()
        if lower.contains("marathon") && !lower.contains("half") { return "MARATHON" }
        if lower.contains("half") { return "HALF" }
        if lower.range(of: #"\b10\s?k\b"#, options: .regularExpression) != nil { return "10K" }
        if lower.range(of: #"\b5\s?k\b"#, options: .regularExpression) != nil { return "5K" }
        if lower.contains("mile") { return "MILE" }

        // 3. Nothing recognizable — a clean generic marker.
        return "GOAL"
    }

    private static func clamp(_ s: String, max: Int = 12) -> String {
        s.count <= max ? s : String(s.prefix(max))
    }
}
