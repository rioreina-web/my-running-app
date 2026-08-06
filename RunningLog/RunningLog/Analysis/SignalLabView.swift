//
//  SignalLabView.swift
//  RunningLog · Analysis
//
//  The Signal Lab — five signals, one athlete.
//
//  Opened from the foot of the Trends tab as a sheet, matching how the pace-
//  bands surface is reached. It is not a tab: the tab bar is the app's five
//  daily destinations, and this is a place you go when you want to look hard at
//  something, not somewhere you land.
//
//  **Structure.** One time control at the top, then five sections that each
//  answer one question and show the arithmetic:
//
//    01  AEROBIC DRIFT     how much more the heart cost late in a long run
//    02  THRESHOLD PACE    the band work, heat-neutral, graded on effort
//    03  HR EFFICIENCY     metres bought per heartbeat, reps vs long
//    04  MOOD AND LOAD     what the training looked like under each label
//    05  HEAT IMPACT       what the weather charged, and what it hid
//
//  **Every lede is computed.** No section carries a written sentence about the
//  data — the prose is a function of the numbers, so it cannot go stale when
//  the numbers move. Where a signal cannot be computed the section says what
//  it is waiting on and names the reason, which is itself a useful reading.
//
//  Section 02 reuses `TrendsThresholdView` verbatim rather than drawing a
//  second threshold chart. Two renderers for one metric is how two surfaces
//  start disagreeing about the same miles.
//

import SwiftUI

struct SignalLabView: View {
    @State private var service: TrendsService
    @State private var insights: TrendInsightsService
    @State private var window: TrendsWindow = .threeMonths
    @State private var customFrom: Date = Date().addingTimeInterval(-89 * 86_400)
    @State private var customTo: Date = Date()
    /// The athlete's threshold band. Shared rather than local so anything else
    /// that reads the same band later cannot disagree about what "in band"
    /// means for the same athlete.
    @State private var settingsStore = BandSettingsStore.shared

    /// Called when a chart's session should open in the log.
    private let onOpenSession: ((String) -> Void)?

    init(
        service: TrendsService = .shared,
        insights: TrendInsightsService = .shared,
        onOpenSession: ((String) -> Void)? = nil
    ) {
        _service = State(initialValue: service)
        _insights = State(initialValue: insights)
        self.onOpenSession = onOpenSession
    }

    // MARK: Derived — built once per render, shared by every section

    private var bucketSet: TrendsBucketSet {
        TrendsSignalBuilder.build(
            days: service.days,
            keySessions: service.keySessions,
            window: window
        )
    }

    private var windowDates: Set<String> { Set(bucketSet.days.map(\.date)) }

    private var driftRead: AerobicDriftRead { AerobicDriftBuilder.build(cards: insights.cards) }

    /// The band the athlete set, read off the raw laps. Falls back to the
    /// server's fixed HM ±5% bucketing when the backend predates `band_laps` —
    /// the section keeps working, the controls just have nothing to move.
    private var thresholdRead: ThresholdRead? {
        if let lab = service.bandLaps {
            return ThresholdBuilder.build(
                lab: lab,
                settings: settingsStore.settings,
                windowDays: window.days
            )
        }
        return service.paceBands.map {
            ThresholdBuilder.build(bands: $0, band: .hm, windowDays: window.days)
        }
    }

    /// True once the raw laps are on hand — the controls are inert without
    /// them, so they don't render.
    private var bandIsAdjustable: Bool { service.bandLaps != nil }

    private var efficiencyRead: BeatEfficiencyRead {
        BeatEfficiencyBuilder.build(keySessions: service.keySessions, windowDates: windowDates)
    }

    private var moodLoadRead: MoodLoadRead { MoodLoadBuilder.build(set: bucketSet) }

    private var heatRead: HeatImpactRead {
        HeatImpactBuilder.build(
            keySessions: service.keySessions,
            bands: service.paceBands,
            windowDates: windowDates
        )
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlateStrip(surface: "Running log — signal lab")

                Text("Five signals, one athlete.")
                    .font(.dripDisplay(32))
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Text(lede)
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                TrendsWindowPicker(window: $window, customFrom: $customFrom, customTo: $customTo)
                    .padding(.top, 18)

                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .background(Color.drip.background)
        .presentationDragIndicator(.visible)
        .task {
            await service.refresh()
            await insights.refresh()
        }
    }

    /// The opening paragraph, counted from the window rather than written.
    private var lede: String {
        let days = bucketSet.days.count
        guard days > 0 else {
            return "Nothing logged in this window yet. Widen it, or log a few runs and the signals fill in."
        }
        let sessions = service.keySessions.filter { windowDates.contains($0.date) }.count
        return "\(days) days, \(Int(bucketSet.totalMiles.rounded())) miles, "
            + "\(sessions) key \(sessions == 1 ? "session" : "sessions"). "
            + "Every pace below is heat-neutral unless it says raw, and every number is "
            + "counted from this window — change the control and the whole page recounts."
    }

    // MARK: Sections

    @ViewBuilder
    private var content: some View {
        if service.isLoading && service.days.isEmpty {
            loadingState
        } else if service.days.isEmpty {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Nothing to analyse yet",
                title: "The Lab reads your logged runs. A few weeks of training and these five signals fill in."
            )
            .padding(.top, 40)
        } else {
            driftSection
            thresholdSection
            efficiencySection
            moodLoadSection
            heatSection
            footer
        }
    }

    // MARK: 01 · drift

    private var driftSection: some View {
        section(number: "01", eyebrow: "Aerobic drift", title: driftTitle, sub: driftSub) {
            if driftRead.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "Waiting on streams",
                    title: "Drift needs per-second heart rate and speed, which are read separately from the timeline. It appears here once a few "
                        + "long runs have been processed."
                )
            } else {
                LabCard { LabDriftChart(read: driftRead) }
            }
        }
    }

    private var driftTitle: String {
        guard let mean = driftRead.mean else { return "Not enough long efforts yet." }
        let meanLabel = String(format: "%+.1f", mean)
        if driftRead.overBand.isEmpty {
            return "Aerobically steady, every reading — mean \(meanLabel)%."
        }
        return "\(driftRead.overBand.count) of \(driftRead.points.count) readings left the band."
    }

    private var driftSub: String {
        var s = "Decoupling is how much more your heart cost per unit of speed in the second half "
            + "of a long run than the first. Under \(Int(driftRead.bandHi))% is aerobically steady."
        if let body = driftRead.body, !body.isEmpty {
            s += " " + body
        }
        return s
    }

    // MARK: 02 · threshold

    private var thresholdSection: some View {
        @Bindable var store = settingsStore
        return section(number: "02", eyebrow: "Threshold pace", title: thresholdTitle, sub: thresholdSub) {
            VStack(alignment: .leading, spacing: 0) {
                if let read = thresholdRead, !read.isEmpty {
                    LabCard {
                        TrendsThresholdView(read: read, onSelect: onOpenSession)
                    }
                } else if bandIsAdjustable {
                    // A band the athlete set can be set to catch nothing. Say
                    // which band found nothing and how to open it back up —
                    // the controls sit directly below.
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "Nothing clears this band",
                        title: emptyBandTitle
                    )
                } else {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "No band work yet",
                        title: "This reads every session that spent time inside your half-marathon pace band. Once a few land, the trend draws itself."
                    )
                }

                if bandIsAdjustable {
                    TrendsThresholdControls(
                        settings: $store.settings,
                        ladder: service.bandLaps?.latestLadder,
                        accent: store.settings.anchor.color(in: service.bandLaps?.latestLadder)
                    )
                    .padding(.top, 16)
                }
            }
        }
    }

    /// What the current band asked for, so an empty chart is a readable
    /// result rather than a dead end.
    private var emptyBandTitle: String {
        let s = settingsStore.settings
        var t = "No session in this window held "
        t += s.minTotalMinutes > 0 ? "\(Int(s.minTotalMinutes.rounded())) minutes" : "time"
        if s.minBlockMinutes > 0 {
            t += " (\(Int(s.minBlockMinutes.rounded())) unbroken)"
        }
        t += " inside \(s.anchor.proseLabel) \(s.widthLabel)."
        if let read = thresholdRead, read.excludedSessions > 0 {
            t += " \(read.excludedSessions) came close and fell under the minimum."
        }
        t += " Widen an edge or lower a minimum and it fills in."
        return t
    }

    private var thresholdTitle: String {
        guard let read = thresholdRead, let latest = read.latest else {
            return "No band work in this window."
        }
        guard let trend = read.trendSecPerMonth else {
            return "\(Int(read.workMinutes.rounded())) minutes of band work, latest at \(TrendsFormat.pace(latest.adjSec))."
        }
        if abs(trend) < 2 {
            return "Threshold pace is holding at \(TrendsFormat.pace(latest.adjSec))."
        }
        return trend < 0
            ? "Threshold pace is \(Int(abs(trend).rounded())) sec a month quicker."
            : "Threshold pace is \(Int(trend.rounded())) sec a month slower."
    }

    private var thresholdSub: String {
        guard let read = thresholdRead else { return "" }
        var s = "Every session with time inside the \(read.anchor.proseLabel) band "
            + "(\(TrendsFormat.pace(read.fastSec))–\(TrendsFormat.pace(read.slowSec)), "
            + "\(read.settings.widthLabel)), heat-neutral."
        if read.hrFloor > 0 {
            s += " Minutes count as work when the average heart rate over them clears "
                + "\(read.hrFloor) bpm."
        } else {
            s += " The effort floor is off, so every in-band minute counts as work."
        }
        if read.cruiseMinutes >= 1 {
            s += " \(Int(read.cruiseMinutes.rounded())) minutes here sat in the band on pace and "
                + "under that floor on effort — long-run cruising, held apart."
        }
        // Never let a minimum quietly delete running from the read.
        if read.excludedSessions > 0 {
            s += " \(read.excludedSessions) further "
                + "\(read.excludedSessions == 1 ? "session" : "sessions") touched the band for "
                + "\(Int(read.excludedMinutes.rounded())) minutes in total and fell under the "
                + "minimum, so \(read.excludedSessions == 1 ? "it is" : "they are") left out here."
        }
        if bandIsAdjustable && read.isAdjusted {
            s += " This is your band, not the shipped one."
        }
        return s
    }

    // MARK: 03 · efficiency

    private var efficiencySection: some View {
        section(number: "03", eyebrow: "HR efficiency", title: efficiencyTitle, sub: efficiencySub) {
            if efficiencyRead.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "No paired readings",
                    title: "Efficiency needs a pace and a heart rate on the same work. Sessions without heart-rate data are skipped rather than "
                        + "estimated."
                )
            } else {
                LabCard { LabEfficiencyChart(read: efficiencyRead) }
            }
        }
    }

    private var efficiencyTitle: String {
        let trends = [efficiencyRead.repsTrend, efficiencyRead.longsTrend].compactMap { $0 }
        guard !trends.isEmpty else { return "Metres per heartbeat, session by session." }
        let moving = trends.filter { abs($0) >= 0.02 }
        if moving.isEmpty { return "Metres per heartbeat is flat." }
        return moving.allSatisfy { $0 > 0 }
            ? "You're buying more distance per heartbeat."
            : "Metres per heartbeat is drifting down."
    }

    private var efficiencySub: String {
        "Distance bought per beat at quality effort — speed divided by heart rate, on heat-neutral "
            + "pace. Reps and long efforts are different instruments, so they never share a line. "
            + "\(efficiencyRead.reps.count) rep and \(efficiencyRead.longs.count) long readings here."
    }

    // MARK: 04 · mood and load

    private var moodLoadSection: some View {
        section(number: "04", eyebrow: "Mood and load", title: moodLoadTitle, sub: moodLoadSub) {
            if moodLoadRead.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "Not enough logged",
                    title: "This compares what the training looked like under each mood you logged. Two labels with a couple of days each and it "
                        + "fills in."
                )
            } else {
                LabCard { LabMoodLoadChart(read: moodLoadRead) }
            }
        }
    }

    private var moodLoadTitle: String {
        guard let separates = moodLoadRead.loadSeparates else {
            return "What the training looked like under each label."
        }
        guard let heavy = moodLoadRead.heaviestMood else { return "Mood against load." }
        return separates
            ? "Your heaviest days were logged \(heavy.id)."
            : "Load doesn't separate your mood labels."
    }

    private var moodLoadSub: String {
        var s = "Mean quality load on the days carrying each mood. Mood stays a word here and never "
            + "becomes a score — it gets a row, not an axis. "
            + "\(moodLoadRead.loggedDays) of \(moodLoadRead.totalDays) days carry a log."
        if let separates = moodLoadRead.loadSeparates, !separates {
            s += " Across this window the labels sit within a tenth of each other on load, "
                + "so whatever is moving mood here, the training load is not visibly it."
        }
        return s
    }

    // MARK: 05 · heat

    private var heatSection: some View {
        section(number: "05", eyebrow: "Heat impact", title: heatTitle, sub: heatSub) {
            if heatRead.isEmpty {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "No weather yet",
                    title: "Sessions carry a correction once their weather has been fetched. Without it, a pace is left exactly as the watch "
                        + "recorded it."
                )
            } else {
                LabCard { LabHeatChart(read: heatRead) }
            }
        }
    }

    private var heatTitle: String {
        guard let mean = heatRead.meanPenalty else { return "The weather, priced." }
        if mean >= 10 { return "The weather charged you \(mean) sec a mile." }
        return "A \(mean) sec a mile correction, and it always helps."
    }

    private var heatSub: String {
        var s = "Raw pace against the same run with the dew-point penalty removed, "
            + "across \(heatRead.points.count) corrected \(heatRead.points.count == 1 ? "session" : "sessions")."
        if let slope = heatRead.secPerTenDegDew, slope > 0 {
            s += " Fitted against dew point, every ten degrees is worth about "
                + "\(String(format: "%.1f", slope)) sec a mile."
        }
        if heatRead.uncorrectedCount > 0 {
            s += " \(heatRead.uncorrectedCount) further "
                + "\(heatRead.uncorrectedCount == 1 ? "session carries" : "sessions carry") no weather, "
                + "and \(heatRead.uncorrectedCount == 1 ? "is" : "are") left out rather than assumed neutral."
        }
        return s
    }

    // MARK: Chrome

    @ViewBuilder
    private func section<Content: View>(
        number: String,
        eyebrow: String,
        title: String,
        sub: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        EditorialRule().padding(.vertical, 26)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DripEyebrow(text: eyebrow)
                Spacer(minLength: 8)
                Text(number)
                    .font(.dripEyebrow(9))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Text(title)
                .font(.dripDisplay(22))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text(sub)
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            content()
                .padding(.top, 14)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialRule().padding(.vertical, 26)
            PlateFooter(
                "Drift is read from the stream detectors; threshold, efficiency, mood and heat are "
                + "computed on this device from the timeline the Trends tab already loaded. "
                + "Sessions missing a reading are left out, never estimated."
            )
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your signals…")
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Signal Lab") {
    SignalLabView(
        service: TrendsService(
            preview: [],
            days: TrendsDay.previewMonthRich,
            keySessions: KeySession.previewLadder,
            paceBands: .preview,
            bandLaps: .preview
        )
    )
}
#endif
