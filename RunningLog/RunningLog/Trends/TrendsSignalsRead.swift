//
//  TrendsSignalsRead.swift
//  RunningLog · Trends
//
//  "What moved" — the line that replaced the recovery score (2026-08-24).
//
//  ── Why this exists ───────────────────────────────────────────────────────
//
//  The score's job was the five-second read: open the tab, learn something.
//  It could not do that job — over 214 days it never left a 37-point strip,
//  had no relationship with `felt_rpe`, and did not separate the days the
//  athlete rested from the days they ran. Deleting it left the five-second
//  read unowned, and six lanes of chart do not fill that hole: they ask the
//  athlete to synthesise, every single time they look.
//
//  So this does the one thing the score was reaching for and got wrong. It
//  names the signals that are OUTSIDE the athlete's own usual range right
//  now, and says nothing at all about the ones that aren't. Most days that
//  is a very short list, and some days it is empty — which is the honest
//  answer and the one a score can never give, because a score must print a
//  number every morning whether or not anything happened.
//
//  ── The rules it will not break ───────────────────────────────────────────
//
//  1. NOTHING IS COMPOSED. Each item names one signal. Two signals moving
//     never merge into a third figure — that summing is exactly what made the
//     old number cancel itself out.
//  2. NO VERDICT, NO INSTRUCTION. Items report a measurement and its
//     distance from that athlete's own normal. A resting HR above your usual
//     is not "bad"; one night cannot separate fatigue from a late meal, a
//     warm room, alcohol or a cold. Banned from every string here, the same
//     list the retired ledger's copy was checked against: rest / ice /
//     should / must / because / caused / recovered / ready / risk.
//  3. SILENCE IS A RESULT. `items` empty is a first-class state with its own
//     sentence, never an empty view and never padding to fill the card.
//  4. EVERY ITEM CARRIES ITS EVIDENCE. `detail` names the measurement, the
//     baseline it was read against, and the dates. No claim without a receipt.
//
//  Deterministic and free of SwiftUI on purpose: this is arithmetic over
//  `TrendsDay`, so it can be reasoned about and tested without a screen, and
//  no model is ever asked to decide what moved.
//

import Foundation

struct TrendsSignalsRead {

    /// One thing worth naming. `detail` is the receipt for `text`.
    struct Item: Identifiable {
        let id = UUID()
        /// The finding, in the athlete's units.
        let text: String
        /// The evidence: the baseline it was measured against, and when.
        let detail: String
        /// Which signal it came from, so a tap can open that lane.
        let lane: TrendsMoodLane?
    }

    let items: [Item]

    /// True when every signal sits inside its own usual range. Not an error
    /// and not an empty state — see rule 3.
    var isQuiet: Bool { items.isEmpty }

    // MARK: - Windows
    //
    // These mirror the nightly lanes exactly (`TrendsBiometrics`), so the
    // sentence at the top of the section and the charts under it can never
    // disagree about what "usual" means.

    /// Nights read for a direction. One night is not a trend — the retired
    /// `overnight` factor used seven for the same reason and this keeps it.
    static let directionNights = 7
    /// How far back a single night is still worth naming on its own.
    static let standoutNights = 14
    /// How far back the athlete's own words are still current.
    static let mentionNights = 10
    /// Nights of silence from a channel before the silence is the finding.
    static let staleNights = 2
    /// Distance from baseline, in SD, at which a *window* has left the band.
    static let bandSD = 0.5
    /// Distance at which a *single night* is worth naming by itself. A
    /// seven-day mean would average it away — the 3h17m night on 2026-08-21
    /// is 2.9 SD out and moves the weekly mean by less than half a band.
    static let standoutSD = 2.0

    // MARK: - Build

    static func read(days: [TrendsDay]) -> TrendsSignalsRead {
        guard days.count > TrendsBiometrics.baselineDays else {
            return TrendsSignalsRead(items: [])
        }
        var out: [Item] = []

        // Nightly channels, in the order the athlete meets them on the card.
        for channel in Channel.allCases {
            out.append(contentsOf: channel.items(days: days))
        }

        // A channel that has stopped reporting, named once across all of them.
        if let silence = silenceItem(days: days) { out.append(silence) }

        // Training load, against this athlete's own weeks rather than a
        // constant. `stress_load` is the only signal with ~100% coverage.
        if let load = loadItem(days: days) { out.append(load) }

        // The athlete's own words. Surfaced, never interpreted.
        if let mentions = mentionItem(days: days) { out.append(mentions) }

        return TrendsSignalsRead(items: out)
    }

    // MARK: - Nightly channels

    enum Channel: CaseIterable {
        case sleep, restingHR, hrv

        var lane: TrendsMoodLane {
            switch self {
            case .sleep: .sleep
            case .restingHR: .restingHR
            case .hrv: .hrv
            }
        }

        var noun: String {
            switch self {
            case .sleep: "sleep"
            case .restingHR: "resting HR"
            case .hrv: "HRV"
            }
        }

        func value(_ day: TrendsDay) -> Double? {
            switch self {
            case .sleep: day.sleepTotalMin.map(Double.init)
            case .restingHR: day.restingHr
            case .hrv: day.hrvRmssd
            }
        }

        /// Native units, spoken the way the athlete says them.
        func format(_ v: Double) -> String {
            switch self {
            case .sleep:
                let m = Int(v.rounded())
                return "\(m / 60)h \(String(format: "%02d", m % 60))m"
            case .restingHR: return "\(Int(v.rounded())) bpm"
            case .hrv: return "\(Int(v.rounded())) ms"
            }
        }

        func items(days: [TrendsDay]) -> [Item] {
            // A channel the athlete has never had says nothing at all. An
            // absent signal is not a finding about the athlete — it is a
            // finding about the watch, and the lane already draws it.
            guard days.contains(where: { value($0) != nil }) else { return [] }

            let end = days.count
            let baseUpper = max(0, end - TrendsSignalsRead.directionNights)
            let baseLower = max(0, baseUpper - TrendsBiometrics.baselineDays)
            let base = days[baseLower..<baseUpper].compactMap(value)
            guard base.count >= TrendsBiometrics.minBaselineNights else { return [] }

            let mean = base.reduce(0, +) / Double(base.count)
            let sd = TrendsBiometrics.stdev(base)
            guard sd > 0 else { return [] }

            var out: [Item] = []

            // 1 · One night far enough out to name on its own.
            let recent = days.suffix(TrendsSignalsRead.standoutNights)
            let worst = recent.compactMap { day -> (TrendsDay, Double)? in
                guard let v = value(day) else { return nil }
                return (day, (v - mean) / sd)
            }
            .filter { abs($0.1) >= TrendsSignalsRead.standoutSD }
            .max { abs($0.1) < abs($1.1) }

            if let (day, z) = worst, let v = value(day) {
                out.append(Item(
                    text: "One night at \(format(v)) on \(TrendsSignalsRead.label(day.date)).",
                    detail: "\(String(format: "%.1f", abs(z))) SD \(z < 0 ? "below" : "above") your usual \(format(mean))",
                    lane: lane
                ))
            }

            // 2 · The seven-day direction. Skipped when a standout night
            //     already carries the window, so one bad night is not
            //     reported twice in two different registers.
            let window = days.suffix(TrendsSignalsRead.directionNights).compactMap(value)
            if worst == nil, window.count >= 3 {
                let wMean = window.reduce(0, +) / Double(window.count)
                let z = (wMean - mean) / sd
                if abs(z) >= TrendsSignalsRead.bandSD {
                    out.append(Item(
                        text: "\(noun.capitalizedFirst) has averaged \(format(wMean)) across \(window.count) of the last \(TrendsSignalsRead.directionNights) nights, \(z > 0 ? "above" : "below") your usual.",
                        detail: "\(format(mean)) usual · \(String(format: "%.1f", abs(z))) SD out",
                        lane: lane
                    ))
                }
            }

            return out
        }

        /// Nights since this channel last reported. `nil` when it never has.
        func staleness(days: [TrendsDay]) -> Int? {
            guard let i = days.lastIndex(where: { value($0) != nil }) else { return nil }
            return days.count - 1 - i
        }
    }

    // MARK: - Silence

    /// A channel that has gone quiet is a fact about the DATA, and it is the
    /// one thing a chart of the readings structurally cannot show — a gap in
    /// a lane looks identical to a lane you haven't scrolled to.
    ///
    /// Reported as one line across every quiet channel rather than one line
    /// each: a watch that stopped syncing takes them all down together, and
    /// three identical sentences read as three problems.
    static func silenceItem(days: [TrendsDay]) -> Item? {
        let quiet = Channel.allCases.compactMap { ch -> (Channel, Int)? in
            guard let gap = ch.staleness(days: days), gap >= staleNights else { return nil }
            return (ch, gap)
        }
        guard let first = quiet.first else { return nil }
        let nouns = quiet.map(\.0.noun).joined(separator: " or ")
        let gap = quiet.map(\.1).min() ?? first.1
        let newest = days.lastIndex(where: { first.0.value($0) != nil }).map { label(days[$0].date) } ?? "—"
        return Item(
            text: "No \(nouns) \(quiet.count > 1 ? "readings" : "reading") for \(gap) nights.",
            detail: "newest is \(newest) · nothing to place against your usual since",
            lane: first.0.lane
        )
    }

    // MARK: - Load

    /// Rolling seven-day sums across the timeline, so "a big week" is measured
    /// against this athlete's own weeks and not a population constant.
    static func loadItem(days: [TrendsDay]) -> Item? {
        let daily = days.map { day -> Double in
            if let zones = day.zoneLoad, !zones.isEmpty { return zones.values.reduce(0, +) }
            return day.stressLoad ?? 0
        }
        guard daily.count >= directionNights * 2 else { return nil }

        var sums: [Double] = []
        for i in (directionNights - 1)..<daily.count {
            sums.append(daily[(i - directionNights + 1)...i].reduce(0, +))
        }
        guard let now = sums.last, sums.count > 1 else { return nil }
        let mean = sums.reduce(0, +) / Double(sums.count)
        let sd = TrendsBiometrics.stdev(sums)
        guard sd > 0 else { return nil }

        let z = (now - mean) / sd
        guard abs(z) >= bandSD else { return nil }

        let miles = days.suffix(directionNights).reduce(0.0) { $0 + $1.miles }
        return Item(
            text: "This week carries \(Int(now.rounded())) TLS, \(z > 0 ? "over" : "under") your usual week.",
            detail: "\(String(format: "%.1f", miles)) miles · \(Int(mean.rounded())) usual · \(String(format: "%.1f", abs(z))) SD out",
            lane: .load
        )
    }

    // MARK: - Body mentions

    /// The athlete's own words, surfaced verbatim and counted. Never a
    /// severity, never an area we inferred, never a diagnosis — the closed
    /// vocabulary and the surface-don't-interpret rule both hold here.
    static func mentionItem(days: [TrendsDay]) -> Item? {
        let recent = days.suffix(mentionNights).filter { !$0.niggles.isEmpty }
        guard !recent.isEmpty else { return nil }

        let areas = Array(Set(recent.flatMap { $0.niggles.map { $0.area.lowercased() } })).sorted()
        let phrase = areas.count == 1
            ? areas[0]
            : areas.dropLast().joined(separator: ", ") + " and " + (areas.last ?? "")

        return Item(
            text: "\(phrase.capitalizedFirst) mentioned on \(recent.count) of the last \(mentionNights) days.",
            detail: recent.map { label($0.date) }.joined(separator: " · "),
            lane: .niggles
        )
    }

    // MARK: - Dates

    /// "Aug 21", from the ISO day. Shares `TrendsWeekday`'s parse so a date
    /// spoken here and the column it points at cannot drift.
    static func label(_ iso: String) -> String {
        TrendsSignalBuilder.shortLabel(iso)
    }
}

private extension String {
    /// Sentence case without touching the rest of the string — `capitalized`
    /// would turn "resting HR" into "Resting Hr".
    var capitalizedFirst: String {
        guard let f = first else { return self }
        return f.uppercased() + dropFirst()
    }
}
