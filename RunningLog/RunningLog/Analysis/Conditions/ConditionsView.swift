import SwiftUI

/// The Conditions — every session, with the weather in it.
///
/// Reached from Settings. Every training session is a row, easy runs included;
/// tapping a row opens its splits. Where the athlete pressed the lap button on
/// a workout, the reps come out as their own pace sheet above the splits.
struct ConditionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ConditionsSession] = []
    @State private var weeks: [ConditionsWeek] = []
    @State private var rangeDays = 56
    @State private var onlyFast = false
    @State private var expanded: Set<UUID> = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var exportURL: URL?
    @State private var showShare = false

    private let fastCut: Double = 375   // TODO: ConditionsRollup.fastCutSeconds(zones:)

    /// The range set. Drives the pace ramp calibration, and never the filtered
    /// set — calibrating on matches means the same run reads a different colour
    /// depending on what else is on screen.
    private var inRange: [ConditionsSession] {
        guard let newest = sessions.first?.date else { return [] }
        let cutoff = newest.addingTimeInterval(-Double(rangeDays) * 86_400)
        return sessions.filter { $0.date >= cutoff }
    }
    private var visible: [ConditionsSession] {
        onlyFast ? inRange.filter { !$0.fastSegments.isEmpty } : inRange
    }
    private var calibration: (slow: Double, fast: Double) {
        // 5th/95th percentile, not min/max: one wall-clock row otherwise
        // stretches the ramp until every real run collapses into two stops.
        let p = inRange.compactMap(\.paceSeconds).sorted()
        guard p.count > 2 else { return (600, 300) }
        return (p[Int(Double(p.count - 1) * 0.95)], p[Int(Double(p.count - 1) * 0.05)])
    }

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(Color.drip.coral)
            } else if loadFailed {
                emptyState(eyebrow: "Couldn't load",
                           title: "The sheet didn't load.",
                           prose: "Check your connection and try again.",
                           cta: "Try again") { Task { await load() } }
            } else if sessions.isEmpty {
                emptyState(eyebrow: "No sessions",
                           title: "Nothing here yet.",
                           prose: "Sync a run from Strava or record a voice log, "
                                + "and it will show up here.",
                           cta: nil, action: nil)
            } else {
                content
            }
        }
        .navigationTitle("The Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { export() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(Color.drip.coral)
                .disabled(visible.isEmpty)
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .task { await load() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                header
                ForEach(groupedWeeks) { bucket in
                    Section {
                        ForEach(bucket.sessions) { session in
                            row(session)
                        }
                    } header: {
                        weekHeader(bucket.start)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Every session, with the weather in it.")
                .font(.dripDisplay(28))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 8)

            Text("Every run, easy ones included. Tap any row and it opens into "
                 + "its splits. Where you pressed the lap button on a workout, the "
                 + "reps come out as their own pace sheet above the splits.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach([28, 56, 400], id: \.self) { d in
                    chip(d == 400 ? "All" : "\(d / 7) wk", on: rangeDays == d) {
                        rangeDays = d; expanded.removeAll()
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                chip("All sessions \(inRange.count)", on: !onlyFast) { onlyFast = false }
                chip("Fast segments \(inRange.filter { !$0.fastSegments.isEmpty }.count)",
                     on: onlyFast) { onlyFast = true }
                Spacer()
            }

            // A filter is easy to switch on and easy to forget, and a filtered
            // list looks identical to a broken one. Say which you are looking at.
            Text(onlyFast
                 ? "Showing \(visible.count) of \(inRange.count) sessions."
                 : "All \(inRange.count) sessions in range. Every one opens into its splits.")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)

            // 2-up, never 3 at this width: three squeezes the numerals.
            DripStatStrip(stats: [
                DripStat("MILES", String(format: "%.0f", inRange.reduce(0) { $0 + $1.miles })),
                DripStat("SESSIONS", "\(inRange.count)",
                         unit: "\(inRange.filter { !$0.fastSegments.isEmpty }.count) quality"),
            ])
        }
        .padding(.bottom, 20)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.dripEyebrow(max(10, DripTypeFloor.eyebrowSmall)))
                .tracking(1.0)
                .foregroundStyle(on ? Color.drip.background : Color.drip.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    Capsule().fill(on ? Color.drip.textPrimary : .clear)
                        .overlay(Capsule().stroke(on ? .clear : Color.drip.divider, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private struct WeekBucket: Identifiable {
        var id: Date { start }
        let start: Date
        let sessions: [ConditionsSession]
    }

    private var groupedWeeks: [WeekBucket] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return Dictionary(grouping: visible) { s in
            cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear],
                                              from: s.date)) ?? s.date
        }
        .sorted { $0.key > $1.key }
        .map { WeekBucket(start: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
    }

    private func weekHeader(_ start: Date) -> some View {
        let w = weeks.first { Calendar.current.isDate($0.start, inSameDayAs: start) }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return HStack(spacing: 6) {
            Text("Week of \(f.string(from: start))".uppercased())
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textPrimary)
            if let w {
                Text("· \(Int(w.miles.rounded())) mi · \(w.daysRun) days · \(w.quality) quality"
                     + (w.isPartial ? " · partial week" : ""))
                    .font(.dripEyebrow(10)).tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .background(Color.drip.background)
        .overlay(alignment: .bottom) { DripHairline() }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ s: ConditionsSession) -> some View {
        let isOpen = expanded.contains(s.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(s.id) } else { expanded.insert(s.id) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        dateRail(s)
                        Text(s.label)
                            .font(.dripDisplay(16))
                            .fontWeight(s.fastSegments.isEmpty ? .regular : .bold)
                            .foregroundStyle(s.fastSegments.isEmpty
                                             ? Color.drip.textSecondary : Color.drip.textPrimary)
                        if !s.fastSegments.isEmpty {
                            Text("×\(s.fastSegments.count)")
                                .font(.dripStat(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", s.miles))
                            .font(.dripStat(14)).foregroundStyle(Color.drip.textPrimary)
                        Text(ConditionsRollup.mmss(s.paceSeconds))
                            .font(.dripStat(12))
                            .foregroundStyle(paceColor(s.paceSeconds))
                            .frame(width: 46, alignment: .trailing)
                    }
                    metaLine(s).padding(.leading, 52)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen { ConditionsDetail(session: s, fastCut: fastCut,
                                         calibration: calibration) }
        }
        .overlay(alignment: .leading) {
            // Mood rides the row's left rule: it costs no width, and its
            // absence is the absence of a marker rather than an empty cell.
            Rectangle()
                .fill(Color.drip.moodBorderColor(for: s.mood) ?? .clear)
                .frame(width: 2)
        }
        .overlay(alignment: .bottom) { DripHairline() }
    }

    private func dateRail(_ s: ConditionsSession) -> some View {
        let day = DateFormatter(); day.dateFormat = "d"
        let dow = DateFormatter(); dow.dateFormat = "EEE"
        return VStack(alignment: .leading, spacing: 3) {
            Text(day.string(from: s.date))
                .font(.dripDisplay(19)).foregroundStyle(Color.drip.textPrimary)
            Text(dow.string(from: s.date).uppercased())
                .font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(width: 40, alignment: .leading)
    }

    @ViewBuilder
    private func metaLine(_ s: ConditionsSession) -> some View {
        let parts: [String] = {
            var p: [String] = []
            if let hr = s.avgHeartRate { p.append("HR \(hr)") }
            if !s.fastSegments.isEmpty {
                p.append("\(s.fastSegments.count)× fast")
                if let hr = s.fastAvgHeartRate { p.append("HR \(hr)") }
            }
            if let t = s.weather?.tempF, let d = s.weather?.dewPointF {
                p.append("\(Int(t.rounded()))° · dew \(Int(d.rounded()))° \(s.weather?.loadTicks ?? "")")
            } else if s.isIndoor {
                p.append("indoor · no weather")
            }
            if let adj = s.adjustedPaceSeconds, (s.heatCostSeconds ?? 0) > 0 {
                p.append("cool \(ConditionsRollup.mmss(adj))")
            }
            if let m = s.mood { p.append(m) }
            return p
        }()
        Text(parts.joined(separator: "   "))
            .font(.dripEyebrow(10)).tracking(0.6)
            .foregroundStyle(Color.drip.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func paceColor(_ seconds: Double?) -> Color {
        guard let s = seconds else { return Color.drip.textTertiary }
        let c = calibration
        return PaceSpectrum.color(forPaceSec: s, slowSec: c.slow, fastSec: c.fast)
    }

    /// Eyebrow + plain-prose nudge + optional CTA. Never an em-dash and never
    /// a blank field: `docs/conventions/empty-states.md`.
    private func emptyState(eyebrow: String, title: String, prose: String,
                            cta: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Text(eyebrow.uppercased())
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Text(title)
                .font(.dripDisplay(24)).foregroundStyle(Color.drip.textPrimary)
            Text(prose)
                .font(.dripBody(15)).foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let cta, let action {
                Button(cta, action: action)
                    .font(.dripLabel(15))
                    .foregroundStyle(Color.drip.coral)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }

    // MARK: Load + export

    private func load() async {
        isLoading = true; loadFailed = false
        do {
            let rows = try await TrainingLogStore.shared.refresh(days: TrainingLogStore.windowDays)
            apply(rows)
        } catch {
            let cached = TrainingLogStore.shared.cachedRows(days: TrainingLogStore.windowDays)
            if cached.isEmpty { loadFailed = true } else { apply(cached) }
        }
        isLoading = false
    }

    private func apply(_ rows: [TodayLogRow]) {
        sessions = ConditionsRollup.sessions(from: rows, fastCut: fastCut)
        weeks = ConditionsWeek.build(sessions)
    }

    private func export() {
        do {
            exportURL = try ConditionsExport.build(sessions: visible, weeks: weeks,
                                                   fastCut: fastCut)
            showShare = true
        } catch {
            exportURL = nil
        }
    }
}

// MARK: - Expansion

private struct ConditionsDetail: View {
    let session: ConditionsSession
    let fastCut: Double
    let calibration: (slow: Double, fast: Double)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let plan = session.plannedWorkout, !plan.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("As you called it".uppercased())
                        .font(.dripEyebrow(10)).tracking(1.4)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text(plan)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.paperDeep)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !session.fastSegments.isEmpty {
                table("Pace sheet · the reps · faster than \(ConditionsRollup.mmss(fastCut))/mi",
                      rows: session.fastSegments, numbered: true)
            }
            if !session.splits.isEmpty {
                table("Splits", rows: session.splits, numbered: true)
            } else {
                Text(session.isIndoor
                     ? "Entered by hand with no watch file, so there are no splits to read."
                     : "This upload came back as a single piece with no split detail.")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
            }

            heat
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 16)
        .padding(.leading, 8)
    }

    private func table(_ title: String, rows: [PaceSegment], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.dripEyebrow(10)).tracking(1.4)
                .foregroundStyle(Color.drip.textSecondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, seg in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(.dripEyebrow(10))
                        .foregroundStyle(Color.drip.textTertiary).frame(width: 20, alignment: .leading)
                    Text(String(format: "%.2f", seg.distanceMiles))
                        .font(.dripStat(12)).frame(width: 42, alignment: .trailing)
                    Text(ConditionsRollup.mmss(seg.durationSeconds))
                        .font(.dripStat(12)).frame(width: 46, alignment: .trailing)
                        .foregroundStyle(Color.drip.textSecondary)
                    Text(seg.pacePerMile).font(.dripStat(12)).fontWeight(.semibold)
                        .frame(width: 46, alignment: .trailing)
                        .foregroundStyle(color(for: seg))
                    Spacer()
                    Text(seg.avgHeartRate.map(String.init) ?? "not worn")
                        .font(.dripStat(12))
                        .foregroundStyle(seg.avgHeartRate == nil
                                         ? Color.drip.textTertiary : Color.drip.textPrimary)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { DripHairline() }
            }
        }
    }

    private func color(for seg: PaceSegment) -> Color {
        guard let s = ConditionsRollup.paceSeconds(from: seg.pacePerMile) else {
            return Color.drip.textPrimary
        }
        return PaceSpectrum.color(forPaceSec: s, slowSec: calibration.slow, fastSec: calibration.fast)
    }

    @ViewBuilder
    private var heat: some View {
        if let w = session.weather, let t = w.tempF, let d = w.dewPointF {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heat · temperature + dew point".uppercased())
                    .font(.dripEyebrow(10)).tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(alignment: .top, spacing: 20) {
                    stat("Temp", "\(Int(t.rounded()))°")
                    stat("Dew point", "\(Int(d.rounded()))°")
                    if let h = w.humidity { stat("Humidity", "\(Int(h.rounded()))%") }
                    if let p = w.adjustmentPct {
                        stat("Pace cost", String(format: "%.1f%%", p * 100))
                    }
                    Spacer()
                }
                if let adj = session.adjustedPaceSeconds, let cost = session.heatCostSeconds {
                    Text("At \(Int(t.rounded()))° with a \(Int(d.rounded()))° dew point the heat "
                         + "cost about \(cost) seconds a mile. On a cool, dry morning this effort "
                         + "reads as \(ConditionsRollup.mmss(adj)).")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("No GPS on this upload, so there is no location to read the weather "
                 + "from. Pace is shown as recorded.")
                .font(.dripBody(13)).foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k.uppercased()).font(.dripEyebrow(9)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
            Text(v).font(.dripStat(17)).foregroundStyle(Color.drip.textPrimary)
        }
    }
}
