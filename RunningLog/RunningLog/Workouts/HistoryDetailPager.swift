//
//  HistoryDetailPager.swift
//  RunningLog
//
//  Turn the journal like a book.
//
//  `HistoryDetailSheet` shows one entry. This wraps a run of sibling entries
//  so the athlete can swipe left/right between them without bouncing back to
//  the feed — the page-turn gesture of a paper training diary.
//
//  Design notes:
//
//  • READING ORDER IS THE BOOK'S, NOT THE FEED'S. The journal feed is
//    newest-first, because that's how you scan a list. A diary is the other way
//    round: the oldest entry is at the front, today's entry is the last written
//    page, and you flip *backwards* to see what's behind you. So the pager
//    mirrors the feed — oldest page on the left, newest on the right — and
//    opening any entry drops you onto that page mid-book. Swipe back (drag
//    left-to-right) for older; swipe forward for newer.
//
//    Callers pass entries in feed order (newest first). `init` does the mirror,
//    so no call site has to think about it.
//
//  • Each page keeps its own `NavigationStack` + toolbar. Edit / Save state is
//    per-entry, so hoisting the toolbar into the pager would mean plumbing
//    every page's `isEditing` and view model back up. Letting the whole page
//    (chrome included) turn is both simpler and truer to the metaphor.
//
//  • Paging is `HingePager` (App/HingePager.swift) — the sheet rotates about
//    its leading edge and lifts off the one beneath. It replaced a
//    `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)`, which could
//    only slide: a paging scroll lays its children side by side, so there is
//    no page "beneath" for a turning sheet to reveal. The page-turn lock below
//    is unchanged, and `HingePager` honours it.
//
//  • One entry in, no pager: the view degrades to a plain `HistoryDetailSheet`.
//    Every existing call site keeps working unchanged.
//

import SwiftUI
import UIKit

// MARK: - Page-turn lock

/// Suppresses the page-turn swipe while a child view owns the horizontal drag.
///
/// The telemetry chart (`UnifiedTelemetryCard`) scrubs on a press-and-drag. Its
/// long-press qualifier already stops a *quick* flick from stealing the gesture,
/// but once scrubbing has begun a horizontal drag would fight the pager. The
/// chart raises this flag for the duration of the scrub; the pager reads it and
/// stops accepting swipes.
///
/// A `Binding` rather than an observable object, matching `SelectedTabKey` /
/// `ShowSidebarKey` in `RunningLogApp.swift` — the default is `.constant(false)`,
/// so a component can write to it unconditionally and the write is simply
/// discarded when no pager is hosting it.
///
/// Add `@Environment(\.pageTurnLocked) private var pageTurnLocked` to any future
/// component with a horizontal drag and bracket the gesture with it.
private struct PageTurnLockKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var pageTurnLocked: Binding<Bool> {
        get { self[PageTurnLockKey.self] }
        set { self[PageTurnLockKey.self] = newValue }
    }
}

// MARK: - Pager

struct HistoryDetailPager: View {
    /// The sibling run in *reading* order — oldest page first, newest last.
    /// Built in `init` by mirroring the caller's feed order; see the file header.
    let entries: [TrainingLog]
    let onUpdate: () -> Void

    @State private var currentID: UUID?
    @State private var pagingLocked = false

    /// - Parameter entries: the run of siblings **in feed order (newest first)** —
    ///   normally exactly what the athlete can see in the surface they tapped
    ///   from. The pager mirrors this into reading order itself.
    /// - Parameter initial: the entry they tapped. Becomes the open page.
    init(entries: [TrainingLog], initial: TrainingLog, onUpdate: @escaping () -> Void) {
        // If the tapped entry isn't in the list (stale feed, filter changed
        // underfoot, an empty list), fall back to a single-page run rather than
        // opening the wrong entry.
        let run = entries.contains { $0.id == initial.id } ? entries : [initial]

        // Mirror rather than re-sort. `sorted(by:)` is not guaranteed stable, so
        // sorting on `displayDate` would let same-day entries swap places between
        // renders and jitter the page you're standing on. Reversing preserves the
        // feed's exact tie-breaking, just back to front.
        self.entries = Array(run.reversed())
        self.onUpdate = onUpdate
        self._currentID = State(initialValue: initial.id)
    }

    private var isPageable: Bool { entries.count > 1 }

    private var currentIndex: Int {
        entries.firstIndex { $0.id == currentID } ?? 0
    }

    var body: some View {
        if isPageable {
            pagedBody
        } else {
            // Single entry — no rail, no scroll container, no behavior change.
            HistoryDetailSheet(entry: entries[0], onUpdate: onUpdate)
        }
    }

    private var pagedBody: some View {
        VStack(spacing: 0) {
            // Book order — oldest sheet first, today last — turned on a
            // hinge. `.book` is what names the VoiceOver actions "Older" and
            // "Newer" the right way round; see App/HingePager.swift.
            HingePager(
                items: entries,
                selection: $currentID,
                locked: $pagingLocked,
                order: .book
            ) { entry in
                HistoryDetailSheet(entry: entry, onUpdate: onUpdate)
            }
            .frame(maxHeight: .infinity)

            PageTurnRail(
                entries: entries,
                currentID: $currentID,
                index: currentIndex
            )
        }
        .background(Color.drip.background)
        .environment(\.pageTurnLocked, $pagingLocked)
        .onChange(of: currentID) { old, new in
            guard old != nil, new != nil, old != new else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .onChange(of: entries.map(\.id)) { oldIDs, ids in
            // The feed reloads after an edit or delete. If the page we were on
            // is gone, land on the nearest surviving neighbour — the entry that
            // slid into its slot — instead of snapping back to the top of the
            // journal, which is where a naive `ids.first` would dump us.
            guard let currentID, !ids.contains(currentID) else { return }
            let removedAt = oldIDs.firstIndex(of: currentID) ?? 0
            self.currentID = ids.indices.contains(removedAt) ? ids[removedAt] : ids.last
        }
        // Custom actions are only surfaced by VoiceOver when the container is
        // itself an accessibility element.
        .accessibilityElement(children: .contain)
        // The turn actions — still named for time, not screen direction — moved
        // to `HingePager`, which derives the wording from `HingeOrder.book`.
    }
}

// MARK: - Page rail

/// The date spine along the bottom edge — a scrollable strip of every entry in
/// the run, so the athlete can see where they are in the journal and jump
/// several pages at once. Filled tick = a run; hollow tick = a note or check-in
/// with no workout attached.
///
/// Runs left-to-right oldest-to-newest, matching the pages above it — the
/// journal's whole timeline laid out the way a book's spine would be.
private struct PageTurnRail: View {
    let entries: [TrainingLog]
    @Binding var currentID: UUID?
    let index: Int

    var body: some View {
        VStack(spacing: 0) {
            DripHairline()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(entries) { entry in
                                tick(for: entry)
                                    .id(entry.id)
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

                // Page number, book-style: the newest entry is the last page, so
                // opening today's run reads "128/128" and flipping back counts
                // down. That's the honest number for a diary — it says how far
                // into the journal you are, not how far down a list.
                Text("\(index + 1)/\(entries.count)")
                    .font(.dripEyebrow(9))
                    .tracking(0.9)
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(.leading, 10)
                    .padding(.trailing, 24)
                    .accessibilityLabel("Page \(index + 1) of \(entries.count)")
            }
            .frame(height: 46)
        }
        .background(Color.drip.background)
    }

    @ViewBuilder
    private func tick(for entry: TrainingLog) -> some View {
        let isCurrent = entry.id == currentID

        Button {
            withAnimation(.snappy(duration: 0.28)) { currentID = entry.id }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(
                        isCurrent ? Color.drip.coral : Color.drip.textTertiary,
                        lineWidth: 1
                    )
                    .background(
                        Circle().fill(
                            entry.hasLinkedWorkout
                                ? (isCurrent ? Color.drip.coral : Color.drip.textTertiary)
                                : Color.clear
                        )
                    )
                    .frame(width: 5, height: 5)

                Text(Self.railDate(entry.displayDate))
                    .font(.dripEyebrow(9))
                    .tracking(1.0)
                    .foregroundStyle(isCurrent ? Color.drip.coral : Color.drip.textTertiary)
            }
            .frame(minWidth: 54)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityDate(entry.displayDate))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    // Formatters are cached — the rail rebuilds these on every scroll frame
    // otherwise, and `DateFormatter` allocation is not cheap.
    private static let railFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let accessibilityFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    static func railDate(_ date: Date) -> String {
        railFormatter.string(from: date).uppercased()
    }

    static func accessibilityDate(_ date: Date) -> String {
        accessibilityFormatter.string(from: date)
    }
}
