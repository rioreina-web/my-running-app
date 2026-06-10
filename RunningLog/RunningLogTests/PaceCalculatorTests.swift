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
