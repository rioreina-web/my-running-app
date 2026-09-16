import Foundation
import Testing
@testable import RunningLog

@Suite("PaceCalculator.parseTime")
struct PaceCalculatorParseTimeTests {
    @Test("marathon H:MM parses as hours and minutes")
    func marathonHMM() {
        #expect(PaceCalculator.parseTime("3:30", forDistance: "marathon") == 12600)
    }

    @Test("marathon 10:00 parses as 10 hours, not 10 minutes")
    func marathonTenHours() {
        #expect(PaceCalculator.parseTime("10:00", forDistance: "marathon") == 36000)
    }

    @Test("marathon H:MM:SS parses fully")
    func marathonHMMSS() {
        #expect(PaceCalculator.parseTime("3:30:15", forDistance: "marathon") == 12615)
    }

    @Test("10K MM:SS parses as minutes and seconds")
    func tenKMMSS() {
        #expect(PaceCalculator.parseTime("45:00", forDistance: "10K") == 2700)
    }

    @Test("mile MM:SS parses as minutes and seconds")
    func mileMMSS() {
        #expect(PaceCalculator.parseTime("5:30", forDistance: "mile") == 330)
    }

    @Test("half-marathon H:MM parses as hours and minutes")
    func halfHMM() {
        #expect(PaceCalculator.parseTime("1:40", forDistance: "half") == 6000)
    }

    @Test("10mi H:MM parses as hours and minutes")
    func tenMileHMM() {
        #expect(PaceCalculator.parseTime("1:10", forDistance: "10mi") == 4200)
    }

    @Test("invalid input returns nil")
    func invalidInput() {
        #expect(PaceCalculator.parseTime("abc", forDistance: "mile") == nil)
        #expect(PaceCalculator.parseTime("", forDistance: "mile") == nil)
    }
}

// MARK: - Heat intensity scaling (2026-08-05)

/// Mirrors the Deno suite in supabase/functions/_shared/pace-heat-adjustment.test.ts.
/// If one side changes and the other doesn't, these diverge — that's the point.
@Suite("PaceCalculator.heatIntensityFactor")
struct PaceCalculatorHeatIntensityTests {

    @Test("floor at recovery, full at LT and faster")
    func rampEndpoints() {
        let lt = 380.0                                   // 6:20/mi threshold
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 380, thresholdPaceSeconds: lt) == 1.0)
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 340, thresholdPaceSeconds: lt) == 1.0)
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 400, thresholdPaceSeconds: lt) == 1.0)
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 560, thresholdPaceSeconds: lt)
                == PaceCalculator.heatIntensityFloor)
        let mid = PaceCalculator.heatIntensityFactor(paceSeconds: 439.3, thresholdPaceSeconds: lt)
        #expect(abs(mid - 0.875) < 0.01)
    }

    @Test("no threshold anchor → the chart as published")
    func noAnchor() {
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 464, thresholdPaceSeconds: nil) == 1.0)
        #expect(PaceCalculator.heatIntensityFactor(paceSeconds: 464, thresholdPaceSeconds: 0) == 1.0)
    }

    @Test("the Aug 5 easy run is credited ~19s/mi, not 25")
    func aug5Regression() {
        // 7:44/mi at 78°F / 75°F dew, LT 322 (this athlete's real interpolated LT).
        let a = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: 464, temperatureF: 78, dewPointF: 75,
            distanceMiles: nil, thresholdPaceSeconds: 322)
        #expect(a.intensityFactor == PaceCalculator.heatIntensityFloor)
        let credit = a.originalPaceSeconds - a.neutralEquivalentPaceSeconds
        #expect(credit > 18 && credit < 20)

        // Unscaled, the chart still says 25 — that's what we walked back.
        let unscaled = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: 464, temperatureF: 78, dewPointF: 75)
        #expect((unscaled.originalPaceSeconds - unscaled.neutralEquivalentPaceSeconds).rounded() == 25)
    }

    @Test("prescription is NOT intensity-scaled; credit is")
    func creditOnly() {
        let easy = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: 464, temperatureF: 78, dewPointF: 75,
            distanceMiles: nil, thresholdPaceSeconds: 322)
        let unscaled = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: 464, temperatureF: 78, dewPointF: 75)
        #expect(abs(easy.adjustedPaceSeconds - unscaled.adjustedPaceSeconds) < 1e-9)
        #expect(easy.creditAdjustmentPercent < easy.effectiveAdjustmentPercent)
        #expect(easy.neutralEquivalentPaceSeconds > unscaled.neutralEquivalentPaceSeconds)
    }

    @Test("SHEET REFERENCE still holds — 5:15/mi at 78/75 → 5:33/mi")
    func sheetReferenceUnchanged() {
        let a = PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: 315, temperatureF: 78, dewPointF: 75)
        #expect(a.adjustedPaceSeconds.rounded() == 333)
    }
}
