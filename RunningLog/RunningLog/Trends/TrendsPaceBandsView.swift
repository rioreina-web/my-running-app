//
//  TrendsPaceBandsView.swift
//  RunningLog · Trends
//
//  Pace Bands — the drill-down that answers *"am I doing the work at the pace
//  I'm supposed to be doing it at, and what is it costing me?"*
//
//  Spec: `outputs/pace-band-surface-spec-2026-08-02.md`.
//  Prototype: `band-toggle-prototype.html`.
//
//  One band at a time. The athlete picks HM or MP and the anchor, range, four
//  stats, three lanes and the table all swap — but the session x-positions do
//  NOT move. Sessions run left→right in the same order and the same column in
//  all three lanes; that vertical alignment is the whole point of the surface,
//  so never re-sort a lane independently.
//
//  Three rules this file exists to keep:
//
//    1. **Report, never grade.** `246 min in band`, never "good week" or
//       "below target". Nothing here suggests an action.
//    2. **Show the correction being applied to her.** Membership rides on
//       heat-adjusted pace; the raw pace is drawn as a hollow ring with a
//       coral stem to the adjusted value. Never silently adjust.
//    3. **Say the bands overlap.** When the two anchors sit close, ±5% each
//       means the same minute qualifies twice. The note is persistent and not
//       dismissible — it's a limit of the metric, not a notification.
//

import SwiftUI

struct TrendsPaceBandsView: View {
    /// The full payload — every qualifying session in the backend's 26-week
    /// fetch. Narrowed by `windowDays` below rather than refetched.
    let data: PaceBands
    /// Trailing window in days, from the Trends tab's range segmenter. Nil
    /// shows everything the payload carries.
    ///
    /// Trends ships ONE time control (see `TrendsRange`), so this surface
    /// takes its window from the tab rather than carrying a second, separately
    /// set range of its own.
    var windowDays: Int? = nil
    /// The segmenter's own label ("12 wk"), echoed in the header so it's clear
    /// the dates below are a *chosen* window and not just where data landed.
    var rangeLabel: String? = nil
    /// Opens the underlying workout. Nil in previews / when the caller has no
    /// pager to push into — the row then simply doesn't offer the affordance.
    var onOpenSession: ((String) -> Void)? = nil

    /// Persisted across launches: she's training for a half, so MP is the
    /// occasional check, and resetting to HM every entry would be a small
    /// papercut every time. (Spec §11 Q2.)
    @AppStorage("trends.paceBands.band") private var storedBand: String = PaceBandKey.hm.rawValue
    /// Index into `shown.sessions` — the scrubbed column, shared by all lanes.
    /// Cleared whenever the window changes, since the indices move under it.
    @State private var selected: Int? = nil

    private var band: PaceBandKey { PaceBandKey(rawValue: storedBand) ?? .hm }

    /// EVERYTHING on this screen reads off this, not off `data` — the four
    /// stats, all three lanes, the overlap minutes, the split prose and the
    /// table. Change the range and every number moves together; nothing is
    /// left describing a window that isn't on screen.
    private var shown: PaceBands {
        windowDays.map { data.windowed(days: $0) } ?? data
    }

    private var summary: PaceBandSummary { shown.summary(band) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                bandToggle.padding(.top, 18)
                anchorBlock.padding(.top, 18)
                explainer.padding(.top, 14)

                if shown.sessions.isEmpty {
                    // Nothing ran in this window at all — a narrower range on a
                    // quiet stretch, not an athlete with no band work. Say
                    // which, rather than drawing three empty lanes.
                    emptyWindow.padding(.top, 24)
                } else {
                    if summary.isEmpty {
                        emptyBand.padding(.top, 24)
                    } else {
                        statRow.padding(.top, 20)
                    }

                    lanesCard.padding(.top, 14)

                    if let s = selectedSession {
                        selectionCard(s).padding(.top, 14)
                    }

                    if let overlap = shown.overlap {
                        overlapNote(overlap).padding(.top, 26)
                    }

                    // The split reads across BOTH bands, so it stays up even
                    // when the selected one is empty — that's exactly when it
                    // explains the most.
                    splitNarrative.padding(.top, 30)

                    if !summary.isEmpty {
                        EditorialRule().padding(.vertical, 24)
                        sessionTable
                    }
                }

                footer.padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background(Color.drip.background)
        .presentationDragIndicator(.visible)
        // The scrub is an index into the windowed list, so a range change
        // would otherwise leave it pointing at a different session — or off
        // the end of a shorter one.
        .onChange(of: windowDays) { _, _ in selected = nil }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlateStrip(surface: "Running log — trends")
            Rectangle().fill(Color.drip.divider).frame(height: 1).padding(.top, 10)

            // Leads with the CHOSEN window, then the dates the data actually
            // spans inside it. The old label showed only the dates, which read
            // like a range someone picked when it was really just where the
            // sessions happened to fall.
            Text(headerLabel)
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 20)

            Text("One band at a time.")
                .font(.dripDisplay(32))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 7)
        }
    }

    /// "Pace bands · 12 wk · 5 May – 1 Aug". Drops whichever pieces we don't
    /// have rather than padding with placeholders.
    private var headerLabel: String {
        var parts = ["Pace bands"]
        if let rangeLabel, !rangeLabel.isEmpty { parts.append(rangeLabel) }
        if !shown.windowLabel.isEmpty { parts.append(shown.windowLabel) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Band toggle

    private var bandToggle: some View {
        HStack(spacing: 0) {
            ForEach(PaceBandKey.allCases) { key in
                let on = key == band
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { storedBand = key.rawValue }
                } label: {
                    Text(key.label)
                        .font(.dripEyebrow(10)).tracking(10 * 0.09)
                        .textCase(.uppercase)
                        .foregroundStyle(on ? Color.white : Color.drip.textSecondary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(on ? key.color : Color.drip.cardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The anchor and its range

    private var anchorBlock: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Text(TrendsFormat.pace(summary.anchorSec))
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(band.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("band \(TrendsFormat.pace(summary.fastSec)) – \(TrendsFormat.pace(summary.slowSec)) /mi")
                Text("±5% · moves weekly")
            }
            .font(.dripEyebrow(11))
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.bottom, 3)

            if shown.isLowConfidence {
                Text("Low confidence")
                    .font(.dripEyebrow(9)).tracking(9 * 0.10)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.drip.coralWash))
                    .padding(.bottom, 4)
            }
        }
    }

    private var explainer: some View {
        Text("A lap gets into the band on its heat-adjusted pace — what the conditions say the effort was worth, not what the watch recorded. The correction is drawn: the hollow ring is raw, and the stem points to the adjusted value.")
            .font(.dripBody(14.5))
            .lineSpacing(4)
            .foregroundStyle(Color.drip.textPrimary)
    }

    // MARK: - Stats

    private var statRow: some View {
        HStack(spacing: 0) {
            stat(value: "\(Int(summary.minutes.rounded()))", label: "Min in band", tint: band.color)
            statDivider
            stat(value: "\(Int(summary.miles.rounded()))", label: "Miles in band")
            statDivider
            stat(value: summary.paceAdjSec.map { TrendsFormat.pace($0) } ?? "no laps",
                 label: "Adj pace")
            statDivider
            stat(value: summary.hrAvg.map(String.init) ?? "no HR", label: "Avg bpm")
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1).padding(.vertical, 10)
    }

    private func stat(value: String, label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.dripStat(17)).monospacedDigit()
                .foregroundStyle(tint ?? Color.drip.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.dripEyebrow(8.5)).tracking(8.5 * 0.09)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }

    // MARK: - The three lanes

    private var lanesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            laneHeader("Pace", note: "heat-adjusted · ring = raw")
            PaceLane(sessions: shown.sessions, band: band, selected: selected,
                     lowConfidence: shown.isLowConfidence, onSelect: select)
                .frame(height: 160)

            laneRule
            laneHeader("Heart rate", note: "avg bpm while in band")
            HeartRateLane(sessions: shown.sessions, band: band, selected: selected,
                          onSelect: select)
                .frame(height: 70)

            laneRule
            laneHeader("Volume", note: "session mi · dark = in band")
            VolumeLane(sessions: shown.sessions, band: band, selected: selected,
                       onSelect: select)
                .frame(height: 92)

            Text("Sessions run left to right, same order in all three lanes. Tap any column.")
                .font(.dripEyebrow(8)).tracking(8 * 0.09)
                .textCase(.uppercase)
                .lineSpacing(3)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.top, 8)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private var laneRule: some View {
        Rectangle().fill(Color.drip.divider).frame(height: 1)
            .padding(.horizontal, 8).padding(.top, 10)
    }

    private func laneHeader(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.dripEyebrow(10)).tracking(10 * 0.12).bold()
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textPrimary)
            Spacer()
            Text(note)
                .font(.dripEyebrow(8.5)).tracking(8.5 * 0.06)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .padding(.top, 9)
    }

    // MARK: - Selection readout

    private var selectedSession: PaceBandSession? {
        guard let i = selected, shown.sessions.indices.contains(i) else { return nil }
        return shown.sessions[i]
    }

    private func select(_ i: Int) {
        withAnimation(.easeOut(duration: 0.15)) {
            selected = (selected == i) ? nil : i
        }
    }

    @ViewBuilder
    private func selectionCard(_ s: PaceBandSession) -> some View {
        let slice = s.slice(band)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.longDateLabel)
                    .font(.dripEyebrow(10)).tracking(10 * 0.12).bold()
                    .foregroundStyle(Color.drip.textSecondary)
                Spacer()
                if let open = onOpenSession {
                    Button { open(s.id) } label: {
                        Text("Open session ↗")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.coral)
                            .overlay(Rectangle().fill(Color.drip.coral).frame(height: 1),
                                     alignment: .bottom)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(primaryLine(s, slice))
                .font(.dripStat(12.5)).monospacedDigit()
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 10)

            Text(secondaryLine(s))
                .font(.dripStat(11)).monospacedDigit().fontWeight(.regular)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 2)

            Text(overlapLine(s, slice))
                .font(.dripBody(13)).italic()
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 9)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func primaryLine(_ s: PaceBandSession, _ slice: PaceBandSlice?) -> String {
        guard let slice else {
            return "\(fmt1(s.sessionMi)) mi · nothing in this band"
        }
        var parts = [
            "\(fmt1(slice.minutes)) min in band",
            "\(TrendsFormat.pace(slice.paceAdjSec)) /mi adj",
        ]
        if let hr = slice.hrAvg { parts.append("\(hr) bpm") }
        return parts.joined(separator: " · ")
    }

    private func secondaryLine(_ s: PaceBandSession) -> String {
        var parts = ["\(fmt1(s.sessionMi)) mi session"]
        if let dew = s.dewPointF { parts.append("\(dew)°F dew") }
        // Only speak about the correction when there ARE in-band minutes for
        // it to have been applied to. Saying "no correction on file" about a
        // session that never entered this band claims a membership that
        // doesn't exist.
        if let slice = s.slice(band) {
            parts.append(slice.hasCorrection
                         ? "+\(slice.correctionSec) s/mi correction"
                         : "no correction on file")
        }
        return parts.joined(separator: " · ")
    }

    private func overlapLine(_ s: PaceBandSession, _ slice: PaceBandSlice?) -> String {
        if s.overlapMin > 0 {
            return "\(fmt1(s.overlapMin)) of these minutes also fall in the other band."
        }
        return slice == nil
            ? "This session ran outside both bands."
            : "All of these minutes belong to this band alone."
    }

    // MARK: - The overlap note (required, persistent)

    private func overlapNote(_ o: PaceBandOverlap) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Rectangle().fill(Color.drip.coral.opacity(0.5)).frame(width: 2)
            // Interpolated, not `Text + Text` — `+` is deprecated as of iOS 26.
            Text("\(Text("Heads up. ").font(.dripBody(14)).bold().foregroundStyle(Color.drip.coral))\(Text(overlapCopy(o)).font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary))")
                .lineSpacing(4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func overlapCopy(_ o: PaceBandOverlap) -> String {
        let minutes = Int(o.minutesBoth.rounded())
        // They can have drifted apart since: the anchors move weekly, so the
        // minutes that double-counted earlier in the window are still real
        // even when the two bands no longer touch today.
        guard o.widthSec > 0 else {
            return "Your two bands don't overlap at this week's anchors, but they did earlier in "
                + "this window — \(minutes) minutes qualify for both. Toggling shows each band on "
                + "its own terms; it doesn't make them independent."
        }
        return "Your MP sits only \(abs(o.gapSec)) s/mi off your HM, so at ±5% the two bands "
            + "overlap by \(o.widthSec) s/mi — \(minutes) minutes across this window qualify for "
            + "both. Toggling shows each band on its own terms; it doesn't make them independent."
    }

    // MARK: - What the split shows

    /// Deterministic, number-citing prose. Counts only — it never says whether
    /// the split is good, and never suggests changing it.
    private var splitNarrative: some View {
        let hmOnly = shown.sessions.filter { $0.hm != nil && $0.mp == nil }.count
        let mpOnly = shown.sessions.filter { $0.mp != nil && $0.hm == nil }.count
        let both = shown.sessions.filter { $0.hm != nil && $0.mp != nil }.count

        return VStack(alignment: .leading, spacing: 0) {
            Text("What the split shows")
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textSecondary)
            Text(both == 0 ? "The two bands barely meet." : "Two different kinds of work.")
                .font(.dripDisplay(23))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 8)
            Text(
                "\(Int(shown.hm.minutes.rounded())) minutes of HM work and "
                + "\(Int(shown.mp.minutes.rounded())) of MP across "
                + "\(shown.sessions.count) session\(shown.sessions.count == 1 ? "" : "s"). "
                + "\(hmOnly) hold HM only, \(mpOnly) hold MP only, \(both) hold both."
            )
            .font(.dripBody(14.5))
            .lineSpacing(4)
            .foregroundStyle(Color.drip.textPrimary)
            .padding(.top, 10)
        }
    }

    // MARK: - Per-session table

    private var sessionTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Per session · \(band.proseLabel)")
                .font(.dripEyebrow(11)).tracking(11 * 0.12)
                .textCase(.uppercase)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                tableHeader
                ForEach(Array(shown.sessions.enumerated()), id: \.element.id) { i, s in
                    tableRow(i, s)
                }
                Text(tableNote)
                    .font(.dripEyebrow(8)).tracking(8 * 0.09)
                    .textCase(.uppercase)
                    .lineSpacing(3)
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("Date").frame(width: 46, alignment: .leading)
            Text("Min").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Adj pace").frame(width: 54, alignment: .trailing)
            Text("Bpm").frame(width: 36, alignment: .trailing)
        }
        .font(.dripEyebrow(8.5)).tracking(8.5 * 0.09)
        .textCase(.uppercase)
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.vertical, 9)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    /// Two targets, one row. The date is the only cell that names the
    /// session, so it's the "take me there" handle — it opens the workout
    /// itself. The numbers keep the cheap in-place scrub: tapping them
    /// highlights the column in all three lanes, same as tapping the chart.
    /// Without a pager to push into (previews), the date falls back to the
    /// scrub rather than dying under the finger.
    private func tableRow(_ i: Int, _ s: PaceBandSession) -> some View {
        let slice = s.slice(band)
        let on = selected == i
        return HStack(spacing: 6) {
            Button {
                if let open = onOpenSession { open(s.id) } else { select(i) }
            } label: {
                Text(s.dateLabel)
                    .underline(onOpenSession != nil, color: Color.drip.textTertiary)
                    .frame(width: 46, alignment: .leading)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.longDateLabel)
            .accessibilityHint(onOpenSession == nil ? "Highlights this session" : "Opens this workout")

            Button { select(i) } label: {
                HStack(spacing: 6) {
                    Text(slice.map { fmt1($0.minutes) } ?? "not in band")
                        .fontWeight(slice == nil ? .regular : .semibold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(slice == nil ? Color.drip.textTertiary : band.color)
                    Text(slice.map { TrendsFormat.pace($0.paceAdjSec) } ?? "")
                        .frame(width: 54, alignment: .trailing)
                        .foregroundStyle(slice == nil ? Color.drip.textTertiary : Color.drip.textPrimary)
                    Text(slice?.hrAvg.map(String.init) ?? "")
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(slice == nil ? Color.drip.textTertiary : Color.drip.textPrimary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.dripStat(11.5)).monospacedDigit()
        .frame(maxWidth: .infinity)
        .background(on ? Color.drip.cardBackgroundElevated : Color.clear)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private var tableNote: String {
        let missing = shown.sessions.count - shown.sessions(in: band).count
        // Named after the affordance the dates now carry — only when they
        // carry it. Previews with no pager say nothing about tapping.
        let tapHint = onOpenSession == nil ? "" : " Tap a date to open the workout."
        guard missing > 0 else {
            return "Every session in this window held work in the \(band.proseLabel) band."
                + tapHint
        }
        return "\(missing) session\(missing == 1 ? "" : "s") in this window held no "
            + "\(band.shortLabel) work. A session appears here once it holds more than two "
            + "minutes in the band." + tapHint
    }

    // MARK: - Empty band + footer

    /// No qualifying sessions at all inside the chosen window. Distinct from
    /// `emptyBand`, which means she ran but nothing landed in THIS band.
    private var emptyWindow: some View {
        EmptyStateView(
            variant: .optionalEmpty,
            eyebrow: "Nothing in this window",
            title: rangeLabel.map {
                "No session in the last \($0) held either band for more than two minutes. Widen the range above to see further back."
            } ?? "No session here held either band for more than two minutes."
        )
    }

    private var emptyBand: some View {
        EmptyStateView(
            variant: .optionalEmpty,
            eyebrow: "No \(band.shortLabel) work yet",
            title: "Nothing has landed between \(TrendsFormat.pace(summary.fastSec)) and "
                 + "\(TrendsFormat.pace(summary.slowSec)) in this window."
        )
    }

    private var footer: some View {
        Text("Membership on heat-adjusted pace · weekly median anchor")
            .font(.dripEyebrow(8)).tracking(8 * 0.10)
            .textCase(.uppercase)
            .lineSpacing(4)
            .foregroundStyle(Color.drip.textTertiary)
    }

    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
}

// MARK: - Shared lane geometry

/// The x-grid every lane shares. `x0` is the y-label gutter; each session owns
/// one equal-width column, and its mark sits at that column's centre. All
/// three lanes build from this, which is what keeps them vertically aligned.
private struct BandGeometry {
    let width: CGFloat
    let count: Int
    let gutter: CGFloat = 30

    var step: CGFloat { count > 0 ? max(0, width - gutter) / CGFloat(count) : 0 }
    func left(_ i: Int) -> CGFloat { gutter + step * CGFloat(i) }
    func center(_ i: Int) -> CGFloat { gutter + step * (CGFloat(i) + 0.5) }
}

/// Transparent per-session hit targets, laid over a lane. One column each, so
/// the tap target is the full column height rather than the mark's few points.
private struct ColumnTapLayer: View {
    let count: Int
    let gutter: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(0..<max(count, 1), id: \.self) { i in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if i < count { onSelect(i) } }
            }
        }
    }
}

// MARK: - Lane 1 · Pace

/// Pace, inverted (faster = up), against the band ribbon that steps weekly.
///
/// Four marks per session, at most: the band ribbon and its dashed anchor
/// line (always), the filled adjusted mark (when the session held the band),
/// and — only when weather gave us a correction — a hollow raw ring joined to
/// the adjusted mark by a coral stem. The stem always points toward faster,
/// which is what makes "the heat cost you this much" legible without a legend.
private struct PaceLane: View {
    let sessions: [PaceBandSession]
    let band: PaceBandKey
    let selected: Int?
    /// A prediction that doesn't earn a hard line gets a dashed band edge.
    let lowConfidence: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let g = BandGeometry(width: geo.size.width, count: sessions.count)
            let h = geo.size.height
            let scale = PaceScale(sessions: sessions, band: band, height: h)

            ZStack(alignment: .topLeading) {
                // Gridlines + labels.
                ForEach(scale.gridlines, id: \.self) { p in
                    let y = scale.y(Double(p))
                    Path { $0.addLines([CGPoint(x: g.gutter, y: y), CGPoint(x: geo.size.width, y: y)]) }
                        .stroke(Color.drip.divider, lineWidth: 1)
                    Text(TrendsFormat.pace(p))
                        .font(.dripEyebrow(8))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                        .position(x: 13, y: y)
                }

                // The band ribbon — a step polygon, because the anchor moves
                // weekly and a run is judged against its own week's band.
                ribbon(g, scale)
                    .fill(band.color.opacity(0.14))
                ribbon(g, scale)
                    .stroke(band.color.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.3,
                                               dash: lowConfidenceDash))

                // The anchor itself.
                anchorPath(g, scale)
                    .stroke(band.color, style: StrokeStyle(lineWidth: 1.7, dash: [4, 3]))

                if let i = selected, sessions.indices.contains(i) {
                    Rectangle().fill(Color.drip.textPrimary.opacity(0.35))
                        .frame(width: 1, height: h)
                        .position(x: g.center(i), y: h / 2)
                }

                // Heat correction: hollow raw ring + coral stem to the
                // adjusted value. Drawn only when a correction exists — a
                // zero-length stem would imply a measurement we don't have.
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    if let slice = s.slice(band) {
                        let yAdj = scale.y(Double(slice.paceAdjSec))
                        if slice.hasCorrection {
                            let yRaw = scale.y(Double(slice.paceRawSec))
                            Path {
                                $0.addLines([CGPoint(x: g.center(i), y: yAdj),
                                             CGPoint(x: g.center(i), y: yRaw)])
                            }
                            .stroke(Color.drip.coral, lineWidth: 2)
                            Circle()
                                .fill(Color.drip.cardBackground)
                                .overlay(Circle().stroke(Color.drip.coral, lineWidth: 2))
                                .frame(width: 7, height: 7)
                                .position(x: g.center(i), y: yRaw)
                        }
                        Circle()
                            .fill(band.color)
                            .overlay(Circle().stroke(Color.drip.cardBackground, lineWidth: 1.6))
                            .frame(width: 10, height: 10)
                            .position(x: g.center(i), y: yAdj)
                    }
                }
            }
            .overlay(ColumnTapLayer(count: sessions.count, gutter: g.gutter, onSelect: onSelect))
        }
    }

    /// Low confidence gets a dashed outer edge — the band is still drawn, but
    /// it doesn't earn a hard line. (Spec §7.)
    private var lowConfidenceDash: [CGFloat] { lowConfidence ? [3, 3] : [] }

    private func ribbon(_ g: BandGeometry, _ scale: PaceScale) -> Path {
        Path { p in
            guard !sessions.isEmpty else { return }
            for (i, s) in sessions.enumerated() {
                let y = scale.y(Double(s.anchorSec(band)) * 0.95)
                if i == 0 { p.move(to: CGPoint(x: g.left(0), y: y)) }
                else { p.addLine(to: CGPoint(x: g.left(i), y: y)) }
                p.addLine(to: CGPoint(x: g.left(i) + g.step, y: y))
            }
            for (i, s) in sessions.enumerated().reversed() {
                let y = scale.y(Double(s.anchorSec(band)) * 1.05)
                p.addLine(to: CGPoint(x: g.left(i) + g.step, y: y))
                p.addLine(to: CGPoint(x: g.left(i), y: y))
            }
            p.closeSubpath()
        }
    }

    private func anchorPath(_ g: BandGeometry, _ scale: PaceScale) -> Path {
        Path { p in
            for (i, s) in sessions.enumerated() {
                let y = scale.y(Double(s.anchorSec(band)))
                if i == 0 { p.move(to: CGPoint(x: g.left(0), y: y)) }
                else { p.addLine(to: CGPoint(x: g.left(i), y: y)) }
                p.addLine(to: CGPoint(x: g.left(i) + g.step, y: y))
            }
        }
    }
}

/// Pace → y, inverted so faster sits higher. The domain covers every band
/// edge and every mark (raw included) in the window, so nothing ever clips.
private struct PaceScale {
    let lo: Double   // fastest sec/mile in view
    let hi: Double   // slowest
    let top: CGFloat
    let usable: CGFloat

    init(sessions: [PaceBandSession], band: PaceBandKey, height: CGFloat) {
        var values: [Double] = []
        for s in sessions {
            let a = Double(s.anchorSec(band))
            values.append(contentsOf: [a * 0.95, a * 1.05])
            if let sl = s.slice(band) {
                values.append(Double(sl.paceAdjSec))
                values.append(Double(sl.paceRawSec))
            }
        }
        let minV = values.min() ?? 300
        let maxV = values.max() ?? 380
        lo = minV - 6
        hi = max(maxV + 6, lo + 20)
        top = 6
        usable = max(height - 14, 1)
    }

    func y(_ pace: Double) -> CGFloat {
        let t = (pace - lo) / (hi - lo)
        return top + usable * CGFloat(min(max(t, 0), 1))
    }

    /// Whole 20-second gridlines inside the domain — pace reads in :20s.
    var gridlines: [Int] {
        let first = Int((lo / 20).rounded(.up)) * 20
        let last = Int((hi / 20).rounded(.down)) * 20
        guard last >= first else { return [] }
        return stride(from: first, through: last, by: 20).map { $0 }
    }
}

// MARK: - Lane 2 · Heart rate

/// Average bpm while in band. The joining line is a reading aid, not data —
/// it stays recessive so it can't be mistaken for a continuous measurement.
private struct HeartRateLane: View {
    let sessions: [PaceBandSession]
    let band: PaceBandKey
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let g = BandGeometry(width: geo.size.width, count: sessions.count)
            let h = geo.size.height
            let pts = marks(g, height: h)

            ZStack(alignment: .topLeading) {
                ForEach(gridValues, id: \.self) { bpm in
                    let y = yFor(Double(bpm), height: h)
                    Path { $0.addLines([CGPoint(x: g.gutter, y: y), CGPoint(x: geo.size.width, y: y)]) }
                        .stroke(Color.drip.divider, lineWidth: 1)
                    Text("\(bpm)")
                        .font(.dripEyebrow(8))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                        .position(x: 13, y: y)
                }

                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f.point)
                    for q in pts.dropFirst() { p.addLine(to: q.point) }
                }
                .stroke(band.color.opacity(0.28), lineWidth: 1.6)

                if let i = selected, sessions.indices.contains(i) {
                    Rectangle().fill(Color.drip.textPrimary.opacity(0.35))
                        .frame(width: 1, height: h)
                        .position(x: g.center(i), y: h / 2)
                }

                ForEach(pts) { m in
                    Circle().fill(band.color).frame(width: 8.4, height: 8.4).position(m.point)
                }
            }
            .overlay(ColumnTapLayer(count: sessions.count, gutter: g.gutter, onSelect: onSelect))
        }
    }

    private var values: [Int] {
        sessions.compactMap { $0.slice(band)?.hrAvg }
    }

    private var domain: (Double, Double) {
        guard let lo = values.min(), let hi = values.max() else { return (145, 180) }
        let pad = 6.0
        return (Double(lo) - pad, max(Double(hi) + pad, Double(lo) - pad + 10))
    }

    /// Whole tens inside the domain.
    private var gridValues: [Int] {
        let (lo, hi) = domain
        let first = Int((lo / 10).rounded(.up)) * 10
        let last = Int((hi / 10).rounded(.down)) * 10
        guard last >= first else { return [] }
        return stride(from: first, through: last, by: 10).map { $0 }
    }

    /// Higher bpm sits higher — HR is not pace and is not inverted.
    private func yFor(_ bpm: Double, height: CGFloat) -> CGFloat {
        let (lo, hi) = domain
        let t = (hi - bpm) / (hi - lo)
        return 6 + max(height - 14, 1) * CGFloat(min(max(t, 0), 1))
    }

    private func marks(_ g: BandGeometry, height: CGFloat) -> [HRMark] {
        sessions.enumerated().compactMap { i, s in
            guard let hr = s.slice(band)?.hrAvg else { return nil }
            return HRMark(id: s.id, point: CGPoint(x: g.center(i),
                                                   y: yFor(Double(hr), height: height)))
        }
    }

    /// One plotted bpm. A session with no HR on its in-band laps simply isn't
    /// here — the line skips it rather than dropping to zero.
    private struct HRMark: Identifiable {
        let id: String
        let point: CGPoint
    }
}

// MARK: - Lane 3 · Volume

/// Session miles with the in-band miles drawn over them. The pale
/// session-total bar stays put across the toggle on purpose: it's the constant
/// against which each band's contribution reads.
private struct VolumeLane: View {
    let sessions: [PaceBandSession]
    let band: PaceBandKey
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let g = BandGeometry(width: geo.size.width, count: sessions.count)
            let h = geo.size.height
            let base = h - 22            // room for the x tick row
            let top: CGFloat = 12        // room for the direct labels
            let maxMi = max(sessions.map(\.sessionMi).max() ?? 1, 1)
            let barW = max(g.step * 0.62, 2)

            ZStack(alignment: .topLeading) {
                Path { $0.addLines([CGPoint(x: g.gutter, y: base), CGPoint(x: geo.size.width, y: base)]) }
                    .stroke(Color.drip.divider, lineWidth: 1)
                Text("0")
                    .font(.dripEyebrow(8))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 26, alignment: .trailing)
                    .position(x: 13, y: base)

                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    let hTotal = CGFloat(s.sessionMi / maxMi) * (base - top)
                    Rectangle()
                        .fill(PaceSpectrum.easy)
                        .frame(width: barW, height: max(hTotal, 1))
                        .position(x: g.center(i), y: base - max(hTotal, 1) / 2)

                    if let slice = s.slice(band) {
                        let hBand = CGFloat(slice.miles / maxMi) * (base - top)
                        Rectangle()
                            .fill(band.color)
                            .frame(width: barW, height: max(hBand, 1))
                            .position(x: g.center(i), y: base - max(hBand, 1) / 2)
                        Text(String(format: "%.1f", slice.miles))
                            .font(.dripEyebrow(7.5))
                            .foregroundStyle(band.color)
                            .position(x: g.center(i), y: base - hTotal - 7)
                    }
                }

                ForEach(tickIndices, id: \.self) { i in
                    Text(sessions[i].dateLabel)
                        .font(.dripEyebrow(8))
                        .foregroundStyle(Color.drip.textTertiary)
                        .position(x: g.center(i), y: base + 12)
                }

                if let i = selected, sessions.indices.contains(i) {
                    Rectangle().fill(Color.drip.textPrimary.opacity(0.35))
                        .frame(width: 1, height: base)
                        .position(x: g.center(i), y: base / 2)
                }
            }
            .overlay(ColumnTapLayer(count: sessions.count, gutter: g.gutter, onSelect: onSelect))
        }
    }

    /// Up to five evenly spread session labels — the axis shows what it has
    /// and never implies continuity across a gap in lap coverage.
    private var tickIndices: [Int] {
        let n = sessions.count
        guard n > 0 else { return [] }
        if n <= 5 { return Array(0..<n) }
        return (0..<5).map { Int((Double($0) / 4.0 * Double(n - 1)).rounded()) }
    }
}

// MARK: - Previews

#Preview("Pace bands · 6 mo") {
    TrendsPaceBandsView(data: .preview, windowDays: 26 * 7, rangeLabel: "6 mo")
}

#Preview("Pace bands · 4 wk (everything recomputed)") {
    TrendsPaceBandsView(data: .preview, windowDays: 4 * 7, rangeLabel: "4 wk")
}

#Preview("Pace bands · empty MP band") {
    TrendsPaceBandsView(data: .previewEmptyMP, windowDays: 26 * 7, rangeLabel: "6 mo")
}
