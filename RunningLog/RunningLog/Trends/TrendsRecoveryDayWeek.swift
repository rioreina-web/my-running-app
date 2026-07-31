//
//  TrendsRecoveryDayWeek.swift
//  RunningLog · Trends
//
//  Approach A's two outer reads around the convergence card:
//    • Day to day — "push or pull today?" — a 7-day strip of clear/watch/hold
//      states + today's read. A STATE, never a 0–100 score.
//    • Week to week — "are you overloading?" — weekly load against the
//      athlete's OWN 8-week trailing baseline, plus an acute single-session
//      spike flag. NO acute:chronic ratio (that number was dismantled — see
//      load-recovery-ratio-2026-07-27.md); load-vs-your-own-baseline is the
//      evidence-consistent overload read.
//
//  Both derive from `TrendsDay` (`buildDailyTimeline`). Biometrics, when
//  present, only sharpen today's day-read; the week read needs no watch.
//

import SwiftUI

// MARK: - Shared

enum DayReadState {
    case clear, watch, hold

    var color: Color {
        switch self {
        case .clear: Color.drip.energized     // green — mood palette, not pace/alert
        case .watch: Color.drip.tired          // amber
        case .hold:  Color.drip.struggling     // terracotta
        }
    }
    var headline: String {
        switch self {
        case .clear: "Today: clear to push."
        case .watch: "Today: ease into it."
        case .hold:  "Today: hold back."
        }
    }
}

/// "yyyy-MM-dd" → UTC Date (matches the endpoint's day keys).
private func parseDay(_ iso: String) -> Date? {
    let p = iso.split(separator: "-")
    guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: y, month: m, day: d))
}

private let weekdayAbbr = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

// MARK: - Day to day

struct RecoveryDayModel {
    struct Day: Identifiable { let id: Int; let label: String; let state: DayReadState }
    let week: [Day]            // last 7, oldest → newest
    let todayState: DayReadState
    let todayNote: String

    init(days: [TrendsDay], biometrics: RecoveryBiometrics?) {
        let last = Array(days.suffix(7))
        var out: [Day] = []
        for (i, d) in last.enumerated() {
            let globalIdx = days.count - last.count + i
            var concerns = 0
            if let m = d.mood?.lowercased(), m == "tired" || m == "struggling" { concerns += 1 }
            // Load carryover: a long run today or yesterday sits on today's legs.
            let prev = globalIdx > 0 ? days[globalIdx - 1] : nil
            if d.type == .long || prev?.type == .long { concerns += 1 }
            // Biometrics only sharpen TODAY (the one morning we have a reading for).
            if i == last.count - 1, let b = biometrics, b.hrvDown && b.rhrUp { concerns += 1 }
            let state: DayReadState = concerns >= 2 ? .hold : concerns == 1 ? .watch : .clear
            let label = parseDay(d.date).map { dt -> String in
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
                return weekdayAbbr[(cal.component(.weekday, from: dt) + 5) % 7]
            } ?? ""
            out.append(Day(id: i, label: label, state: state))
        }
        week = out
        todayState = out.last?.state ?? .clear

        // Today's read — named from the signals actually present.
        let today = last.last
        let yesterday = last.count >= 2 ? last[last.count - 2] : nil
        var reasons: [String] = []
        if let b = biometrics, b.hrvDown && b.rhrUp {
            reasons.append("HRV sat low and resting HR high overnight")
        }
        let heavyMoodDays = last.filter { d in
            guard let m = d.mood?.lowercased() else { return false }
            return m == "tired" || m == "struggling"
        }.count
        if let m = today?.mood?.lowercased(), m == "tired" || m == "struggling" {
            reasons.append(heavyMoodDays >= 3 ? "you’ve logged several tired days this week" : "you read tired today")
        }
        if yesterday?.type == .long || today?.type == .long {
            reasons.append("a long run is in your legs")
        }
        if reasons.isEmpty {
            todayNote = "Nothing is stacking up — mood, load and the overnight numbers are all sitting easy. You’re clear to push."
        } else {
            let joined = reasons.count > 1
                ? reasons.dropLast().joined(separator: ", ") + ", and " + reasons.last!
                : reasons.first!
            let tail = todayState == .hold ? " Keep today easy." : " Nothing alarming, just worth a lighter touch."
            todayNote = joined.prefix(1).uppercased() + joined.dropFirst() + "." + tail
        }
    }
}

struct TrendsRecoveryDayView: View {
    let days: [TrendsDay]
    var biometrics: RecoveryBiometrics? = nil
    private var m: RecoveryDayModel { RecoveryDayModel(days: days, biometrics: biometrics) }

    var body: some View {
        let model = m
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(model.week) { d in
                    VStack(spacing: 5) {
                        Circle().fill(d.state.color).frame(width: 16, height: 16)
                        Text(d.label.uppercased()).font(.dripCaption(8))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text(model.todayState.headline)
                .font(.dripDisplay(17))
                .foregroundStyle(model.todayState == .hold ? Color.drip.coral : Color.drip.textPrimary)
                .padding(.top, 12)
            Text(model.todayNote)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Text("clear · watch · hold — a state, never a number")
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 10)
        }
    }
}

// MARK: - Week to week

struct RecoveryWeekModel {
    struct Bar: Identifiable { let id: Int; let miles: Double; let isReference: Bool; let isPartial: Bool }
    let bars: [Bar]            // up to 12 trailing weeks, oldest → newest
    /// The most recent COMPLETE week — the overload read compares this, not the
    /// current partial week (spec: label the partial week, don't extrapolate).
    let referenceMiles: Double
    let baselineMiles: Double  // 8-week trailing mean, before the reference week
    let pct: Int
    /// True when the current (newest) week is still in progress.
    let hasPartial: Bool
    /// A single run more than 100% longer than the longest in the prior 30
    /// days — the one load signal the evidence backs (HRR 2.28).
    let spike: (miles: Double, priorMax: Double)?

    init(days: [TrendsDay], today: Date = Date()) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let todayUTC = cal.startOfDay(for: today)
        let weekly = Self.weeklyMiles(days)          // [(monday, miles)] oldest → newest

        // A week is partial when its Sunday is on/after today.
        func partial(_ monday: Date) -> Bool {
            let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday
            return sunday >= todayUTC
        }
        // Reference = last complete week; baseline = the 8 complete weeks before it.
        let refIdx = weekly.lastIndex { !partial($0.monday) }
        referenceMiles = refIdx.map { weekly[$0].miles } ?? (weekly.last?.miles ?? 0)
        let prior = refIdx.map { Array(weekly[..<$0]) } ?? Array(weekly.dropLast())
        let priorMiles = prior.suffix(8).map(\.miles)
        baselineMiles = priorMiles.isEmpty ? 0 : priorMiles.reduce(0, +) / Double(priorMiles.count)
        pct = baselineMiles > 0 ? Int(((referenceMiles / baselineMiles) - 1) * 100) : 0
        hasPartial = weekly.last.map { partial($0.monday) } ?? false

        let trailing = Array(weekly.suffix(12))
        let refMonday = refIdx.map { weekly[$0].monday }
        bars = trailing.enumerated().map { i, w in
            Bar(id: i, miles: w.miles, isReference: w.monday == refMonday, isPartial: partial(w.monday))
        }
        spike = Self.acuteSpike(days)
    }

    /// Group dense daily miles into Monday-first (ISO) weeks.
    private static func weeklyMiles(_ days: [TrendsDay]) -> [(monday: Date, miles: Double)] {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        var byWeek: [Date: Double] = [:]
        for d in days {
            guard let date = parseDay(d.date) else { continue }
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            guard let monday = cal.date(from: comps) else { continue }
            byWeek[monday, default: 0] += d.miles
        }
        return byWeek.sorted { $0.key < $1.key }.map { (monday: $0.key, miles: $0.value) }
    }

    /// The most recent day whose miles exceed 2× the largest single day in the
    /// preceding 30 days. Returns nil on a gradual ramp — which is correct: a
    /// build without an outlier has no acute spike, only elevated load.
    private static func acuteSpike(_ days: [TrendsDay]) -> (miles: Double, priorMax: Double)? {
        let recent = max(days.count - 14, 0)
        for i in stride(from: days.count - 1, through: recent, by: -1) {
            let m = days[i].miles
            if m <= 0 { continue }
            let priorStart = max(0, i - 30)
            let priorMax = days[priorStart..<i].map(\.miles).max() ?? 0
            if priorMax > 0 && m > 2 * priorMax {
                return (miles: m, priorMax: priorMax)
            }
        }
        return nil
    }
}

struct TrendsRecoveryWeekView: View {
    let days: [TrendsDay]
    private var m: RecoveryWeekModel { RecoveryWeekModel(days: days) }

    var body: some View {
        let model = m
        VStack(alignment: .leading, spacing: 0) {
            ramp(model)
                .frame(height: 76)
                .padding(.bottom, 8)

            (Text(model.hasPartial ? "Last full week " : "This week ")
                + Text("\(Int(model.referenceMiles.rounded())) mi").bold()
                + Text(" · your 8-week average is ")
                + Text("\(Int(model.baselineMiles.rounded()))").bold()
                + Text(model.pct >= 0 ? " — up \(model.pct)%" : " — down \(abs(model.pct))%").bold()
                + Text(model.pct >= 25 ? ", the steepest jump in the block." : "."))
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let s = model.spike {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.drip.coral).frame(width: 7, height: 7)
                    Text("Acute spike · \(Int(s.miles.rounded())) mi run, over 100% longer than your last 30 days")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }

            Text("load vs your own trailing baseline — no acute:chronic ratio")
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 10)
        }
    }

    private func ramp(_ model: RecoveryWeekModel) -> some View {
        GeometryReader { geo in
            let maxM = max(model.bars.map(\.miles).max() ?? 1, 1)
            let baseY = geo.size.height * (1 - CGFloat(model.baselineMiles / maxM))
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(model.bars) { b in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(b.isReference ? Color.drip.coral
                                  : Color.drip.textPrimary.opacity(b.isPartial ? 0.13 : 0.28))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, geo.size.height * CGFloat(b.miles / maxM)))
                    }
                }
                // Your own 8-week baseline.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: baseY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: baseY))
                }
                .stroke(Color.drip.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}
