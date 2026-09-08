//
//  KeySessionTests.swift
//  RunningLogTests
//
//  Pins the resolution order for key sessions: athlete override beats plan
//  intent beats derived, first non-nil wins.
//
//  This is worth pinning hard because the failure it prevents is subtle and
//  was, for months, the actual behavior: four surfaces each guessing, and the
//  athlete unable to correct any of them. The tests below are the contract
//  that stops a fifth rule growing back.
//

import Testing
import Foundation
@testable import RunningLog

@Suite("Key session resolution")
struct KeySessionTests {

    // MARK: - Precedence

    @Test("Athlete override beats plan intent, both directions")
    func overrideBeatsIntent() {
        #expect(KeySessionMark.isKey(override: true, planIntent: false,
                                 derived: false, isFuture: false) == true)
        #expect(KeySessionMark.isKey(override: false, planIntent: true,
                                 derived: true, isFuture: false) == false)
    }

    @Test("Athlete override beats the derived rule, both directions")
    func overrideBeatsDerived() {
        // The un-star case: a day starred only because of a stray fast
        // stretch. This is the one the athlete complained about.
        #expect(KeySessionMark.isKey(override: false, planIntent: nil,
                                 derived: true, isFuture: false) == false)
        // And the mark case: an ordinary easy run the athlete calls key.
        #expect(KeySessionMark.isKey(override: true, planIntent: nil,
                                 derived: false, isFuture: false) == true)
    }

    @Test("Plan intent beats the derived rule when nothing was overridden")
    func intentBeatsDerived() {
        #expect(KeySessionMark.isKey(override: nil, planIntent: true,
                                 derived: false, isFuture: false) == true)
        #expect(KeySessionMark.isKey(override: nil, planIntent: false,
                                 derived: true, isFuture: false) == false)
    }

    @Test("With nothing declared, the derived rule decides")
    func derivedIsTheFallback() {
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: true, isFuture: false) == true)
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: false, isFuture: false) == false)
    }

    @Test("Nothing said anywhere, and nothing derivable, is not key")
    func silenceIsNotKey() {
        // nil derived means the surface can't score the day — e.g. quality_load
        // hasn't been computed. A missing star is honest; a wrong star is the
        // bug being fixed. Never fall back to a looser rule here.
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: nil, isFuture: false) == false)
    }

    // MARK: - The future

    @Test("A future day with plan intent IS key")
    func futureWithIntentIsKey() {
        // The case that couldn't exist before: a key session is a thing you
        // intend, so it's knowable before you run it.
        #expect(KeySessionMark.isKey(override: nil, planIntent: true,
                                 derived: nil, isFuture: true) == true)
    }

    @Test("A future day with no declaration is never key, whatever is derived")
    func futureWithoutIntentIsNotKey() {
        // There is no run to score yet. The derived rule must not apply to the
        // future even if a caller passes something optimistic.
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: true, isFuture: true) == false)
    }

    @Test("An athlete override still applies to a future day")
    func futureRespectsOverride() {
        #expect(KeySessionMark.isKey(override: true, planIntent: nil,
                                 derived: nil, isFuture: true) == true)
        #expect(KeySessionMark.isKey(override: false, planIntent: true,
                                 derived: nil, isFuture: true) == false)
    }

    // MARK: - Provenance

    @Test("Provenance names the level that decided, not the answer")
    func provenanceReportsTheDecidingLevel() {
        #expect(KeySessionMark.provenance(override: nil, planIntent: nil) == .auto)
        #expect(KeySessionMark.provenance(override: nil, planIntent: true) == .planned)
        #expect(KeySessionMark.provenance(override: nil, planIntent: false) == .planned)
        #expect(KeySessionMark.provenance(override: true, planIntent: nil) == .athlete)
        #expect(KeySessionMark.provenance(override: false, planIntent: true) == .athlete)
    }

    @Test("Agreement does not erase the athlete's mark")
    func agreementKeepsAthleteProvenance() {
        // A day the athlete marked key that ALSO derives as key is still
        // .athlete. The mark is a fact about intent; it shouldn't vanish just
        // because the app happened to agree.
        #expect(KeySessionMark.provenance(override: true, planIntent: nil) == .athlete)
    }

    @Test("Explicitly not-key is a real answer, not silence")
    func falseIsNotNil() {
        // The whole reason the field is Bool? and not Bool. Without the
        // nullable middle you can only fail to claim a day was key; you can't
        // say it wasn't — and "back to auto" becomes unreachable.
        #expect(KeySessionMark.provenance(override: false, planIntent: nil) == .athlete)
        #expect(KeySessionMark.isKey(override: false, planIntent: nil,
                                 derived: true, isFuture: false) == false)
    }

    // MARK: - The derived rule and the floor

    @Test("Derived key-ness is the load floor, nothing else")
    func derivedIsTheFloor() {
        // The floor is 25 weighted minutes, calibrated against 23 real
        // lap-scored sessions: stride sets land 5.4–13.1, the smallest genuine
        // session 42.1, and the interval between is empty.
        #expect(QualityLoad.qualifies(42.1) == true)
        #expect(QualityLoad.qualifies(13.1) == false)   // a stride set
        #expect(QualityLoad.qualifies(25) == true)      // exactly the floor
        #expect(QualityLoad.qualifies(24.9) == false)
    }

    @Test("An unscored day is not key, and is not the same as a zero day")
    func unscoredIsNotZero() {
        // nil means "we never scored this" — pre-migration, or a session with
        // no features computed. It must NOT fall back to a looser rule.
        #expect(QualityLoad.qualifies(nil) == false)
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: nil, isFuture: false) == false)
    }

    @Test("An easy run does not become key — the trap that stars every day")
    func easyRunIsNotKey() {
        // The iOS half of the named regression in _shared/qualityLoad.test.ts.
        // An ordinary easy run persists quality_load = NULL, so the day has no
        // score, so it is not key — no matter how long the run was.
        #expect(KeySessionMark.isKey(override: nil, planIntent: nil,
                                 derived: QualityLoad.qualifies(nil),
                                 isFuture: false) == false)
    }

    // MARK: - Day-key comparison

    @Test("String day keys sort chronologically, which is how future is judged")
    func dayKeysAreOrdered() {
        // isKey(onDayKey:) decides "future" with a string comparison. That is
        // only safe because "yyyy-MM-dd" is zero-padded and fixed-width — it
        // sorts lexicographically exactly as it sorts chronologically. Change
        // the format and that silently breaks.
        #expect("2026-08-07" < "2026-08-10")
        #expect("2026-08-09" < "2026-09-01")
        #expect("2026-12-31" < "2027-01-01")
    }

    // MARK: - Day keys

    @Test("Day keys are local dates, and stable")
    func dayKeyIsLocalAndStable() {
        // day_overrides.date is a LOCAL date (matching daily_checkins). A run
        // logged late in the evening must key to that day, not tomorrow UTC.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 7
        comps.hour = 21; comps.minute = 30
        let evening = Calendar.current.date(from: comps)!
        #expect(KeySessionStore.dayKey(evening) == "2026-08-07")

        comps.hour = 6; comps.minute = 15
        let morning = Calendar.current.date(from: comps)!
        #expect(KeySessionStore.dayKey(morning) == KeySessionStore.dayKey(evening))
    }
}
