//
//  HomeDayPager.swift
//  RunningLog
//
//  The views for the paged Today surface: one past day, one gap, one session
//  entry, and the folio rail along the bottom edge.
//
//  Today's own page is not here — it lives in `TodayHomeView`, because it is
//  the only page that carries the check-ins and the coach note, and those
//  need that view's state.
//
//  THE MECHANIC IS NOT NEW. `HistoryDetailPager` already turns pages in this
//  app: ScrollView(.horizontal) + LazyHStack + .scrollTargetBehavior(.paging)
//  + .scrollPosition, a rail underneath, a soft haptic on the turn, and
//  accessibility actions named for time rather than for screen direction.
//  This file follows that pattern deliberately — two pagers that behave
//  differently would be worse than either.
//
//  ONE DELIBERATE DIVERGENCE, AND IT IS UNRESOLVED. `HistoryDetailPager` runs
//  oldest → newest, book order, so today's run is the last page and "128/128"
//  means the end of the journal. This pager runs newest → oldest: today is the
//  front page and turning goes back in time, which is what the prototype
//  established and what a newspaper does. An athlete who turns pages in both
//  surfaces will find "back in time" is a different direction in each. Pick
//  one before this ships. Flipping this one is a reversal of
//  `HomePageBuilder.pages` plus the rail's numbering — nothing else.
//

import Supabase
import SwiftUI
import UIKit
import os

// MARK: - Page frame

/// Every page sits in this. The vertical scroll is a fallback, not the
/// design: `.basedOnSize` means a page that fits does not bounce, so it
/// reads as a sheet of paper rather than a scroll view that happens to be
/// short. A page that overflows — a very long entry, or Dynamic Type at the
/// top of the range — scrolls rather than clipping.
struct HomePageFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

// MARK: - A past day

/// One day that is not today: its date, its sessions in clock order, and
/// nothing else. No mood prompt (back-filling a check-in invents the
/// athlete's own words), no coach note (there is no dated coach-note fetch
/// yet), no tomorrow (tomorrow is relative to today, not to the page).
struct HomeDayPageView: View {
    let day: Date
    let sessions: [TrainingSession]
    /// Tapping a session opens the workout detail. Passed in rather than
    /// owned here so the sheet is presented once, by the pager, instead of
    /// once per page.
    var onOpen: (TrainingSession) -> Void = { _ in }

    var body: some View {
        HomePageFrame {
            VStack(alignment: .leading, spacing: 22) {
                HomeDayHeader(day: day, isToday: false)

                EditorialRule()

                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("THE DAY")
                            .font(.dripEyebrow(11))
                            .tracking(1.3)
                            .foregroundStyle(Color.drip.textSecondary)
                        Text("Rest.")
                            .font(.dripDisplay(23))
                            .foregroundStyle(Color.drip.textPrimary)
                        // The empty-state pattern from
                        // docs/conventions/empty-states.md: state the
                        // absence, then say what would fill it.
                        Text("No run logged. When you take one, it lands here.")
                            .font(.system(size: 14, design: .serif).italic())
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                } else {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        HomeSessionEntry(
                            session: session,
                            showClockTime: sessions.count > 1,
                            ordinal: index + 1,
                            of: sessions.count,
                            onOpen: { onOpen(session) }
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.voiceOverDate(day))
    }

    private static let voiceOverFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    static func voiceOverDate(_ date: Date) -> String {
        voiceOverFormatter.string(from: date)
    }
}

// MARK: - Day header

/// Coral day-of-week eyebrow on today, warm gray on every other day — the
/// coral is the active-day signal, and a past page is not active.
struct HomeDayHeader: View {
    let day: Date
    let isToday: Bool
    var aside: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.weekday(day))
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(isToday ? Color.drip.coral : Color.drip.textSecondary)

            Text(Self.headline(day))
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)

            if let aside {
                Text(aside)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }()

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()

    static func weekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date).uppercased()
    }

    /// "August 18th." — month, ordinal day, period. The period is the spec's
    /// rule for standalone headlines, not a typo.
    static func headline(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let ordinal = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(monthFormatter.string(from: date)) \(ordinal)."
    }
}

// MARK: - One session

/// A session, not a run and not a day. `TrainingSession` is what
/// `SessionRollup` assembles out of uploads — see that file's header for why
/// a day cell holding one number cannot represent this athlete.
struct HomeSessionEntry: View {
    let session: TrainingSession
    /// A day with one session says "THE SESSION". A day with two or three
    /// says when each one started, because that is the thing that
    /// distinguishes them.
    var showClockTime: Bool = false
    var ordinal: Int = 1
    var of: Int = 1
    /// Nil makes the block inert — it is still the whole session, just not a
    /// button. Kept optional so a future read-only surface can reuse this
    /// without inventing a destination for the tap.
    var onOpen: (() -> Void)? = nil

    @AppStorage("distanceUnit") private var distanceUnitRaw = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private var moodColor: Color {
        switch (session.mood ?? "").lowercased() {
        case "energized":  return Color.drip.energized
        case "positive":   return Color.drip.positive
        case "neutral":    return Color.drip.neutral
        case "tired":      return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured":    return Color.drip.injured
        default:           return Color.drip.textTertiary
        }
    }

    private var eyebrow: String {
        guard showClockTime else { return "THE SESSION" }
        return "\(Self.clock(session.start))  ·  \(ordinal) OF \(of)"
    }

    private var headlineLine: String {
        let name = CoachIntent.displayName(for: session.typeKey)
        guard session.miles > 0.05 else { return "\(name)." }
        return "\(name), \(DistanceFormat.string(miles: session.miles, unit: unit))."
    }

    /// Pace is derived from miles and minutes inside `TrainingSession` —
    /// `workout_pace_per_mile` is populated on 12% of rows and is never a
    /// display source. See that property's note.
    private var metaLine: String? {
        var parts: [String] = []
        if let pace = session.paceSeconds {
            parts.append("\(DistanceFormat.paceMMSS(secPerMile: pace, unit: unit)) / \(unit.short)")
        }
        if session.minutes > 0 {
            parts.append("\(Int(session.minutes.rounded())) min")
        }
        if let mood = session.mood, !mood.isEmpty {
            parts.append(mood.uppercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: "   ·   ")
    }

    private var quoted: String? {
        guard let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return "\u{201C}\(note)\u{201D}"
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) { entry }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityHint("Opens the workout")
        } else {
            entry
        }
    }

    private var entry: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(moodColor)
                .frame(width: 2)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.drip.textSecondary)

                Text(headlineLine)
                    .font(.dripDisplay(23))
                    .foregroundStyle(Color.drip.textPrimary)

                if let metaLine {
                    Text(metaLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                if let quoted {
                    // Clamped, not truncated silently: the page is the front
                    // page of that day, and the whole entry lives in the
                    // session sheet. If this clamp starts biting often, the
                    // fix is a "read it" affordance, not a taller page.
                    Text(quoted)
                        .font(.system(size: 14.5, design: .serif).italic())
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(3)
                        .lineLimit(6)
                }

                if session.foldedCount > 0 {
                    Text("\(session.foldedCount) duplicate row folded in")
                        .font(.dripEyebrow(9))
                        .tracking(0.9)
                        .foregroundStyle(Color.drip.textTertiary)
                }

                // The whole block is the tap target; this is the affordance
                // that says so. Editorial link style — verb + arrow — per the
                // design system's "Mark complete ↗" pattern.
                if onOpen != nil {
                    Text("Read it \u{2197}")
                        .font(.dripLabel(13))
                        .foregroundStyle(Color.drip.coral)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date).uppercased()
    }
}

// MARK: - Gap

/// Two or more consecutive days with nothing logged. Turning past a rest
/// week should feel like turning past a rest week — not like the log
/// skipping, and not like five identical empty pages.
struct HomeGapPageView: View {
    let from: Date
    let through: Date
    let days: Int

    private var line: String {
        let spelled = NumberFormatter()
        spelled.numberStyle = .spellOut
        let word = spelled.string(from: NSNumber(value: days)) ?? "\(days)"
        return "— \(word) quiet days —"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(line)
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Color.drip.textTertiary)
            Text(Self.range(from: from, through: through))
                .font(.dripEyebrow(9))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(days) days with nothing logged")
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static func range(from: Date, through: Date) -> String {
        "\(rangeFormatter.string(from: from).uppercased()) – \(rangeFormatter.string(from: through).uppercased())"
    }
}

// MARK: - Folio rail

/// The spine along the bottom edge: a tick per page, the page you are on in
/// coral, and the book-style page number. Modelled on `PageTurnRail` in
/// HistoryDetailPager.swift — same shape, same 46pt height, same cached
/// formatters, because the two rails sit two taps apart in the app.
///
/// The ticks are Buttons rather than decoration on purpose: they are the only
/// way to move between pages that does not require a swipe, which is what
/// makes this reachable under VoiceOver and Switch Control.
struct HomeFolioRail: View {
    let pages: [HomePage]
    @Binding var currentID: HomePage.ID?
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            DripHairline()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(pages) { page in
                                tick(for: page).id(page.id)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: currentID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.24)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                    .onAppear {
                        guard let currentID else { return }
                        proxy.scrollTo(currentID, anchor: .center)
                    }
                }

                Text("\(index + 1)/\(pages.count)")
                    .font(.dripEyebrow(9))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.leading, 10)
                    .padding(.trailing, 24)
                    .accessibilityLabel("Page \(index + 1) of \(pages.count)")
            }
            .frame(height: 46)
        }
        .background(Color.drip.background)
    }

    @ViewBuilder
    private func tick(for page: HomePage) -> some View {
        let isCurrent = page.id == currentID
        let tint = isCurrent ? Color.drip.coral : Color.drip.textTertiary

        Button {
            withAnimation(.snappy(duration: 0.28)) { currentID = page.id }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(tint, lineWidth: 1)
                    .background(Circle().fill(isFilled(page) ? tint : Color.clear))
                    .frame(width: 5, height: 5)

                Text(label(for: page))
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(tint)
            }
            .frame(minWidth: 54)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: page))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// Filled tick = a day. Hollow = the cockpit or a gap — pages that are
    /// not a day in the athlete's log.
    private func isFilled(_ page: HomePage) -> Bool {
        if case .day = page { return true }
        return false
    }

    private func label(for page: HomePage) -> String {
        switch page {
        case .day(let d):       return Self.railDate(d)
        case .cockpit:          return "NUMBERS"
        case .gap(_, _, let n): return "\(n) DAYS"
        }
    }

    private func accessibilityLabel(for page: HomePage) -> String {
        switch page {
        case .day(let d):       return HomeDayPageView.voiceOverDate(d)
        case .cockpit:          return "The numbers"
        case .gap(_, _, let n): return "\(n) quiet days"
        }
    }

    private static let railFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static func railDate(_ date: Date) -> String {
        railFormatter.string(from: date).uppercased()
    }
}

// MARK: - Opening a session

/// Turns a tapped `TrainingSession` into the payload `HistoryDetailPager`
/// wants.
///
/// The day pages are built from `TodayLogRow`s — the narrow projection
/// `TrainingLogStore` holds. The detail sheet needs `TrainingLog`, which has
/// columns that projection never fetched (`created_at`, `processing_status`,
/// `title`). Converting one to the other would mean inventing a `createdAt`,
/// so the rows are fetched for real, by id, at the moment of the tap.
///
/// Fetching by id rather than by day bounds is deliberate: the ids are already
/// in hand from `session.allPieces`, and a day-bounded query would have to
/// pick a timezone. `SessionRollup.localDay`'s note explains what a UTC day
/// does to 8 rows in this account.
///
/// `TrainingLog.columns`, never `select("*")` — a bare select drags the
/// `external_streams` blob across the wire (PERF-AUDIT-2026-08-10, finding #1).
enum HomeSessionOpener {

    /// - Parameters:
    ///   - sessionsOnDay: every session on the tapped page. All of their rows
    ///     go into the pager, so paging inside the sheet walks the whole day —
    ///     the same behaviour as the Trends day drill-down.
    ///   - focus: the session that was tapped. Becomes the open page.
    /// - Returns: nil when the fetch fails or comes back empty, in which case
    ///   nothing opens. A sheet that opens onto an error is worse than a tap
    ///   that does nothing.
    @MainActor
    static func resolve(sessionsOnDay: [TrainingSession],
                        focus: TrainingSession) async -> DayWorkouts? {
        let ids = sessionsOnDay.flatMap { $0.allPieces }.map(\.id)
        guard !ids.isEmpty else { return nil }

        do {
            let entries: [TrainingLog] = try await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .in("id", values: ids.map { $0.uuidString })
                .order("workout_date", ascending: false, nullsFirst: false)
                .execute()
                .value

            guard !entries.isEmpty else { return nil }

            // `TrainingSession.id` is its first piece's row id, so this lands
            // on the tapped session rather than the day's first upload.
            let initial = entries.first { $0.id == focus.id } ?? entries[0]
            return DayWorkouts(entries: entries, initial: initial)
        } catch {
            Log.coach.error("Home session open failed: \(error.localizedDescription)")
            return nil
        }
    }
}
