//
//  TrendsThresholdControls.swift
//  RunningLog · Trends
//
//  The band, made adjustable.
//
//  Four things used to be constants and are now controls: what the band sits
//  on, where its two edges are, and how much of a session has to land inside
//  it before that session is band work at all. The chart above stays
//  chrome-free — every control lives here, folded away until asked for, so the
//  default reading is still a picture rather than a console.
//
//  **Why the edges are separate.** The 2026-08-02 audit found the leak on the
//  slow edge: long-run cruising drifting into the band. A single ±% can only
//  answer that by tightening the fast edge too, which discards real hard work
//  to fix a problem the fast edge never had. Two edges, moved independently,
//  fix the leak where it is.
//
//  **Why two minimums.** A total catches the drive-by. It does not catch the
//  long run that clips the band four times for three minutes each — twelve
//  honest minutes, no threshold session. The unbroken-block minimum does.
//
//  Nothing here computes anything about training. It edits a `BandSettings`;
//  `ThresholdBuilder` does the arithmetic and `TrendsThresholdView` draws it.
//

import SwiftUI

struct TrendsThresholdControls: View {

    /// How the four blocks are assembled.
    ///
    /// **Why `tabbed` exists.** Stacked, the four blocks run to roughly 700pt:
    /// the athlete scrolls past three settings to reach the fourth, and can
    /// never see the chart and the control she is moving at the same time. The
    /// full-screen detail has the width to lay them out as a strip instead, and
    /// nothing is hidden by doing so — each segment carries its own current
    /// value, which is `summaryLine` distributed across four labels rather than
    /// folded away behind one.
    enum Layout {
        /// Summary line + ADJUST, four blocks stacked. The inline card's.
        case inline
        /// Four-segment strip, one block below it. The detail's.
        case tabbed
    }

    /// Which block the strip is showing. View state, forgotten on dismiss —
    /// the athlete opened a tab, she didn't set a preference.
    private enum Block: String, CaseIterable, Identifiable {
        case anchor, band, minimum, floor
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anchor: "Anchor"
            case .band: "Band"
            case .minimum: "Minimum"
            case .floor: "Floor"
            }
        }
    }

    @Binding var settings: BandSettings
    /// The ladder in force at the end of the window — turns each chip into a
    /// real pace instead of an initialism. Nil before any data loads.
    let ladder: BandLadder?
    /// Colour of the current anchor, so the controls and the band agree.
    let accent: Color
    var layout: Layout = .inline
    /// Which segment the strip opens on. Only read by `.tabbed`.
    var initialBlock: String? = nil

    @State private var expanded = false
    @State private var block: Block = .anchor
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    var body: some View {
        switch layout {
        case .inline: inlineBody
        case .tabbed: tabbedBody
        }
    }

    // MARK: Inline — unchanged

    private var inlineBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    anchorBlock.padding(.top, 16)
                    edgeBlock.padding(.top, 20)
                    minimumBlock.padding(.top, 20)
                    floorBlock.padding(.top, 20)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }

    // MARK: Tabbed

    private var tabbedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            blockStrip

            Group {
                switch block {
                case .anchor: anchorBlock
                case .band: edgeBlock
                case .minimum: minimumBlock
                case .floor: floorBlock
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.16), value: block)
        .onAppear {
            if let initialBlock, let b = Block(rawValue: initialBlock) { block = b }
        }
    }

    /// The strip is also the read. Each segment carries its own current value,
    /// so the complete settings summary is visible without opening anything —
    /// the property the collapsed inline header has and this must not lose.
    private var blockStrip: some View {
        HStack(spacing: 0) {
            ForEach(Block.allCases) { b in
                Button {
                    block = b
                    if b != .anchor { customFocused = false }
                } label: {
                    VStack(spacing: 4) {
                        Text(b.title.uppercased())
                            .font(.dripEyebrow(smallType).weight(.semibold))
                            .tracking(1.0)
                            .foregroundStyle(
                                block == b ? Color.drip.textPrimary : Color.drip.textTertiary
                            )
                        Text(value(for: b))
                            .font(.dripEyebrow(microType))
                            .tracking(0.4)
                            .monospacedDigit()
                            .foregroundStyle(
                                block == b ? accent : Color.drip.textTertiary
                            )
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(block == b ? Color.drip.coral : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(b.title)
                .accessibilityValue(value(for: b))
                .accessibilityAddTraits(block == b ? [.isSelected] : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    /// One segment's current setting, in the shortest honest form.
    private func value(for b: Block) -> String {
        switch b {
        case .anchor: settings.anchor.label
        case .band: settings.widthLabel
        case .minimum:
            "\(Int(settings.minTotalMinutes.rounded()))/\(Int(settings.minBlockMinutes.rounded()))"
        case .floor: settings.hrFloor > 0 ? "\(settings.hrFloor)" : "OFF"
        }
    }

    // MARK: Header

    /// Collapsed, this line IS the settings read — the athlete can see what
    /// band she is looking at without opening anything.
    private var header: some View {
        Button {
            expanded.toggle()
            if !expanded { customFocused = false }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summaryLine)
                    .font(.dripEyebrow(smallType))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(expanded ? "DONE" : "ADJUST")
                    .font(.dripEyebrow(microType).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Band settings. \(summaryLine)")
        .accessibilityHint(expanded ? "Collapses the controls" : "Opens the band controls")
    }

    private var summaryLine: String { Self.summaryLine(settings, ladder: ladder) }

    /// The band, in one line.
    ///
    /// Static so every surface that states the current band — this header, and
    /// the Trends tab's `Adjust ›` row — says it from one definition. Two
    /// hand-written summaries of the same settings is how a screen ends up
    /// describing a band it isn't drawing.
    static func summaryLine(_ settings: BandSettings, ladder: BandLadder?) -> String {
        var s = "\(settings.anchor.label) \(settings.widthLabel)"
        if let ladder {
            let edges = settings.edges(anchorSec: settings.anchor.sec(in: ladder))
            s += " · \(TrendsFormat.pace(edges.fast))–\(TrendsFormat.pace(edges.slow))"
        }
        let mins = Int(settings.minTotalMinutes.rounded())
        let block = Int(settings.minBlockMinutes.rounded())
        if mins > 0 || block > 0 { s += " · MIN \(mins)/\(block) MIN" }
        return s.uppercased()
    }

    // MARK: Anchor

    private var anchorBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldHeader(
                blockTitle(inline: "Anchor", tabbed: "What the band sits on"),
                trailing: settings.isDefault ? nil : (layout == .tabbed ? "Reset all" : "Reset")
            ) {
                settings = .default
                customText = ""
            }

            // Two rows rather than a scroller: seven chips plus the typed one
            // fit, and a horizontal scroller hides options behind a gesture
            // nobody knows to make.
            VStack(spacing: 6) {
                chipRow(Array(BandAnchor.zones.prefix(4)))
                HStack(spacing: 6) {
                    ForEach(Array(BandAnchor.zones.dropFirst(4)), id: \.self) { chip($0) }
                    customChip
                }
            }

            if let gloss = settings.anchor.gloss {
                Text(gloss)
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if customFocused || settings.anchor.isCustom {
                customField
            }
        }
    }

    private func chipRow(_ anchors: [BandAnchor]) -> some View {
        HStack(spacing: 6) {
            ForEach(anchors, id: \.self) { chip($0) }
        }
    }

    private func chip(_ anchor: BandAnchor) -> some View {
        let selected = settings.anchor == anchor
        return Button {
            settings.anchor = anchor
            customFocused = false
        } label: {
            VStack(spacing: 1) {
                Text(anchor.label)
                    .font(.dripEyebrow(smallType).weight(.semibold))
                    .tracking(0.8)
                // The pace under the label is the whole reason the chips are
                // legible — "10K" is a name, "5:02" is the thing being asked.
                if let ladder {
                    Text(TrendsFormat.pace(anchor.sec(in: ladder)))
                        .font(.dripEyebrow(microType))
                        .tracking(0.3)
                        .opacity(selected ? 0.75 : 0.6)
                }
            }
            .foregroundStyle(selected ? Color.drip.background : Color.drip.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? accent : Color.drip.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.clear : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(anchor.proseLabel)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var customChip: some View {
        let selected = settings.anchor.isCustom
        return Button {
            customFocused = true
            if case .custom(let sec) = settings.anchor, customText.isEmpty {
                customText = TrendsFormat.pace(sec)
            }
        } label: {
            VStack(spacing: 1) {
                Text(selected ? settings.anchor.label : "SET")
                    .font(.dripEyebrow(smallType).weight(.semibold))
                    .tracking(0.8)
                Text("MY PACE")
                    .font(.dripEyebrow(microType))
                    .tracking(0.3)
                    .opacity(selected ? 0.75 : 0.6)
            }
            .foregroundStyle(selected ? Color.drip.background : Color.drip.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? accent : Color.drip.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.clear : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set a custom pace")
    }

    private var customField: some View {
        HStack(spacing: 8) {
            TextField("5:35", text: $customText)
                .focused($customFocused)
                .font(.dripBody(14))
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .onSubmit(commitCustom)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.drip.cardBackgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(customIsValid ? Color.drip.divider : Color.drip.coral, lineWidth: 1)
                )

            Button("Use", action: commitCustom)
                .font(.dripEyebrow(smallType).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(customIsValid ? Color.drip.textPrimary : Color.drip.textTertiary)
                .disabled(!customIsValid)
        }
        .overlay(alignment: .bottomLeading) {
            // Coral as punctuation: one mark, only when the input can't be read.
            if !customText.isEmpty && !customIsValid {
                Text("MIN/MI, LIKE 5:35")
                    .font(.dripEyebrow(microType))
                    .tracking(0.8)
                    .foregroundStyle(Color.drip.coral)
                    .offset(y: 15)
            }
        }
    }

    private var customIsValid: Bool { BandSettings.parsePace(customText) != nil }

    private func commitCustom() {
        guard let sec = BandSettings.parsePace(customText) else { return }
        settings.anchor = .custom(sec)
        customFocused = false
    }

    // MARK: Edges

    private var edgeBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldHeader(blockTitle(inline: "Band", tabbed: "Where the two edges sit"),
                        trailing: nil, action: nil)

            edgeSlider(
                label: "Fast edge",
                value: $settings.fastPct,
                sign: "−",
                paceSec: ladder.map { edgePace(.fast, $0) }
            )
            edgeSlider(
                label: "Slow edge",
                value: $settings.slowPct,
                sign: "+",
                paceSec: ladder.map { edgePace(.slow, $0) }
            )

            Text("Tighten the slow edge to keep long-run cruising out; leave the "
                + "fast edge open so genuine hard reps still count.")
                .font(.dripBody(11.5))
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum Edge { case fast, slow }

    private func edgePace(_ edge: Edge, _ ladder: BandLadder) -> Int {
        let e = settings.edges(anchorSec: settings.anchor.sec(in: ladder))
        return edge == .fast ? e.fast : e.slow
    }

    private func edgeSlider(
        label: String,
        value: Binding<Double>,
        sign: String,
        paceSec: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.dripEyebrow(microType))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer(minLength: 0)
                Text("\(sign)\(BandSettings.pctText(value.wrappedValue))%")
                    .font(.dripEyebrow(smallType).weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                if let paceSec {
                    Text(TrendsFormat.pace(paceSec))
                        .font(.dripEyebrow(smallType))
                        .tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                        .monospacedDigit()
                }
            }
            Slider(
                value: value,
                in: BandSettings.pctRange,
                step: BandSettings.pctStep
            )
            .tint(accent)
            .accessibilityLabel(label)
            .accessibilityValue(
                "\(BandSettings.pctText(value.wrappedValue)) percent"
                    + (paceSec.map { ", \(TrendsFormat.pace($0)) per mile" } ?? "")
            )
        }
    }

    // MARK: Minimums

    private var minimumBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldHeader(blockTitle(inline: "Minimum per session", tabbed: "Minimum per session"),
                        trailing: nil, action: nil)

            stepRow(
                label: "Total in band",
                value: $settings.minTotalMinutes,
                range: BandSettings.minutesRange,
                unit: "min"
            )
            stepRow(
                label: "Longest unbroken",
                value: $settings.minBlockMinutes,
                range: BandSettings.blockRange,
                unit: "min"
            )

            Text("A long run that touches the band four times for three minutes "
                + "each clears a twelve-minute total and fails a five-minute block. "
                + "Sessions held out are counted under the chart, never dropped in "
                + "silence.")
                .font(.dripBody(11.5))
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Effort floor

    private var floorBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldHeader(
                blockTitle(inline: "Effort floor", tabbed: "Effort floor"),
                trailing: settings.hrFloor > 0 ? "Turn off" : "Turn on"
            ) {
                settings.hrFloor = settings.hrFloor > 0 ? 0 : BandSettings.default.hrFloor
            }

            if settings.hrFloor > 0 {
                stepRow(
                    label: "Average HR at or above",
                    value: Binding(
                        get: { Double(settings.hrFloor) },
                        set: { settings.hrFloor = Int($0.rounded()) }
                    ),
                    range: Double(BandSettings.hrFloorRange.lowerBound)
                        ... Double(BandSettings.hrFloorRange.upperBound),
                    unit: "bpm",
                    step: 1
                )
                Text("In-band minutes count as work when the average heart rate over "
                    + "them clears this. Under it they're logged as cruising and held "
                    + "apart — not deleted.")
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Off — every in-band minute counts as work, including sessions "
                    + "with no heart rate. The right setting without a strap, and the "
                    + "wrong one with.")
                    .font(.dripBody(11.5))
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Chrome

    /// Block headings differ by layout. Inline, the heading is the only name
    /// the block has, so it names the setting. Tabbed, the segment above it
    /// already says "Band" — repeating it spends a line saying nothing, so the
    /// heading says what the control *does* instead.
    private func blockTitle(inline: String, tabbed: String) -> String {
        layout == .tabbed ? tabbed : inline
    }

    private func fieldHeader(
        _ title: String,
        trailing: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            DripEyebrow(text: title)
            Spacer(minLength: 8)
            if let trailing, let action {
                Button(trailing.uppercased(), action: action)
                    .font(.dripEyebrow(microType).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    private func stepRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        step: Double = 1
    ) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)

            Spacer(minLength: 0)

            stepButton("−", enabled: value.wrappedValue > range.lowerBound) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }

            Text("\(Int(value.wrappedValue.rounded())) \(unit)")
                .font(.dripEyebrow(smallType).weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 52)

            stepButton("+", enabled: value.wrappedValue < range.upperBound) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.wrappedValue.rounded())) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            case .decrement:
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(
        _ glyph: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.dripBody(15))
                .foregroundStyle(enabled ? Color.drip.textPrimary : Color.drip.textTertiary)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color.drip.cardBackgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5).stroke(Color.drip.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Preview

#if DEBUG
private struct ThresholdControlsHarness: View {
    @State var settings: BandSettings = .default
    var layout: TrendsThresholdControls.Layout = .inline

    var body: some View {
        ScrollView {
            TrendsThresholdControls(
                settings: $settings,
                ladder: BandLadder(mp: 338, hmp: 323, lt: 318, k10: 308, k5: 295, k3: 286, mile: 274),
                accent: settings.anchor.color(in: nil),
                layout: layout
            )
            .padding(24)
        }
        .background(Color.drip.background)
    }
}

#Preview("Threshold controls · inline") { ThresholdControlsHarness() }

/// The detail's layout. Worth its own preview: the strip has to stay legible at
/// four segments on the narrowest phone, and each segment's value is the read —
/// if one truncates, the settings summary is no longer complete.
#Preview("Threshold controls · tabbed") { ThresholdControlsHarness(layout: .tabbed) }
#endif
