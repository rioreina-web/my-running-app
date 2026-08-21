//
//  TrendsDetailViews.swift
//  RunningLog
//
//  The four Trends drill-down screens, pushed from the overview tracks in
//  TrendsTabView. Each is a full detail screen with a chart built for that
//  dimension (design: trends-drilldowns-prototype.html):
//
//    • VolumeDetailView      bars + 4-wk average + acute:chronic band
//    • KeySessionsDetailView pace progression + reuses WorkoutsAndRepsSection
//                            (session list → WorkoutRepChart rep splits)
//    • MoodDetailView        per-week mood ribbon + distribution
//    • NigglesDetailView     recurrence swimlanes + verbatim quotes
//
//  All four are driven by the already-loaded `[TrendsWeek]` (no new fetches),
//  except KeySessions, which reuses the self-contained WorkoutsAndRepsSection
//  for the real rep-level data. Charts hand-drawn with Canvas to match
//  UnifiedTrainingChart. Post Run Drip.
//
//  Follow-ups noted inline: intensity-weighted ACWR from athlete_state, a
//  daily mood ribbon, and severity-encoded niggle markers all want richer
//  data than the weekly timeline carries today.
//

import SwiftUI

// MARK: - Shared bits

/// Editorial detail header (eyebrow + display title).
private struct DetailHead: View {
    let eyebrow: String
    let title: String
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.dripEyebrow(11)).tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                if let tag {
                    Text(tag.uppercased())
                        .font(.dripEyebrow(9)).tracking(0.8)
                        .foregroundStyle(Color.drip.tired)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.drip.tired.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            Text(title)
                .font(.dripDisplay(26))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrackEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.dripEyebrow(10)).tracking(1.0)
            .foregroundStyle(Color.drip.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Draw a small mono label into a Canvas context.
private func canvasLabel(
    _ ctx: GraphicsContext, _ s: String, at p: CGPoint,
    anchor: UnitPoint = .center, size: CGFloat = 8.5,
    color: Color = Color.drip.textTertiary
) {
    ctx.draw(
        Text(s).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundColor(color),
        at: p, anchor: anchor
    )
}

private func paceString(_ sec: Int) -> String { "\(sec / 60):\(String(format: "%02d", sec % 60))" }

/// Days-from-civil for "YYYY-MM-DD" (Hinnant). Pure integer math, no timezone —
/// matches the UTC day the backend emits. Only relative differences are used,
/// so the constant offset is irrelevant.
private func civilDay(_ iso: String) -> Int {
    let parts = iso.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return 0 }
    let yy = (m <= 2) ? y - 1 : y
    let era = (yy >= 0 ? yy : yy - 399) / 400
    let yoe = yy - era * 400
    let doy = (153 * ((m > 2 ? m - 3 : m + 9)) + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe
}

private var detailBackground: some View { Color.drip.background.ignoresSafeArea() }

// MARK: - Volume

struct VolumeDetailView: View {
    let weeks: [TrendsWeek]
    var flagged: [TrendsFlaggedRun] = []
    var trimmed: [TrendsFlaggedRun] = []
    var onSetExcluded: (String, Bool) -> Void = { _, _ in }

    /// Canonical intensity-weighted ACWR from athlete_state (builder B) — the
    /// same number shown elsewhere in the app. When nil (state not built yet)
    /// the view falls back to its miles-based ratio. §1 drift fix: this view
    /// used to always recompute its own miles-based ACWR, so the same athlete
    /// could see two different ACWR values in one session.
    var canonicalAcwr: Double? = nil

    /// When true, render the content bare (no ScrollView / nav chrome) so it can
    /// expand INLINE inside the Trends tab. False = the standalone pushed screen.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            detailContent
        } else {
            ScrollView { detailContent.padding(20) }
                .background(detailBackground)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Trimmed 2026-07-27 (Rio) to the parts the overlap above doesn't already
    /// show. Three things came out:
    ///
    ///   • `DetailHead` "The build." — a second headline for what section 01
    ///     already names.
    ///   • `VolumeChart` — weekly bars with the 4-week average. The overlap's
    ///     volume track is the same chart from the same `[TrendsWeek]`, so the
    ///     section was stacking one on top of the other.
    ///   • `flagBanner` "DATA CHECK · LOOKS OFF" — a maintenance chore with a
    ///     Restore button. It belongs on the workout in Log, where it can be
    ///     fixed in context; at the top of an analytics surface it only makes
    ///     the numbers below it look untrustworthy before they're read.
    ///
    /// What's left is what the overlap can't say: the three totals, the
    /// acute:chronic band, and the read. `flagBanner`, `flagRow` and the
    /// `flagged`/`trimmed`/`onSetExcluded` inputs stay wired so restoring the
    /// banner is a one-line change if it turns out to be needed elsewhere.
    @ViewBuilder private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    DripStatTile(
                        label: "This wk",
                        value: thisWeekMiles,
                        unit: "mpw",
                        delta: thisWeekCaption,
                        deltaTone: .neutral
                    )
                    DripStatTile(label: "4-wk avg", value: fourWeekAvg, unit: "mpw")
                    DripStatTile(label: "Peak", value: peakMiles, unit: "mpw")
                }

                TrackEyebrow(text: "Load balance · acute : chronic").padding(.top, 18).padding(.bottom, 6)
                ACWRBar(value: acwr).frame(height: 48)
                // `acwrNarrative` used to print here — "Acute:chronic is 0.92 —
                // inside the 0.8–1.3 band. A steady, controlled ramp." The bar
                // already draws the value, the band and where the value sits in
                // it. The sentence was the chart, retyped. (Rio, 2026-08-03.)
            }
    }

    private var flagBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATA CHECK · LOOKS OFF")
                .font(.dripEyebrow(10)).tracking(1.0)
                .foregroundStyle(Color.drip.tired)

            if !flagged.isEmpty {
                Text("\(flagged.count) \(flagged.count == 1 ? "run" : "runs") didn't add up — kept out of your totals. Trim to drop it, Keep to count it.")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(flagged) { f in flagRow(f, isTrimmed: false) }
            }

            if !trimmed.isEmpty {
                Text("TRIMMED")
                    .font(.dripEyebrow(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 2)
                ForEach(trimmed) { f in flagRow(f, isTrimmed: true) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.tired.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func flagRow(_ f: TrendsFlaggedRun, isTrimmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(f.date) · \(Int(f.miles)) mi\(f.pace.map { " · \($0)/mi" } ?? "")")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textPrimary)
                Text(f.reason)
                    .font(.dripBody(11)).foregroundStyle(Color.drip.textTertiary)
            }
            Spacer(minLength: 8)
            if isTrimmed {
                actionChip("Restore") { onSetExcluded(f.id, false) }
            } else {
                actionChip("Keep") { onSetExcluded(f.id, false) }
                actionChip("Trim") { onSetExcluded(f.id, true) }
            }
        }
        .padding(.vertical, 7)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private func actionChip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dripEyebrow(10)).tracking(0.6)
                .foregroundStyle(Color.drip.coral)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .overlay(Capsule().stroke(Color.drip.coral.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func legendSwatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(label).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textSecondary)
        }
    }

    // Derived stats (miles-based; intensity-weighted ACWR from athlete_state
    // is the follow-up — see trends-tab-data-wiring.md §10).
    private var nonEmpty: [TrendsWeek] { weeks.filter { $0.miles > 0 } }

    // The last week in the window is always the current, in-progress week
    // (the data service builds the window "ending this Monday"). We read it
    // directly from `weeks.last` — not `nonEmpty.last` — so that a week with
    // zero miles logged so far still reads as *this* week at 0, rather than
    // silently falling back to last week's completed total.
    private var currentWeek: TrendsWeek? { weeks.last }

    /// Completed weeks only — everything except the current in-progress one.
    private var completedWeeks: [TrendsWeek] { weeks.dropLast() }

    /// Monday = 1 … Sunday = 7. How far into the current week we are.
    private var daysIntoWeek: Int {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        // `weekday` is 1=Sun…7=Sat; ISO ordinal maps Mon→1 … Sun→7.
        let weekday = cal.component(.weekday, from: Date())
        return ((weekday + 5) % 7) + 1
    }

    private var isWeekComplete: Bool { daysIntoWeek >= 7 }

    /// Actual miles logged so far this week — the honest headline number.
    private var thisWeekMiles: String { String(Int(currentWeek?.miles ?? 0)) }

    /// A projected full-week total, paced from the miles logged so far. Only
    /// shown mid-week; frantically precise projections aren't the point, so it
    /// rounds to the nearest mile and is labelled "~" (an estimate, not a
    /// promise). Follow-up once daily current-week streams land: pace the
    /// projection against remaining *planned* days instead of a flat per-day
    /// rate, which under-counts before the weekend long run.
    private var projectedWeekMiles: Int {
        let soFar = currentWeek?.miles ?? 0
        guard daysIntoWeek > 0 else { return Int(soFar) }
        return Int((soFar / Double(daysIntoWeek) * 7).rounded())
    }

    /// Sub-line under the "This wk" number. Mid-week it flags how far in we are
    /// and the on-pace estimate so the raw number isn't misread as "behind";
    /// once the week is done it just confirms the total is final.
    private var thisWeekCaption: String {
        isWeekComplete
            ? "week complete"
            : "day \(daysIntoWeek)/7 · on pace ~\(projectedWeekMiles)"
    }

    /// Average of the last 4 *completed* weeks. Excludes the current
    /// in-progress week, whose partial total would otherwise drag the
    /// baseline down and make every mid-week glance look like a shortfall.
    private var fourWeekAvg: String {
        let last4 = completedWeeks.filter { $0.miles > 0 }.suffix(4)
        guard !last4.isEmpty else { return "0" }
        return String(Int(last4.map(\.miles).reduce(0, +) / Double(last4.count)))
    }
    private var peakMiles: String { String(Int(weeks.map(\.miles).max() ?? 0)) }

    private var acwr: Double {
        // Prefer the canonical intensity-weighted ratio from athlete_state so
        // this drilldown matches the ACWR shown elsewhere. The miles-based
        // computation below is the fallback for when state isn't built yet.
        if let a = canonicalAcwr { return a }
        // Chronic load = the up-to-4 completed weeks before this one.
        let chronicSlice = completedWeeks.filter { $0.miles > 0 }.suffix(4)
        guard !chronicSlice.isEmpty else { return 1.0 }
        let chronic = chronicSlice.map(\.miles).reduce(0, +) / Double(chronicSlice.count)
        // Acute load = this week. Mid-week we use the on-pace projection, not
        // the partial total, so the ratio reflects where the week is heading
        // rather than reading as a false "spike down" every Monday–Wednesday.
        let acute = isWeekComplete
            ? (currentWeek?.miles ?? 0)
            : Double(projectedWeekMiles)
        return chronic > 0 ? acute / chronic : 1.0
    }

}

private struct VolumeChart: View {
    let weeks: [TrendsWeek]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard !weeks.isEmpty else { return }
            let n = weeks.count
            let padL: CGFloat = 4, padR: CGFloat = 4
            let base = h - 18, top: CGFloat = 14
            let maxMiles = max(weeks.map(\.miles).max() ?? 1, 1)
            let slot = (w - padL - padR) / CGFloat(n)
            let bw = min(slot * 0.6, 16)
            func x(_ i: Int) -> CGFloat { padL + slot * (CGFloat(i) + 0.5) }
            func yFor(_ m: Double) -> CGFloat { base - CGFloat(m / maxMiles) * (base - top) }

            // baseline
            var bl = Path(); bl.move(to: CGPoint(x: padL, y: base)); bl.addLine(to: CGPoint(x: w - padR, y: base))
            ctx.stroke(bl, with: .color(Color.drip.divider), lineWidth: 1)
            canvasLabel(ctx, "\(Int(maxMiles)) mpw", at: CGPoint(x: w - padR, y: top - 4), anchor: .trailing)

            // bars
            for (i, wk) in weeks.enumerated() {
                let cx = x(i)
                let totH = CGFloat(wk.miles / maxMiles) * (base - top)
                let qH = CGFloat(wk.qualityMiles / maxMiles) * (base - top)
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: base - totH, width: bw, height: max(totH - qH, 0))), with: .color(Color.drip.paperDeep))
                ctx.fill(Path(CGRect(x: cx - bw / 2, y: base - totH, width: bw, height: max(qH, 0))), with: .color(Color.drip.textSecondary))
            }

            // 4-wk rolling average
            var line = Path(); var started = false
            for i in 0..<n {
                let s = max(0, i - 3)
                let seg = weeks[s...i].map(\.miles)
                let avg = seg.reduce(0, +) / Double(seg.count)
                let pt = CGPoint(x: x(i), y: yFor(avg))
                if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
            }
            ctx.stroke(line, with: .color(Color.drip.textPrimary.opacity(0.6)), lineWidth: 1.6)

            // first/last month ticks
            if let f = weeks.first { canvasLabel(ctx, f.month.uppercased(), at: CGPoint(x: x(0), y: h - 4), anchor: .leading) }
            if let l = weeks.last { canvasLabel(ctx, l.month.uppercased(), at: CGPoint(x: x(n - 1), y: h - 4), anchor: .trailing) }
        }
    }
}

/// Acute:chronic marker on a 0.6–1.6 scale with the 0.8–1.3 sweet-spot band.
private struct ACWRBar: View {
    let value: Double
    private let lo = 0.6, hi = 1.6, sweetLo = 0.8, sweetHi = 1.3
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let trackY = h * 0.4, trackH: CGFloat = 10
            func fx(_ v: Double) -> CGFloat { CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * w }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: trackY, width: w, height: trackH), cornerRadius: 3), with: .color(Color.drip.paperDeep))
            // Sweet-spot band is a neutral gray, not mood-green (green stays mood-only).
            ctx.fill(Path(CGRect(x: fx(sweetLo), y: trackY, width: fx(sweetHi) - fx(sweetLo), height: trackH)), with: .color(Color.drip.textTertiary.opacity(0.18)))
            let mx = fx(value)
            var m = Path(); m.move(to: CGPoint(x: mx, y: trackY - 6)); m.addLine(to: CGPoint(x: mx, y: trackY + trackH + 6))
            ctx.stroke(m, with: .color(Color.drip.coral), lineWidth: 2)
            canvasLabel(ctx, String(format: "%.2f", value), at: CGPoint(x: mx, y: trackY - 10), anchor: .center, size: 9, color: Color.drip.coral)
            canvasLabel(ctx, "0.8", at: CGPoint(x: fx(sweetLo), y: h - 3), anchor: .center)
            canvasLabel(ctx, "1.3 SWEET SPOT", at: CGPoint(x: fx(sweetHi), y: h - 3), anchor: .leading)
        }
    }
}

// MARK: - Key sessions (Section A: same effort, faster?)

/// The honest pace chart. One dot per quality session = its **work-bout pace**
/// (rest excluded), grouped by the athlete's own pace zone, heat-adjusted when
/// conditions weren't ideal (hollow dots, raw pace on tap). The editorial
/// headline is *earned* — it renders only with enough same-zone sessions and a
/// meaningful improvement. Spec: outputs/key-sessions-chart-redesign-2026-07-02.md.
struct KeySessionsDetailView: View {
    let sessions: [KeySession]
    var volume: [QualityVolumeWeek] = []

    @State private var selectedZone: String?
    @State private var selectedID: String?

    /// When true, render the content bare (no ScrollView / nav chrome) so it can
    /// expand INLINE inside the Trends tab. False = the standalone pushed screen.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            detailContent
        } else {
            ScrollView { detailContent.padding(20) }
                .background(detailBackground)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                if sessions.isEmpty {
                    // Degradation floor: nothing at the sharp end at all.
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "KEY SESSIONS",
                        title: "No workouts with reps in range. The first interval day, MP miles, or LT session lands here — reps read one by one, rest excluded, grouped by zone."
                    )
                    .padding(.top, 8)
                    WorkoutsAndRepsSection().padding(.top, 24)
                } else {
                    // Cut 2026-07-27 (Rio): the three zone-filtered sections
                    // that used to sit here are out of Trends.
                    //
                    //   A · "SAME EFFORT, FASTER?"  zone chips + pace line
                    //   B · "THE WORK BEHIND IT"    stacked quality minutes
                    //   C · "SAME PACE, CHEAPER"    average work-HR line
                    //
                    // Each drew a trend line from four or five points, so a
                    // flat result read as "nothing happened" over a block that
                    // plainly wasn't flat — and the five-stop stack in B isn't
                    // legible at phone width. The honest version of this
                    // question lives in the head-to-head comparison, which
                    // sets two real sessions against each other instead of
                    // fitting a line through too few.
                    //
                    // `SectionAChart`, `SectionBView`, `SectionCView`,
                    // `InvitationChart` and their helpers below are now
                    // unreferenced — left in place for one pass rather than
                    // deleted, so this is trivially reversible. Sweep them
                    // when the structure settles.
                    WorkoutsAndRepsSection()
                }
            }
    }

    /// Editorial hairline between stacked sections.
    private var sectionRule: some View {
        Rectangle().fill(Color.drip.divider).frame(height: 1).padding(.vertical, 20)
    }

    // MARK: header (eyebrow + gated headline + cited narrative)

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("KEY SESSIONS · SAME EFFORT, FASTER?")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            Text(headline)
                .font(.dripDisplay(26))
                .foregroundStyle(Color.drip.textPrimary)
            Text(narrative)
                .font(.dripBody(14)).lineSpacing(3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(zonesInRange, id: \.self) { z in
                let sel = z == activeZone
                Button {
                    selectedZone = z
                    selectedID = nil
                } label: {
                    Text(KeyZone.label(z))
                        .font(.dripEyebrow(11)).tracking(1.0)
                        .foregroundStyle(sel ? Color.drip.background : Color.drip.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            Capsule().fill(sel ? Color.drip.textPrimary : Color.drip.cardBackground)
                        )
                        .overlay(
                            Capsule().stroke(Color.drip.divider, lineWidth: sel ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func tapReadout(_ s: KeySession) -> some View {
        let raw = paceString(s.workPaceSec)
        let detail: String
        if s.isHeatAdjusted, let adj = s.workPaceAdjSec {
            let cat = (s.heatCategory ?? "").replacingOccurrences(of: "_", with: " ")
            detail = "\(raw) raw · \(paceString(adj)) adj\(cat.isEmpty ? "" : " · \(cat)")"
        } else {
            detail = "\(raw)\(s.structure.map { " · \($0)" } ?? "")"
        }
        return Text("\(s.dateLabel.uppercased()) · \(detail)")
            .font(.dripEyebrow(11)).tracking(0.3)
            .foregroundStyle(Color.drip.background)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.drip.textPrimary))
    }

    // MARK: derived

    /// Work zones with ≥ 2 sessions in range, ordered fast → slow.
    private var zonesInRange: [String] {
        let counts = Dictionary(grouping: sessions, by: { $0.zone.lowercased() })
        return counts.filter { $0.value.count >= 2 }.keys
            .sorted { KeyZone.rank($0) < KeyZone.rank($1) }
    }

    /// Default = the zone with the most sessions (tie → faster zone).
    private var defaultZone: String? {
        zonesInRange.max { a, b in
            let ca = sessions.filter { $0.zone.lowercased() == a }.count
            let cb = sessions.filter { $0.zone.lowercased() == b }.count
            if ca != cb { return ca < cb }
            return KeyZone.rank(a) > KeyZone.rank(b)
        }
    }

    private var activeZone: String? {
        if let z = selectedZone, zonesInRange.contains(z) { return z }
        return defaultZone
    }

    /// Selected zone's sessions, date-sorted.
    private var zoneSessions: [KeySession] {
        guard let z = activeZone else { return [] }
        return sessions.filter { $0.zone.lowercased() == z }.sorted { $0.date < $1.date }
    }

    private var selectedSession: KeySession? {
        guard let id = selectedID else { return nil }
        return zoneSessions.first { $0.id == id }
    }

    private var hasAdjusted: Bool { zoneSessions.contains { $0.isHeatAdjusted } }

    /// Improvement (sec/mi) = median of first 2 effective paces minus median of
    /// last 2. Positive = faster over the block.
    private var improvementSecPerMi: Double {
        let paces = zoneSessions.map { Double($0.effectivePaceSec) }
        guard paces.count >= 4 else { return 0 }
        let first2 = Array(paces.prefix(2)), last2 = Array(paces.suffix(2))
        let med = { (xs: [Double]) in xs.reduce(0, +) / Double(xs.count) }
        return med(first2) - med(last2)
    }

    /// "The engine is growing." is earned, not asserted: ≥ 4 same-zone sessions
    /// AND a ≥ 5 sec/mi heat-adjusted improvement (proxy for data_depth ≥ 2).
    private var earned: Bool { zoneSessions.count >= 4 && improvementSecPerMi >= 5 }

    private var headline: String {
        guard let z = activeZone else { return "Key sessions." }
        return earned ? "The engine is growing." : "\(KeyZone.label(z)) pace."
    }

    private var narrative: String {
        guard let z = activeZone, let first = zoneSessions.first, let last = zoneSessions.last else {
            return "Rep pace, rest excluded."
        }
        let label = KeyZone.label(z)
        let adjNote = hasAdjusted ? " Rest breaks excluded; hot days normalized." : " Rest breaks excluded."
        if earned {
            return "\(label) reps at \(paceString(last.effectivePaceSec)) vs. \(paceString(first.effectivePaceSec)) earlier in the block — at the same effort.\(adjNote)"
        }
        if zoneSessions.count < 4 {
            return "\(zoneSessions.count) \(label) sessions in range at \(paceString(last.effectivePaceSec)). A few more and the same-effort trend fills in.\(adjNote)"
        }
        // Enough data, but no meaningful drop — stay descriptive, don't claim.
        return "\(label) work holding around \(paceString(last.effectivePaceSec)).\(adjNote)"
    }

    // MARK: low data (sessions exist, no zone has a pair yet)

    private var newestSession: KeySession? {
        sessions.max { $0.date < $1.date }
    }

    /// Editorial header for the low-data state. The headline is descriptive
    /// (never a fitness claim — data_depth gating), and the narrative cites
    /// real numbers per the pull-quote rule.
    private var lowDataHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("KEY SESSIONS · SAME EFFORT, FASTER?")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.coral)
            Text("First marks on the page.")
                .font(.dripDisplay(26))
                .foregroundStyle(Color.drip.textPrimary)
            Text(lowDataNarrative)
                .font(.dripBody(14)).lineSpacing(3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "3 quality sessions in range — 5K at 5:07, 10K at 5:14, HMP at 5:17.
    /// A pace only trends against its own kind: two sessions in the same
    /// zone start the line."
    private var lowDataNarrative: String {
        let byZone = Dictionary(grouping: sessions) { $0.zone.lowercased() }
        let ordered = byZone.keys.sorted { KeyZone.rank($0) < KeyZone.rank($1) }
        let cites = ordered.prefix(3).compactMap { z -> String? in
            guard let s = byZone[z]?.max(by: { $0.date < $1.date }) else { return nil }
            return "\(KeyZone.label(z)) at \(paceString(s.effectivePaceSec))"
        }.joined(separator: ", ")
        let opener = sessions.count == 1
            ? "1 quality session in range — \(cites)."
            : "\(sessions.count) quality sessions in range — \(cites)."
        return opener + " A pace only trends against its own kind: two sessions in the same zone start the line."
    }

    /// Static zone → count chips ("5K · 1"). Ink only; the invitation chart
    /// below holds this cluster's single coral element.
    private var zoneTally: some View {
        let byZone = Dictionary(grouping: sessions) { $0.zone.lowercased() }
        let ordered = byZone.keys.sorted { KeyZone.rank($0) < KeyZone.rank($1) }
        return HStack(spacing: 8) {
            ForEach(ordered, id: \.self) { z in
                Text("\(KeyZone.label(z)) · \(byZone[z]?.count ?? 0)")
                    .font(.dripEyebrow(11)).tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color.drip.cardBackground))
                    .overlay(Capsule().stroke(Color.drip.divider, lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
    }
}

/// The low-data invitation: the newest quality session as a real dot, and an
/// explicitly-dashed open slot where its same-zone pair would land. The slot
/// is a placeholder, never a faked measurement — dashed tertiary stroke,
/// labeled for the zone whose line it would start.
private struct InvitationChart: View {
    let session: KeySession

    var body: some View {
        Canvas { ctx, size in
            let baseY = size.height - 26
            var base = Path()
            base.move(to: CGPoint(x: 8, y: baseY))
            base.addLine(to: CGPoint(x: size.width - 8, y: baseY))
            ctx.stroke(base, with: .color(Color.drip.divider), lineWidth: 1)

            let y = size.height * 0.38
            let dotX = size.width * 0.28
            let slotX = size.width * 0.74
            let r: CGFloat = 4.6

            // The real session — in its zone's pace color (matches Section A/B).
            ctx.fill(
                Path(ellipseIn: CGRect(x: dotX - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(SectionBView.color(session.zone, active: nil))
            )
            canvasLabel(ctx, paceString(session.effectivePaceSec),
                        at: CGPoint(x: dotX, y: y - 13), anchor: .center, color: Color.drip.textPrimary)
            canvasLabel(ctx, session.dateLabel.uppercased(),
                        at: CGPoint(x: dotX, y: size.height - 8), anchor: .center)

            // Dashed path to the open slot.
            var link = Path()
            link.move(to: CGPoint(x: dotX + 10, y: y))
            link.addLine(to: CGPoint(x: slotX - 10, y: y))
            ctx.stroke(link, with: .color(Color.drip.textTertiary),
                       style: StrokeStyle(lineWidth: 1.4, dash: [2, 5]))

            // The slot itself — clearly not data.
            ctx.stroke(
                Path(ellipseIn: CGRect(x: slotX - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(Color.drip.textTertiary),
                style: StrokeStyle(lineWidth: 1.4, dash: [2, 3])
            )
            canvasLabel(ctx, "NEXT \(KeyZone.label(session.zone).uppercased()) DAY",
                        at: CGPoint(x: slotX, y: size.height - 8), anchor: .center)
        }
    }
}

/// Section A scatter: work-bout pace (y, faster = top) over date (x), one dot
/// per session. Filled = ideal conditions; hollow = heat-adjusted. Dots are
/// tappable via an invisible overlay that shares the chart's layout math.
private struct SectionAChart: View {
    let sessions: [KeySession]
    @Binding var selectedID: String?

    private let padL: CGFloat = 8, padR: CGFloat = 8, top: CGFloat = 26

    /// The PaceSpectrum color for this chart's (single) zone — the same mapping
    /// the Section-B bars use, so the pace line and the work bars agree on color
    /// (three-palette rule: pace rides the blue ramp as a ramp, never as a lone alert dot).
    private var zoneColor: Color { SectionBView.color(sessions.first?.zone ?? "", active: nil) }

    var body: some View {
        GeometryReader { geo in
            let pts = layout(in: geo.size)
            ZStack {
                Canvas { ctx, size in draw(ctx, size: size, pts: pts) }
                // Tap targets — one padded hit area per dot.
                ForEach(pts, id: \.session.id) { p in
                    Circle()
                        .fill(Color.clear).contentShape(Circle())
                        .frame(width: 34, height: 34)
                        .position(p.point)
                        .onTapGesture {
                            selectedID = (selectedID == p.session.id) ? nil : p.session.id
                        }
                }
            }
        }
    }

    private struct Plotted { let session: KeySession; let point: CGPoint }

    private func layout(in size: CGSize) -> [Plotted] {
        guard !sessions.isEmpty else { return [] }
        let bot = size.height - 26
        let paces = sessions.map { $0.effectivePaceSec }
        let pMin = CGFloat(paces.min() ?? 0), pMax = CGFloat(paces.max() ?? 1)
        let span = max(pMax - pMin, 1)
        let days = sessions.map { CGFloat(civilDay($0.date)) }
        let dMin = days.min() ?? 0, dMax = days.max() ?? 1
        let dSpan = max(dMax - dMin, 1)
        func y(_ p: Int) -> CGFloat { top + (CGFloat(p) - pMin) / span * (bot - top) } // faster→top
        func x(_ i: Int) -> CGFloat {
            guard sessions.count > 1 else { return size.width / 2 }
            let frac = (days[i] - dMin) / dSpan
            return padL + frac * (size.width - padL - padR)
        }
        return sessions.enumerated().map { i, s in
            Plotted(session: s, point: CGPoint(x: x(i), y: y(s.effectivePaceSec)))
        }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, pts: [Plotted]) {
        guard let first = pts.first, let last = pts.last else { return }
        let bot = size.height - 26

        var baseline = Path()
        baseline.move(to: CGPoint(x: padL, y: bot)); baseline.addLine(to: CGPoint(x: size.width - padR, y: bot))
        ctx.stroke(baseline, with: .color(Color.drip.divider), lineWidth: 1)

        // Connecting line within the (single) zone.
        if pts.count > 1 {
            var line = Path()
            for (i, p) in pts.enumerated() {
                if i == 0 { line.move(to: p.point) } else { line.addLine(to: p.point) }
            }
            ctx.stroke(line, with: .color(zoneColor.opacity(0.45)), lineWidth: 1.6)
        }

        // Dots: filled = ideal, hollow = heat-adjusted. Selected = larger ring.
        for p in pts {
            let r: CGFloat = (p.session.id == selectedID) ? 5.6 : 4.4
            let rect = CGRect(x: p.point.x - r, y: p.point.y - r, width: r * 2, height: r * 2)
            if p.session.isHeatAdjusted {
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.drip.background))
                ctx.stroke(Path(ellipseIn: rect), with: .color(zoneColor), lineWidth: 2)
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(zoneColor))
            }
        }

        // Endpoint pace labels.
        canvasLabel(ctx, paceString(first.session.effectivePaceSec),
                    at: CGPoint(x: first.point.x, y: first.point.y - 12), anchor: .center, color: Color.drip.textSecondary)
        if pts.count > 1 {
            canvasLabel(ctx, paceString(last.session.effectivePaceSec),
                        at: CGPoint(x: last.point.x, y: last.point.y - 12), anchor: .center, size: 9, color: Color.drip.textPrimary)
        }

        // Endpoint date ticks.
        canvasLabel(ctx, first.session.dateLabel.uppercased(), at: CGPoint(x: padL, y: size.height - 6), anchor: .leading)
        if pts.count > 1 {
            canvasLabel(ctx, last.session.dateLabel.uppercased(), at: CGPoint(x: size.width - padR, y: size.height - 6), anchor: .trailing)
        }
    }
}

// MARK: - Key sessions (Section B: the work behind it)

/// Weekly time-at-quality-pace, stacked by work zone. Each zone carries its
/// own PaceSpectrum color — faster zones sit deeper toward navy — so the stack
/// reads in the same "color == pace" language as every other pace surface
/// (three-palette rule: pace rides the blue ramp as a ramp, never as a lone alert dot). When a zone is selected
/// in Section A, the rest dim so focus reads through value, not hue. Answers
/// "am I accumulating work at these paces, or was that one hero session?"
/// Easy/recovery volume is deliberately out — this is the sharp end only.
private struct SectionBView: View {
    let volume: [QualityVolumeWeek]
    let activeZone: String?

    /// Recent weeks, matching the mockup's density.
    private var shown: [QualityVolumeWeek] { Array(volume.suffix(8)) }
    private var hasAny: Bool { shown.contains { $0.total > 0 } }

    /// Work zones that actually appear in the shown weeks, fast → slow. Drives
    /// the legend so it only names zones the athlete has real time in.
    private var zonesPresent: [String] {
        let present = Set(shown.flatMap { wk in wk.zoneSeconds.filter { $0.value > 0 }.keys })
        return KeyZone.order.filter { present.contains($0) }
    }

    /// PaceSpectrum color per work zone (pace == blue; faster == deeper navy).
    /// When a zone is selected in Section A, the others dim to 40% so the
    /// selection reads through value — coral stays out of pace surfaces.
    static func color(_ zone: String, active: String?) -> Color {
        let base: Color
        switch zone.lowercased() {
        case "mile": base = PaceSpectrum.mile
        case "3k":   base = PaceSpectrum.threeK
        case "5k":   base = PaceSpectrum.fiveK
        case "10k":  base = PaceSpectrum.tenK
        case "hmp":  base = PaceSpectrum.hmp
        case "mp":   base = PaceSpectrum.mp
        default:     base = PaceSpectrum.steady
        }
        if let active, zone.lowercased() != active.lowercased() {
            return base.opacity(0.4)
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE WORK BEHIND IT")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Text(narrative)
                .font(.dripBody(14)).lineSpacing(3)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.top, 4)

            if hasAny {
                SectionBChart(weeks: shown, activeZone: activeZone)
                    .frame(height: 150).padding(.top, 10)
                legend.padding(.top, 8)
            } else {
                Text("No quality time logged in these weeks yet. It fills in as you bank sessions at these paces.")
                    .font(.dripBody(13)).foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var narrative: String {
        if let z = activeZone.map(KeyZone.label) {
            return "Minutes at quality paces, by week. \(z) stands out; the rest dim back. One hero session isn't a block — this is the accumulation."
        }
        return "Minutes at quality paces, by week. Faster paces read deeper."
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(zonesPresent, id: \.self) { z in
                swatch(SectionBView.color(z, active: nil), KeyZone.label(z))
            }
            Spacer(minLength: 0)
        }
    }

    private func swatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(label).font(.dripEyebrow(9)).foregroundStyle(Color.drip.textSecondary)
        }
    }
}

private struct SectionBChart: View {
    let weeks: [QualityVolumeWeek]
    let activeZone: String?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard !weeks.isEmpty else { return }
            let base = h - 18, top: CGFloat = 10
            let maxTotal = max(weeks.map(\.total).max() ?? 1, 1)
            let n = weeks.count
            let padL: CGFloat = 6, padR: CGFloat = 6
            let slot = (w - padL - padR) / CGFloat(n)
            let bw = min(slot * 0.62, 20)
            func cx(_ i: Int) -> CGFloat { padL + slot * (CGFloat(i) + 0.5) }

            var bl = Path(); bl.move(to: CGPoint(x: padL, y: base)); bl.addLine(to: CGPoint(x: w - padR, y: base))
            ctx.stroke(bl, with: .color(Color.drip.divider), lineWidth: 1)
            canvasLabel(ctx, "\(maxTotal / 60) min", at: CGPoint(x: w - padR, y: top - 2), anchor: .trailing)

            // Stack slow → fast, bottom → top (reverse of the fast→slow order).
            let stackOrder = Array(KeyZone.order.reversed())
            for (i, wk) in weeks.enumerated() {
                var yCursor = base
                for z in stackOrder {
                    let secs = wk.zoneSeconds[z] ?? 0
                    if secs <= 0 { continue }
                    let barH = CGFloat(secs) / CGFloat(maxTotal) * (base - top)
                    let rect = CGRect(x: cx(i) - bw / 2, y: yCursor - barH, width: bw, height: max(barH - 1, 0.5))
                    ctx.fill(Path(rect), with: .color(SectionBView.color(z, active: activeZone)))
                    yCursor -= barH
                }
            }

            if let f = weeks.first { canvasLabel(ctx, f.dateLabel.uppercased(), at: CGPoint(x: cx(0), y: h - 4), anchor: .leading) }
            if let l = weeks.last, n > 1 { canvasLabel(ctx, l.dateLabel.uppercased(), at: CGPoint(x: cx(n - 1), y: h - 4), anchor: .trailing) }
        }
    }
}

// MARK: - Key sessions (Section C: same pace, cheaper)

/// Effort vs. output for the selected zone: average work HR over time. The
/// honest fitness signal is the drift — the same pace arriving at a lower
/// heart rate. Gated on HR coverage (≥ 3 sessions with lap-level HR); shows
/// the empty-state otherwise. Observation only — never a medical claim.
private struct SectionCView: View {
    let sessions: [KeySession]  // selected zone, date-sorted
    let zoneLabel: String

    private var withHR: [KeySession] { sessions.filter { $0.workHrAvg != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAME PACE, CHEAPER")
                .font(.dripEyebrow(11)).tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)

            if withHR.count >= 3 {
                Text(narrative)
                    .font(.dripBody(14)).lineSpacing(3)
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
                SectionCChart(sessions: withHR).frame(height: 120).padding(.top, 10)
            } else {
                EmptyStateView(
                    variant: .dataPending,
                    eyebrow: "EFFORT VS. OUTPUT",
                    title: "Not enough heart-rate data on these sessions yet. Runs synced with HR will start filling this in."
                )
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var narrative: String {
        guard let first = withHR.first?.workHrAvg, let last = withHR.last?.workHrAvg else { return "" }
        let pace = paceRange
        // Only claim a drop when it's real (> 1 bpm) — otherwise stay descriptive.
        if last < first - 1 {
            let whenPart = withHR.first.map { " in \($0.dateLabel.split(separator: " ").first.map(String.init) ?? $0.dateLabel)" } ?? ""
            return "\(zoneLabel) work around \(pace) now arrives at ~\(last) bpm; it was ~\(first)\(whenPart). Same output, less cost."
        }
        return "\(zoneLabel) work around \(pace) at ~\(last) bpm — effort holding steady."
    }

    private var paceRange: String {
        let ps = withHR.map { $0.effectivePaceSec }
        guard let lo = ps.min(), let hi = ps.max() else { return "" }
        return lo == hi ? paceString(lo) : "\(paceString(lo))–\(paceString(hi))"
    }
}

private struct SectionCChart: View {
    let sessions: [KeySession]  // all carry workHrAvg

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let top: CGFloat = 18, bot = h - 20
            let hrs = sessions.compactMap { $0.workHrAvg }
            guard let hMin = hrs.min(), let hMax = hrs.max() else { return }
            let span = CGFloat(max(hMax - hMin, 1))
            let days = sessions.map { CGFloat(civilDay($0.date)) }
            let dMin = days.min() ?? 0, dMax = days.max() ?? 1
            let dSpan = max(dMax - dMin, 1)
            let padL: CGFloat = 8, padR: CGFloat = 8
            func x(_ i: Int) -> CGFloat { sessions.count > 1 ? padL + (days[i] - dMin) / dSpan * (w - padL - padR) : w / 2 }
            func y(_ hr: Int) -> CGFloat { top + (CGFloat(hr) - CGFloat(hMin)) / span * (bot - top) } // lower HR → top

            var bl = Path(); bl.move(to: CGPoint(x: padL, y: bot)); bl.addLine(to: CGPoint(x: w - padR, y: bot))
            ctx.stroke(bl, with: .color(Color.drip.divider), lineWidth: 1)
            canvasLabel(ctx, "AVG WORK HR", at: CGPoint(x: w - padR, y: top - 8), anchor: .trailing)

            var line = Path(); var started = false
            for (i, s) in sessions.enumerated() {
                guard let hr = s.workHrAvg else { continue }
                let pt = CGPoint(x: x(i), y: y(hr))
                if started { line.addLine(to: pt) } else { line.move(to: pt); started = true }
            }
            ctx.stroke(line, with: .color(Color.drip.textPrimary.opacity(0.25)), lineWidth: 1.2)

            for (i, s) in sessions.enumerated() {
                guard let hr = s.workHrAvg else { continue }
                let r: CGFloat = 4
                ctx.fill(Path(ellipseIn: CGRect(x: x(i) - r, y: y(hr) - r, width: r * 2, height: r * 2)), with: .color(Color.drip.textPrimary))
                canvasLabel(ctx, "\(hr)", at: CGPoint(x: x(i), y: y(hr) - 10), anchor: .center, color: Color.drip.textSecondary)
            }

            if let f = sessions.first { canvasLabel(ctx, f.dateLabel.uppercased(), at: CGPoint(x: padL, y: h - 4), anchor: .leading) }
            if sessions.count > 1, let l = sessions.last { canvasLabel(ctx, l.dateLabel.uppercased(), at: CGPoint(x: w - padR, y: h - 4), anchor: .trailing) }
        }
    }
}

// MARK: - Recovery

/// The load half of the Trends "Recovery" section: how often the hard days
/// land, read off `athlete_state.load_distribution.recovery_read`, with the
/// down-week / body-signal chips underneath. Renders BELOW the recovery-score
/// ledger, which owns the section's number.
///
/// This used to open with three stat tiles, led by "Readiness N/100" off
/// `athlete_state.last_readiness_score` — a second 0–100 on the same screen
/// as today's score, computed by an older server model the ledger replaced
/// (see `TrendsRecoveryDemand.swift`). Two scales, one screen; the tiles
/// also broke their own numbers ("4.2" wrapped mid-digit) whenever all three
/// rendered. One quiet line now, and no second score. (Rio, 2026-08-17.)
///
/// Surface, never prescribe. Hard rule #2 forbids the AI telling the athlete to
/// rest or push, and the niggles rule forbids interpreting body signals — so
/// every line here is descriptive (a hard-session count, a cadence, a
/// count of active mentions), never advice or diagnosis.
struct RecoveryReadView: View {
    var hardSessions28d: Int?
    var avgDaysBetweenHard: Double?
    var downWeek: Bool?
    /// Distinct active/possible body-part mentions from athlete_state — a count
    /// only, surfaced never diagnosed.
    var bodySignalCount: Int = 0

    /// When true, render bare (no ScrollView / nav chrome) so it expands INLINE
    /// in the Trends tab. False = the standalone pushed screen. Matches the
    /// other detail views.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            detailContent
        } else {
            ScrollView { detailContent.padding(20) }
                .background(detailBackground)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var hasData: Bool {
        hardSessions28d != nil || avgDaysBetweenHard != nil || downWeek == true
    }

    @ViewBuilder private var detailContent: some View {
        if !hasData {
            EmptyStateView(
                variant: .dataPending,
                eyebrow: "Recovery read pending",
                title: "Log a few more sessions and your rest-and-load balance fills in here."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Only parts with data render, so a thin state never shows an
                // em-dash placeholder (hard rule #8).
                cadenceLine
                statusRow.padding(.top, 12)
                // `recoveryRead` prose printed here once, then three stat
                // tiles said the same thing in three boxes of three different
                // heights. One baseline-aligned line now — the numbers carry
                // it, and nothing can wrap. (Rio, 2026-08-17.)
            }
        }
    }

    /// One line, numbers first: "6 hard sessions in 28 days · one every 4.2
    /// days". `lineLimit(1)` + scale factor so a number can never break
    /// across lines the way the old tiles did.
    @ViewBuilder private var cadenceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let h = hardSessions28d {
                Text("\(h)")
                    .font(.dripStat(28)).monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                Text(h == 1 ? "hard session in 28 days" : "hard sessions in 28 days")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                if let a = avgDaysBetweenHard {
                    Text("· one every \(String(format: "%.1f", a)) days")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            } else if let a = avgDaysBetweenHard {
                Text(String(format: "%.1f", a))
                    .font(.dripStat(28)).monospacedDigit()
                    .foregroundStyle(Color.drip.textPrimary)
                Text("days between hard sessions · avg")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    // A quiet fact row: down-week (neutral chip) + body signals. Coral is the
    // one alert in this cluster — design system's one-coral-per-cluster rule.
    private var statusRow: some View {
        HStack(spacing: 8) {
            if downWeek == true {
                chip("DOWN WEEK · PLANNED BACK-OFF", tone: .neutral)
            }
            if bodySignalCount > 0 {
                chip("WATCHING · \(bodySignalCount) BODY \(bodySignalCount == 1 ? "SIGNAL" : "SIGNALS")", tone: .alert)
            } else {
                chip("BODY · ALL CLEAR", tone: .neutral)
            }
        }
    }

    private enum ChipTone { case neutral, alert }
    private func chip(_ text: String, tone: ChipTone) -> some View {
        let color = tone == .alert ? Color.drip.injured : Color.drip.textSecondary
        return Text(text)
            .font(.dripEyebrow(9)).tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // Descriptive read, numbers only, no prescription. Prose em-dash is fine
    // (hard rule #8 bans em-dashes only as empty-state placeholders).
}

// MARK: - Mood

struct MoodDetailView: View {
    let weeks: [TrendsWeek]

    /// When true, render the content bare (no ScrollView / nav chrome) so it can
    /// expand INLINE inside the Trends tab. False = the standalone pushed screen.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            detailContent
        } else {
            ScrollView { detailContent.padding(20) }
                .background(detailBackground)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                // Embedded, the Trends tab already heads this block. Rendering
                // DetailHead here too put a third headline level inside one
                // section — section head, then a 26pt display line, then the
                // track eyebrows. (Rio, 2026-08-03.)
                if !embedded {
                    DetailHead(eyebrow: "Mood · from your voice logs", title: "How the block has felt.")
                }

                TrackEyebrow(text: "Week by week").padding(.top, embedded ? 0 : 16).padding(.bottom, 8)
                ribbon
                legend.padding(.top, 12)

                TrackEyebrow(text: "Distribution").padding(.top, 20).padding(.bottom, 8)
                distribution

                // Her words, not ours. The generated sentence that used to
                // introduce this quote is gone (it claimed a weekday pattern
                // this view holds no daily data to see); the quote stays,
                // because it is the one piece of language on the surface the
                // athlete actually wrote. (Rio, 2026-08-03.)
                if let q = latestQuote {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\u{201C}\(q.0)\u{201D}")
                            .font(.dripBody(14).italic())
                            .foregroundStyle(Color.drip.textPrimary)
                        Text(q.1)
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.drip.coral.opacity(0.5)).frame(width: 2)
                    }
                    .padding(.top, 18)
                }
            }
    }

    // Weeks laid out in rows of 8, oldest first. Each row is anchored by the
    // date of its first week, so any swatch can be placed in time instead of
    // reading as abstract color. Empty weeks render as a paper-deep cell.
    private var ribbon: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Direction cue so the grid reads as a timeline.
            Text("\(weeks.first?.dateLabel ?? "") → \(weeks.last?.dateLabel ?? "") · oldest to newest")
                .font(.dripEyebrow(9)).tracking(0.4)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 2)

            ForEach(Array(weekRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text(row.first?.dateLabel ?? "")
                        .font(.dripEyebrow(9)).tracking(0.3)
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 46, alignment: .leading)
                    ForEach(Array(row.enumerated()), id: \.offset) { _, wk in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(wk.mood.isEmpty ? Color.drip.paperDeep : TrendsMoodColor.color(wk.mood))
                            .frame(height: 34)
                            .frame(maxWidth: .infinity)
                    }
                    // Keep swatch widths aligned when the last row is short.
                    if row.count < 8 {
                        ForEach(0..<(8 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // Color key so swatches decode in place, without cross-referencing the
    // Distribution bars below. Only moods actually present are shown.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(moodCounts.map(\.0), id: \.self) { mood in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TrendsMoodColor.color(mood))
                        .frame(width: 11, height: 11)
                    Text(mood.uppercased())
                        .font(.dripEyebrow(9)).tracking(0.5)
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    // Weeks chunked into rows of 8, preserving chronological order.
    private var weekRows: [[TrendsWeek]] {
        stride(from: 0, to: weeks.count, by: 8).map { start in
            Array(weeks[start..<min(start + 8, weeks.count)])
        }
    }

    private var distribution: some View {
        let counts = moodCounts
        let maxC = max(counts.map(\.1).max() ?? 1, 1)
        return VStack(spacing: 7) {
            ForEach(counts, id: \.0) { mood, n in
                HStack(spacing: 8) {
                    Text(mood.uppercased()).font(.dripEyebrow(9)).tracking(0.6)
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 78, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.drip.paperDeep)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(TrendsMoodColor.color(mood))
                                .frame(width: geo.size.width * CGFloat(n) / CGFloat(maxC))
                        }
                    }
                    .frame(height: 10)
                    Text("\(n)").font(.dripStat(11)).foregroundStyle(Color.drip.textPrimary).frame(width: 18, alignment: .trailing)
                }
            }
        }
    }

    private var moodCounts: [(String, Int)] {
        let order = ["energized", "positive", "neutral", "tired", "struggling", "injured"]
        var dict: [String: Int] = [:]
        for wk in weeks where !wk.mood.isEmpty { dict[wk.mood, default: 0] += 1 }
        return order.compactMap { m in dict[m].map { (m, $0) } }
    }

    private var latestQuote: (String, String)? {
        guard let wk = weeks.last(where: { $0.voiceQuote != nil }), let q = wk.voiceQuote else { return nil }
        return (q, wk.dateLabel)
    }
}

// MARK: - Niggles

struct NigglesDetailView: View {
    let weeks: [TrendsWeek]

    /// When true, render the content bare (no ScrollView / nav chrome) so it can
    /// expand INLINE inside the Trends tab. False = the standalone pushed screen.
    var embedded: Bool = false

    var body: some View {
        if embedded {
            detailContent
        } else {
            ScrollView { detailContent.padding(20) }
                .background(detailBackground)
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
                // Same as MoodDetailView: the tab heads this block when
                // embedded, so the display headline would be a second one.
                // `niggleTitle` still carries the count, in a quiet register.
                if embedded {
                    Text(niggleTitle)
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    DetailHead(eyebrow: "Niggles · recurrence", title: niggleTitle, tag: "surface, don't diagnose")
                }

                if labels.isEmpty {
                    Text("Nothing stacking right now. Body-part mentions show up here when you voice them.")
                        .font(.dripBody(15)).foregroundStyle(Color.drip.textSecondary)
                        .padding(.top, 18)
                } else {
                    TrackEyebrow(text: "By body part · \(weeks.count) weeks").padding(.top, 16).padding(.bottom, 6)
                    NiggleSwimlanes(weeks: weeks, labels: labels).frame(height: CGFloat(labels.count) * 40 + 24)

                    TrackEyebrow(text: "In your words").padding(.top, 18).padding(.bottom, 8)
                    ForEach(Array(quoteWeeks.enumerated()), id: \.offset) { _, wk in
                        quoteCard(wk)
                    }
                }

                Text("In your words. Never interpreted.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 12)
            }
    }

    private var labels: [String] {
        var seen: [String] = []
        for wk in weeks { for n in wk.niggles where !seen.contains(n) { seen.append(n) } }
        return seen
    }
    private var niggleTitle: String {
        switch labels.count {
        case 0: "All clear."
        case 1: "One thing, watched."
        default: "\(labels.count) things, watched."
        }
    }
    private var quoteWeeks: [TrendsWeek] { Array(weeks.filter { $0.voiceQuote != nil && !$0.niggles.isEmpty }.reversed()) }

    private func quoteCard(_ wk: TrendsWeek) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(wk.niggles.joined(separator: ", "))
                    .font(.dripBody(15).weight(.bold))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Text(wk.dateLabel.uppercased()).font(.dripEyebrow(9)).tracking(0.8)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            if let q = wk.voiceQuote {
                Text("\u{201C}\(q)\u{201D}").font(.dripBody(14).italic())
                    .foregroundStyle(Color.drip.textPrimary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.bottom, 9)
    }
}

private struct NiggleSwimlanes: View {
    let weeks: [TrendsWeek]
    let labels: [String]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let n = weeks.count
            let x0: CGFloat = 76, xe = w - 6
            let slot = (xe - x0) / CGFloat(max(n, 1))
            func x(_ i: Int) -> CGFloat { x0 + slot * (CGFloat(i) + 0.5) }

            for (li, label) in labels.enumerated() {
                let y = 18 + CGFloat(li) * 40
                canvasLabel(ctx, label, at: CGPoint(x: 4, y: y), anchor: .leading, size: 9, color: Color.drip.textSecondary)
                var lane = Path(); lane.move(to: CGPoint(x: x0, y: y)); lane.addLine(to: CGPoint(x: xe, y: y))
                ctx.stroke(lane, with: .color(Color.drip.divider.opacity(0.7)), lineWidth: 1)
                for (i, wk) in weeks.enumerated() where wk.niggles.contains(label) {
                    // Severity isn't carried by the weekly timeline yet, so
                    // markers are uniform; severity-encoding is a follow-up.
                    let r: CGFloat = 4.4
                    ctx.fill(Path(ellipseIn: CGRect(x: x(i) - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color.drip.injured))
                }
            }
            // month ticks
            var last = ""
            for (i, wk) in weeks.enumerated() where wk.month != last {
                canvasLabel(ctx, wk.month.uppercased(), at: CGPoint(x: x(i), y: h - 4), anchor: .center)
                last = wk.month
            }
        }
    }
}
