//
//  TrendsPreviewData.swift
//  RunningLog · Trends
//
//  Preview fixtures for the Trends surfaces. Extracted 2026-08-05 from
//  `TrendsCalendarView.swift`, which was deleted with the rest of the orphaned
//  calendar work — the fixture outlived the view it was written for and has
//  four live call sites (`TrendsV2View`, `TrendsTabView`, `SignalLabView` and
//  the app's `-trendsV2Preview` scaffold).
//
//  Demo data only. Nothing here is reachable from a signed-in build.
//

import Foundation

extension TrendsDay {
    /// A "good data, hard block" arc — 12 weeks of a watch-worn athlete
    /// building volume into a heavy final week, with a fortnight of tired days
    /// and three right-achilles mentions in the recent big weeks. Long enough
    /// (84 days) to feed the calendar (Month/Block), the verdict, and the
    /// recovery day/week reads. Demo data for reviewing the populated surface.
    static var previewMonthRich: [TrendsDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyy-MM-dd"

        // Monday-align the start so weekly targets map cleanly to Mon–Sun weeks
        // (the recovery week model groups by ISO Monday). The final week is the
        // current, partial one (Mon…today).
        let todayDow = (cal.component(.weekday, from: today) + 5) % 7   // Mon=0
        let thisMonday = cal.date(byAdding: .day, value: -todayDow, to: today)!
        let startMonday = cal.date(byAdding: .day, value: -11 * 7, to: thisMonday)!
        let n = (cal.dateComponents([.day], from: startMonday, to: today).day ?? 0) + 1
        // Weekly mileage arc; the spike (60) is week 10 — the last COMPLETE
        // week — so the overload read fires on a full week, and week 11 is the
        // current partial week.
        let targets: [Double] = [34, 38, 36, 42, 45, 40, 47, 49, 44, 51, 60, 40]
        let share: [Double] = [0, 0.17, 0.13, 0.15, 0.10, 0.13, 0.30]   // Mon…Sun
        let warm = ["energized", "positive", "neutral", "positive", "energized"]
        let heavy = ["tired", "struggling", "tired", "neutral", "tired"]

        return (0..<n).map { i in
            let d = cal.date(byAdding: .day, value: i, to: startMonday)!
            let back = n - 1 - i
            let dow = i % 7                                   // Mon=0 (start is a Monday)
            let target = targets[min(targets.count - 1, i / 7)]
            let type: SessionChannel = dow == 0 ? .rest : dow == 1 ? .key : dow == 6 ? .long : .easy
            let miles = type == .rest ? 0 : (target * share[dow] * 10).rounded() / 10
            let recent = back < 14   // last fortnight reads tired
            let mood = type == .rest
                ? (recent ? "tired" : "positive")
                : (recent ? heavy[dow % heavy.count] : warm[dow % warm.count])
            // Achilles mentions on Sundays of the recent, bigger weeks.
            let niggles: [DayNiggle] = (dow == 6 && (i / 7) >= 6 && (i / 7) % 2 == 0)
                ? [DayNiggle(area: "achilles", side: "right", severity: "grumbling",
                             quote: "same right achilles — noticeable on the stairs after")]
                : []
            return TrendsDay(date: fmt.string(from: d), miles: miles, type: type, mood: mood, niggles: niggles)
        }
    }
}


// MARK: - Preview data

extension KeySession {
    /// Synthetic quality sessions across ~12 weeks — MP/HMP/5K each improving
    /// (neutral pace falling), for the ladder preview.
    static var previewLadder: [KeySession] {
        func mk(_ daysAgo: Int, _ zone: String, pace: Int, adj: Int, mi: Double) -> KeySession {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
            let d = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")!; f.dateFormat = "yyyy-MM-dd"
            let iso = f.string(from: d)
            return KeySession(id: iso + zone, date: iso, dateLabel: "", zone: zone,
                              workPaceSec: pace, workPaceAdjSec: adj, heatCategory: "warm",
                              workHrAvg: 158, structure: nil, distanceMi: mi,
                              qualityLoad: 20, kind: "quality")
        }
        return [
            mk(80, "mp", pace: 452, adj: 442, mi: 6), mk(52, "mp", pace: 446, adj: 436, mi: 8), mk(18, "mp", pace: 440, adj: 430, mi: 7),
            mk(74, "hmp", pace: 424, adj: 419, mi: 4), mk(40, "hmp", pace: 418, adj: 413, mi: 5), mk(12, "hmp", pace: 412, adj: 407, mi: 6),
            mk(60, "5k", pace: 382, adj: 378, mi: 3), mk(26, "5k", pace: 378, adj: 374, mi: 3.5),
            mk(30, "10k", pace: 398, adj: 394, mi: 4),   // single → withheld, named
        ]
    }
}
