//
//  TrendsRecoverySection.swift
//  RunningLog · Trends
//
//  Section 04 · Recovery, rebuilt 2026-08-19 around `TrendsRecoveryRead`.
//
//  ── What this replaces ────────────────────────────────────────────────────
//
//  The shipped section opened everything at once: a 46pt score, a band, a
//  delta, a gauge, a four-clause ceiling apology in 9pt uppercase, a sleep
//  prompt, a receipt toggle, then a SECOND subhead with a load line and two
//  chips under it. Nothing was foldable, so the whole model shouted at equal
//  volume and the athlete had to read all of it to find the one thing that
//  had changed.
//
//  ── The shape now ─────────────────────────────────────────────────────────
//
//  One always-visible read, then three chunks that open on tap:
//
//      «  A big block, and your own signals are following it down.  »
//         LOAD  +18% vs usual        BODY  38 · WORN
//
//      ▸ TRAINING LOAD              +18% VS USUAL
//      ▸ HOW YOU'RE ABSORBING IT    38 · 4 OF 4 INPUTS
//      ▸ HOW THIS WAS MEASURED      TLS · FULL READ
//
//  The sentence leads because demand x supply is the question; the two axes
//  sit under it because they are what the sentence is made of; everything
//  else waits behind a tap. Collapsed rows carry their own headline value, so
//  the section still reports without being opened — the fold hides detail,
//  never the finding.
//
//  Nothing here persists its open state. The athlete asked to see the working
//  once, not forever, so the next visit opens folded again — the same rule the
//  old receipt followed and the section explainers still follow.
//

import SwiftUI

// MARK: - Press style

/// Local twin of the anchor press style in `TrendsSignalSections` (which is
/// file-private there). Same feel: a faint ink wash under the finger.
private struct RecoveryPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.drip.textPrimary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Chunk

/// One foldable chunk: a title, a value that stays readable while closed, and
/// content that appears on tap.
private struct RecoveryChunk<Content: View>: View {
    let title: String
    /// The headline the row keeps while folded. This is the whole reason the
    /// fold is safe — a closed chunk still says its number.
    let value: String
    var tint: Color = Color.drip.textPrimary
    @Binding var isOpen: Bool
    @ViewBuilder var content: () -> Content

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isOpen.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title.uppercased())
                        .font(.dripEyebrow(smallType))
                        .tracking(1.1)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer(minLength: 8)
                    Text(value.uppercased())
                        .font(.dripEyebrow(microType))
                        .tracking(0.6)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("⌄")
                        .font(.dripEyebrow(smallType))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(RecoveryPressStyle())
            .accessibilityLabel("\(title), \(value)")
            .accessibilityHint(isOpen ? "Collapse" : "Expand")

            if isOpen {
                content()
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().overlay(Color.drip.divider)
        }
    }
}

// MARK: - Section

struct TrendsRecoverySection: View {
    let read: TrendsRecoveryRead
    /// Refetches after an inline sleep rating lands, so the read re-scores
    /// with the Tier-1 branch instead of waiting for the next visit.
    var onSleepLogged: (() -> Void)?

    @State private var loadOpen = false
    @State private var bodyOpen = false
    @State private var methodOpen = false

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
            axes.padding(.top, 16)
            Divider().overlay(Color.drip.divider).padding(.top, 16)

            RecoveryChunk(
                title: "Training load",
                value: read.load.chip,
                tint: Color.drip.textPrimary,
                isOpen: $loadOpen
            ) { loadDetail }

            RecoveryChunk(
                title: "How you're absorbing it",
                value: bodyChipValue,
                tint: standingColour,
                isOpen: $bodyOpen
            ) { bodyDetail }

            RecoveryChunk(
                title: "How this was measured",
                value: methodChipValue,
                tint: Color.drip.textTertiary,
                isOpen: $methodOpen
            ) { methodDetail }
        }
    }

    // MARK: The read

    /// The sentence. Demand x supply is the question the athlete came with,
    /// and this is the model's answer to it — so it leads, in reading type
    /// rather than in the eyebrow uppercase everything else here wears.
    private var headline: some View {
        Text(read.sentence)
            .font(.dripBody(16))
            .foregroundStyle(Color.drip.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }

    /// The two axes, side by side and equally weighted — the layout is the
    /// argument. Neither one is the score; the pair is the read.
    private var axes: some View {
        HStack(alignment: .top, spacing: 14) {
            axisCell(
                label: "Load",
                value: loadValue,
                unit: loadUnitLabel,
                note: loadNote,
                tint: Color.drip.textPrimary
            )
            Rectangle()
                .fill(Color.drip.divider)
                .frame(width: 1, height: 46)
            axisCell(
                label: "Body",
                value: bodyValue,
                unit: bodyUnitLabel,
                note: bodyNote,
                tint: standingColour
            )
        }
    }

    private func axisCell(
        label: String, value: String, unit: String?, note: String, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.dripStat(30))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit.uppercased())
                        .font(.dripEyebrow(microType))
                        .tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            Text(note)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Axis values

    // A gated axis reports its own PROGRESS toward being readable rather than
    // printing a placeholder. Hard rule #8 bans the em-dash cell, and a count
    // of days already logged is both honest and better news than a blank.

    private var loadValue: String {
        guard let n = read.load.needIndex else { return "\(read.load.historyDays)" }
        let pct = Int(abs(n).rounded())
        if pct < 10 { return "level" }
        return (n > 0 ? "+" : "−") + "\(pct)"
    }

    private var loadUnitLabel: String? {
        guard let n = read.load.needIndex else { return "days in" }
        return Int(abs(n).rounded()) < 10 ? nil : "% vs usual"
    }

    private var loadNote: String {
        guard read.load.needIndex != nil else {
            return "\(TrendsRecoveryDemand.warmUpDays) days of history needed to read load"
        }
        return "what training is asking"
    }

    private var bodyValue: String {
        guard let p = read.body.percentile else { return "\(read.body.sampleDays)" }
        return "\(p)"
    }

    private var bodyUnitLabel: String? {
        guard let standing = read.body.standing else { return "days in" }
        return standing.rawValue
    }

    private var bodyNote: String {
        guard let standing = read.body.standing else {
            return "\(TrendsRecoveryRead.minimumSample) days needed to rank against your own"
        }
        return standing.note
    }

    private var standingColour: Color {
        switch read.body.standing {
        case .flat: Color.drip.struggling
        case .worn: Color.drip.tired
        case .steady: Color.drip.neutral
        case .clear: Color.drip.positive
        case nil: Color.drip.textSecondary
        }
    }

    private var bodyChipValue: String {
        guard let p = read.body.percentile else {
            return "\(read.body.channelsWithData) of \(read.body.channelCount) inputs"
        }
        return "\(p) · \(read.body.channelsWithData) of \(read.body.channelCount) inputs"
    }

    private var methodChipValue: String {
        (read.load.isTLS ? "TLS" : "no TLS") + " · " + read.confidence.label
    }

    // MARK: Chunk · Training load

    private var loadDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailLine(read.load.headline, emphasis: true)

            if let spike = read.load.spikeMultiple {
                detailRow(
                    "Big day",
                    String(format: "%.1fx your longest day in 30 d", (spike * 10).rounded() / 10)
                )
            }
            if let hard = read.load.hardSessions28d {
                detailRow(
                    "Hard sessions",
                    "\(hard) in 28 days" + (read.load.avgDaysBetweenHard.map {
                        String(format: " · one every %.1f days", $0)
                    } ?? "")
                )
            } else if let gap = read.load.avgDaysBetweenHard {
                detailRow("Between hard", String(format: "%.1f days avg", gap))
            }
            if read.load.downWeek == true {
                detailRow("This week", "planned back-off")
            }

            detailNote(
                read.load.isTLS
                ? "Measured in TLS — weighted training minutes, so a mile of intervals counts heavier than a mile of jogging. Your last 7 days against your own last 42, as a difference rather than a ratio."
                : "Measured in duration x session type, not TLS — at least one run in the window carries no stress load yet. Your last 7 days against your own last 42."
            )
        }
    }

    // MARK: Chunk · How you're absorbing it

    private var bodyDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = read.body.percentile {
                detailLine(
                    "Higher than \(p)% of your last \(read.body.sampleDays) days",
                    emphasis: true
                )
            } else {
                detailLine(
                    "\(read.body.sampleDays) days ranked so far · \(TrendsRecoveryRead.minimumSample) needed for a percentile",
                    emphasis: true
                )
            }

            ForEach(read.body.factors) { factor in
                factorRow(factor)
            }

            // The one gap the athlete can close from here. HRV is deliberately
            // not offered as a tap: it is a permission grant with an ordering
            // trap, and on a Garmin it is not in Apple Health at all.
            if read.body.gaps.contains(.sleepRating) {
                SleepCheckInPrompt(style: .compact, onSaved: onSleepLogged)
                    .padding(.top, 12)
            }

            if !read.body.degradations.isEmpty {
                detailNote(
                    "Running on: " + read.body.degradations.joined(separator: " · ")
                )
            }
        }
    }

    private func factorRow(_ factor: TrendsRecoveryRead.Factor) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.name)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(factor.evidence.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(0.5)
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(factor.points == 0 ? "0" : (factor.points > 0 ? "+\(factor.points)" : "−\(abs(factor.points))"))
                .font(.dripStat(14))
                .monospacedDigit()
                .foregroundStyle(
                    factor.points > 0 ? Color.drip.positive
                        : factor.points < 0 ? Color.drip.coral
                        : Color.drip.textTertiary
                )
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().overlay(Color.drip.divider) }
    }

    // MARK: Chunk · How this was measured

    private var methodDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailLine(read.confidence.label.capitalized, emphasis: true)
            detailRow("Load", read.load.isTLS
                ? "TLS · weighted training minutes"
                : "duration x session type · TLS missing on a run in range")
            detailRow("Body", "\(read.body.channelsWithData) of \(read.body.channelCount) channels · ranked against \(read.body.sampleDays) of your own days")
            detailRow("History", "\(read.load.historyDays) days")

            detailNote("Two axes, never added together. Load says what training is asking; Body ranks today's signals against your own history, so 50 is your own median day and every band stays reachable. Your words lead, the watch corroborates. Today's run counts tomorrow.")
        }
    }

    // MARK: Detail primitives

    private func detailLine(_ text: String, emphasis: Bool) -> some View {
        Text(text)
            .font(emphasis ? .dripBody(14) : .dripCaption(12))
            .foregroundStyle(emphasis ? Color.drip.textPrimary : Color.drip.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Divider().overlay(Color.drip.divider) }
    }

    private func detailNote(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.dripEyebrow(microType))
            .tracking(0.5)
            .foregroundStyle(Color.drip.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }
}
