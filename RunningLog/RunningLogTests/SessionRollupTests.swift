//
//  SessionRollupTests.swift
//  RunningLogTests
//
//  Pins the behaviour of `SessionRollup` — the layer that turns uploads into
//  the sessions The Sheet renders.
//
//  Every fixture here is a real shape from this athlete's `training_logs`,
//  rebuilt from LOCAL clock components so the suite is timezone-independent.
//  The dates matter: each one is a case that was wrong before this layer
//  existed, and each assertion below is the specific regression it prevents.
//
//    Aug 4  — five uploads, TWO sessions. Day-rollup reported one 15.7 mi
//             threshold day that never happened.
//    Aug 8  — an 18.1 mi long run and a 2.24 mi / 43 min evening walk.
//             Averaged together the long run read 8:01 instead of 6:38.
//    Jul 18 — a Strava row and a voice memo for the same run, five hours
//             apart on the clock. Counted twice = +13.49 mi of fiction, and
//             a session-gap test alone would never pair them.
//    Aug 5  — a 7:01pm run stored as `2026-08-06 00:01Z`. Grouped by a UTC
//             calendar it lands on the wrong date.
//

import Foundation
import Testing
@testable import RunningLog

// MARK: - Fixtures

private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    // Built from LOCAL components on purpose: the suite must pass in any
    // timezone, and the rollup's contract is about the athlete's local clock.
    var c = DateComponents()
    c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = minute
    return Calendar.current.date(from: c)!
}

private func row(
    _ date: Date,
    _ miles: Double,
    _ minutes: Double,
    _ type: String,
    mood: String? = nil,
    source: String = "strava",
    notes: String? = nil,
    audio: Bool = false
) -> TodayLogRow {
    TodayLogRow(
        id: UUID(), date: date, miles: miles, pace: nil, typeKey: type,
        mood: mood, coachInsight: nil, notes: notes, cleanedNotes: nil,
        durationMinutes: minutes, source: source,
        audioUrl: audio ? "memo.m4a" : nil, paceSegments: nil, parsed: nil
    )
}

private func mmss(_ seconds: Double?) -> String {
    guard let seconds else { return "" }
    return DistanceFormat.paceMMSS(secPerMile: seconds, unit: .miles)
}

// MARK: - Suite

@Suite("Session rollup")
struct SessionRollupTests {

    // Aug 4 2026: warm-up + threshold + cooldown in the morning, then a
    // double in the evening.
    private var aug4Rows: [TodayLogRow] {
        [
            row(at(8, 4, 6, 8), 1.76, 14, "recovery"),
            row(at(8, 4, 6, 28), 7.95, 48, "threshold", mood: "tired", audio: true),
            row(at(8, 4, 7, 23), 1.00, 9, "recovery", mood: "neutral", audio: true),
            row(at(8, 4, 17, 52), 3.97, 30, "easy"),
            row(at(8, 4, 18, 53), 1.00, 7, "easy")
        ]
    }

    @Test("A day's uploads split into sessions on the clock gap")
    func splitsIntoSessions() {
        let s = SessionRollup.sessions(from: aug4Rows)
        #expect(s.count == 2)

        // Chronological within the day, so the date numeral leads the block.
        #expect(s[0].start < s[1].start)
        #expect(s[0].isSecond == false)
        #expect(s[1].isSecond == true)

        #expect(abs(s[0].miles - 10.71) < 0.001)
        #expect(abs(s[1].miles - 4.97) < 0.001)
    }

    @Test("A session is named for its hardest piece, not its first")
    func namedForHardestPiece() {
        let s = SessionRollup.sessions(from: aug4Rows)
        // The 6:08am warm-up is `recovery`; the session is a threshold session.
        #expect(WorkoutLabel.display(s[0].typeKey) == "Threshold")
        #expect(s[0].isQuality)
        #expect(WorkoutLabel.display(s[1].typeKey) == "Easy")
    }

    @Test("Mood comes from the named piece, not from whichever leg got a memo")
    func moodFollowsIntent() {
        // Both the threshold rep and the cooldown carry a memo. The row must
        // speak with the session's voice — "tired" — not the cooldown's.
        let s = SessionRollup.sessions(from: aug4Rows)
        #expect(s[0].mood == "tired")
    }

    @Test("Splitting sessions never changes the totals")
    func totalsAreInvariant() {
        let deduped = aug4Rows.dedupedByPhysicalWorkout()
        let before = deduped.reduce(0) { $0 + ($1.miles ?? 0) }
        let after = SessionRollup.sessions(from: aug4Rows).reduce(0) { $0 + $1.miles }
        #expect(abs(before - after) < 0.001)
    }

    @Test("A long run is not averaged with the evening walk that followed it")
    func longRunKeepsItsPace() {
        // 18.10 mi in 120 min = 6:38. Rolled together with a 2.24 mi / 43 min
        // walk the same day, it reads 8:01 — which is the number the old
        // day-grouped sheet showed.
        let rows = [
            row(at(8, 8, 6, 36), 18.10, 120, "long_run", mood: "positive", audio: true),
            row(at(8, 8, 18, 17), 2.24, 43, "recovery")
        ]
        let s = SessionRollup.sessions(from: rows)
        #expect(s.count == 2)
        #expect(mmss(s[0].paceSeconds) == "6:38")
        #expect(mmss(s[1].paceSeconds) == "19:12")
    }

    @Test("A warm-up and its cooldown stay one session across a 65-minute gap")
    func gapToleranceHoldsSessionsTogether() {
        // Jul 21's real spacing. A 60-minute threshold would split this into
        // two sessions; 90 keeps it whole.
        let rows = [
            row(at(7, 21, 6, 5), 2.01, 16, "easy"),
            row(at(7, 21, 7, 26), 1.02, 8, "recovery")
        ]
        #expect(SessionRollup.sessions(from: rows).count == 1)
    }

    @Test("A voice memo mirroring a GPS run is counted once, words kept")
    func voiceMemoFoldsButStillSpeaks() {
        // Five hours apart on the clock — a session-gap test alone would never
        // pair these, which is why the voice/GPS fold must stay at DAY level.
        let words = "Good long run, had been feeling banged up with a sore left knee but felt ok."
        let rows = [
            row(at(7, 18, 1, 38), 13.49, 91, "long_run"),
            row(at(7, 18, 6, 38), 13.49, 91, "long_run", source: "voice_log", notes: words)
        ]
        let s = SessionRollup.sessions(from: rows)
        #expect(s.count == 1)
        #expect(abs(s[0].miles - 13.49) < 0.001)   // not 26.98
        #expect(s[0].foldedCount == 1)
        // The folded row is the ONLY carrier of the words. Reading notes from
        // the kept set alone loses them.
        #expect(s[0].note == words)
    }

    @Test("An evening run stays on its own local day")
    func eveningRunKeepsItsDate() {
        // Stored as 2026-08-06T00:01Z. Grouped by a UTC calendar it becomes an
        // Aug 6 run and, on the wrong week boundary, moves a week's mileage.
        let rows = [
            row(at(8, 5, 8, 18), 6.01, 47, "recovery"),
            row(at(8, 5, 19, 1), 4.01, 30, "easy")
        ]
        let s = SessionRollup.sessions(from: rows)
        #expect(s.count == 2)
        #expect(s.allSatisfy { $0.day == SessionRollup.localDay(at(8, 5, 12, 0)) })
    }

    @Test("Tags match on the normalized key, so legacy spellings still filter")
    func tagsUseNormalizedKeys() {
        // `tempo` and `interval` are both live in stored rows. A raw-key filter
        // silently drops them.
        let tempo = SessionRollup.sessions(from: [row(at(6, 17, 6, 30), 5.29, 31, "tempo")])[0]
        #expect(SessionTag.threshold.matches(tempo))
        #expect(SessionTag.key.matches(tempo))

        let interval = SessionRollup.sessions(from: [row(at(8, 11, 6, 29), 6.64, 40, "interval")])[0]
        #expect(SessionTag.intervals.matches(interval))
        #expect(SessionTag.key.matches(interval))
    }

    @Test("Doubles matches only a day's second and later sessions")
    func doublesTagMatchesSecondSessions() {
        let s = SessionRollup.sessions(from: aug4Rows)
        #expect(SessionTag.doubles.matches(s[0]) == false)
        #expect(SessionTag.doubles.matches(s[1]))
    }

    @Test("Search reaches the words on folded pieces")
    func searchReachesFoldedWords() {
        let rows = [
            row(at(7, 18, 1, 38), 13.49, 91, "long_run"),
            row(at(7, 18, 6, 38), 13.49, 91, "long_run",
                source: "voice_log", notes: "Sore left knee but felt ok.")
        ]
        let s = SessionRollup.sessions(from: rows)[0]
        #expect(s.matches(query: "knee"))
        #expect(s.matches(query: "elbow") == false)
    }

    @Test("A search snippet keeps the matched term visible")
    func snippetLeadsWithTheMatch() {
        // The column fits ~40 characters. A window centred on the match
        // ellipses the term itself away and explains nothing.
        let long = "I felt pretty comfortable on this moderate long run, taking two gels, "
                 + "and my knee settled after a few miles of easy running downhill."
        let s = SessionRollup.sessions(from: [
            row(at(8, 8, 6, 36), 18.10, 120, "long_run", notes: long)
        ])[0]

        let snip = s.snippet(for: "knee")
        #expect(snip != nil)
        if let snip {
            let offset = snip.text.distance(from: snip.text.startIndex, to: snip.match.lowerBound)
            #expect(offset < 20)
        }
    }

    @Test("Junk Strava titles are not quoted as diary entries")
    func junkTitlesAreNotWords() {
        let s = SessionRollup.sessions(from: [
            row(at(8, 7, 8, 3), 7.0, 53, "easy", notes: "Morning Run")
        ])[0]
        #expect(s.note == nil)
    }

    @Test("Pace is derived and never renders a :60 second")
    func paceNeverRendersSixtySeconds() {
        // 6.0 mi in 47.96 min = 479.6 s/mi. Flooring the minutes (7) and
        // rounding the remainder (59.6 → 60) independently prints "7:60"; the
        // correct carry is "8:00".
        //
        // (2026-08-24) The inputs used to be 6.1 mi in 48 min, which is
        // 472.13 s/mi — it renders "7:52" under both the naive and the correct
        // formatter, so it never exercised the carry, and the "8:00"
        // expectation was simply wrong arithmetic. The seconds remainder has
        // to land in [59.5, 60) for this test to mean anything.
        let s = SessionRollup.sessions(from: [
            row(at(7, 19, 6, 0), 6.0, 47.96, "intervals")
        ])[0]
        #expect(mmss(s.paceSeconds) == "8:00")
    }
}
