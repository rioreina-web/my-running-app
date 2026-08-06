//
//  TrendsSignalSections.swift
//  RunningLog · Trends
//
//  The three sections wrapped around the signal chart: the computed read, the
//  recovery ledger, and the findings. Each is a thin view over the pure types
//  in `TrendsSignalModels.swift` — no arithmetic happens in this file, so the
//  prose on screen cannot drift from the picture above it.
//

import SwiftUI

// MARK: - Range switcher

/// The one time control on Trends. Everything below it re-reads at the
/// selected window; nothing carries a second range of its own.
struct TrendsWindowPicker: View {
    @Binding var window: TrendsWindow
    @Binding var customFrom: Date
    @Binding var customTo: Date

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(TrendsWindow.presets) { preset in
                    pill(preset.label, selected: window == preset) { window = preset }
                }
                pill("Custom", selected: window.isCustom) {
                    window = .custom(from: customFrom, to: customTo)
                }
            }

            if window.isCustom {
                HStack(spacing: 10) {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date)
                        .labelsHidden()
                    Text("to")
                        .font(.dripEyebrow(smallType))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.drip.textTertiary)
                    DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
                .onChange(of: customFrom) { _, _ in window = .custom(from: customFrom, to: customTo) }
                .onChange(of: customTo) { _, _ in window = .custom(from: customFrom, to: customTo) }
            }
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.dripEyebrow(smallType).weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(selected ? Color.drip.background : Color.drip.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    Capsule().fill(selected ? Color.drip.textPrimary : Color.drip.cardBackgroundElevated)
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Press feedback

/// The press state shared by every anchor control on this page — an ink wash
/// over whatever the control already draws. No new colour enters the palette,
/// and because it's an overlay it sits above the chip's own card fill rather
/// than behind it.
private struct TrendsAnchorPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.drip.textPrimary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - The read

struct TrendsReadHeader: View {
    let read: TrendsRead
    let set: TrendsBucketSet
    /// Scrolls the page to a section id. `nil` in previews, where the chips
    /// render as plain cells rather than claiming to be buttons.
    var onJump: ((String) -> Void)?

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DripEyebrow(text: "The read · \(read.dateRange)")

            // Headline. Coral is punctuation, not paint — one coral element in
            // this cluster, and it's the accent clause.
            (
                Text(read.headline)
                    .foregroundStyle(Color.drip.textPrimary)
                + Text(read.headlineAccent.isEmpty ? "" : " \(read.headlineAccent)")
                    .foregroundStyle(Color.drip.coral)
            )
            .font(.dripDisplay(27))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            Text(read.note)
                .font(.dripBody(12.5))
                .italic()
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            chips.padding(.top, 16)

            Text("Every number counted from the window in view · deltas compare the back half to the front half")
                .font(.dripEyebrow(microType))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// Each chip is a verdict about one section, so tapping it goes there.
    /// Four of the five read out of the signal lanes; recovery has its own
    /// receipt below.
    private var chips: some View {
        HStack(spacing: 1) {
            chip("\(Int(set.totalMiles.rounded()))", "Miles", milesDelta, tint: nil,
                 anchor: "signals")
            chip("\(set.keySessionCount)", "Key work", perWeek, tint: nil,
                 anchor: "signals")
            chip(set.modalMood?.uppercased() ?? "—", "Most days",
                 "\(set.moodLoggedDays)/\(set.days.count) logged",
                 tint: nil, compact: true, anchor: "signals")
            chip("\(set.niggleMentionCount)", "Niggles",
                 "\(set.niggleAreas.count) area\(set.niggleAreas.count == 1 ? "" : "s")", tint: nil,
                 anchor: "signals")
            chip("\(set.currentRecovery)", "Recovery",
                 TrendsRecoveryLedger.Band.of(set.currentRecovery).rawValue.uppercased(),
                 tint: TrendsSignalLanes.bandColour(set.currentRecovery),
                 anchor: "recovery")
        }
        .background(Color.drip.divider)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var milesDelta: String {
        let half = set.buckets.count / 2
        guard half > 0 else { return "—" }
        let front = set.buckets.prefix(half).map(\.miles)
        let back = set.buckets.suffix(set.buckets.count - half).map(\.miles)
        let f = front.isEmpty ? 0 : front.reduce(0, +) / Double(front.count)
        let b = back.isEmpty ? 0 : back.reduce(0, +) / Double(back.count)
        guard f > 0 else { return "—" }
        let pct = (b - f) / f * 100
        return "\(pct >= 0 ? "+" : "−")\(Int(abs(pct).rounded()))%"
    }

    private var perWeek: String {
        guard !set.days.isEmpty else { return "—" }
        let rate = Double(set.keySessionCount) / Double(set.days.count) * 7
        return String(format: "%.1f/wk", rate)
    }

    @ViewBuilder
    private func chip(_ value: String, _ key: String, _ detail: String,
                      tint: Color?, compact: Bool = false,
                      anchor: String) -> some View {
        if let onJump {
            Button { onJump(anchor) } label: {
                chipBody(value, key, detail, tint: tint, compact: compact)
            }
            .buttonStyle(TrendsAnchorPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        } else {
            chipBody(value, key, detail, tint: tint, compact: compact)
        }
    }

    private func chipBody(_ value: String, _ key: String, _ detail: String,
                          tint: Color?, compact: Bool) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(compact ? .dripStat(9) : .dripStat(15))
                .foregroundStyle(tint ?? Color.drip.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, compact ? 4 : 0)
            Text(key.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(0.7)
                .foregroundStyle(Color.drip.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)
            Text(detail)
                .font(.dripEyebrow(microType))
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 3)
        .background(Color.drip.cardBackgroundElevated)
    }
}

// MARK: - Recovery ledger

/// The score, and the arithmetic that produced it. See the doc comment on
/// `TrendsRecoveryLedger` for why a number ships here at all.
struct TrendsRecoveryLedgerView: View {
    let ledger: TrendsRecoveryLedger
    /// Yesterday's score, for the delta. `nil` on the first day of history.
    let previous: Int?
    /// Scrolls back up to the signal lanes, where this score has a trend line.
    /// The number and its history sit two sections apart; this is the link.
    var onSeeTrend: (() -> Void)?

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    private var bandColour: Color { TrendsSignalLanes.bandColour(ledger.total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Text("\(ledger.total)")
                    .font(.dripStat(46))
                    .foregroundStyle(bandColour)
                Text(ledger.band.rawValue.uppercased())
                    .font(.dripEyebrow(11).weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(bandColour)
                    .padding(.bottom, 5)
                Spacer(minLength: 4)
                if let previous {
                    // Day-to-day moves smaller than the surface's own noise
                    // threshold (`TrendsRead.noiseThreshold`) are not reported
                    // as movement — the Read below calls those moves noise,
                    // and this line must not contradict it.
                    let d = ledger.total - previous
                    let noise = Int(TrendsRead.noiseThreshold)
                    Text((abs(d) < noise
                            ? "level vs yesterday"
                            : "\(d >= 0 ? "+" : "−")\(abs(d)) vs yesterday").uppercased())
                        .font(.dripEyebrow(smallType))
                        .tracking(0.9)
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.bottom, 7)
                }
            }
            .padding(.top, 12)

            if let onSeeTrend {
                Button(action: onSeeTrend) { gauge }
                    .buttonStyle(TrendsAnchorPressStyle(cornerRadius: 4))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("See recovery trend")
                    .accessibilityAddTraits(.isButton)
                    .padding(.top, 12)
            } else {
                gauge.padding(.top, 12)
            }

            // Rows grouped by where the evidence came from — WORDS / RUNS /
            // NIGHTS — so the evidence hierarchy is visible on the receipt:
            // the athlete's words lead, the watch corroborates. Empty groups
            // vanish; an athlete with no night pipeline sees two.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groupedFactors, id: \.label) { group in
                    Text(group.label.uppercased())
                        .font(.dripEyebrow(microType))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.top, 13)
                        .padding(.bottom, 6)
                    Divider().overlay(Color.drip.divider)
                    ForEach(group.factors) { factor in
                        factorRow(factor)
                        Divider().overlay(Color.drip.divider)
                    }
                }
            }
            .padding(.top, 3)

            HStack(alignment: .firstTextBaseline) {
                Text(ledger.arithmetic.uppercased())
                    .font(.dripEyebrow(smallType))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(ledger.total)")
                    .font(.dripStat(14))
                    .foregroundStyle(bandColour)
            }
            .padding(.top, 11)

            // Coverage — the cheap version of the Daily Read's confidence
            // idea (§2f): a read from three inputs must not look identical
            // to one from seven. It changes tone, never the number.
            Text(coverage)
                .font(.dripEyebrow(microType))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text("Load is measured against your own 8-week average, not an acute:chronic ratio · your words lead, the watch corroborates · today's run counts tomorrow")
                .font(.dripEyebrow(microType))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    /// Factors grouped by evidence source, words → runs → nights.
    private var groupedFactors: [(label: String, factors: [TrendsRecoveryLedger.Factor])] {
        let order: [(TrendsRecoveryLedger.Factor.Source, String)] = [
            (.words, "Your words"), (.runs, "Your runs"), (.nights, "Your nights"),
        ]
        return order.compactMap { source, label in
            let matching = ledger.factors.filter { $0.source == source }
            return matching.isEmpty ? nil : (label, matching)
        }
    }

    /// "5 of 7 inputs had data · full read". Counts factors whose input
    /// channel actually spoke today — zero-with-data ("none in 14 days")
    /// still counts as data; "not logged" / "not enough history" do not.
    private var coverage: String {
        let m = ledger.factors.count
        let n = ledger.factors.filter(\.hasData).count
        let hasNights = ledger.factors.contains { $0.source == .nights }
        let scope = hasNights ? "full read" : "words-and-runs read"
        return "\(n) of \(m) inputs had data · \(scope)"
    }

    /// The four bands of the real 8…96 scale.
    private static let gaugeBands: [(label: String, lo: Double, hi: Double, colour: Color)] = [
        ("Flat", 8, 45, Color.drip.struggling),
        ("Worn", 45, 60, Color.drip.tired),
        ("Steady", 60, 75, Color.drip.neutral),
        ("Clear", 75, 96, Color.drip.positive),
    ]

    /// The band gauge — proportional to the real scale, with a marker at the
    /// score. The previous strip was four equal quarters and no marker: it
    /// read as decoration and misstated the scale (Flat spans 8…45, nearly
    /// half of it). Only the occupied band carries its colour; the others sit
    /// at low alpha so the strip stays quiet. The marker is ink, going coral
    /// only in Flat — coral is alert, and that is the card's one alert state.
    private var gauge: some View {
        let span = 96.0 - 8.0
        let score = Double(ledger.total)

        return GeometryReader { geo in
            let w = geo.size.width
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Self.gaugeBands, id: \.label) { band in
                            Rectangle()
                                .fill(band.colour.opacity(
                                    ledger.band.rawValue == band.label ? 0.9 : 0.16))
                                .frame(width: max(0, w * (band.hi - band.lo) / span))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.top, 4)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(ledger.band == .flat ? Color.drip.coral : Color.drip.textPrimary)
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(0, w * (score - 8) / span - 1), w - 2))
                }
                HStack(spacing: 0) {
                    ForEach(Self.gaugeBands, id: \.label) { band in
                        Text(band.label.uppercased())
                            .font(.dripEyebrow(microType))
                            .tracking(0.6)
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: max(0, w * (band.hi - band.lo) / span),
                                   alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 28)
    }

    private func factorRow(_ factor: TrendsRecoveryLedger.Factor) -> some View {
        // Fixed ±18 scale (the mood ceiling — the largest any factor can
        // swing) so the same −6 draws the same length on every receipt.
        // Day-relative scaling made bars incomparable across days: −6 drew
        // long on a quiet day and short on a loud one.
        let fraction = min(1.0, Double(abs(factor.points)) / 18.0)
        let tint: Color = factor.points > 0 ? Color.drip.energized
            : factor.points < 0 ? Color.drip.struggling : Color.drip.textTertiary

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(factor.name)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(factor.evidence.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)

            // Diverging bar around a centre tick — the sign is visible before
            // the number is read.
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.drip.divider)
                        .frame(width: 1, height: 14)
                        .offset(x: half)
                    if factor.points != 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint.opacity(0.75))
                            .frame(width: half * fraction, height: 8)
                            .offset(x: factor.points > 0 ? half : half - half * fraction, y: 3)
                    }
                }
            }
            .frame(width: 78, height: 14)

            Text("\(factor.points > 0 ? "+" : "")\(factor.points)")
                .font(.dripStat(12))
                .foregroundStyle(tint)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Findings

struct TrendsFindingsView: View {
    let findings: [TrendsRead.Finding]

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                HStack(alignment: .top, spacing: 11) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint(finding.tone))
                        .frame(width: 5)
                        .padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(finding.text)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(finding.meta.uppercased())
                            .font(.dripEyebrow(microType))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)

                if index < findings.count - 1 {
                    Divider().overlay(Color.drip.divider)
                }
            }
        }
    }

    private func tint(_ tone: TrendsRead.Finding.Tone) -> Color {
        switch tone {
        case .niggle: Color.drip.injured
        case .mood: Color.drip.tired
        case .neutral: Color.drip.textTertiary
        }
    }
}
