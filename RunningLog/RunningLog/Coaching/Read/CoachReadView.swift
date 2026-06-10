//
//  CoachReadView.swift
//  RunningLog
//
//  The Coach Read page. Replaces the legacy `CoachView` chat UI in
//  the Coach tab (self-coached path). Composes the five primitives
//  from Phase 3 into the editorial layout from the design mock:
//
//    Plate strip → Dateline → Byline → Headline → ReadProse →
//    Signature → CantSeeBlock (if present) → SourcesPanel →
//    ConfidenceBar → Editorial rule → Ask bar (pinned).
//
//  Data comes from `DailyReadService.shared`, which already
//  refreshes on app launch + foreground. Pull-to-refresh forces a
//  re-fetch; the service short-circuits on the existing completed
//  row when there's nothing new.
//
//  Phase 4.1 of coach-the-read-prompts.md.
//

import SwiftUI

struct CoachReadView: View {
    @State private var service = DailyReadService.shared

    // Sheet-routing state — chips write their id here, this view
    // reads and presents the matching detail sheet.
    @State private var selectedWorkoutId: UUID?
    @State private var selectedDocId: UUID?

    // Ask-bar local state. Submit handler is a placeholder in v1 —
    // Phase 4.2 wires it into `service.ask()` and the reply view.
    @State private var askText = ""
    @State private var showingAskComingSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let read = service.todayRead {
                    plateStrip
                    dateline(for: read)
                    coachByline(for: read)
                    headline(for: read)
                    prose(for: read)
                    signatureLine(for: read)

                    if let cantSee = read.cantSee {
                        CantSeeBlock(block: cantSee)
                            .padding(.top, 16)
                    }

                    SourcesPanel(
                        sources: read.sources,
                        workouts: service.workoutsById,
                        docs: service.docsById,
                        selectedWorkoutId: $selectedWorkoutId,
                        selectedDocId: $selectedDocId
                    )
                    .padding(.top, 12)

                    ConfidenceBar(confidence: read.confidence)
                        .padding(.top, 4)

                    editorialRule
                        .padding(.vertical, 24)
                } else if service.isLoading {
                    skeleton
                } else if service.lastError != nil {
                    errorState
                } else {
                    // No row yet, not loading, no error — first launch
                    // on a brand-new account before refresh has fired.
                    skeleton
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            askBar
        }
        .sheet(item: workoutSheetItem) { item in
            // Detail sheet for a workout chip tap. The actual
            // workout-detail surface lives elsewhere in the app;
            // for v1 we present a lightweight summary.
            workoutDetailSheet(for: item.id)
        }
        .sheet(item: docSheetItem) { item in
            if let doc = service.docsById[item.id] {
                DocDetailSheet(doc: doc)
            }
        }
        .alert("Ask the coach — coming soon", isPresented: $showingAskComingSoon) {
            Button("OK") { askText = "" }
        } message: {
            Text("Question replies ship in the next update.")
        }
    }

    // MARK: - Sub-views

    /// Two stacked rows on each side, ink/ink-2 split — matches the
    /// `PlateStrip` primitive in `ui_kits/ios_app/Primitives.jsx`.
    /// Left: brand line in ink, descriptor in ink-2. Right: figure
    /// number in ink; the optional bottom-right "edition" slot is
    /// dropped because the Read's date already lives in the dateline
    /// row below.
    private var plateStrip: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RUNNING LOG")
                    .foregroundStyle(Color.drip.textPrimary)
                Text("— COACH · THE READ")
                    .foregroundStyle(Color.drip.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("FIG. 14")
                    .foregroundStyle(Color.drip.textPrimary)
            }
        }
        .font(.dripStat(10))
        .tracking(1.4) // 0.14em × 10pt
        .padding(.bottom, 12)
    }

    /// "THU · MAY 14 · WK 9 / 16" + "↗ HISTORY".
    /// The week-of-block segment is omitted in modes other than
    /// PLAN_MODE — we'd need to fetch the active plan separately
    /// to compute it, and Phase 1's edge function already knows the
    /// mode but doesn't surface it to iOS. Future enhancement.
    private func dateline(for read: CoachRead) -> some View {
        HStack {
            Text(Self.datelineString(for: read.readDate))
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textPrimary)
                .tracking(1.3) // 0.12em × 11pt — section-eyebrow tracking
            Spacer()
            Button {
                // History view not yet wired — Phase 5+ feature.
            } label: {
                Text("↗ HISTORY")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.3)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 16)
    }

    /// 28pt black circle with coral border + "C" inside, then mono
    /// coral "FROM YOUR COACH · <weekday> <time>".
    private func coachByline(for read: CoachRead) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.drip.textPrimary)
                Circle()
                    .stroke(Color.drip.coral, lineWidth: 1.5)
                Text("C")
                    .font(.dripDisplay(14))
                    .foregroundStyle(Color.drip.background)
            }
            .frame(width: 28, height: 28)

            Text("FROM YOUR COACH · \(Self.bylineTimeString(for: read.generatedAt))")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.coral)
                .tracking(1.3) // 0.12em × 11pt — coral section eyebrow
        }
        .padding(.bottom, 12)
    }

    /// 32pt display headline. Line-height 1.02 — tight, magazine-cover
    /// register. Approximated via lineSpacing since SwiftUI's `Text`
    /// doesn't expose explicit line-height.
    private func headline(for read: CoachRead) -> some View {
        Text(read.headline)
            .font(.dripDisplay(32))
            .foregroundStyle(Color.drip.textPrimary)
            .lineSpacing(0) // tight; 1.02 lh ≈ default at this size
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
        .padding(.bottom, 16)
    }

    /// "— posted <weekday> morning · N min read" in italic body 12pt.
    private func signatureLine(for read: CoachRead) -> some View {
        Text(Self.signatureString(for: read))
            .font(.dripBody(12))
            .italic()
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.bottom, 8)
    }

    /// Editorial rule: short line · dot · short line, centered.
    /// Same primitive used elsewhere in the design — kept inline
    /// here because no shared component exists yet.
    private var editorialRule: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
        .frame(maxWidth: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - States

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Byline placeholder.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(width: 160, height: 12)
                .padding(.top, 40)

            // Headline placeholder — two lines.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.drip.divider)
                .frame(maxWidth: 240)
                .frame(height: 36)

            // Paragraph placeholder — four lines.
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.drip.divider)
                        .frame(height: 14)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load today's read.")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Pull to refresh.")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            TextField("Ask the coach…", text: $askText)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .submitLabel(.send)
                .onSubmit {
                    // Phase 4.2 will replace this with the real
                    // service.ask() → CoachReplyView push.
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
                .overlay(
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity, alignment: .top),
                    alignment: .top
                )
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
                            .font(.dripStat(10))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(0.8)
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

    /// "THU · MAY 14" for now. Plan-week segment ("WK 9 / 16") is
    /// gated on a plan fetch we haven't wired yet.
    private static func datelineString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: date).uppercased()
    }

    /// "THU 7:41 AM" — the byline's time stamp.
    private static func bylineTimeString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f.string(from: date).uppercased()
    }

    /// "— posted Thursday morning · 3 min read".
    private static func signatureString(for read: CoachRead) -> String {
        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: "en_US_POSIX")
        dayF.dateFormat = "EEEE"
        let day = dayF.string(from: read.generatedAt)
        let words = read.paragraph.reduce(into: 0) { acc, seg in
            if case .text(let s) = seg {
                acc += s.split { !$0.isLetter }.count
            }
        }
        // Generous reading-rate floor — short Reads read fast.
        let mins = max(1, Int((Double(words) / 220.0).rounded(.up)))
        return "— posted \(day) morning · \(mins) min read"
    }
}

/// Wrapper so we can drive `.sheet(item:)` from a `UUID?` binding.
private struct UUIDItem: Identifiable, Hashable {
    let id: UUID
}
