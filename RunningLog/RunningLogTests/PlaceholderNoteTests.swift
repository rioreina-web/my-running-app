import Foundation
import Testing
@testable import RunningLog

// Guards for `PlaceholderNote.swift`. The list of titles here is pinned to the
// regex in `is_strava_placeholder_note`
// (supabase/migrations/20260618000000_dedupe_merge_precedence_fix.sql:37) — if
// these two ever disagree, the dedup merge and the UI are telling the athlete
// different stories about the same row.

@Suite("PlaceholderNote")
struct PlaceholderNoteTests {

    @Test("Strava's default titles are not the athlete's words",
          arguments: [
            "Morning Run", "Evening Run", "Afternoon Run", "Lunch Run",
            "Night Run", "Late Night Run", "Early Morning Run",
            "Morning Ride", "Evening Workout", "Afternoon Swim",
            "Morning Walk", "Evening Hike", "Lunch Activity",
          ])
    func defaultTitlesArePlaceholders(_ title: String) {
        #expect(PlaceholderNote.isPlaceholder(title))
        #expect(PlaceholderNote.athleteWords(title) == nil)
    }

    @Test("Case and surrounding whitespace don't smuggle a title through")
    func caseAndWhitespaceInsensitive() {
        #expect(PlaceholderNote.isPlaceholder("EVENING RUN"))
        #expect(PlaceholderNote.isPlaceholder("evening run"))
        #expect(PlaceholderNote.isPlaceholder("  Evening Run  "))
        #expect(PlaceholderNote.isPlaceholder("Evening   Run"))
        #expect(PlaceholderNote.isPlaceholder("Evening\tRun"))
    }

    @Test("Empty and absent notes are placeholders — the slot is free")
    func emptyIsPlaceholder() {
        #expect(PlaceholderNote.isPlaceholder(nil))
        #expect(PlaceholderNote.isPlaceholder(""))
        #expect(PlaceholderNote.isPlaceholder("   \n "))
    }

    @Test("A real memo survives untouched")
    func realMemoIsAthleteWords() {
        let memo = "I felt pretty comfortable on this moderate long run, taking two gels."
        #expect(!PlaceholderNote.isPlaceholder(memo))
        #expect(PlaceholderNote.athleteWords(memo) == memo)
    }

    @Test("A title the athlete chose is theirs, however short",
          arguments: [
            "Tempo",                       // custom, one word
            "Evening Run — legs felt dead", // Strava's title plus real words
            "Morning Runs",                // not the singular default
            "Run",                         // no time-of-day prefix
            "Morning",                     // no activity noun
            "Long Run",                    // "long" is not a time of day
            "Recovery Run",
          ])
    func customTitlesAreNotPlaceholders(_ title: String) {
        #expect(!PlaceholderNote.isPlaceholder(title))
        #expect(PlaceholderNote.athleteWords(title) == title)
    }

    @Test("athleteWords trims, so a quote never renders with stray padding")
    func athleteWordsTrims() {
        #expect(PlaceholderNote.athleteWords("  felt strong  ") == "felt strong")
    }
}
