//
//  TrendsRecoveryView.swift
//  RunningLog · Trends
//
//  The Trends-v2 recovery card (spec §5): recovery as CONVERGENCE, not a
//  score. There is no 0–100 readiness number and there never will be — the
//  card runs the convergence rule and reports what it found.
//
//  Signals are tiered by evidence weight (recovery-trend-v2 §2b):
//    • Tier 1 — the athlete's own words (niggles, mood). LEADS: the runner
//      literature puts the predictive signal in cheap self-report.
//    • Tier 2 — overnight biometrics (resting HR, HRV). Corroborate only,
//      read only as a pair. No `daily_biometrics` yet → "no watch data".
//    • Tier 3 — annotation (load). Never agrees or disagrees.
//
//  Tier 1 needs NO watch data, so this card is honest and useful today. All
//  signals derive from `TrendsDay` (`buildDailyTimeline`); a card can't drift
//  from the calendar it sits under.
//
//  Copy carries the recovery-trend-v2 §4 ban: no "readiness", "recovered",
//  "ready", "risk", no numeric score. Coral stays on the state headline only.
//

import SwiftUI

struct TrendsRecoveryView: View {
    /// Full daily history, oldest → newest. The card windows it by `scale`.
    let days: [TrendsDay]
    let scale: TrendsCalendarScale
    /// Overnight biometrics — present once a watch is connected AND baselines
    /// have accrued. `nil` renders Tier 2 as the honest "no watch data" state.
    /// (Real source will be `daily_biometrics`, once that table + webhook land.)
    var biometrics: RecoveryBiometrics? = nil

    private var model: RecoveryModel {
        RecoveryModel(days: days, window: scale.rawValue, biometrics: biometrics)
    }

    var body: some View {
        let m = model
        let v = m.verdict

        VStack(alignment: .leading, spacing: 0) {
            Text(v.state)
                .font(.dripDisplay(26))
                .foregroundStyle(v.alert ? Color.drip.coral : Color.drip.textPrimary)

            Text(v.note)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            ForEach(Array(RecoveryTier.allCases.enumerated()), id: \.element) { idx, tier in
                let rows = m.signals.filter { $0.tier == tier }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tier.label)
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textSecondary)
                        Text(tier.why)
                            .font(.dripBody(11.5))
                            .italic()
                            .foregroundStyle(Color.drip.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                        ForEach(rows) { signalRow($0) }
                    }
                    .padding(.top, idx == 0 ? 18 : 16)
                }
            }

            // The gap worth closing — sleep quality, the best-evidenced single
            // signal, and the one the app doesn't have.
            VStack(alignment: .leading, spacing: 6) {
                Text("The gap worth closing")
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textSecondary)
                Text("Self-reported sleep quality is the best-evidenced single signal in the runner literature, and it isn’t captured. One tap a night would be a cheaper input than the whole watch pipeline.")
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.drip.paperDeep))
            .padding(.top, 16)
        }
    }

    // MARK: One signal row — name · value+delta · read

    private func signalRow(_ s: RecoverySignal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(s.name)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                if s.valueAbsent {
                    Text(s.value)
                        .font(.dripBody(10.5)).italic()
                        .foregroundStyle(Color.drip.textTertiary)
                } else {
                    Text(s.value)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Text(s.delta)
                    .font(.dripCaption(8))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Read: agreement carried by INK WEIGHT, never colour (spec §5).
            Text(s.readLabel)
                .font(.dripCaption(9))
                .fontWeight(s.agrees ? .semibold : .regular)
                .foregroundStyle(s.agrees ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }
}

// MARK: - Tiers

enum RecoveryTier: Int, CaseIterable, Hashable {
    case one = 1, two, three

    var label: String {
        switch self {
        case .one:   "Tier 1 · your own words"
        case .two:   "Tier 2 · overnight, corroborating"
        case .three: "Tier 3 · annotation"
        }
    }
    var why: String {
        switch self {
        case .one:   "Elevated 1–2 weeks before a problem in the runner cohorts. This is the evidenced side."
        case .two:   "Read only as a pair, only against your own baseline, never on its own."
        case .three: "Shown for context. Neither of these ever agrees or disagrees."
        }
    }
}

// MARK: - Signal + verdict model

struct RecoverySignal: Identifiable {
    let id = UUID()
    let tier: RecoveryTier
    let name: String
    let value: String
    let valueAbsent: Bool
    let delta: String
    let agrees: Bool
    /// gap = a signal the app is missing (sleep quality); shown, never scored.
    let gap: Bool

    /// The right-hand read label — agreement is in the WORD, colour never used.
    var readLabel: String {
        if gap { return "gap" }
        if tier == .three { return "context" }
        return agrees ? "agrees" : "holds"
    }
}

struct RecoveryVerdict {
    let state: String
    let alert: Bool
    let note: String
}

/// Overnight biometrics for the recovery card's Tier 2. All values are the
/// athlete's own 7-night mean vs their own 28-day baseline — never an imported
/// range. Direction uses a smallest-worthwhile-change deadband.
struct RecoveryBiometrics {
    let hrvNow: Double      // ms (lnRMSSD-scaled), 7-night mean
    let hrvBase: Double     // 28-day baseline
    let rhrNow: Double      // bpm, 7-night mean
    let rhrBase: Double     // 28-day baseline
    let sleepNowMin: Int    // 7-night mean sleep duration
    let sleepPrevMin: Int   // prior window

    var rhrUp: Bool { rhrNow > rhrBase + 1.0 }
    var hrvDown: Bool { hrvNow < hrvBase - 1.0 }

    /// A "good data, hard block" demo: HRV down + resting HR up (the one
    /// interpretable pairing), short sleep. The state a watch surfaces deep in
    /// a heavy week — used until the `daily_biometrics` pipeline is live.
    static let previewGood = RecoveryBiometrics(
        hrvNow: 57.5, hrvBase: 63.0, rhrNow: 50.4, rhrBase: 47.2,
        sleepNowMin: 410, sleepPrevMin: 445)
}

/// Pure convergence model — derives the tiered signals and the verdict from
/// the daily substrate. No biometrics yet, so Tier 2 is always "no watch
/// data"; the verdict runs on Tier 1, exactly the spec's ship-now path.
struct RecoveryModel {
    let signals: [RecoverySignal]
    let verdict: RecoveryVerdict

    init(days: [TrendsDay], window n: Int, biometrics: RecoveryBiometrics? = nil) {
        let win = Array(days.suffix(n))
        let priorSlice = days.count >= 2 * n ? Array(days[(days.count - 2 * n)..<(days.count - n)]) : []

        // Tier 1 — niggles.
        let mentions = win.flatMap { $0.niggles }
        var areaCounts: [String: Int] = [:]
        for m in mentions { areaCounts[m.area.lowercased(), default: 0] += 1 }
        let topArea = areaCounts.max { $0.value < $1.value }
        let niggleAgrees = (topArea?.value ?? 0) > 1
        let niggle = RecoverySignal(
            tier: .one, name: "Niggles",
            value: "\(mentions.count) \(mentions.count == 1 ? "mention" : "mentions")",
            valueAbsent: false,
            delta: niggleAgrees ? "\(topArea!.value)× \(topArea!.key)" : "no repeat area",
            agrees: niggleAgrees, gap: false)

        // Tier 1 — mood.
        let heavy = win.filter { d in
            guard let m = d.mood?.lowercased() else { return false }
            return m == "tired" || m == "struggling"
        }.count
        let moodAgrees = win.isEmpty ? false : Double(heavy) / Double(win.count) >= 0.45
        let mood = RecoverySignal(
            tier: .one, name: "Mood",
            value: "\(heavy) of \(win.count) days", valueAbsent: false,
            delta: "tired or struggling", agrees: moodAgrees, gap: false)

        // Tier 1 — sleep quality (the gap).
        let sleepQuality = RecoverySignal(
            tier: .one, name: "Sleep quality", value: "not captured", valueAbsent: true,
            delta: "one tap a night would add it", agrees: false, gap: true)

        // Tier 2 — biometrics. Present once a watch is connected + baselines
        // accrue; otherwise the honest "no watch data" state. HRV is read ONLY
        // paired with resting HR (§6): it agrees only when HRV↓ AND RHR↑.
        let rhr: RecoverySignal
        let hrv: RecoverySignal
        if let b = biometrics {
            rhr = RecoverySignal(
                tier: .two, name: "Resting HR", value: String(format: "%.1f bpm", b.rhrNow),
                valueAbsent: false, delta: "\(b.rhrUp ? "up" : "flat") vs your baseline",
                agrees: b.rhrUp, gap: false)
            hrv = RecoverySignal(
                tier: .two, name: "HRV", value: String(format: "%.1f ms", b.hrvNow),
                valueAbsent: false, delta: "\(b.hrvDown ? "down" : "flat") — only read with resting HR",
                agrees: b.hrvDown && b.rhrUp, gap: false)
        } else {
            rhr = RecoverySignal(tier: .two, name: "Resting HR", value: "no watch data",
                                 valueAbsent: true, delta: "needs 28 nights", agrees: false, gap: false)
            hrv = RecoverySignal(tier: .two, name: "HRV", value: "no watch data",
                                 valueAbsent: true, delta: "needs 28 nights", agrees: false, gap: false)
        }

        // Tier 3 — annotation (load; sleep duration when a watch is present).
        let nowMiles = win.reduce(0) { $0 + $1.miles }
        let priorMiles = priorSlice.reduce(0) { $0 + $1.miles }
        let pct = priorMiles > 0 ? Int(((nowMiles / priorMiles) - 1) * 100) : 0
        let loadDelta = priorSlice.isEmpty
            ? "no prior window to compare"
            : "\(pct >= 0 ? "+" : "−")\(abs(pct))% vs previous \(n / 7) weeks"
        let load = RecoverySignal(tier: .three, name: "Load", value: "\(Int(nowMiles.rounded())) mi",
                                  valueAbsent: false, delta: loadDelta, agrees: false, gap: false)

        var tier3: [RecoverySignal] = []
        if let b = biometrics {
            let dMin = b.sleepNowMin - b.sleepPrevMin
            tier3.append(RecoverySignal(
                tier: .three, name: "Sleep", value: Self.hhmm(b.sleepNowMin), valueAbsent: false,
                delta: "\(dMin < 0 ? "−" : "+")\(abs(dMin))m vs previous", agrees: false, gap: false))
        }
        tier3.append(load)

        signals = [niggle, mood, sleepQuality, rhr, hrv] + tier3

        // Convergence verdict (§2d): active needs ≥1 Tier 1 AND ≥1 Tier 2;
        // biometrics never fire alone. Tier 1 alone reaches quiet with real copy.
        let t1 = [niggle, mood].filter { $0.agrees }
        let t2 = [rhr, hrv].filter { $0.agrees }
        let names = Self.joinNames(t1)

        if !t1.isEmpty && !t2.isEmpty {
            verdict = RecoveryVerdict(
                state: "A shape worth watching.", alert: true,
                note: "Your own words moved and the overnight numbers moved with them — \(names), alongside \(Self.joinNames(t2, lowercase: false)). Any one of those is noise. Together it’s a shape worth watching, and what it means is yours.")
        } else if t1.count >= 2 {
            verdict = RecoveryVerdict(
                state: "Your own words are moving.", alert: true,
                note: "\(names.prefix(1).uppercased() + names.dropFirst()) are both pointing the same way. That’s the side of this the evidence actually supports, and it doesn’t need a watch to say so.")
        } else if t1.count == 1 {
            verdict = RecoveryVerdict(
                state: "One thing is moving.", alert: false,
                note: "Only \(names) is moving. One signal on its own isn’t a pattern — it stays in the list below so you can see it, and it doesn’t reach further than that.")
        } else if !t2.isEmpty {
            verdict = RecoveryVerdict(
                state: "Numbers moved, your words didn’t.", alert: false,
                note: "The overnight numbers drifted this week, but nothing in your own words did. On its own that isn’t a pattern — as likely a late night or a glass of wine as anything about training. Noted, not flagged.")
        } else {
            verdict = RecoveryVerdict(
                state: "No shape here.", alert: false,
                note: "Your load moved around this window and the recovery signals didn’t track it either way. That’s the boring answer, and it’s the true one.")
        }
    }

    private static func joinNames(_ sigs: [RecoverySignal], lowercase: Bool = true) -> String {
        let ns = sigs.map { lowercase ? $0.name.lowercased() : $0.name }
        if ns.count > 1 { return ns.dropLast().joined(separator: ", ") + " and " + ns.last! }
        return ns.first ?? ""
    }

    private static func hhmm(_ min: Int) -> String {
        "\(min / 60)h \(String(format: "%02d", min % 60))m"
    }
}

#Preview("Recovery convergence") {
    TrendsRecoveryView(days: TrendsDay.previewMonth, scale: .month)
        .padding()
        .background(Color.drip.cardBackground)
}
