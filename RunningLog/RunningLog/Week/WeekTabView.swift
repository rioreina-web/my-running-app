//
//  WeekTabView.swift
//  RunningLog · Week
//
//  Tab 11 — WEEK. The weekly decision surface, built from the athlete's own
//  runs.
//
//    01 · Am I getting faster?      threshold bands, session by session
//    02 · Am I absorbing the work?  load vs own baseline, words, overnight
//    03 · What moves the marathon?  long runs, spectrum, threshold volume
//
//  EVERY NUMBER IS TAPPABLE AND EVERY NUMBER CAN NAME ITS SOURCE. Tap a point
//  on the threshold line and you get the session, its minutes in band, the
//  heat-adjusted pace membership was decided on, and the raw pace the watch
//  recorded. Tap a load bar and you get the runs in that week and what each
//  contributed. Tap the week total and you get the days that add up to it.
//  That last one exists because the first version of this tab showed "48 mi"
//  and could not say where it came from — the answer was that I made it up.
//
//  WHAT IT WILL NOT DO. If a value cannot be derived from the athlete's rows,
//  the section says so in a sentence and shows nothing. No placeholder series,
//  no greyed chart with invented shape, no dash standing in for a number.
//  `WeekRead.Unavailable` carries the reason and `WeekUnavailableNote` renders
//  it. Three sections are in that state today: heart-rate efficiency (built,
//  not plumbed), overnight biometrics (not captured — `vital-webhook` has no
//  daily-sleep branch), and the proposals (no engine exists).
//
//  COPY RULE. Section 02 asks whether the athlete is absorbing the work. It
//  does NOT ask whether they are "healthy" or "overtraining" — the first is a
//  medical claim, the second a clinical diagnosis. Section 01 may conclude
//  ("Faster.") because pace is a measurement; sections about the body get a
//  subject for a headline, never a verdict.
//

import SwiftUI
import UIKit

struct WeekTabView: View {

    @State private var service = WeekService.shared
    @State private var selectedBandIndex = 0
    @State private var selectedLoadWeek: Int?
    @State private var flashed: WeekAnchor?
    @State private var provenance: WeekProvenance?

    var body: some View {
        content
            .background(Color.drip.background)
            .navigationBarTitleDisplayMode(.inline)
            .task { await service.refresh() }
            .refreshable { await service.refresh(force: true) }
            .sheet(item: $provenance) { WeekProvenanceSheet(provenance: $0) }
    }

    @ViewBuilder
    private var content: some View {
        if let read = service.read {
            surface(read)
        } else if service.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.drip.background)
        } else {
            EmptyStateView(
                variant: service.lastError == nil ? .dataPending : .error,
                eyebrow: "Week",
                title: service.lastError == nil
                    ? "Log a run and this fills in."
                    : "Couldn't load your training."
            )
        }
    }

    // MARK: - Surface

    private func surface(_ read: WeekRead) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        plateRow(read)
                        headerBlock(read)
                        weekStripCard(read)
                        WeekRuleView()
                        sectionFaster(read, proxy: proxy)
                    }
                    Group {
                        WeekRuleView()
                        sectionAbsorbing(read)
                        WeekRuleView()
                        sectionMarathon(read)
                        WeekRuleView()
                        sectionTheCall(read)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Header

    private func plateRow(_ read: WeekRead) -> some View {
        HStack {
            plateLabel(read.plateBlock)
            Spacer()
            plateLabel(read.plateRange)
        }
        .padding(.top, 4)
    }

    private func plateLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.dripEyebrow(9))
            .tracking(1.26)
            .foregroundStyle(Color.drip.textSecondary)
    }

    private func headerBlock(_ read: WeekRead) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            WeekEyebrow(text: read.eyebrow)
            Text(read.title)
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
            Text(read.subtitle)
                .font(.dripBody(13.5))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.top, 18)
    }

    // MARK: - Week strip

    private func weekStripCard(_ read: WeekRead) -> some View {
        WeekCard {
            HStack(alignment: .firstTextBaseline) {
                WeekEyebrow(text: "Your week")
                Spacer()
                // The total is a button. "What's this from?" is one tap.
                Button {
                    provenance = weekTotalProvenance(read)
                } label: {
                    HStack(spacing: 5) {
                        WeekCaption(text: read.weekSummary, tint: Color.drip.textSecondary)
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.drip.coral)
                    }
                }
                .buttonStyle(.plain)
            }
            WeekStripView(days: read.days, changedDayNames: []) { day in
                provenance = dayProvenance(day)
            }
            .padding(.top, 10)
            tapHint("Tap a day to see its runs").padding(.top, 10)
        }
        .padding(.top, 16)
    }

    // MARK: - 01 · Faster

    private func sectionFaster(_ read: WeekRead, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            questionHead(
                number: "01 · Am I getting faster?",
                title: "Faster.",
                note: "Am I doing the work at the pace I'm supposed to be doing it at?"
            )

            if let note = read.bandsUnavailable {
                WeekCard(anchor: .threshold, flashed: flashed) {
                    WeekEyebrow(text: "Threshold check")
                    WeekUnavailableNote(note: note).padding(.top, 8)
                }
                .id(WeekAnchor.threshold)
            } else if !read.bands.isEmpty {
                thresholdCard(read)
            }

            if let note = read.efficiencyUnavailable {
                WeekCard(anchor: .efficiency, flashed: flashed) {
                    WeekEyebrow(text: "Heart-rate efficiency")
                    WeekUnavailableNote(note: note).padding(.top, 8)
                }
                .id(WeekAnchor.efficiency)
            }

            if !read.fasterSentence.isEmpty {
                Text(read.fasterSentence)
                    .font(.dripBody(13))
                    .italic()
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    private func activeBand(_ read: WeekRead) -> WeekRead.Band? {
        guard !read.bands.isEmpty else { return nil }
        return read.bands[min(selectedBandIndex, read.bands.count - 1)]
    }

    @ViewBuilder
    private func thresholdCard(_ read: WeekRead) -> some View {
        if let band = activeBand(read) {
            WeekCard(anchor: .threshold, flashed: flashed) {
                HStack(alignment: .firstTextBaseline) {
                    WeekEyebrow(text: "Threshold check")
                    Spacer()
                    bandToggle(read)
                }
                statRow(value: band.currentPace,
                        unit: "/mi",
                        delta: band.delta,
                        deltaTint: band.delta.hasPrefix("−") ? Color.drip.positive : Color.drip.textSecondary)
                    .padding(.top, 10)

                WeekLineChart(points: band.points, tint: band.tint, height: 68) { index in
                    provenance = bandProvenance(band, index: index)
                }
                .padding(.top, 10)

                axisRow(first: band.points.first?.weekLabel,
                        last: band.points.last?.weekLabel)
                WeekCaption(text: band.footnote).padding(.top, 8)
                tapHint("Tap a session to see what it's from").padding(.top, 8)
            }
            .id(WeekAnchor.threshold)
        }
    }

    private func bandToggle(_ read: WeekRead) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(read.bands.enumerated()), id: \.element.id) { index, band in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selectedBandIndex = index }
                } label: {
                    Text(band.key)
                        .font(.dripEyebrow(9.5))
                        .tracking(0.95)
                        .foregroundStyle(selectedBandIndex == index
                                         ? Color.drip.background
                                         : Color.drip.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.drip.textPrimary)
                                .opacity(selectedBandIndex == index ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the \(band.key) band")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.drip.paperDeep))
    }

    // MARK: - 02 · Absorbing

    private func sectionAbsorbing(_ read: WeekRead) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            questionHead(
                number: "02 · Am I absorbing the work?",
                title: "Load and recovery.",
                note: "Your own words lead. The overnight numbers corroborate — never the reverse."
            )
            loadCard(read)
            recoveryCard(read)
        }
    }

    private func loadCard(_ read: WeekRead) -> some View {
        WeekCard(anchor: .load, flashed: flashed) {
            HStack(alignment: .firstTextBaseline) {
                WeekEyebrow(text: "Training load")
                Spacer()
                WeekCaption(text: "Stacked by pace zone")
            }
            statRow(value: read.load.current,
                    unit: "load",
                    delta: read.load.deltaText,
                    deltaTint: read.load.deltaText.hasPrefix("+") ? Color.drip.tired : Color.drip.textSecondary)
                .padding(.top, 10)

            if read.load.weeks.isEmpty {
                WeekUnavailableNote(note: .needsHistory("No weeks with computed load yet."))
                    .padding(.top, 8)
            } else {
                WeekLoadChart(load: read.load, selectedIndex: $selectedLoadWeek) { week in
                    provenance = loadProvenance(week, load: read.load)
                }
                .padding(.top, 10)
                WeekCaption(text: loadReadout(read)).padding(.top, 8)
                tapHint("Tap a week to see the runs in it").padding(.top, 6)
            }
        }
        .id(WeekAnchor.load)
    }

    private func loadReadout(_ read: WeekRead) -> String {
        guard let index = selectedLoadWeek, read.load.weeks.indices.contains(index) else {
            return "Tap a week to read it"
        }
        let week = read.load.weeks[index]
        let share = Int((week.sharpShare * 100).rounded())
        return "\(week.label) · \(Int(week.total)) load · \(share)% from MP and faster"
    }

    private func recoveryCard(_ read: WeekRead) -> some View {
        WeekCard(anchor: .recovery, flashed: flashed) {
            HStack(alignment: .firstTextBaseline) {
                WeekEyebrow(text: "Your words lead")
                Spacer()
                WeekCaption(text: "14 days")
            }

            if read.recovery.niggles.isEmpty {
                WeekCaption(text: "No body mentions in the window")
                    .padding(.top, 10)
            } else {
                HStack(spacing: 6) {
                    ForEach(read.recovery.niggles) { niggle in
                        WeekChip(text: "\(niggle.name) · \(niggle.status)",
                                 tint: niggle.tint,
                                 strikethrough: niggle.resolved)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }

            if !read.recovery.niggleDots.isEmpty {
                dotRow(read).padding(.top, 10)
            }
            if !read.recovery.moods.isEmpty {
                moodRow(read).padding(.top, 8)
            }
            WeekCaption(text: read.recovery.moodSummary).padding(.top, 8)

            Rectangle().fill(Color.drip.divider).frame(height: 1).padding(.vertical, 13)

            WeekEyebrow(text: "Overnight")

            if let note = read.overnightUnavailable {
                WeekUnavailableNote(note: note).padding(.top, 8)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(read.recovery.overnight) { stat in
                        overnightColumn(stat)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            Text(read.recovery.sentence)
                .font(.dripBody(13))
                .italic()
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .id(WeekAnchor.recovery)
    }

    private func dotRow(_ read: WeekRead) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(read.recovery.niggleDots.enumerated()), id: \.offset) { _, mentioned in
                Circle()
                    .fill(mentioned ? Color.drip.coral : Color.drip.textTertiary)
                    .opacity(mentioned ? 1 : 0.3)
                    .frame(width: 5, height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Niggle mentions across the last 14 days")
    }

    /// An unlogged day is an EMPTY RING, never a colour. This athlete logs a
    /// mood on a minority of runs, so most of this row is honestly blank —
    /// and that blankness is itself the finding.
    private func moodRow(_ read: WeekRead) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(read.recovery.moods.enumerated()), id: \.offset) { _, tint in
                Group {
                    if let tint {
                        Circle().fill(tint)
                    } else {
                        Circle().stroke(Color.drip.textTertiary.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(width: 9, height: 9)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Mood from your logs; empty rings are days with nothing logged")
    }

    private func overnightColumn(_ stat: WeekRead.OvernightStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WeekCaption(text: stat.label, tint: Color.drip.textTertiary)
            HStack(spacing: 4) {
                Text(stat.value)
                    .font(.dripStat(13))
                    .foregroundStyle(Color.drip.textPrimary)
                if let baseline = stat.baseline {
                    Text("/ \(baseline)")
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            WeekCaption(text: stat.note, tint: stat.noteTint)
        }
    }

    // MARK: - 03 · The marathon

    private func sectionMarathon(_ read: WeekRead) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            questionHead(
                number: "03 · What moves the marathon?",
                title: "The marathon.",
                note: "Long runs, threshold volume — and the paces you don't visit."
            )
            longRunCard(read)
            spectrumCard(read)
            HStack(alignment: .top, spacing: 12) {
                miniStatCard(read.longThreshold)
                miniStatCard(read.volume)
            }
        }
    }

    private func longRunCard(_ read: WeekRead) -> some View {
        WeekCard(anchor: .longRuns, flashed: flashed) {
            HStack(alignment: .firstTextBaseline) {
                WeekEyebrow(text: "Long runs")
                Spacer()
                WeekCaption(text: "Last four")
            }
            if read.longRuns.isEmpty {
                WeekUnavailableNote(note: .needsHistory("No runs in the window are classified as long runs yet."))
                    .padding(.top, 8)
            } else {
                ledgerHeader.padding(.top, 12)
                ForEach(read.longRuns) { run in
                    Button {
                        guard !run.laps.isEmpty else { return }
                        provenance = longRunProvenance(run)
                    } label: {
                        ledgerRow(run)
                    }
                    .buttonStyle(.plain)
                }
                tapHint("Fuelling and cardiac drift aren't captured yet — this shows what is.")
                    .padding(.top, 10)
            }
        }
        .id(WeekAnchor.longRuns)
    }

    private var ledgerHeader: some View {
        HStack(spacing: 6) {
            WeekCaption(text: "Date").frame(width: 48, alignment: .leading)
            WeekCaption(text: "Dist").frame(width: 38, alignment: .leading)
            WeekCaption(text: "Inside it").frame(maxWidth: .infinity, alignment: .leading)
            WeekCaption(text: "Time").frame(width: 52, alignment: .trailing)
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private func ledgerRow(_ run: WeekRead.LongRun) -> some View {
        HStack(spacing: 6) {
            Text(run.date)
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 48, alignment: .leading)
            Text(run.distance)
                .font(.dripStat(12))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 38, alignment: .leading)
            Text(run.inside.uppercased())
                .font(.dripEyebrow(9))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(run.durationLabel)
                .font(.dripStat(12))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    private func spectrumCard(_ read: WeekRead) -> some View {
        WeekCard(anchor: .spectrum, flashed: flashed) {
            HStack(alignment: .firstTextBaseline) {
                WeekEyebrow(text: "Where your miles live")
                Spacer()
                WeekCaption(text: "Last 4 weeks")
            }
            if read.spectrum.isEmpty {
                WeekUnavailableNote(note: .needsHistory("No runs in the last four weeks carry a lap breakdown, so there's nothing to split by pace."))
                    .padding(.top, 8)
            } else {
                WeekSpectrumBar(slices: read.spectrum) { slice in
                    provenance = spectrumProvenance(slice)
                }
                .padding(.top, 12)
                spectrumLegend(read).padding(.top, 10)
                if !read.spectrumNote.isEmpty {
                    WeekChip(text: read.spectrumNote, tint: PaceSpectrum.steady)
                        .padding(.top, 10)
                }
                tapHint("Tap a zone to see the runs in it").padding(.top, 8)
            }
        }
        .id(WeekAnchor.spectrum)
    }

    private func spectrumLegend(_ read: WeekRead) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(legendRows(read), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { index in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(read.spectrum[index].zone.color)
                                .frame(width: 8, height: 8)
                            WeekCaption(
                                text: "\(read.spectrum[index].zone.label) \(shareText(read.spectrum[index].share))",
                                tint: Color.drip.textSecondary
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func legendRows(_ read: WeekRead) -> [[Int]] {
        let indices = Array(read.spectrum.indices)
        return stride(from: 0, to: indices.count, by: 4).map {
            Array(indices[$0..<min($0 + 4, indices.count)])
        }
    }

    private func shareText(_ share: Double) -> String {
        share >= 10 ? "\(Int(share.rounded()))%" : String(format: "%.1f%%", share)
    }

    private func miniStatCard(_ stat: WeekRead.MiniStat) -> some View {
        WeekCard {
            WeekEyebrow(text: stat.eyebrow)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stat.value)
                    .font(.dripStat(21))
                    .foregroundStyle(Color.drip.textPrimary)
                WeekCaption(text: stat.unit)
            }
            .padding(.top, 8)
            WeekCaption(text: stat.caption).padding(.top, 7)
            if !stat.note.isEmpty {
                WeekCaption(text: stat.note, tint: stat.noteTint).padding(.top, 4)
            }
        }
    }

    // MARK: - The call

    private func sectionTheCall(_ read: WeekRead) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                WeekEyebrow(text: "The call", tint: Color.drip.coral)
                Text("What's missing.")
                    .font(.dripDisplay(25))
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(.top, 3)
            }
            if let note = read.proposalsUnavailable {
                WeekCard { WeekUnavailableNote(note: note) }
            }
        }
    }

    // MARK: - Shared

    private func questionHead(number: String, title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            WeekEyebrow(text: number)
            Text(title)
                .font(.dripDisplay(25))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 3)
            Text(note)
                .font(.dripBody(13))
                .italic()
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private func statRow(value: String, unit: String, delta: String, deltaTint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.dripStat(27))
                .foregroundStyle(Color.drip.textPrimary)
            WeekCaption(text: unit, tint: Color.drip.textSecondary)
            Spacer(minLength: 8)
            Text(delta.uppercased())
                .font(.dripEyebrow(10))
                .tracking(0.8)
                .foregroundStyle(deltaTint)
                .multilineTextAlignment(.trailing)
        }
    }

    private func axisRow(first: String?, last: String?) -> some View {
        HStack {
            WeekCaption(text: first ?? "")
            Spacer()
            WeekCaption(text: last ?? "")
        }
        .padding(.top, 4)
    }

    private func tapHint(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.drip.coral)
            WeekCaption(text: text, tint: Color.drip.textTertiary)
        }
    }

    // MARK: - Provenance builders
    //
    // Each one is built from the datum that was tapped, so a sheet can only
    // ever show rows that actually went into the number above it.

    private func weekTotalProvenance(_ read: WeekRead) -> WeekProvenance {
        let ran = read.days.filter { ($0.miles ?? 0) > 0 }
        return WeekProvenance(
            eyebrow: "Where this comes from",
            title: read.weekSummary,
            subtitle: "Week of \(read.plateRange)",
            method: "Every run logged this week, deduped and summed. Days you ran twice are counted once as a day and twice as runs — which is why the run count is higher than the number of days.",
            rows: ran.map { day in
                WeekSourceRun(
                    date: day.name,
                    name: day.runs.count > 1 ? "\(day.runs.count) runs" : day.label,
                    detail: day.runs.map { String(format: "%.1f", $0.miles) }.joined(separator: " + "),
                    value: String(format: "%.1f mi", day.miles ?? 0),
                    secondary: nil
                )
            },
            coverage: "\(ran.count) days with running",
            tint: Color.drip.coral,
            valueHeader: "Miles"
        )
    }

    private func dayProvenance(_ day: WeekRead.Day) -> WeekProvenance {
        WeekProvenance(
            eyebrow: "Where this comes from",
            title: String(format: "%.1f mi", day.miles ?? 0),
            subtitle: "\(day.name) · \(day.runs.count) \(day.runs.count == 1 ? "run" : "runs")",
            method: "The runs logged on this day, in clock order.",
            rows: day.runs.map {
                WeekSourceRun(date: $0.clock, name: $0.label,
                              detail: "", value: String(format: "%.1f mi", $0.miles),
                              secondary: nil)
            },
            coverage: "",
            tint: Color.drip.coral,
            valueHeader: "Miles"
        )
    }

    private func bandProvenance(_ band: WeekRead.Band, index: Int) -> WeekProvenance {
        let point = band.points[index]
        return WeekProvenance(
            eyebrow: "Where this comes from",
            title: paceString(point.paceSec),
            subtitle: "\(band.key) band · \(point.weekLabel)",
            method: band.method,
            rows: point.sessions,
            coverage: band.footnote,
            tint: band.tint,
            valueHeader: "Adjusted pace"
        )
    }

    private func loadProvenance(_ week: WeekRead.LoadWeek, load: WeekRead.Load) -> WeekProvenance {
        WeekProvenance(
            eyebrow: "Where this comes from",
            title: String(Int(week.total.rounded())),
            subtitle: "Load · week of \(week.label)",
            method: load.method,
            rows: week.sessions,
            coverage: load.baselineLabel,
            tint: PaceSpectrum.steady,
            valueHeader: "Load"
        )
    }

    private func spectrumProvenance(_ slice: WeekRead.SpectrumSlice) -> WeekProvenance {
        WeekProvenance(
            eyebrow: "Where this comes from",
            title: slice.miles,
            subtitle: "\(slice.zone.label) · \(shareText(slice.share)) of the last 4 weeks",
            method: "Miles whose lap pace sat in this zone, taken from the per-lap breakdown of each run. Runs without laps carry no breakdown and are not counted here.",
            rows: slice.sessions,
            coverage: "\(slice.sessions.count) runs put miles in this zone",
            tint: slice.zone.color,
            valueHeader: "In zone"
        )
    }

    private func longRunProvenance(_ run: WeekRead.LongRun) -> WeekProvenance {
        WeekProvenance(
            eyebrow: "Where this comes from",
            title: "\(run.distance) mi",
            subtitle: "\(run.date) · \(run.inside)",
            method: "The runs logged on this day and what each contributed.",
            rows: run.laps,
            coverage: "",
            tint: PaceSpectrum.easy,
            valueHeader: "Duration"
        )
    }

    private func paceString(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

#Preview("Empty account") {
    NavigationStack {
        ScrollView { Text("Preview renders empty states — see WeekPreviewData.swift") }
    }
}
