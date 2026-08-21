//
//  JournalPager.swift
//  RunningLog
//
//  The training journal, paged by WORKOUT rather than by day.
//
//  Pages are one session's detail — the session, the athlete's words, the
//  charts, the read — turned by a swipe. The spine along the bottom edge
//  lists recent runs; tapping one loads its pages. Day paging (HomePage.swift)
//  is not used in this mode; see `TodayHomeView.journalMode`, which is the one
//  line that switches between them.
//
//  Prototype: journal-workout-pages-prototype.html
//
//  WHAT THIS DOES NOT DO, DELIBERATELY
//
//  It does not touch `HistoryDetailSheet`. That sheet is the workout detail
//  everywhere else in the app — the Log feed, the Trends day drill-down, the
//  Week rows — and its sections are private to it and its view model. Cutting
//  it into pages would mean refactoring a shipped surface with six call sites
//  to prove a layout. So this composes the two pieces that ARE public
//  (`WorkoutRepReceiptView`, `SessionAskBlock`) and writes the rest thin.
//
//  The cost of that decision, stated plainly: **two surfaces now render one
//  session.** This one and `HistoryDetailSheet`. That is the thing to resolve
//  before this ships — either the journal replaces the sheet everywhere, or
//  this goes away. It is fine while both are behind one switch and being
//  compared; it is not fine shipped.
//
//  The mechanic is `HistoryDetailPager`'s, again: paging ScrollView +
//  a hinge turn (App/HingePager.swift), a rail underneath, a soft haptic,
//  accessibility actions named for content rather than screen direction.
//

import Supabase
import SwiftUI
import UIKit

// MARK: - Pages

/// Which pages a session has depends on what the session actually holds.
/// A run with no words has no words page; a run with no GPS stream has no
/// charts page. Pages are never rendered empty to keep the count even.
enum JournalPage: String, Identifiable, CaseIterable {
    case session   // headline, mood, the three measures
    case words     // the athlete's own entry
    case workout   // conditions, signals, splits, telemetry, route
    case read      // the stored read, the comparison, the ask box

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: return "The session"
        case .words:   return "In your words"
        case .workout: return "The workout"
        case .read:    return "The read"
        }
    }
}

enum JournalPageBuilder {

    /// - Parameters:
    ///   - log: the entry being read.
    ///   - hasStream: whether a GPS/lap stream exists for it. The charts page
    ///     is the whole reason `WorkoutRepReceiptView` exists, and without a
    ///     stream that view renders a "logged without GPS" block — noise as a
    ///     page of its own.
    static func pages(for log: TrainingLog, hasStream: Bool) -> [JournalPage] {
        var pages: [JournalPage] = [.session]

        let words = (log.cleanedNotes ?? log.notes)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !words.isEmpty || log.audioUrl != nil { pages.append(.words) }

        if hasStream { pages.append(.workout) }

        pages.append(.read)   // always — the ask box works with no data at all
        return pages
    }
}

// MARK: - The pager

struct JournalPagerView: View {

    /// Recent runs, newest first — the spine's order and the order a tap
    /// moves through. Feed order, not reading order: unlike
    /// `HistoryDetailPager` this pager does not turn between entries, so
    /// there is nothing to mirror.
    let entries: [TrainingLog]

    @State private var entryID: UUID?
    @State private var pageID: JournalPage.ID?
    @State private var pagingLocked = false
    @State private var hasStream = false

    init(entries: [TrainingLog], initial: TrainingLog? = nil) {
        self.entries = entries
        _entryID = State(initialValue: initial?.id ?? entries.first?.id)
    }

    private var entry: TrainingLog? {
        entries.first { $0.id == entryID } ?? entries.first
    }

    private var pages: [JournalPage] {
        guard let entry else { return [.read] }
        return JournalPageBuilder.pages(for: entry, hasStream: hasStream)
    }

    private var pageIndex: Int {
        pages.firstIndex { $0.id == pageID } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if let entry {
                // The four faces of one session, turned on a hinge rather
                // than slid. `HingePager` owns the gesture, the shading and
                // the accessibility actions; everything below it — progress,
                // spine, haptics — is unchanged.
                HingePager(
                    items: pages,
                    selection: $pageID,
                    locked: $pagingLocked,
                    order: .sequence
                ) { page in
                    pageView(page, entry: entry)
                }
                .frame(maxHeight: .infinity)
                .environment(\.pageTurnLocked, $pagingLocked)

                JournalProgress(count: pages.count, index: pageIndex)

                JournalSpine(
                    entries: entries,
                    entryID: $entryID,
                    trailing: "\(pageIndex + 1)/\(pages.count) · \(pages[pageIndex].label)"
                )
            } else {
                EmptyStateView(
                    variant: .optionalEmpty,
                    eyebrow: "Nothing logged",
                    title: "No runs yet. When you log one, it opens here.",
                    cta: nil
                )
                .padding(.horizontal, 24)
                Spacer()
            }
        }
        .background(Color.drip.background)
        .task(id: entryID) { await loadStreamFlag() }
        .onChange(of: entryID) { old, new in
            guard old != nil, new != nil, old != new else { return }
            // A new run always opens on its first page. Landing on "the read"
            // of a run you have not looked at yet is backwards.
            pageID = JournalPage.session.id
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .onChange(of: pageID) { old, new in
            guard old != nil, new != nil, old != new else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .accessibilityElement(children: .contain)
        // Turn actions live on `HingePager` now — see App/HingePager.swift.
    }

    @ViewBuilder
    private func pageView(_ page: JournalPage, entry: TrainingLog) -> some View {
        switch page {
        case .session: JournalSessionPage(log: entry)
        case .words:   JournalWordsPage(log: entry)
        case .workout: JournalWorkoutPage(log: entry)
        case .read:    JournalReadPage(log: entry)
        }
    }

    /// Whether this entry has a lap/stream row behind it, which decides
    /// whether the charts page exists.
    ///
    /// KNOWN GAP: this is a cheap proxy — `paceSegments` on the row itself —
    /// not the `linkedStreamLogId` resolution `HistoryDetailViewModel` does,
    /// which also finds a stream on a *sibling* row (a voice memo paired with
    /// a Strava upload). So a voice entry whose GPS lives on its twin will not
    /// show a charts page here, and does in the sheet. Fixing it means
    /// lifting that resolution out of the view model.
    private func loadStreamFlag() async {
        guard let entry else { return }
        let has = (entry.paceSegments?.isEmpty == false) || entry.vitalWorkoutId != nil
        await MainActor.run {
            hasStream = has
            if pageID == nil { pageID = JournalPage.session.id }
        }
    }
}

// MARK: - Progress

/// One segment per page of the run you are reading. Thin, above the spine —
/// the spine says which run, this says where in it.
struct JournalProgress: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< max(count, 1), id: \.self) { i in
                Rectangle()
                    .fill(i == index ? Color.drip.coral : Color.drip.paperDeep)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 9)
        .accessibilityHidden(true)   // the spine's trailing label says it in words
    }
}

// MARK: - Spine

/// The run spine: every recent session as a date tick, newest first, the one
/// you are reading in coral. Filled tick = a quality session.
///
/// Same shape as `PageTurnRail` in HistoryDetailPager.swift, and for the same
/// reason — it is the second rail in the app and they should not feel like
/// two different objects.
struct JournalSpine: View {
    let entries: [TrainingLog]
    @Binding var entryID: UUID?
    let trailing: String

    var body: some View {
        VStack(spacing: 0) {
            DripHairline()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(entries) { e in
                                tick(for: e).id(e.id)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: entryID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.24)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onAppear {
                        guard let entryID else { return }
                        proxy.scrollTo(entryID, anchor: .center)
                    }
                }

                Text(trailing)
                    .font(.dripEyebrow(9))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .padding(.trailing, 20)
            }
            .frame(height: 52)
        }
        .background(Color.drip.background)
    }

    @ViewBuilder
    private func tick(for e: TrainingLog) -> some View {
        let isCurrent = e.id == entryID
        let tint = isCurrent ? Color.drip.coral : Color.drip.textTertiary
        let quality = SessionRollup.isQuality(e.workoutType)

        Button {
            withAnimation(.snappy(duration: 0.28)) { entryID = e.id }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(tint, lineWidth: 1)
                    .background(Circle().fill(quality ? tint : Color.clear))
                    .frame(width: 5, height: 5)
                Text(Self.spineDate(e.displayDate))
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(tint)
            }
            .frame(minWidth: 56)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.voiceOver(e.displayDate))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private static let spineFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let voiceOverFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .none; return f
    }()

    static func spineDate(_ d: Date) -> String { spineFormatter.string(from: d).uppercased() }
    static func voiceOver(_ d: Date) -> String { voiceOverFormatter.string(from: d) }
}

// MARK: - Loading the spine

/// The runs the spine offers. One query, newest first.
///
/// `TrainingLogStore` holds the window this app runs on, but it holds
/// `TodayLogRow` — the narrow projection — and every page here needs
/// `TrainingLog`. Rather than convert (which would mean inventing a
/// `createdAt`; see HomeSessionOpener), the journal fetches the entries it
/// pages through, once, at the same time as everything else on the surface.
///
/// `TrainingLog.columns`, never `select("*")`: a bare select drags the
/// `external_streams` blob (PERF-AUDIT-2026-08-10, finding #1).
enum JournalEntries {

    /// 40 runs is roughly five weeks for this athlete. Far enough back that
    /// the spine is worth scrolling, short enough that it is one small query.
    static let limit = 40

    static func recent() async -> [TrainingLog] {
        do {
            let rows: [TrainingLog] = try await supabase
                .from("training_logs")
                .select(TrainingLog.columns)
                .eq("user_id", value: AuthManager.shared.userId)
                .order("workout_date", ascending: false, nullsFirst: false)
                .limit(limit)
                .execute()
                .value
            // Undated rows (a memo saved before its workout arrived) have no
            // place on a spine that is a date rail. Filtered here rather than
            // in the query so the filter is visible.
            return rows.filter { $0.workoutDate != nil }
        } catch {
            Log.coach.error("Journal entries load failed: \(error.localizedDescription)")
            return []
        }
    }
}
