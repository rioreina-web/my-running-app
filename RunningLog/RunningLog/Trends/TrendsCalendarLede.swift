//
//  TrendsCalendarLede.swift
//  RunningLog · Trends
//
//  The calendar's derived sentence — the spec's core rule ("state a conclusion
//  before you draw a picture, and compute it from the same data as the
//  picture"). Reports where the niggle mentions actually fell relative to load
//  and weekday. Co-occurrence only — it never says what a mention *means*.
//
//  This mirrors the `trends-insights` A1 (load-clustering) + A4 (weekday) logic
//  as a view-layer read of `TrendsDay`. When the endpoint's cards are wired in,
//  this can defer to them; until then it keeps the calendar honest on-device.
//

import Foundation

enum TrendsCalendarLede {

    /// The one or two derived sentences shown above the calendar grid.
    static func text(days: [TrendsDay], window: Int) -> String {
        let win = Array(days.suffix(window))
        let mentions = win.flatMap { d in d.niggles.map { (area: $0.area.lowercased(), date: d.date) } }

        if mentions.isEmpty {
            return "No body mentions in this window. Volume, mood and load are still plotted together — the quiet stretch is worth seeing too."
        }

        var counts: [String: Int] = [:]
        for m in mentions { counts[m.area, default: 0] += 1 }
        let (area, count) = counts.max { $0.value < $1.value }!

        if count < 2 {
            return "One mention in this window — \(area). One isn’t a pattern. It’s plotted here so you can see what it sat next to."
        }

        // Weekly mileage across the window, to rank "big" weeks.
        let weekly = weeklyMiles(win)                    // [(monday, miles)]
        guard !weekly.isEmpty else { return "" }
        let milesSorted = weekly.map(\.miles).sorted(by: >)
        let third = max(1, Int(ceil(Double(weekly.count) / 3.0)))
        let bigThreshold = milesSorted[min(third - 1, milesSorted.count - 1)]

        // Weeks that carried a mention of `area`, and their mileage.
        let hitMondays = Set(mentions.filter { $0.area == area }.compactMap { mondayOf($0.date) })
        let hitMiles = weekly.filter { hitMondays.contains($0.monday) }.map(\.miles)
        let bigHits = hitMiles.filter { $0 >= bigThreshold }
        let milesList = joinMiles(hitMiles)

        let load: String
        if bigHits.count == hitMiles.count {
            load = "Every \(area) mention lands in your highest-mileage weeks — \(milesList) miles. Nothing in the lighter ones. That shape is load-shaped; what it means is your call."
        } else if bigHits.isEmpty {
            load = "Your \(area) mentions don’t track your mileage — they fall in weeks of \(milesList) miles, none near your biggest. That’s a real finding, and a reassuring one."
        } else {
            let others = hitMiles.count - bigHits.count
            let tail = others == 1 ? "the other doesn’t" : "the others don’t"
            load = "\(bigHits.count) of \(hitMiles.count) \(area) mentions land in your bigger weeks (\(milesList) miles); \(tail). Too mixed to call a pattern either way."
        }

        // The weekday sentence — the one only a calendar earns.
        let dows = mentions.filter { $0.area == area }.compactMap { weekday($0.date) }
        if dows.count >= 2, dows.allSatisfy({ $0 == dows[0] }) {
            return load + " Every one of them lands on a \(dayName(dows[0]))."
        }
        return load
    }

    // MARK: - Date helpers (UTC, matching the endpoint's day keys)

    private static func parse(_ iso: String) -> Date? {
        let p = iso.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func mondayOf(_ iso: String) -> Date? {
        guard let d = parse(iso) else { return nil }
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d))
    }

    private static func weekday(_ iso: String) -> Int? {
        guard let d = parse(iso) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return (cal.component(.weekday, from: d) + 5) % 7   // Mon=0
    }

    private static func dayName(_ dow: Int) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][dow]
    }

    private static func weeklyMiles(_ days: [TrendsDay]) -> [(monday: Date, miles: Double)] {
        var byWeek: [Date: Double] = [:]
        for d in days {
            guard let monday = mondayOf(d.date) else { continue }
            byWeek[monday, default: 0] += d.miles
        }
        return byWeek.sorted { $0.key < $1.key }.map { (monday: $0.key, miles: $0.value) }
    }

    private static func joinMiles(_ ms: [Double]) -> String {
        let ints = ms.sorted(by: <).map { String(Int($0.rounded())) }
        if ints.count > 1 { return ints.dropLast().joined(separator: ", ") + " and " + ints.last! }
        return ints.first ?? "0"
    }
}
