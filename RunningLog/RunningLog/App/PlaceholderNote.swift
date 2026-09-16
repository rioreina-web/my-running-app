//
//  PlaceholderNote.swift
//  RunningLog
//
//  Is this text the athlete's own words, or is it Strava's?
//
//  Strava names every unnamed activity for the time of day it started —
//  "Morning Run", "Evening Run", "Afternoon Ride" — and that title syncs into
//  `training_logs.cleaned_notes` alongside real memo text. The two are
//  indistinguishable by type: both are a non-empty string in the same column.
//
//  The server already knows the difference. `is_strava_placeholder_note(text)`
//  (supabase/migrations/20260618000000_dedupe_merge_precedence_fix.sql:37) is
//  what stops the dedup merge letting a Strava title overwrite a voice memo.
//  The client had no equivalent test, so every surface that falls back to
//  `cleaned_notes` for "what the athlete said" treated the title as testimony:
//
//    • WorkoutRepReceiptView's memo slot rendered `NOTE — "Evening Run"`, and
//      because the slot was occupied, the RECORD VOICE MEMO affordance never
//      appeared — the fake note locked you out of leaving a real one.
//    • DayAnalysisSheet printed “Evening Run” in italic quotation marks under
//      the session header, in the same voice as an actual memo.
//
//  This is a hard-rule-#8 violation wearing a disguise: not an em-dash
//  placeholder, but a sentence the athlete never said, presented as if they had.
//
//  The pattern below is a deliberate byte-for-byte mirror of the SQL regex.
//  Two matchers that drift apart are worse than one — if you change this list,
//  change the migration in the same commit, and vice versa.
//

import Foundation

enum PlaceholderNote {
    /// Mirror of `is_strava_placeholder_note`'s regex. Anchored at both ends on
    /// purpose: "Evening Run" is Strava's, but "Evening Run — felt awful" is
    /// yours, and a custom title you actually chose is never a placeholder.
    private static let pattern =
        #"^(early morning|morning|lunch|afternoon|evening|night|late night)\s+(run|ride|workout|activity|swim|walk|hike)$"#

    /// True when `text` is empty or a Strava default activity title.
    static func isPlaceholder(_ text: String?) -> Bool {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return true }
        return t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `text` when it is the athlete's own words, else nil — so a caller can
    /// write `PlaceholderNote.athleteWords(row.cleanedNotes)` and get the
    /// correct empty state for free rather than remembering to guard.
    static func athleteWords(_ text: String?) -> String? {
        guard !isPlaceholder(text) else { return nil }
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
