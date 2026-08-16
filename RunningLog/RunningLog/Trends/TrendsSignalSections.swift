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
    /// Refetches the timeline after an inline sleep rating lands, so the score
    /// re-reads with the Tier-1 branch instead of waiting for the next visit.
    var onSleepLogged: (() -> Void)?

    /// The receipt — factor rows, arithmetic, coverage, method note — folded
    /// away by default. The card's job at a glance is the number, the band and
    /// the move since yesterday; expanded, it ran past a full screen height and
    /// pushed section 03 out of reach. Nothing here is persisted: the athlete
    /// asked to see the working once, not forever, so the next visit opens
    /// folded again. Same rule the section explainers follow.
    @State private var showsReceipt = false

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
                    // threshold (`TrendsSignalRead.noiseThreshold`) are not reported
                    // as movement — the Read below calls those moves noise,
                    // and this line must not contradict it.
                    let d = ledger.total - previous
                    let noise = Int(TrendsSignalRead.noiseThreshold)
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

            // Sits above the fold on purpose. A ceiling the athlete can't see
            // is the one thing on this card that would quietly change how they
            // read every number on it, so it does not wait behind a tap.
            if let ceilingNote {
                Text(ceilingNote)
                    .font(.dripEyebrow(microType))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // The one gap on this card the athlete can close from the card. A
            // note that says the rating is missing, on a surface with no way to
            // give one, is a complaint rather than a disclosure — and the rating
            // is the single highest-leverage input the ledger has (Tier 1, +4/−6,
            // against duration's +2/−3). HRV is deliberately not offered here:
            // it is a permission grant with an ordering trap, not one tap.
            if ledger.gaps.contains(.sleepRating) {
                SleepCheckInPrompt(style: .compact, onSaved: onSleepLogged)
                    .padding(.top, 10)
            }

            // The fold. Above it the card is a glance; below it, a receipt.
            Divider().overlay(Color.drip.divider).padding(.top, 16)

            receiptToggle

            if showsReceipt {
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
    }

    /// The one door into the receipt. It names what's behind it rather than
    /// saying "more", and it carries the coverage count while folded — so the
    /// collapsed card still admits how much evidence the score had, which is
    /// the one thing from the receipt that changes how much to trust the
    /// number.
    private var receiptToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { showsReceipt.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text((showsReceipt ? "Hide the arithmetic" : "How this was scored").uppercased())
                    .font(.dripEyebrow(smallType))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                if !showsReceipt {
                    Text("·")
                        .font(.dripEyebrow(microType))
                        .foregroundStyle(Color.drip.textTertiary)
                    Text(coverageShort)
                        .font(.dripEyebrow(microType))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 6)
                Text("⌄")
                    .font(.dripEyebrow(smallType))
                    .foregroundStyle(Color.drip.textTertiary)
                    .rotationEffect(.degrees(showsReceipt ? 180 : 0))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrendsAnchorPressStyle(cornerRadius: 4))
        .padding(.top, 10)
        .accessibilityLabel(
            showsReceipt ? "Hide the arithmetic behind the score"
                         : "Show the arithmetic behind the score"
        )
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
    ///
    /// A factor that scored on a fallback path is counted as having data,
    /// because it did — so the count alone cannot distinguish a full read
    /// from a degraded one. Until 2026-08-07 the scope word didn't either:
    /// it said "full read" whenever ANY nights factor existed, which meant a
    /// ledger running on resting HR with no HRV at all, and on sleep duration
    /// with no nightly rating, still announced itself as full. `degradations`
    /// is what closes that gap.
    private var scopeWord: String {
        let hasNights = ledger.factors.contains { $0.source == .nights }
        if !hasNights { return "words-and-runs read" }
        return ledger.degradations.isEmpty ? "full read" : "partial read"
    }

    private var coverage: String {
        let m = ledger.factors.count
        let n = ledger.factors.filter(\.hasData).count
        let head = "\(n) of \(m) inputs had data · \(scopeWord)"
        guard !ledger.degradations.isEmpty else { return head }
        return head + " · " + ledger.degradations.joined(separator: " · ")
    }

    /// The collapsed toggle's version — same claim, no room for the clauses.
    /// The full list is one tap away and the scope word already carries the
    /// warning, so this shortens rather than lies.
    private var coverageShort: String {
        let m = ledger.factors.count
        let n = ledger.factors.filter(\.hasData).count
        return "\(n) of \(m) · \(scopeWord)"
    }

    /// The gauge's colour per band. The BOUNDS are not repeated here — they
    /// come from `Band.lowerBound` / `.upperBound`, so the strip cannot draw a
    /// band starting somewhere the score doesn't classify it.
    private static func gaugeColour(_ band: TrendsRecoveryLedger.Band) -> Color {
        switch band {
        case .flat: Color.drip.struggling
        case .worn: Color.drip.tired
        case .steady: Color.drip.neutral
        case .clear: Color.drip.positive
        }
    }

    /// The band gauge — proportional to the real scale, with a marker at the
    /// score. The previous strip was four equal quarters and no marker: it
    /// read as decoration and misstated the scale (Flat spans 8…45, nearly
    /// half of it). Only the occupied band carries its colour; the others sit
    /// at low alpha so the strip stays quiet. The marker is ink, going coral
    /// only in Flat — coral is alert, and that is the card's one alert state.
    private var gauge: some View {
        let span = 96.0 - 8.0
        let score = Double(ledger.total)
        // Bands today's live channels cannot reach. With no HRV and no nightly
        // sleep rating the roof is 74 and `Clear` starts at 75 — so the band is
        // drawn as territory that is open when it is arithmetically closed.
        // Hatching it and capping the strip is the same discipline as the
        // chart's `degradationNote`: state what was dropped, don't hide it.
        let unreachable = Set(ledger.unreachableBands)
        let ceiling = Double(ledger.ceiling)

        return GeometryReader { geo in
            let w = geo.size.width
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(TrendsRecoveryLedger.Band.allCases, id: \.rawValue) { band in
                            Rectangle()
                                .fill(Self.gaugeColour(band).opacity(
                                    unreachable.contains(band) ? 0.05
                                        : ledger.band == band ? 0.9 : 0.16))
                                .frame(width: max(0, w * Double(band.upperBound - band.lowerBound) / span))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.top, 4)

                    // The cap: where today's inputs top out. Ink-2 hairline, so
                    // it reads as a limit of the instrument rather than an alert
                    // about the athlete — coral stays reserved for Flat.
                    if !unreachable.isEmpty {
                        Rectangle()
                            .fill(Color.drip.textTertiary)
                            .frame(width: 1, height: 10)
                            .offset(x: min(max(0, w * (ceiling - 8) / span), w - 1), y: 2)
                    }

                    RoundedRectangle(cornerRadius: 1)
                        .fill(ledger.band == .flat ? Color.drip.coral : Color.drip.textPrimary)
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(0, w * (score - 8) / span - 1), w - 2))
                }
                HStack(spacing: 0) {
                    ForEach(TrendsRecoveryLedger.Band.allCases, id: \.rawValue) { band in
                        Text(band.rawValue.uppercased())
                            .font(.dripEyebrow(microType))
                            .tracking(0.6)
                            .foregroundStyle(unreachable.contains(band)
                                             ? Color.drip.textTertiary.opacity(0.4)
                                             : Color.drip.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: max(0, w * Double(band.upperBound - band.lowerBound) / span),
                                   alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 28)
    }

    /// Names the cap in words when the gauge draws one. Observation only —
    /// it states the arithmetic and what would lift it, and never tells the
    /// athlete to do anything.
    private var ceilingNote: String? {
        guard let lowest = ledger.unreachableBands.first else { return nil }
        let needs = lowest.lowerBound
        let why = ledger.degradations.isEmpty
            ? nil
            : ledger.degradations.joined(separator: " · ")
        let head = "\(lowest.rawValue) needs \(needs) · today's inputs top out at \(ledger.ceiling)"
        return why.map { head + " · " + $0 } ?? head
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
