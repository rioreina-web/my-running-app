//
//  TrendsThresholdDetailView.swift
//  RunningLog · Trends
//
//  Section 04, full screen.
//
//  **Why this exists.** The inline card is the glance: four stats, a 168pt
//  chart, one line of prose. That is the right size for a section you scroll
//  past. It is the wrong size for the two things section 04 is actually for —
//  moving the band and moving the window while watching what the chart does.
//  Inline, the four control blocks ran to roughly 700pt of scroll, so the
//  control being moved and the chart it moved were never on screen together,
//  and the range control was four sections above.
//
//  This screen puts all three in one place: the chart at 250pt, the controls as
//  a strip under it, and the time control fixed at the top rather than
//  scrolling. Plus the thing the chart cannot do — name every session and say
//  why it graded the way it did.
//
//  **It owns no data.** Everything arrives as a binding or an already-built
//  read:
//
//    * `window` is the SAME `@State` the tab holds. Change the range here and
//      the page behind this screen is already changed. There is no second
//      window that can disagree with the first — the invariant from
//      `TrendsSignalModels.swift`.
//    * `settings` is the same `BandSettingsStore.shared` binding the inline
//      controls write. One band, so the Lab's section 02 and this cannot start
//      disagreeing about the same miles.
//    * `read` is built once per render by the host and handed down. Rebuilding
//      it here would walk every lap in the window a second time.
//
//  The one capability it holds rather than borrows is `resolveDay` — a closure,
//  not the whole `TrendsService`, so a tap on a session can open that workout
//  and this screen can fetch nothing else.
//

import SwiftUI

struct TrendsThresholdDetailView: View {
    /// Built by the host. Nil when the backend predates `band_laps` — but the
    /// host doesn't offer the door in that case, so in practice this is nil
    /// only when the current band catches nothing.
    let read: ThresholdRead?
    @Binding var settings: BandSettings
    /// The tab's window. A binding, not a copy — see the file header.
    @Binding var window: TrendsWindow
    @Binding var customFrom: Date
    @Binding var customTo: Date
    /// The ladder in force at the end of the window, for the anchor chips.
    let ladder: BandLadder?
    /// The dates the window resolved to, and the running inside them. Built by
    /// the host off the same slice the page reads — this screen does no date
    /// arithmetic of its own, so its range line and the tab's cannot differ.
    let meta: (range: String, count: String)?
    /// Which control segment to open on. `"band"` when entered from the
    /// `Adjust ›` line, nil (→ anchor) from the section head.
    var initialBlock: String? = nil
    /// Opens one day's workouts. The screen's only fetch.
    let resolveDay: (String, String?) async -> DayWorkouts?

    @Environment(\.dismiss) private var dismiss

    @State private var dayWorkouts: DayWorkouts?

    @ScaledMetric(relativeTo: .caption2)
    private var microType: CGFloat = DripTypeFloor.eyebrowMicro
    @ScaledMetric(relativeTo: .caption2)
    private var smallType: CGFloat = DripTypeFloor.eyebrowSmall

    private var accent: Color { settings.anchor.color(in: ladder) }

    var body: some View {
        VStack(spacing: 0) {
            head

            // Fixed, not scrolling. The reason this screen exists is to change
            // the band and the range while watching the chart; a range control
            // you have to scroll back to is the problem it is fixing.
            TrendsWindowPicker(
                window: $window,
                customFrom: $customFrom,
                customTo: $customTo,
                isPinned: true,
                meta: meta
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chartCard
                    controls
                    sessionList
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
        .background(Color.drip.background)
        .sheet(item: $dayWorkouts) { dw in
            HistoryDetailPager(entries: dw.entries, initial: dw.initial, onUpdate: {})
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The grabber is drawn rather than borrowed: `fullScreenCover` has
            // no drag indicator of its own, and without one the screen reads as
            // a navigation push it can't be dismissed like.
            Capsule()
                .fill(Color.drip.divider)
                .frame(width: 34, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    DripEyebrow(text: "Section 04", coral: true)
                    Text("Threshold pace")
                        .font(.dripDisplay(24))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Spacer(minLength: 12)
                Button("Done") { dismiss() }
                    .font(.dripEyebrow(smallType).weight(.semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.textPrimary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chartCard: some View {
        if let read, !read.isEmpty {
            LabCard {
                TrendsThresholdView(
                    read: read,
                    onSelect: { open(sessionId: $0, in: read) },
                    chartHeight: 250
                )
            }
        } else {
            // A band the athlete set can be set to catch nothing. Name the band
            // that found nothing and how to open it back up — the controls are
            // directly below, which is the whole argument for this screen.
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing clears this band",
                title: emptyTitle
            )
            .padding(.vertical, 20)
        }
    }

    private var emptyTitle: String {
        var t = "No session in this window held "
        t += settings.minTotalMinutes > 0
            ? "\(Int(settings.minTotalMinutes.rounded())) minutes" : "time"
        if settings.minBlockMinutes > 0 {
            t += " (\(Int(settings.minBlockMinutes.rounded())) unbroken)"
        }
        t += " inside \(settings.anchor.proseLabel) \(settings.widthLabel)."
        if let read, read.excludedSessions > 0 {
            t += " \(read.excludedSessions) came close and fell under the minimum."
        }
        t += " Widen an edge, lower a minimum, or open the window up."
        return t
    }

    // MARK: Controls

    private var controls: some View {
        TrendsThresholdControls(
            settings: $settings,
            ladder: ladder,
            accent: accent,
            layout: .tabbed,
            initialBlock: initialBlock
        )
        .padding(.top, 22)
    }

    // MARK: Sessions

    /// The honest half of the chart. A mark can only *place* a session; this
    /// can say why it graded the way it did — and it counts what the minimums
    /// held out rather than letting an empty stretch of chart imply nothing ran.
    @ViewBuilder
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
                .padding(.bottom, 18)

            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: "Sessions in this window")
                Spacer(minLength: 8)
                Text(listCount)
                    .font(.dripEyebrow(microType))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 4)

            if let read, !read.isEmpty {
                // Newest first — the same order the journal reads in.
                ForEach(read.points.reversed()) { point in
                    Button {
                        open(sessionId: point.id, in: read)
                    } label: {
                        row(point, floor: read.hrFloor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Nothing in this window cleared the band. The chart above says which band, and the controls say how to open it.")
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 26)
    }

    private var listCount: String {
        guard let read else { return "—" }
        var s = "\(read.points.count) counted"
        if read.excludedSessions > 0 { s += " · \(read.excludedSessions) held out" }
        return s
    }

    private func row(_ p: ThresholdPoint, floor: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(p.dateLabel.uppercased())
                .font(.dripEyebrow(microType))
                .tracking(0.8)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(TrendsFormat.pace(p.adjSec))
                    .font(.dripDisplay(16))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(rowDetail(p))
                    .font(.dripEyebrow(microType))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            gradePill(p.grade)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(p.dateLabel), \(TrendsFormat.pace(p.adjSec)) per mile, "
                + "\(Int(p.minutes.rounded())) minutes in band, \(gradeWord(p.grade, floor: floor))"
        )
        .accessibilityHint("Opens this workout")
    }

    private func rowDetail(_ p: ThresholdPoint) -> String {
        var bits = ["\(Int(p.minutes.rounded())) min"]
        // Only worth saying when the time came in pieces — on one unbroken
        // block the two numbers are the same number.
        if p.isFragmented { bits.append("block \(Int(p.blockMinutes.rounded()))") }
        bits.append(p.hrAvg.map { "\($0) bpm" } ?? "no hr")
        if p.hasCorrection { bits.append("raw \(TrendsFormat.pace(p.rawSec))") }
        return bits.joined(separator: " · ")
    }

    /// Takes the floor from the READ rather than from `settings`. They agree
    /// today because the read is rebuilt from the same settings each render —
    /// but this screen's whole argument is that it borrows numbers instead of
    /// recomputing them, and two sources for one figure is how that stops
    /// being true.
    private func gradeWord(_ g: ThresholdGrade, floor: Int) -> String {
        switch g {
        case .work: "graded work"
        case .cruise: "cruising, under the \(floor) floor"
        case .unclassed: "not graded, no heart rate"
        }
    }

    /// Coral only on `unclassed` — it is the alert palette, and "we could not
    /// grade this" is the only one of the three that is a flag rather than a
    /// result. Work and cruise are both real outcomes and share the band hue.
    private func gradePill(_ g: ThresholdGrade) -> some View {
        let text: String
        let fg: Color
        let bg: Color
        switch g {
        case .work:
            text = "Work"; fg = accent; bg = accent.opacity(0.12)
        case .cruise:
            text = "Cruise"
            fg = Color.drip.textSecondary
            bg = Color.drip.cardBackgroundElevated
        case .unclassed:
            text = "No HR"; fg = Color.drip.coral; bg = Color.drip.coral.opacity(0.10)
        }
        return Text(text.uppercased())
            .font(.dripEyebrow(microType).weight(.semibold))
            .tracking(0.9)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }

    // MARK: Drill-down

    /// Opens the workout behind a mark or a row, from this screen rather than
    /// by dismissing back to the tab — tapping a session should not cost the
    /// athlete the band she just set.
    private func open(sessionId: String, in read: ThresholdRead) {
        guard let point = read.points.first(where: { $0.id == sessionId }) else { return }
        Task {
            if let dw = await resolveDay(point.date, point.id) {
                dayWorkouts = dw
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct ThresholdDetailHarness: View {
    @State var settings: BandSettings = .default
    @State var window: TrendsWindow = .thirtyDays
    @State var from = Date().addingTimeInterval(-59 * 86_400)
    @State var to = Date()

    let read: ThresholdRead?

    var body: some View {
        TrendsThresholdDetailView(
            read: read,
            settings: $settings,
            window: $window,
            customFrom: $from,
            customTo: $to,
            ladder: BandLaps.preview.latestLadder,
            meta: (range: "Jul 9 – Aug 7", count: "24 run days"),
            resolveDay: { _, _ in nil }
        )
    }
}

#Preview("Threshold detail") {
    ThresholdDetailHarness(
        read: ThresholdBuilder.build(
            lab: .preview, settings: .default, windowDays: 30
        )
    )
}

/// The band set to catch nothing. The state the controls exist to get out of,
/// and the one most likely to look like a bug if its copy is wrong.
#Preview("Threshold detail · empty band") {
    ThresholdDetailHarness(read: nil)
}
#endif
