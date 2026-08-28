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
///
/// **Pinned mode (2026-08-07).** This used to sit in the scrolling stack, above
/// four long sections — by the time you were reading section 04 the range was a
/// scroll-to-top away, which is not "one control" so much as one control you
/// have to go and find. It now lives in the host's `safeAreaInset`, and
/// `isPinned` says whether the content beneath it has moved.
///
/// **`isPinned` changes nothing about the layout.** Only a hairline appears, so
/// content reads as passing *under* the bar. It was drafted as "shorter pills
/// when stuck", which is a nice idea and a feedback loop: this view is the top
/// safe-area inset, so changing its height moves `contentOffset`, which changes
/// `isPinned`, which changes its height. Constant geometry is what makes the
/// pin honest. The hosts add hysteresis on top.
struct TrendsWindowPicker: View {
    @Binding var window: TrendsWindow
    @Binding var customFrom: Date
    @Binding var customTo: Date

    /// Draws the hairline. Set by the host from its own scroll position; the
    /// picker never reads a scroll offset itself, and never changes size.
    var isPinned: Bool = false

    /// "Jul 9 – Aug 7" and "24 runs" — the dates the chosen window resolved to,
    /// and how much running is inside them. Nil on surfaces that state the
    /// range elsewhere (the Lab has its own lede).
    var meta: (range: String, count: String)? = nil

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

            if let meta {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(meta.range)
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer(minLength: 0)
                    Text(meta.count)
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .font(.dripEyebrow(microType))
                .tracking(0.9)
                .textCase(.uppercase)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(meta.range), \(meta.count)")
            }
        }
        // Constant, so the inset's height never moves. The picker supplies its
        // own 24 because a `safeAreaInset` spans the full window and carries no
        // ambient padding — it is no longer inside the page's padded stack.
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // The fill matches the page rather than a card: what makes the bar read
        // as the page's own edge instead of a floating widget is that it is the
        // same paper. Always drawn, so the bar is opaque at rest too — content
        // must not show through it mid-scroll.
        .background(Color.drip.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
                .opacity(isPinned ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.18), value: isPinned)
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
    let read: TrendsSignalRead
    let set: TrendsBucketSet
    /// Scrolls the page to a section id. `nil` in previews, where the chips
    /// render as plain cells rather than claiming to be buttons.
    var onJump: ((String) -> Void)?

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    /// Headline plus its accent clause as one run of text. Built by
    /// interpolation rather than `Text + Text` — the `+` operator is
    /// deprecated as of iOS 26.
    ///
    /// Coral is punctuation, not paint — one coral element in this cluster,
    /// and it's the accent clause.
    private var headline: Text {
        let base = Text(read.headline).foregroundStyle(Color.drip.textPrimary)
        guard !read.headlineAccent.isEmpty else { return base }
        return Text("\(base) \(Text(read.headlineAccent).foregroundStyle(Color.drip.coral))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DripEyebrow(text: "The read · \(read.dateRange)")

            headline
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

struct TrendsFindingsView: View {
    let findings: [TrendsSignalRead.Finding]

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

    private func tint(_ tone: TrendsSignalRead.Finding.Tone) -> Color {
        switch tone {
        case .niggle: Color.drip.injured
        case .mood: Color.drip.tired
        case .neutral: Color.drip.textTertiary
        }
    }
}
