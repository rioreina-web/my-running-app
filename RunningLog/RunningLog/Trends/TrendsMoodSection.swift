import SwiftUI

//  MOOD · what the last fortnight came back as, against the fortnight before.
//
//  The headline is a count over a window — "7 of 14 days struggling or worse" —
//  not a score. Definitive because the window is concrete, reversible because
//  you can point at the seven in the chart below, and a trend because the
//  fortnight before it is printed underneath.
//
//  WHAT IS TAPPABLE, AND WHAT IS DELIBERATELY NOT.
//
//  A day cell selects. The row under the chart opens it. Those are two separate
//  taps on purpose: this tab already learned on 2026-08-03 that a chart which
//  opens a sheet on touch cannot be scrolled past — every attempt to scroll the
//  page started on the chart and presented a workout. So the chart READS, and
//  opening is a deliberate second tap on a row that names the day it will open.
//
//  The counted list at the foot is the other tappable thing: tapping a label
//  dims every cell that isn't it, which answers "which four days were
//  struggling" by pointing rather than by scrubbing fourteen columns.
//
//  ONE TIME CONTROL, LOCALLY. Every other section on this tab reads the
//  segmenter's `window`. This one does not: the segmenter offers 6/12/26 weeks
//  and this read is defined on a fortnight. The stepper is scoped here and
//  labelled with its absolute span so it can't be mistaken for the tab's range.
struct TrendsMoodSection: View {

    let service: TrendsService
    let days: [TrendsDay]
    let keySessions: [KeySession]

    @State private var blocksBack = 0
    @State private var lanesOn: Set<TrendsMoodLane> = TrendsMoodLane.defaultOn
    @State private var scrubIndex: Int?
    @State private var highlight: String?
    @State private var dayWorkouts: DayWorkouts?
    @State private var isOpening = false

    @ScaledMetric(relativeTo: .caption2)
    private var eyebrowSmall: CGFloat = DripTypeFloor.eyebrowSmall

    // Both blocks are HELD, not computed.
    //
    // `TrendsMoodBlocks.block` walks the entire timeline — it has to, because
    // the nightly lanes need a 28-day baseline sitting behind the window's
    // first column. As computed properties these ran twice on every body
    // evaluation, which on a scrolling tab is once per frame.
    @State private var block: TrendsMoodBlock?
    @State private var previous: TrendsMoodBlock?

    /// "What moved" — held for the same reason the blocks are. It walks the
    /// whole timeline for its baselines, so recomputing it per body evaluation
    /// is once per frame on a scrolling tab.
    ///
    /// Always read from TODAY, never from the fortnight the stepper is
    /// parked on: stepping back to look at July must not change what the app
    /// says is happening now.
    @State private var signalsRead: TrendsSignalsRead?

    private var maxBack: Int { TrendsMoodBlocks.maxBlocksBack(dayCount: days.count) }

    private var activeLanes: [TrendsMoodLane] {
        TrendsMoodLane.drawOrder.filter { lanesOn.contains($0) }
    }

    /// The day behind a column. `buckets` and `days` are both day-grain on this
    /// surface, so the index is shared — but bounds-check rather than assume,
    /// because a refresh can land between the two reads.
    private func day(_ block: TrendsMoodBlock, _ i: Int) -> TrendsDay? {
        block.days.indices.contains(i) ? block.days[i] : nil
    }

    /// Cheap stand-in for "the timeline changed". The count alone would miss a
    /// refresh that replaced today's row without adding one.
    private var dataFingerprint: String {
        "\(days.count)|\(days.last?.date ?? "")|\(keySessions.count)"
    }

    var body: some View {
        Group {
            if let block {
                loaded(block)
            } else if days.count < TrendsMoodRead.windowDays {
                Text("Log 14 days and this fills in.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: blocksBack) { _, _ in
            scrubIndex = nil
            highlight = nil
            rebuild()
        }
        .onChange(of: dataFingerprint) { _, _ in rebuild() }
        .sheet(item: $dayWorkouts) { dw in
            HistoryDetailPager(entries: dw.entries, initial: dw.initial, onUpdate: {})
        }
    }

    private func loaded(_ block: TrendsMoodBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The finding first, then the evidence under it. The lanes answer
            // "show me"; this answers "is there anything to look at".
            if let signalsRead {
                TrendsSignalsReadView(read: signalsRead) { lane in
                    withAnimation(.easeInOut(duration: 0.16)) { _ = lanesOn.insert(lane) }
                }
                .padding(.bottom, 22)
            }
            stepper(block)
            headline(block)
            said(block)
            chips
            chart(block)
            selectionRow(block)
            counted(block)
        }
    }

    private func rebuild() {
        block = TrendsMoodBlocks.block(days: days, keySessions: keySessions, blocksBack: blocksBack)
        previous = TrendsMoodBlocks.block(days: days, keySessions: keySessions, blocksBack: blocksBack + 1)
        signalsRead = TrendsSignalsRead.read(days: days)
    }

    // MARK: The window

    private func stepper(_ block: TrendsMoodBlock) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.rangeLabel)
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Text(blocksBack == 0
                     ? "LAST 14 DAYS"
                     : "\(blocksBack * TrendsMoodRead.windowDays)–\(blocksBack * TrendsMoodRead.windowDays + TrendsMoodRead.windowDays) DAYS AGO")
                    .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                stepButton("chevron.left", label: "Previous 14 days", enabled: blocksBack < maxBack) {
                    blocksBack += 1
                }
                stepButton("chevron.right", label: "Next 14 days", enabled: blocksBack > 0) {
                    blocksBack = max(0, blocksBack - 1)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().overlay(Color.drip.divider) }
        .overlay(alignment: .bottom) { Divider().overlay(Color.drip.divider) }
    }

    private func stepButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Color.drip.textSecondary : Color.drip.textTertiary.opacity(0.35))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: The headline

    private func headline(_ block: TrendsMoodBlock) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(block.lowDays)")
                    .font(.dripStat(46))
                    .foregroundStyle(block.lowDays > 0 ? Color.drip.coral : Color.drip.textPrimary)
                Text("of \(block.dayCount) days")
                    .font(.dripDisplay(21))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer(minLength: 0)
            }

            Text(headlineLabel(block))
                .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.3)
                .foregroundStyle(block.isThin ? Color.drip.tired : Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenHeadline(block))
    }

    /// The thin case says how many days it actually heard from. "2 of 14"
    /// understates badly when only three of the fourteen were logged.
    private func headlineLabel(_ block: TrendsMoodBlock) -> String {
        let base = "STRUGGLING OR WORSE".uppercased()
        guard block.isThin else { return base }
        return base + " · ONLY \(block.loggedDays) OF \(block.dayCount) LOGGED"
    }

    private var move: TrendsMoodRead.Move? {
        guard let block, let previous else { return nil }
        return .of(now: block.lowDays, then: previous.lowDays)
    }

    private func spokenHeadline(_ block: TrendsMoodBlock) -> String {
        var line = "\(block.lowDays) of the last \(block.dayCount) days struggling or worse"
        if block.isThin { line += ", from only \(block.loggedDays) logged days" }
        if let previous, let move {
            switch move {
            case .worse: line += ". Up from \(previous.lowDays) in the 14 days before."
            case .better: line += ". Down from \(previous.lowDays) in the 14 days before."
            case .flat: line += ". Against \(previous.lowDays) in the 14 days before."
            }
        }
        return line
    }

    private func said(_ block: TrendsMoodBlock) -> some View {
        Text(sentence(block))
            .font(.dripBody(13.5))
            .foregroundStyle(Color.drip.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.drip.coral).frame(width: 2)
            }
            .padding(.top, 18)
    }

    /// Clustering is what a count still can't show, so the longest run is said
    /// out loud. Four scattered days and four in a row are not the same
    /// fortnight.
    private func sentence(_ block: TrendsMoodBlock) -> String {
        var line = block.longestLowRun >= 2
            ? "Longest run of low days: \(block.longestLowRun)."
            : (block.lowDays > 0 ? "No low days back to back." : "No struggling or injured days.")
        if block.niggleDays > 0 {
            let area = block.topNiggleArea.map { " — mostly \($0)" } ?? ""
            line += " Niggles on \(block.niggleDays) \(block.niggleDays == 1 ? "day" : "days")\(area)."
        }
        return line
    }

    // MARK: Lane toggles

    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chipRows.enumerated()), id: \.offset) { row in
                HStack(spacing: 6) {
                    ForEach(row.element) { lane in chip(lane) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 18)
    }

    /// A nightly lane is offered when the athlete has that series AT ALL,
    /// anywhere in the timeline — a stable property of the athlete, not of the
    /// fortnight on screen, so the chip row does not reshuffle underneath the
    /// reader as they step back through blocks. Whether a given fortnight can
    /// actually place those nights against a baseline is the lane's own
    /// business, and it says so in place.
    ///
    /// This is also how HRV stays off the screen until it exists. The Apple
    /// Health path has supplied resting HR and sleep since 2026-08-06 and zero
    /// HRV (iOS never reports a denied READ scope — the query just returns an
    /// empty array), so an HRV chip today would offer a lane that can only ever
    /// draw nothing. It appears on its own the first night a reading lands.
    private var offeredLanes: [TrendsMoodLane] {
        TrendsMoodLane.drawOrder.filter { lane in
            switch lane {
            case .sleep: days.contains { $0.sleepTotalMin != nil }
            case .restingHR: days.contains { $0.restingHr != nil }
            case .hrv: days.contains { $0.hrvRmssd != nil }
            default: true
            }
        }
    }

    private var chipRows: [[TrendsMoodLane]] {
        let all = offeredLanes
        return stride(from: 0, to: all.count, by: 3).map { Array(all[$0..<min($0 + 3, all.count)]) }
    }

    private func chip(_ lane: TrendsMoodLane) -> some View {
        let isOn = lanesOn.contains(lane)
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                // Never leave the chart with nothing in it.
                if isOn { if lanesOn.count > 1 { lanesOn.remove(lane) } } else { lanesOn.insert(lane) }
            }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isOn ? lane.chipColour : Color.drip.divider)
                    .frame(width: 8, height: 8)
                Text(lane.chipLabel.uppercased())
                    .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .foregroundStyle(isOn ? Color.drip.background : Color.drip.textTertiary)
            .background(isOn ? Color.drip.textPrimary : Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isOn ? Color.clear : Color.drip.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lane.chipLabel)
        .accessibilityValue(isOn ? "shown" : "hidden")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: The chart

    private func chart(_ block: TrendsMoodBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(readout(block))
                .font(.dripEyebrow(eyebrowSmall - 1)).tracking(0.4)
                .foregroundStyle(Color.drip.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            TrendsMoodLanes(
                block: block,
                lanes: activeLanes,
                scrubIndex: $scrubIndex,
                highlight: highlight
            )
        }
        .padding(12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .padding(.top, 12)
    }

    private func readout(_ block: TrendsMoodBlock) -> String {
        if let i = scrubIndex, block.buckets.indices.contains(i) {
            return TrendsMoodLanes.spoken(block.buckets[i], day: day(block, i))
        }
        if let highlight {
            let word = highlight == "nolog" ? "days with no log" : highlight
            return "Showing \(word). Tap the row again to clear."
        }
        return "Tap or drag a day to read it. Tap a row at the foot to pick out one kind of day."
    }

    /// Opening a day is a SEPARATE tap from selecting it — see the note at the
    /// top of this file. The row names the day it will open, so nothing is
    /// presented that wasn't asked for.
    @ViewBuilder
    private func selectionRow(_ block: TrendsMoodBlock) -> some View {
        if let i = scrubIndex, block.buckets.indices.contains(i) {
            let bucket = block.buckets[i]
            Button {
                openDay(bucket.startISO)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bucket.label.uppercased())
                            .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.2)
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(TrendsMoodLanes.spoken(bucket, day: day(block, i)))
                            .font(.dripBody(13.5))
                            .foregroundStyle(Color.drip.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if isOpening {
                        ProgressView().controlSize(.small)
                    } else if bucket.miles > 0 {
                        Text("OPEN ↗")
                            .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.2)
                            .foregroundStyle(Color.drip.coral)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(bucket.miles <= 0 || isOpening)
            .padding(.top, 10)
            .accessibilityLabel(TrendsMoodLanes.spoken(bucket, day: day(block, i)))
            .accessibilityHint(bucket.miles > 0 ? "Opens this day" : "Rest day, nothing to open")
        }
    }

    private func openDay(_ iso: String) {
        guard !isOpening else { return }
        isOpening = true
        Task { @MainActor in
            let resolved = await service.resolveDay(dayISO: iso)
            isOpening = false
            dayWorkouts = resolved
        }
    }

    // MARK: Mood by day

    /// No weights, no arithmetic to explain — the bar IS the list, and the list
    /// is the days. Tapping a row points at those days in the chart above.
    private func counted(_ block: TrendsMoodBlock) -> some View {
        let counts = block.counts
        let unlogged = block.dayCount - block.loggedDays
        return VStack(alignment: .leading, spacing: 0) {
            Text("MOOD BY DAY")
                .font(.dripEyebrow(eyebrowSmall - 1)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.bottom, 10)

            ForEach(TrendsMoodRead.vocabulary, id: \.self) { label in
                countRow(
                    label,
                    key: label,
                    count: counts[label] ?? 0,
                    of: block.dayCount,
                    colour: TrendsMoodColor.color(label)
                )
            }
            countRow("No log", key: "nolog", count: unlogged, of: block.dayCount,
                     colour: Color.drip.paperDeep)

            Text("Each day counted once, as you logged it. No averages, no score. Low days are struggling or injured. Tired is not counted as a low day — a hard session should leave you tired.")
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 14)
        }
        .padding(.top, 22)
        .overlay(alignment: .top) { Divider().overlay(Color.drip.divider) }
    }

    private func countRow(
        _ label: String,
        key: String,
        count: Int,
        of total: Int,
        colour: Color
    ) -> some View {
        let isOn = highlight == key
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                highlight = isOn ? nil : key
                scrubIndex = nil
            }
        } label: {
            HStack(spacing: 9) {
                Text(label.uppercased())
                    .font(.dripEyebrow(eyebrowSmall - 1)).tracking(0.8)
                    .foregroundStyle(isOn ? Color.drip.textPrimary : Color.drip.textSecondary)
                    .frame(width: 74, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.drip.paperDeep.opacity(0.6))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colour)
                            .frame(width: total > 0 && count > 0
                                   ? max(3, geo.size.width * CGFloat(count) / CGFloat(total))
                                   : 0)
                    }
                }
                .frame(height: 11)

                Text(count > 0 ? "\(count)d" : "—")
                    .font(.dripStat(10))
                    .foregroundStyle(count > 0 ? Color.drip.textPrimary : Color.drip.textTertiary)
                    .frame(width: 30, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(isOn ? Color.drip.paperDeep.opacity(0.55) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityLabel("\(label), \(count) days")
        .accessibilityValue(isOn ? "picked out" : "")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
