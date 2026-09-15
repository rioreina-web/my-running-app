//
//  CoachReadView.swift
//  RunningLog
//
//  The Coach Read page — the Coach tab for the self-coached path.
//
//  Shape (2026-09-15, "read design clarity" pass):
//
//      FROM YOUR COACH · TUE · SEP 15          ← eyebrow: who + when
//      Tempos are coming down.                 ← headline: the one thing
//      [paragraph with inline ◆ / § chips]     ← feeling → work → volume → watch
//      TO SIT WITH                             ← 1-2 soft questions, italic,
//      │ How did Sunday's 16 feel…                coral-at-50% left bar
//      │ ONE DATA POINT                        ← cant-see block (gray bar)
//      READ FROM · 5 WORKOUTS · 2 MEMOS ▪▪▫ MED← one-line basis, expands
//      ── · ──                                 ← editorial rule
//      [Ask the coach…]                        ← pinned ask bar
//
//  What came out, and why: the plate strip ("RUNNING LOG · FIG. 14"),
//  the C-avatar byline, the "posted Thursday morning · 3 min read"
//  signature, a dead "↗ HISTORY" link, and a separate confidence row.
//  None of them helped the athlete understand what the coach was
//  saying; together they were more chrome than content. The decisions
//  log (`outputs/maya-product-roadmap-2026-05-28.md`, "Coach format:
//  minimal") called for eyebrow + headline + paragraph + questions.
//  Rationale and the content shape live in
//  `outputs/coach-read-clarity-2026-09-15.md`.
//
//  Data comes from `DailyReadService.shared`, which refreshes on app
//  launch + foreground. Pull-to-refresh forces a re-fetch; the service
//  short-circuits on the existing completed row when there's nothing
//  new.
//

import SwiftUI

struct CoachReadView: View {
    @State private var service = DailyReadService.shared

    // Sheet-routing state — chips write their id here, this view
    // reads and presents the matching detail sheet.
    @State private var selectedWorkoutId: UUID?
    @State private var selectedDocId: UUID?

    // Ask-bar local state. Submit handler is a placeholder in v1 —
    // the conversational reply flow lands with `service.ask()`.
    @State private var askText = ""
    @State private var showingAskComingSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let read = service.todayRead {
                    eyebrow(for: read)
                    headline(for: read)
                    prose(for: read)

                    SoftQuestionsBlock(questions: read.questions)
                        .padding(.top, read.questions.isEmpty ? 0 : 20)

                    if let cantSee = read.cantSee {
                        CantSeeBlock(block: cantSee)
                            .padding(.top, 20)
                    }

                    SourcesPanel(
                        sources: read.sources,
                        confidence: read.confidence,
                        workouts: service.workoutsById,
                        docs: service.docsById,
                        selectedWorkoutId: $selectedWorkoutId,
                        selectedDocId: $selectedDocId
                    )
                    .padding(.top, 24)

                    EditorialRule()
                        .frame(maxWidth: 200)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if service.isLoading {
                    skeleton
                } else if service.lastError != nil {
                    EmptyStateView(
                        variant: .error,
                        eyebrow: "The read",
                        title: "Couldn't load today's read. Pull down to try again."
                    )
                    .padding(.top, 40)
                } else {
                    EmptyStateView(
                        variant: .dataPending,
                        eyebrow: "The read",
                        title: "No read yet. Pull down and the coach will read your week."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.drip.background.ignoresSafeArea())
        .refreshable {
            try? await service.refresh()
        }
        .task {
            // The app refreshes on launch/foreground; this covers the
            // first visit on a fresh install before that has fired.
            if service.todayRead == nil && !service.isLoading {
                try? await service.refresh()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            askBar
        }
        .sheet(item: workoutSheetItem) { item in
            workoutDetailSheet(for: item.id)
        }
        .sheet(item: docSheetItem) { item in
            if let doc = service.docsById[item.id] {
                DocDetailSheet(doc: doc)
            }
        }
        .alert("Ask the coach", isPresented: $showingAskComingSoon) {
            Button("OK") { askText = "" }
        } message: {
            Text("Question replies ship in the next update.")
        }
    }

    // MARK: - Sub-views

    /// "FROM YOUR COACH · TUE · SEP 15". One coral eyebrow — the
    /// design system's "active section" use of coral — carrying both
    /// who is speaking and which day the Read is for. Replaces the
    /// plate strip, the dateline row and the avatar byline.
    private func eyebrow(for read: CoachRead) -> some View {
        Text("FROM YOUR COACH · \(Self.datelineString(for: read.readDate))")
            .font(.dripEyebrow(11))
            .foregroundStyle(Color.drip.coral)
            .tracking(1.3) // 0.12em × 11pt — section-eyebrow tracking
            .padding(.bottom, 12)
            .accessibilityLabel("From your coach, \(Self.accessibleDateString(for: read.readDate))")
    }

    /// 32pt display headline — the one thing this Read is about. The
    /// validator guarantees the trailing period (design rule: every
    /// standalone headline ends in a period).
    private func headline(for read: CoachRead) -> some View {
        Text(read.headline)
            .font(.dripDisplay(32))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(0)
            .padding(.bottom, 16)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The flowing paragraph with inline chips.
    private func prose(for read: CoachRead) -> some View {
        ReadProse(
            segments: read.paragraph,
            workouts: service.workoutsById,
            docs: service.docsById,
            selectedWorkoutId: $selectedWorkoutId,
            selectedDocId: $selectedDocId
        )
    }

    // MARK: - States

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Eyebrow placeholder.
            SkeletonBar(width: 180, height: 12)
                .padding(.top, 8)

            // Headline placeholder — two lines.
            SkeletonBar(height: 34)
            SkeletonBar(width: 220, height: 34)

            // Paragraph placeholder — four lines.
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBar(height: 14)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            TextField("Ask the coach…", text: $askText)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .submitLabel(.send)
                .onSubmit {
                    if !askText.trimmingCharacters(in: .whitespaces).isEmpty {
                        showingAskComingSoon = true
                    }
                }

            Button {
                if !askText.trimmingCharacters(in: .whitespaces).isEmpty {
                    showingAskComingSoon = true
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        askText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.drip.textTertiary
                            : Color.drip.coral
                    )
            }
            .buttonStyle(.plain)
            .disabled(askText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.drip.cardBackground
                .overlay(alignment: .top) {
                    Hairline()
                }
        )
    }

    // MARK: - Sheet routing

    /// Bridge between the `Binding<UUID?>` chips write to and the
    /// `Identifiable` shape `.sheet(item:)` expects.
    private var workoutSheetItem: Binding<UUIDItem?> {
        Binding(
            get: { selectedWorkoutId.map(UUIDItem.init) },
            set: { selectedWorkoutId = $0?.id }
        )
    }
    private var docSheetItem: Binding<UUIDItem?> {
        Binding(
            get: { selectedDocId.map(UUIDItem.init) },
            set: { selectedDocId = $0?.id }
        )
    }

    @ViewBuilder
    private func workoutDetailSheet(for id: UUID) -> some View {
        if let workout = service.workoutsById[id] {
            // Minimal v1 — full WorkoutDetailView integration can
            // come later. For now we show the workout's basic info.
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(Self.workoutTitle(for: workout))
                            .font(.dripDisplay(24))
                            .foregroundStyle(Color.drip.textPrimary)
                        if let meta = workout.coachReadMetaLine {
                            Text(meta)
                                .font(.dripEyebrow(11))
                                .tracking(1.1)
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        if let notes = workout.cleanedNotes ?? workout.notes {
                            Text(notes)
                                .font(.dripBody(15))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineSpacing(4)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.drip.background.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("WORKOUT")
                            .font(.dripEyebrow(10))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)
                    }
                }
            }
        }
    }

    private static func workoutTitle(for workout: TrainingLog) -> String {
        let type = (workout.workoutType ?? "run").capitalized
        if let mi = workout.workoutDistanceMiles {
            return String(format: "%.1f mi %@", mi, type)
        }
        return type
    }

    // MARK: - Date helpers

    /// "TUE · SEP 15". `read_date` is a date-only value decoded at UTC
    /// midnight, so format it in UTC too or a US-evening device would
    /// show the previous day.
    private static func datelineString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE · MMM d"
        return f.string(from: date).uppercased()
    }

    /// "Tuesday, September 15" — for VoiceOver.
    private static func accessibleDateString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }
}

/// Wrapper so we can drive `.sheet(item:)` from a `UUID?` binding.
private struct UUIDItem: Identifiable, Hashable {
    let id: UUID
}
