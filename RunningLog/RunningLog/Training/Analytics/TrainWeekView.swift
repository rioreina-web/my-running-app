//
//  TrainWeekView.swift
//  RunningLog · Training › Analytics
//
//  Train's CURRENT mode: today and this week, read as SESSIONS.
//
//  WHY THIS REPLACED FOUR SECTIONS
//  The old CURRENT stacked `summary` + `todaySection` + `currentWeekSection`
//  + `WeekStressStripSection`: a stat strip, today, the same week as a list,
//  and the same week again as a load strip. Three of those answer "what did
//  this week cost" and none of them says what the sessions WERE. A week of
//  training reads as named sessions — "6 × 1K @ HMP", not "14.7 mi" — and
//  that is the one reading no other tab offers.
//
//  WHAT LIVES ELSEWHERE (do not re-add it here)
//    · 13-week volume, ACWR, load          → Week tab
//    · pace × volume, zone mix, paces      → Trends / Ask
//    · the session archive, search, chips  → Sheet tab
//    · the fitness range and its history   → Trends
//  This surface links out to Trends in one line and otherwise stays quiet.
//
//  SESSIONS, NOT UPLOADS
//  Every row is built by `SessionRollup`, the same rollup The Sheet uses:
//  dedup → local calendar day → split on a 90-minute clock gap. A day with a
//  6:05am workout and a 6:12pm double is TWO sessions and says so; five Strava
//  uploads around one track session are ONE. Rolling to the day instead would
//  print "14.7 mi · 6 × 1K", describing a workout that never happened.
//
//  MILES ARE RUNNING-ONLY, TIME IS EVERYTHING
//  The totals strip carries both. Cross-training is training and belongs on
//  the page, but folding it into miles would corrupt ACWR and the projection —
//  it is cardiovascular stress, not mechanical (decision, 2026-05-28). Today
//  no non-run rows exist for any athlete: both ingest paths filter to running
//  (`VitalManager` sport == "running", `strava-sync` RUN_SPORT_TYPES), so the
//  time column currently equals running time. It is split out anyway so the
//  surface is already correct on the day that changes.
//

import os
import Supabase
import SwiftUI

struct TrainWeekView: View {

    // MARK: State

    @State private var sessions: [TrainingSession] = []
    @State private var goal: AthleteGoal?
    @State private var projectedSeconds: Int?
    @State private var loaded = false
    @State private var loadFailed = false

    /// Which day rows are open. Seeded on load with the most recent day that
    /// has a session, so the surface opens on the last thing the athlete did
    /// without a separate "today" hero duplicating a row inches below it.
    @State private var openDays: Set<Date> = []
    /// Seeding runs once. Without this a refresh would slam a row the athlete
    /// deliberately collapsed back open.
    @State private var didSeed = false

    /// Tapping a day opens the full day sheet. Owned by the parent tab so the
    /// detail surface stays shared rather than forked.
    var onOpenDay: ((Date) -> Void)?

    private let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2   // Monday. A training week is not a Sunday week.
        return c
    }()

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loadFailed && !loaded {
                EmptyStateView(
                    variant: .error,
                    eyebrow: "Couldn't load",
                    title: "This week didn't load. Check your connection and try again.",
                    cta: .init(label: "Retry") { Task { await load(force: true) } }
                )
                .padding(.vertical, 30)
            } else {
                totals
                weekLedger
                    .padding(.top, 20)
                goalLine
                    .padding(.top, 22)
            }
        }
        .task { await load(force: false) }
    }

    // MARK: 1 · Totals — two currencies

    private var totals: some View {
        HStack(spacing: 0) {
            totalCell(value: milesText, key: "Miles", sub: avgComparison)
            totalDivider
            totalCell(value: timeText, key: "Time", sub: "ALL TRAINING")
            totalDivider
            totalCell(value: "\(daysWithRunning) / 7", key: "Days", sub: daysSub)
        }
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
        .padding(.top, 22)
    }

    private var totalDivider: some View {
        Rectangle().fill(Color.drip.divider).frame(width: 1, height: 52)
    }

    @ViewBuilder
    private func totalCell(value: String, key: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.uppercased())
                .font(.dripEyebrow(9))
                .tracking(1.5)
                .foregroundStyle(Color.drip.textTertiary)
            Text(value)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
            Text(sub)
                .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 13)
        .padding(.vertical, 13)
    }

    // MARK: 2 · The week, as sessions

    private var weekLedger: some View {
        VStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                dayRow(day)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let daySessions = sessions(on: day)
        let lead = leadSession(daySessions)
        let isToday = day == today
        let isOpen = openDays.contains(day) && lead != nil

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                // The 2pt leading rule is MOOD and only mood — see the
                // left-rule rule in the design system. No mood, no colour.
                Rectangle()
                    .fill(Color.drip.moodBorderColor(for: lead?.mood) ?? Color.drip.divider)
                    .frame(width: 2)
                    .cornerRadius(1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(dayLabel(day))
                            .font(.dripEyebrow(9))
                            .tracking(1.4)
                            .foregroundStyle(isToday ? Color.drip.coral : Color.drip.textTertiary)
                            .frame(width: 50, alignment: .leading)

                        Text(name(for: lead, day: day))
                            .font(.dripLabel(14))
                            .foregroundStyle(nameColor(lead, day: day))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let lead {
                            Text(milesString(dayMiles(daySessions)))
                                .font(.dripStat(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text(paceString(lead.paceSeconds))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.drip.textTertiary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }

                    if let sub = subLine(daySessions) {
                        Text(sub)
                            .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.leading, 59)
                    }

                    if isOpen, let lead {
                        expandedSession(lead)
                            .padding(.leading, 59)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                guard lead != nil else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    if openDays.contains(day) { openDays.remove(day) } else { openDays.insert(day) }
                }
            }

            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    /// The reps, the athlete's words, and nothing invented. Blocks come from
    /// `parsed_structure` — the only source carrying true rep pace — so a 6:00
    /// rep reads as 6:00 rather than as the mile it lived inside.
    @ViewBuilder
    private func expandedSession(_ session: TrainingSession) -> some View {
        let blocks = repBlocks(session)

        VStack(alignment: .leading, spacing: 0) {
            if let note = session.note, !note.isEmpty {
                Text("\u{201C}\(note)\u{201D}")
                    .font(.dripBodyItalic(12.5))
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, blocks.isEmpty ? 0 : 10)
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                HStack(spacing: 8) {
                    Text(b.label)
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 50, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(b.color)
                            .frame(width: max(6, geo.size.width * b.fraction), height: 7)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)

                    Text(b.pace)
                        .font(.dripStat(11.5))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 40, alignment: .trailing)

                    Text(b.hr)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }

            if session.foldedCount > 0 {
                Text("\(session.foldedCount) DUPLICATE UPLOAD\(session.foldedCount == 1 ? "" : "S") FOLDED IN")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.top, 8)
            }

            if let onOpenDay {
                Button {
                    onOpenDay(session.day)
                } label: {
                    Text("OPEN DAY \u{2197}")
                        .font(.dripEyebrow(9))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }

    // MARK: 3 · One line out to the goal

    @ViewBuilder
    private var goalLine: some View {
        if let goal {
            VStack(spacing: 0) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.headline.uppercased())
                            .font(.dripEyebrow(9))
                            .tracking(1.5)
                            .foregroundStyle(Color.drip.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(projectedText)
                                .font(.dripStat(15))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text(goal.contextLine.uppercased())
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("TRENDS \u{2197}")
                        .font(.dripEyebrow(9))
                        .tracking(1.4)
                        .foregroundStyle(Color.drip.coral)
                }
                .padding(.vertical, 14)
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
        }
    }

    // MARK: - Derived

    private var today: Date { SessionRollup.localDay(Date()) }

    private var weekDays: [Date] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: start)) }
    }

    private func sessions(on day: Date) -> [TrainingSession] {
        sessions.filter { $0.day == day }.sorted { $0.start < $1.start }
    }

    /// A day is NAMED for its hardest session — the same intent ladder the
    /// rollup uses, so a track day reads "Intervals", not "Recovery" because
    /// the warm-up sorted first.
    private func leadSession(_ ss: [TrainingSession]) -> TrainingSession? {
        ss.max { SessionRollup.rank($0.typeKey) < SessionRollup.rank($1.typeKey) }
    }

    private func dayMiles(_ ss: [TrainingSession]) -> Double { ss.reduce(0) { $0 + $1.miles } }

    private var weekSessions: [TrainingSession] {
        let days = Set(weekDays)
        return sessions.filter { days.contains($0.day) }
    }

    private var milesText: String { milesString(weekSessions.reduce(0) { $0 + $1.miles }) }

    private var timeText: String {
        let mins = Int(weekSessions.reduce(0) { $0 + $1.minutes }.rounded())
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    private var daysWithRunning: Int { Set(weekSessions.map(\.day)).count }

    private var daysSub: String {
        let elapsed = weekDays.filter { $0 <= today }.count
        return sessions(on: today).isEmpty ? "TODAY OPEN" : "DAY \(elapsed) OF 7"
    }

    /// Compares this week against the trailing four — but only once the week
    /// is actually over.
    ///
    /// A part-week delta is not a comparison, it is a countdown: on Monday
    /// morning a week going exactly to plan reads "-88% VS AVG", which is
    /// alarming and meaningless. While the week is open this states the
    /// baseline instead and lets the athlete do the comparing. Stays silent
    /// entirely when there is no baseline, rather than printing "+0%".
    private var avgComparison: String {
        let prior = priorFourWeekAverage
        guard prior > 0.5 else { return "NO BASELINE YET" }
        guard weekIsComplete else { return String(format: "AVG %.0f / WK", prior) }
        let mine = weekSessions.reduce(0) { $0 + $1.miles }
        let pct = Int(((mine / prior) - 1) * 100)
        if pct == 0 { return "ON AVERAGE" }
        return "\(pct > 0 ? "+" : "")\(pct)% VS AVG"
    }

    /// True on the week's last day. The comparison only becomes fair here.
    private var weekIsComplete: Bool {
        guard let last = weekDays.last else { return false }
        return last <= today
    }

    private var priorFourWeekAverage: Double {
        guard let thisWeekStart = weekDays.first else { return 0 }
        guard let windowStart = cal.date(byAdding: .day, value: -28, to: thisWeekStart) else { return 0 }
        let prior = sessions.filter { $0.day >= windowStart && $0.day < thisWeekStart }
        guard !prior.isEmpty else { return 0 }
        return prior.reduce(0) { $0 + $1.miles } / 4.0
    }

    private var projectedText: String {
        guard let projectedSeconds else { return goal?.timeDisplay ?? "" }
        return format(seconds: projectedSeconds)
    }

    // MARK: Row copy

    private func dayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f.string(from: day)
    }

    /// Never an em-dash — an empty day says what it is (hard rule #8).
    private func name(for lead: TrainingSession?, day: Date) -> String {
        if let lead { return WorkoutLabel.display(lead.typeKey) }
        if day == today { return "Nothing logged yet" }
        if day > today { return "To run" }
        return "Rest"
    }

    private func nameColor(_ lead: TrainingSession?, day: Date) -> Color {
        guard let lead else { return Color.drip.textTertiary }
        // Blue names a keyed session — the design system's one licensed use.
        return lead.isQuality ? Color(hex: "1F4FA8") : Color.drip.textPrimary
    }

    private func subLine(_ ss: [TrainingSession]) -> String? {
        guard ss.count > 1 else { return nil }
        let parts = ss.map { milesString($0.miles) }.joined(separator: " + ")
        return "\(ss.count) sessions · \(parts)"
    }

    private func milesString(_ m: Double) -> String { String(format: "%.1f", m) }

    private func paceString(_ sec: Double?) -> String {
        guard let sec, sec > 0 else { return "" }
        let t = Int(sec.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func format(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Rep blocks

    private struct RepBlock {
        let label: String
        let pace: String
        let hr: String
        let fraction: Double
        let color: Color
    }

    /// Work legs of the session's hardest upload, shaded on the pace ramp
    /// across that session's own range, so a negative split is visible before
    /// a single number is read.
    private func repBlocks(_ session: TrainingSession) -> [RepBlock] {
        let hardest = session.pieces.max { SessionRollup.rank($0.typeKey) < SessionRollup.rank($1.typeKey) }
        guard let blocks = hardest?.structureBlocks, blocks.count > 1 else { return [] }

        let work = blocks.filter { ($0.role ?? "") != "recovery" }
        let paces: [Double] = work.compactMap { parsePace($0.avgPace) }
        guard paces.count > 1, let slow = paces.max(), let fast = paces.min(), slow > fast else { return [] }

        return work.prefix(9).map { b in
            let sec = parsePace(b.avgPace)
            let frac: Double = {
                guard let sec, slow > fast else { return 0.5 }
                // Faster reps read longer — speed, not duration.
                return 0.42 + 0.58 * ((slow - sec) / (slow - fast))
            }()
            return RepBlock(
                label: b.distanceMiles.map { String(format: "%.1f mi", $0) } ?? (b.role ?? "").uppercased(),
                pace: b.avgPace ?? "",
                hr: b.avgHr.map(String.init) ?? "",
                fraction: min(1, max(0.18, frac)),
                color: sec.map { PaceSpectrum.color(forPaceSec: $0, slowSec: slow, fastSec: fast) }
                    ?? Color.drip.textTertiary
            )
        }
    }

    private func parsePace(_ s: String?) -> Double? {
        guard let s else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return m * 60 + sec
    }

    // MARK: - Load

    private func load(force: Bool) async {
        // Cache first so the week paints immediately on tab switch.
        let cached = TrainingLogStore.shared.cachedRows(days: 60)
        if !cached.isEmpty {
            sessions = SessionRollup.sessions(from: cached)
            loaded = true
            seedOpenDay()
        }

        do {
            let rows = try await TrainingLogStore.shared.refresh(days: 60)
            sessions = SessionRollup.sessions(from: rows)
            loaded = true
            loadFailed = false
            seedOpenDay()
        } catch {
            Log.coach.error("TrainWeekView load failed: \(error)")
            if !loaded { loadFailed = true }
        }

        if goal == nil { goal = await AthleteGoal.fetchActive() }
        if projectedSeconds == nil, let key = goal?.distanceKey {
            projectedSeconds = await AthleteGoal.fetchProjection(for: key)
        }
    }

    /// Opens the most recent day that has a session. Runs once — a later
    /// refresh must not reopen a row the athlete closed.
    private func seedOpenDay() {
        guard !didSeed else { return }
        for day in weekDays.reversed() where day <= today {
            if !sessions(on: day).isEmpty {
                openDays.insert(day)
                didSeed = true
                return
            }
        }
        // A week with nothing in it yet is not a failure to seed — leave
        // `didSeed` false so the first logged run opens itself.
    }
}

// MARK: - AthleteGoal

/// The athlete's goal, read from `user_goals` rather than `training_plans`.
///
/// `TodayGoal.fetchActive()` reads the active PLAN, which is the right source
/// when one exists — but a plan is optional by design (the product is
/// journey-centric, `activePlan == nil` is a first-class state), and a
/// self-coached athlete with a goal and no plan would get nothing back. This
/// reads the goal itself, which survives with or without a plan.
struct AthleteGoal {
    let timeSeconds: Int
    let distanceKey: String
    let title: String?
    let raceDate: Date?

    var timeDisplay: String {
        let h = timeSeconds / 3600, m = (timeSeconds % 3600) / 60, s = timeSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Prefers the athlete's own words for the goal over a composed phrase.
    var headline: String {
        if let title, !title.isEmpty { return title }
        return "\(timeDisplay) \(distanceKey.replacingOccurrences(of: "_", with: " "))"
    }

    var contextLine: String {
        var parts = ["projected"]
        if let raceDate {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: raceDate)
            ).day ?? 0
            if days > 0 { parts.append("\(days) days") }
        }
        return parts.joined(separator: " · ")
    }

    static func fetchActive() async -> AthleteGoal? {
        struct Row: Decodable {
            let target_time_seconds: Int?
            let target_race_distance: String?
            let goal_title: String?
            let target_date: String?
        }
        do {
            let rows: [Row] = try await supabase
                .from("user_goals")
                .select("target_time_seconds, target_race_distance, goal_title, target_date")
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let r = rows.first,
                  let secs = r.target_time_seconds,
                  let dist = r.target_race_distance else { return nil }
            return AthleteGoal(
                timeSeconds: secs,
                distanceKey: dist,
                title: r.goal_title,
                raceDate: parseDate(r.target_date)
            )
        } catch {
            Log.coach.error("AthleteGoal fetch failed: \(error)")
            return nil
        }
    }

    /// Latest snapshot's projection for the goal distance. Only Int columns are
    /// decoded — the SDK's `.value` decoder throws on DATE/TIMESTAMP columns,
    /// so none are selected.
    static func fetchProjection(for distanceKey: String) async -> Int? {
        struct Row: Decodable {
            let predicted_marathon_seconds: Int?
            let predicted_half_seconds: Int?
            let predicted_10k_seconds: Int?
            let predicted_5k_seconds: Int?
        }
        do {
            let rows: [Row] = try await supabase
                .from("fitness_snapshots")
                .select("predicted_marathon_seconds, predicted_half_seconds, predicted_10k_seconds, predicted_5k_seconds")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let r = rows.first else { return nil }
            switch distanceKey.lowercased() {
            case "marathon":              return r.predicted_marathon_seconds
            case "half_marathon", "half": return r.predicted_half_seconds
            case "10k":                   return r.predicted_10k_seconds
            case "5k":                    return r.predicted_5k_seconds
            default:                      return nil
            }
        } catch {
            Log.coach.error("Projection fetch failed: \(error)")
            return nil
        }
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: String(s.prefix(10)))
    }
}
