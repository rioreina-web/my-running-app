//
//  SessionAskBlock.swift
//  RunningLog
//
//  "Ask this session" — one field, a rail of questions, one prose answer.
//  Replaces the single `insightBlock` row on the workout detail sheet.
//
//  Lives in `Workouts/` because it is part of the sheet's editorial layout and
//  uses the sheet's typography (`dripEyebrow(10)`, `tracking(1.2)`), not the
//  Trends `AskBar`'s.
//
//  IT OWNS NO INSIGHT LOGIC. `summaryText`, `memoTranscriptUrl` and
//  `generateThenReveal()` are private members of the `HistoryDetailSheet`
//  extension, and `showInsight` is `@State` on the sheet. A block reaching for
//  them wouldn't compile. Closures in, no shared state.
//
//  Layout matches `session-ask-prototype.html` (the `.askblock` / `.askbar` /
//  `.rail` / `.chip` / `.more` / `.prose` / `.src` rules).
//
//  SESSION-ASK-APPLY.md §4.
//

import SwiftUI

struct SessionAskBlock: View {
    /// `training_logs.id`. `HistoryDetailEntry.id` is a UUID.
    let workoutId: UUID
    /// "AUG 18" — built at the call site, the only place the file-private
    /// `Date.editorialDateString` helper is visible.
    let dateLabel: String

    // ── the read chip's state, all owned by the sheet ──
    let hasInsight: Bool
    let canGenerateInsight: Bool
    let isGenerating: Bool
    let hasInsightError: Bool
    let onReadTapped: () -> Void

    @State private var text = ""
    @State private var answer: SessionAskService.Answer?
    @State private var askedQuestion: String?
    @State private var isAsking = false
    @State private var askError: String?
    @State private var showAll = false
    @FocusState private var fieldFocused: Bool

    /// The pager's page-turn lock (`HistoryDetailPager`). While the athlete is
    /// typing, a horizontal drag must not turn the page: UIKit is also trying
    /// to keep the focused field on screen, and the two fight — the page
    /// drifts, or a swipe that was meant to move the cursor flips the entry
    /// and takes the half-typed question with it. The lock already exists for
    /// the telemetry scrubber; this is the same problem.
    ///
    /// Defaults to `.constant(false)` when no pager is hosting us (a
    /// single-entry sheet), so the write is simply discarded.
    @Environment(\.pageTurnLocked) private var pageTurnLocked

    /// Mirrored from `session-questions.ts:COLD_START_QUESTIONS`. `suggested`
    /// arrives with the first answer, so on a cold sheet the rail shows three
    /// questions that apply to any run at all. An empty rail reads as broken;
    /// a generic one reads as not-loaded-yet, which is what it is. These three
    /// strings living in two places is the one duplication in this design and
    /// it is deliberate.
    private static let coldStartQuestions = [
        "Was this the right session for where I am right now?",
        "How does this compare to the last one like it?",
    ]

    // The rail shows five; the rest go behind the disclosure. RAIL_SIZE on the
    // server is 5 and the read chip occupies the first slot, so four follow.
    private static let railSize = 4

    private var suggestions: [String] {
        if let answer, !answer.suggested.isEmpty {
            return answer.suggested.map(\.text)
        }
        return Self.coldStartQuestions
    }

    private var railQuestions: [String] { Array(suggestions.prefix(Self.railSize)) }

    /// Changes whenever the rail's chips change text — the signal
    /// `SessionAskChipFlow` uses to throw away cached chip sizes. Cheap:
    /// hashing five short strings once per body, against re-measuring five
    /// wrapped paragraphs of Crimson Pro on every layout pass.
    private var railCacheKey: Int {
        var hasher = Hasher()
        hasher.combine(showAll)
        hasher.combine(hasInsight)
        hasher.combine(isGenerating)
        hasher.combine(hasInsightError)
        hasher.combine(canGenerateInsight)
        for q in suggestions { hasher.combine(q) }
        return hasher.finalize()
    }
    private var restQuestions: [String] { Array(suggestions.dropFirst(Self.railSize)) }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            askBar.padding(.top, 11)
            rail.padding(.top, 12)

            if !restQuestions.isEmpty {
                moreButton.padding(.top, 12)
            }

            if isAsking {
                loadingRow
            } else if let askError {
                errorRow(askError)
            } else if let answer {
                answerView(answer)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { DripHairline() }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .onChange(of: fieldFocused) { _, focused in
            pageTurnLocked.wrappedValue = focused
        }
        // Paging away, closing the sheet, or the block being swapped out while
        // the field still holds focus would otherwise leave the pager locked.
        .onDisappear { pageTurnLocked.wrappedValue = false }
    }

    // ── .abhead ──────────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("✦")
                .font(.system(size: 11))
                .foregroundStyle(Color.drip.coral)
            Text("ASK THIS SESSION")
                .font(.dripEyebrow(9.5)).tracking(1.3)
                .foregroundStyle(Color.drip.textPrimary)
            Spacer(minLength: 8)
            Text(dateLabel)
                .font(.dripEyebrow(8.5)).tracking(1.0)
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    // ── .askbar ──────────────────────────────────────────────
    private var askBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this run…", text: $text)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit { submit(text) }
                .disabled(isAsking)

            Button {
                submit(text)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canSubmit ? Color.drip.background : Color.drip.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(canSubmit ? Color.drip.textPrimary : Color.drip.paperDeep)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .animation(.easeInOut(duration: 0.15), value: canSubmit)
        }
        .padding(.leading, 15)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.drip.cardBackgroundElevated)
        )
        .overlay(
            Capsule().strokeBorder(
                fieldFocused ? Color.drip.textSecondary : Color.drip.divider,
                lineWidth: 1
            )
        )
        .animation(.easeInOut(duration: 0.15), value: fieldFocused)
    }

    // ── .rail ────────────────────────────────────────────────
    private var rail: some View {
        // `key` invalidates the layout's measurement cache: the chips are
        // whole sentences, and a new answer brings a new set of them.
        SessionAskChipFlow(spacing: 6, key: railCacheKey) {
            readChip
            ForEach(railQuestions, id: \.self) { q in
                questionChip(q)
            }
            if showAll {
                ForEach(restQuestions, id: \.self) { q in
                    questionChip(q)
                }
            }
        }
    }

    /// The read chip — five states, the same priority order `insightBlock`
    /// used. A re-skin of a working state machine, not a new one.
    /// `generateCoachInsight()` and `saveCoachInsight(_:)` are not touched;
    /// only the affordance moves.
    @ViewBuilder
    private var readChip: some View {
        let label: String = {
            if hasInsight { return "What's the read on this session?" }
            if isGenerating { return "WRITING YOUR READ…" }
            if hasInsightError { return "COULDN'T GET IT · RETRY" }
            if canGenerateInsight { return "What's the read on this session?" }
            return "THE READ NEEDS A MEMO"
        }()
        let enabled = hasInsight || hasInsightError || (canGenerateInsight && !isGenerating)
        let dashed = !enabled && !isGenerating

        Button { onReadTapped() } label: {
            HStack(spacing: 5) {
                if isGenerating {
                    ProgressView()
                        .tint(Color.drip.coral)
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                } else {
                    Text("✦")
                        .font(.system(size: 10))
                        .foregroundStyle(enabled ? Color.drip.coral : Color.drip.textTertiary)
                }
                Text(label)
                    .font(.dripEyebrow(10)).tracking(0.4)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(enabled ? Color.drip.textPrimary : Color.drip.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(enabled ? Color.drip.coralWash : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    enabled ? Color.drip.coral.opacity(0.4) : Color.drip.divider,
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // ── .chip ────────────────────────────────────────────────
    private func questionChip(_ question: String) -> some View {
        Button { submit(question) } label: {
            Text(question)
                .font(.dripEyebrow(10)).tracking(0.4)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.drip.cardBackgroundElevated))
                .overlay(Capsule().strokeBorder(Color.drip.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isAsking)
    }

    // ── .more ────────────────────────────────────────────────
    private var moreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
        } label: {
            Text(showAll ? "FEWER QUESTIONS ⌃" : "MORE QUESTIONS ⌄")
                .font(.dripEyebrow(9)).tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // ── .load ────────────────────────────────────────────────
    private var loadingRow: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.drip.coral)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())
            Text("READING THIS SESSION…")
                .font(.dripEyebrow(9.5)).tracking(1.2)
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(.vertical, 26)
    }

    // ── .dashed (error) ──────────────────────────────────────
    private func errorRow(_ message: String) -> some View {
        Text(message.uppercased())
            .font(.dripEyebrow(9)).tracking(1.1)
            .foregroundStyle(Color.drip.textTertiary)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    Color.drip.divider,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            )
            .padding(.top, 15)
    }

    // ── .prose + .src ────────────────────────────────────────
    // Renders inline beneath the field. No sheet: `AskAnswerCard` exists to
    // lay out a fact grid, a chart and a band switcher, and this surface
    // renders none of them. What remains is a paragraph and a line of small
    // type (§5.4).
    @ViewBuilder
    private func answerView(_ answer: SessionAskService.Answer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let askedQuestion {
                Text(askedQuestion)
                    .font(.dripDisplay(19))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }

            // Paragraph breaks are meaningful here — the prompt is told a
            // trade-off earns several short paragraphs — so split rather than
            // rendering one slab.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(paragraphs(of: answer.answer), id: \.self) { para in
                    Text(para)
                        .font(.dripBody(15))
                        .lineSpacing(4)
                        .foregroundStyle(Color.drip.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let readFrom = answer.readFrom, !readFrom.isEmpty {
                Text(readFrom.uppercased())
                    .font(.dripCaption(10)).tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .overlay(alignment: .top) { DripHairline() }
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 15)
    }

    private func paragraphs(of body: String) -> [String] {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // ── ask ──────────────────────────────────────────────────
    private func submit(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }

        fieldFocused = false
        askedQuestion = trimmed
        askError = nil
        text = ""
        isAsking = true

        Task {
            defer { isAsking = false }
            do {
                let result = try await SessionAskService.shared.ask(trimmed, workoutId: workoutId)
                withAnimation(.easeInOut(duration: 0.2)) {
                    answer = result
                    // A fresh rail comes back with every answer, so collapse
                    // the disclosure — leaving it open would show the previous
                    // session's overflow against the new suggestions.
                    showAll = false
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    answer = nil
                    askError = "Couldn't get an answer · tap a question to retry"
                }
            }
        }
    }
}

/// Wrapping chip rail — the prototype's `.rail { display:flex; flex-wrap:wrap }`.
///
/// A dedicated layout rather than `DripFlowLayout` or `FlowRow`: both size
/// their subviews with `sizeThatFits(.unspecified)`, which for a Text asks
/// "how wide if you never wrap". The chips here hold whole questions ("Was
/// this the right session for where I am right now?"), so that measurement
/// runs off the edge of the sheet. This proposes the container width to each
/// chip, letting a long one wrap internally the way the CSS flex item does —
/// which is why the prototype bothers to set `line-height` and `text-align`
/// on `.chip` at all.
private struct SessionAskChipFlow: Layout {
    var spacing: CGFloat = 6

    /// Identifies the current set of chips. When it changes, cached sizes are
    /// thrown away. See `SessionAskBlock.railCacheKey`.
    var key: Int = 0

    /// Measured chip sizes, held across layout passes.
    ///
    /// `Layout` offers a cache precisely so text isn't re-measured on every
    /// pass, and this rail is measured a lot: it lives in the same view as the
    /// "Ask about this run…" field, so **every keystroke** re-runs its layout.
    /// Measuring a wrapped question ("Was this the right session for where I
    /// am right now?") in a custom serif face is the slow kind of layout work,
    /// and until this cache existed it happened up to twice per chip per pass
    /// — once in `sizeThatFits`, then all over again in `placeSubviews`.
    struct Cache {
        var key: Int = 0
        var width: CGFloat = -1
        var count: Int = -1
        var sizes: [CGSize] = []

        var isEmpty: Bool { sizes.isEmpty }
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // A different rail (new answer, disclosure toggled, read chip changed
        // state) invalidates every measurement.
        if cache.key != key || cache.count != subviews.count { cache = Cache() }
    }

    private func sizes(_ subviews: Subviews, maxWidth: CGFloat, cache: inout Cache) -> [CGSize] {
        if !cache.isEmpty, cache.key == key, cache.width == maxWidth, cache.count == subviews.count {
            return cache.sizes
        }
        let measured = subviews.map { subview -> CGSize in
            let ideal = subview.sizeThatFits(.unspecified)
            guard ideal.width > maxWidth else { return ideal }
            // Too wide for a row: re-measure, capped, so it wraps its text.
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        cache = Cache(key: key, width: maxWidth, count: subviews.count, sizes: measured)
        return measured
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let measured = sizes(subviews, maxWidth: maxWidth, cache: &cache)

        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for size in measured {
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let measured = sizes(subviews, maxWidth: bounds.width, cache: &cache)

        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for (index, size) in measured.enumerated() {
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The pulsing dot from the prototype's `.load` row (`@keyframes pulse`).
private struct PulseModifier: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.25 : 1)
            .animation(
                .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
    }
}
