import Foundation
import Testing
@testable import RunningLog

// Guards for the recovery-need DEMAND term and the quadrant read
// (`outputs/recovery-need-model-2026-08-06.md` §2 and §4).
//
// The properties defended here are the ones the design argues for explicitly,
// so a future tuning pass that quietly violates one fails here:
//
//   · carrying your usual load costs 0 (the 08-06 recalibration's fixed point)
//   · the warm-up gate withholds the index instead of inventing a hole
//   · demand and the old load pair are never both on the receipt
//   · `Clear` stays mathematically attainable
//   · low demand + dragging words is reachable — the cell that caught the only
//     real injury episode in the data, and the one a load-only score cannot
//     produce

// MARK: - Fixtures

private let isoDay: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

private func iso(_ i: Int) -> String {
    isoDay.string(from: Date(timeIntervalSince1970: 1_780_272_000 + Double(i) * 86_400))
}

/// `n` days whose mileage is chosen per index, with optional mood/duration.
private func series(
    _ n: Int,
    mood: (Int) -> String? = { _ in nil },
    duration: ((Int) -> Int?)? = nil,
    stress: ((Int) -> Double?)? = nil,
    miles: (Int) -> Double
) -> [TrendsDay] {
    (0..<n).map { i in
        let m = miles(i)
        return TrendsDay(
            date: iso(i),
            miles: m,
            type: .init(token: m > 0 ? "easy" : "rest"),
            mood: mood(i),
            niggles: [],
            durationMin: duration?(i),
            stressLoad: stress?(i)
        )
    }
}

/// A flat block — the same mileage every day.
private func flat(_ n: Int, miles: Double = 8) -> [TrendsDay] {
    series(n) { _ in miles }
}

private func factor(_ name: String, _ factors: [TrendsRecoveryLedger.Factor]) -> TrendsRecoveryLedger.Factor? {
    factors.first { $0.name == name }
}

// MARK: - The warm-up gate

@Suite("TrendsRecoveryDemand warm-up gate")
struct DemandWarmUpTests {

    @Test("under six weeks of history the need index is withheld, not zeroed")
    func gateClosed() {
        let days = flat(30)
        #expect(TrendsRecoveryDemand.balance(days: days, at: 29).needIndex == nil)
        #expect(TrendsRecoveryFactors.recoveryNeed(days: days, at: 29) == nil)
    }

    @Test("at six weeks the index opens")
    func gateOpens() {
        let days = flat(60)
        #expect(TrendsRecoveryDemand.balance(days: days, at: 59).needIndex != nil)
        #expect(TrendsRecoveryFactors.recoveryNeed(days: days, at: 59) != nil)
    }

    /// A closed gate must not strand the receipt without any load row at all —
    /// it falls back to the pair that shipped before this change.
    @Test("a closed gate falls back to the previous load pair")
    func gateClosedFallsBack() {
        let factors = TrendsRecoveryFactors.all(days: flat(30), at: 29)
        #expect(factor("Recovery need", factors) == nil)
        #expect(factor("Load", factors) != nil)
    }

    /// Load must never be counted twice. When demand is on, the old pair is off.
    @Test("demand and the old load pair are never both present")
    func noDoubleCounting() {
        let factors = TrendsRecoveryFactors.all(days: flat(60), at: 59)
        #expect(factor("Recovery need", factors) != nil)
        #expect(factor("Load", factors) == nil)
        #expect(factor("Recent load", factors) == nil)
    }
}

// MARK: - The need index

@Suite("TrendsRecoveryDemand need index")
struct DemandNeedIndexTests {

    /// The fixed point of the 2026-08-06 recalibration. Being in training is
    /// the normal state of an athlete in training; a score that charges for it
    /// can never read better than Worn during a healthy block. It must not
    /// subtract — and it must keep the +5 the shipped `loadVsBaseline` gave a
    /// steady block, or every well-managed block silently drops a band.
    @Test("carrying your usual load never subtracts")
    func usualLoadIsFree() throws {
        let f = try #require(TrendsRecoveryFactors.recoveryNeed(days: flat(90), at: 89))
        #expect(f.points == 5)
        #expect(f.evidence.contains("in line with your usual"))
    }

    /// A perfectly flat block must read exactly balanced. Seeding both EWMAs
    /// from the same mean is what makes this true; starting both at zero left
    /// a +13% phantom hole on this very series, since the 7-day mean converges
    /// in a fortnight and the 42-day one takes a quarter.
    @Test("a flat block has no cold-start bias")
    func noColdStartBias() throws {
        let index = try #require(TrendsRecoveryDemand.balance(days: flat(90), at: 89).needIndex)
        #expect(abs(index) < 0.5)
        // And at the gate itself, where the un-seeded version read +58%.
        let atGate = try #require(TrendsRecoveryDemand.balance(days: flat(45), at: 44).needIndex)
        #expect(abs(atGate) < 0.5)
    }

    @Test("a sharp ramp opens a hole and subtracts")
    func rampSubtracts() throws {
        // Eleven weeks steady, then a fortnight at triple.
        let days = series(90) { $0 < 76 ? 6 : 18 }
        let balance = TrendsRecoveryDemand.balance(days: days, at: 89)
        let index = try #require(balance.needIndex)
        #expect(index > 0)
        let f = try #require(TrendsRecoveryFactors.recoveryNeed(days: days, at: 89))
        #expect(f.points < 0)
        #expect(f.evidence.contains("over your usual"))
    }

    @Test("a taper closes the hole and credits")
    func taperCredits() throws {
        let days = series(90) { $0 < 76 ? 12 : 1 }
        let index = try #require(TrendsRecoveryDemand.balance(days: days, at: 89).needIndex)
        #expect(index < 0)
        let f = try #require(TrendsRecoveryFactors.recoveryNeed(days: days, at: 89))
        #expect(f.points > 0)
        #expect(f.evidence.contains("under your usual"))
    }

    /// It is a normalized DIFFERENCE against the athlete's own chronic load, so
    /// doubling every day's mileage must not change the reading. This is what
    /// makes it personal rather than a population threshold — and what lets the
    /// unit ladder swap units safely.
    @Test("the index is scale-free")
    func scaleFree() throws {
        let small = try #require(TrendsRecoveryDemand.balance(days: flat(90, miles: 3), at: 89).needIndex)
        let large = try #require(TrendsRecoveryDemand.balance(days: flat(90, miles: 30), at: 89).needIndex)
        #expect(abs(small - large) < 0.001)
    }
}

// MARK: - The load unit ladder

@Suite("TrendsRecoveryDemand load unit")
struct DemandLoadUnitTests {

    @Test("stress_load wins when every running day carries it")
    func prefersStressLoad() {
        let days = series(60, stress: { _ in 100 }) { _ in 8 }
        #expect(TrendsRecoveryDemand.loadUnit(for: days) == .stressLoad)
    }

    /// Partial coverage must NOT be mixed: an acute window denominated in
    /// stress_load against a chronic window denominated in duration would make
    /// the difference between them an artifact of the unit.
    @Test("partial stress_load coverage drops a rung rather than mixing units")
    func partialCoverageDropsARung() {
        let days = series(60, duration: { _ in 60 }, stress: { $0 > 30 ? 100 : nil }) { _ in 8 }
        #expect(TrendsRecoveryDemand.loadUnit(for: days) == .durationIntensity)
    }

    @Test("no duration at all falls to miles")
    func fallsToMiles() {
        #expect(TrendsRecoveryDemand.loadUnit(for: flat(60)) == .milesIntensity)
    }

    @Test("a rest day is a real zero, not missing data")
    func restIsZero() {
        let rest = TrendsDay(date: iso(0), miles: 0, type: .rest, mood: nil, niggles: [])
        #expect(TrendsRecoveryDemand.sessionLoad(rest, unit: .milesIntensity) == 0)
    }
}

// MARK: - The session spike

@Suite("TrendsRecoveryDemand session spike")
struct DemandSpikeTests {

    @Test("a day past twice the prior 30-day max is flagged")
    func spikeFlagged() throws {
        let days = series(60) { $0 == 59 ? 22 : 8 }
        let f = try #require(TrendsRecoveryFactors.sessionSpike(days: days, at: 59))
        #expect(f.points == -5)
        // Says "day", not "run" — the substrate sums doubles, and the receipt
        // must not overstate what was measured.
        #expect(f.evidence.contains("day"))
    }

    @Test("an ordinary long run is not a spike")
    func ordinaryLongRunIsNotASpike() {
        let days = series(60) { $0 == 59 ? 12 : 8 }
        #expect(TrendsRecoveryFactors.sessionSpike(days: days, at: 59) == nil)
    }

    @Test("a rest day is never a spike")
    func restIsNeverASpike() {
        let days = series(60) { $0 == 59 ? 0 : 8 }
        #expect(TrendsRecoveryFactors.sessionSpike(days: days, at: 59) == nil)
    }
}

// MARK: - The quadrant read

@Suite("TrendsRecoveryLedger quadrant")
struct RecoveryQuadrantTests {

    /// The cell the whole two-term split exists for: training is quiet, the
    /// words are low. A load-only readiness number cannot produce this, and it
    /// is the cell that caught the only real injury episode in the data.
    @Test("light training with dragging words reads as the tell, not as fresh")
    func quietButDragging() {
        let days = series(90, mood: { $0 >= 83 ? "struggling" : nil }) { $0 < 76 ? 12 : 1 }
        let ledger = TrendsRecoveryLedger.ledger(days: days, at: 89)
        #expect(ledger.supply == .dragging)
        #expect(ledger.quadrant == .quietButDragging)
    }

    @Test("light training with quiet words reads fresh")
    func fresh() {
        let days = series(90) { $0 < 76 ? 12 : 1 }
        let ledger = TrendsRecoveryLedger.ledger(days: days, at: 89)
        #expect(ledger.supply == .holding)
        #expect(ledger.quadrant == .fresh)
    }

    @Test("a big block the body is following reads as the flag")
    func followingDown() {
        let days = series(90, mood: { $0 >= 83 ? "struggling" : nil }) { $0 < 76 ? 6 : 18 }
        let ledger = TrendsRecoveryLedger.ledger(days: days, at: 89)
        #expect(ledger.quadrant == .followingDown)
    }

    @Test("a big block nothing is following reads as adapting")
    func adaptingWell() {
        let days = series(90) { $0 < 76 ? 6 : 18 }
        let ledger = TrendsRecoveryLedger.ledger(days: days, at: 89)
        #expect(ledger.quadrant == .adaptingWell)
    }

    @Test("a closed warm-up gate reports unknown rather than guessing")
    func unknownBeforeWarmUp() {
        #expect(TrendsRecoveryLedger.ledger(days: flat(20), at: 19).quadrant == .unknown)
    }

    /// Copy discipline — the read describes, never prescribes.
    @Test("no quadrant sentence uses a banned word")
    func sentencesStayInsideTheLint() {
        let banned = ["rest", "ice", "should", "must", "because", "caused",
                      "recovered", "ready", "risk"]
        let all: [TrendsRecoveryLedger.Quadrant] =
            [.adaptingWell, .followingDown, .fresh, .quietButDragging, .unknown]
        for quadrant in all {
            let words = quadrant.sentence.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
            for word in banned {
                #expect(!words.contains(word), "\(quadrant) says '\(word)'")
            }
        }
    }
}

// MARK: - Reachability, re-proved after the swap

@Suite("Recovery ledger reachability after the demand swap")
struct DemandReachabilityTests {

    /// The 08-05 retool existed because `Clear` (75) was mathematically
    /// unreachable against a 69-point ceiling. Replacing two load factors
    /// worth +11 at best with one worth +11 at best keeps that fix intact —
    /// capping the new factor lower would have silently reintroduced the bug.
    @Test("Clear is still attainable")
    func clearStaysAttainable() {
        #expect(TrendsRecoveryFactors.theoreticalRange.high >= 75)
    }

    @Test("the floor still clamps at 8")
    func floorClamps() {
        #expect(TrendsRecoveryFactors.theoreticalRange.low == 8)
    }
}
