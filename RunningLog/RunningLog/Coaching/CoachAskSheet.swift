//
//  CoachAskSheet.swift
//  RunningLog
//
//  The Ask surface. Presented from the `AskBar` at the foot of Trends, and
//  from any surface that stages a question via `CoachAskContext` (e.g. a
//  chart scrub pre-seeding "the week of May 26").
//
//  TWO ANSWER PATHS. Which one leads depends on how the question was asked:
//
//    • A CHIP is a request for a specific computed answer, so it takes the
//      COMPUTED path only (`ask` edge function → one analyzer in
//      `_shared/analyzers/` → real math over the athlete's own rows → fact
//      lines, chart spec, coverage). A model then writes two sentences over
//      those facts and is mechanically forbidden from speaking a number that
//      isn't in them. No router, no cost, no paragraph.
//
//    • TYPED TEXT leads with PROSE (`coaching-agent`, via
//      `DailyReadService.ask`) and hangs the computed card underneath as
//      receipts when an analyzer also matched.
//
//  THAT ORDER INVERTED ON 2026-08-10 (server flag `UNBOUND_ANSWERS`). It used
//  to be computed-first with prose as the fallthrough, which had two costs:
//  a question the router matched could never get a conversational answer, and
//  one it didn't match rendered "NO ANALYZER" at the athlete — the registry's
//  coverage gap dressed up as a verdict on their question. The registry is no
//  longer the ceiling for what can be asked.
//
//  What that trades away: prose is not number-guarded. The Layer-2 guard over
//  analyzer facts is untouched and still absolute, but the paragraph beside it
//  can speak a number the math didn't print. `AskFeature.freeTextEnabled`
//  carries the full ledger of what's still open.
//
//  Both paths keep their own gate — `AskFeature.isEnabled` for computed,
//  `CoachAskFeature.isEnabled` for prose — because their prompts are guarded
//  differently and one should be able to go dark without the other.
//
//  LAYOUT NOTE (2026-08-06 rebuild). The composer used to be a bare
//  `TextEditor` on a full-height sheet: a white box with a caret in it and
//  two thirds of the screen empty below. Three things changed and each is
//  load-bearing, so keep them if you reshape this file.
//
//    • **The catalog is the primary path, the field is the secondary one.**
//      Layer 1 is free and deterministic; free text pays for a router hop and
//      can miss. So the rail renders ABOVE the field, and the field is
//      introduced as the fallback ("or ask in your own words"). A blank box
//      in a product whose answer space is a closed enum of ~50 analyzers is
//      the surface failing to say what it knows.
//    • **The sheet is detented.** `.medium` while composing, promoted to
//      `.large` the moment there's an answer to read. A sheet sized for the
//      answer while you're still asking the question reads as broken.
//    • **One coral per cluster.** The eyebrow is the accent. The primary
//      button is therefore an ink capsule — the same "active" affordance
//      `AskGroupHeader` uses — not a second coral fill. See
//      `design-system/README.md`: coral is punctuation, not paint.
//

import SwiftUI
import os

struct CoachAskSheet: View {
    let focus: String?
    /// When non-nil the sheet skips the composer and runs this analyzer on
    /// appear — the chip path. The athlete already said what they wanted.
    let analyzer: AskAnalyzer?

    @Environment(\.dismiss) private var dismiss
    @State private var service = AskService.shared
    @State private var text: String
    @State private var phase: Phase = .compose
    @State private var detent: PresentationDetent
    @State private var showAllSuggestions = false
    /// Label of the variant being fetched. Held here rather than going through
    /// `.loading` so switching bands doesn't blank the answer you're reading —
    /// the card stays put and the tapped chip dims.
    @State private var pendingVariant: String?
    @FocusState private var fieldFocused: Bool

    /// How many analyzers the rail shows before the "all questions" door.
    /// Enough to demonstrate the range, few enough to scan at `.medium`.
    private static let suggestionPreviewCount = 8

    enum Phase: Equatable {
        case compose
        case loading
        /// A computed answer. Carries the question that produced it so the
        /// card can title itself after a follow-up replaces the content.
        case analyzed(question: String, response: AskResponse)
        /// A conversational answer to a typed question (2026-08-10). `card`
        /// carries the computed answer when one ALSO matched, rendered beneath
        /// the prose as its receipts — nil when nothing in the registry fit,
        /// which is now an ordinary outcome rather than a failure.
        case answered(question: String, read: CoachRead, card: AskResponse?)
        case failed(String)
    }

    init(question: String, focus: String?, analyzer: AskAnalyzer? = nil) {
        self.focus = focus
        self.analyzer = analyzer
        _text = State(initialValue: question)
        // A chip tap opens straight into an answer, so it opens tall. The
        // composer opens at half height — it has a field and a rail to show,
        // not an answer.
        _detent = State(initialValue: analyzer == nil ? .medium : .large)
    }

    private var eyebrow: String {
        if let focus { return "ASK · \(focus.uppercased())" }
        return analyzer == nil ? "ASK THE COACH" : "ASK"
    }

    /// The composer is live only while nothing has been asked. Once an answer
    /// is on screen the rail would compete with the follow-ups the answer
    /// itself emitted, which are better questions than our standing ones.
    private var isComposing: Bool { phase == .compose }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAsk: Bool { !trimmed.isEmpty && phase != .loading }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // A chip tap already asked its question; showing the
                    // composer above the answer would invite editing a
                    // question that isn't editable.
                    if analyzer == nil { composer }

                    switch phase {
                    case .compose:
                        EmptyView()
                    case .loading:
                        loadingView
                    case let .analyzed(question, response):
                        AskAnswerCard(
                            question: question,
                            response: response,
                            onFollowup: { followup in
                                Task { await run(analyzerId: followup.id, question: followup.label) }
                            },
                            onVariant: { variant in
                                Task { await switchTo(variant, of: response, question: question) }
                            },
                            pendingVariant: pendingVariant
                        )
                    case let .answered(question, read, card):
                        VStack(alignment: .leading, spacing: 22) {
                            replyView(read)
                            if let card {
                                receiptsHeader
                                AskAnswerCard(
                                    question: question,
                                    response: card,
                                    onFollowup: { followup in
                                        Task { await run(analyzerId: followup.id, question: followup.label) }
                                    },
                                    onVariant: { variant in
                                        Task { await switchTo(variant, of: card, question: question) }
                                    },
                                    pendingVariant: pendingVariant
                                )
                            }
                        }
                    case let .failed(message):
                        failureView(message)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Matches the close affordance used across the app's
                    // sheets (AddInjurySheet, HistoryView, ContentLibrary).
                    // A bare `Button("Close")` inherits the system's glass
                    // capsule, which is both oversized and off-system here.
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .task {
            await service.loadCatalog()
            guard let analyzer, phase == .compose else { return }
            await run(analyzerId: analyzer.id, question: analyzer.label)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.dripEyebrow(10))
                .tracking(1.3)
                .foregroundStyle(Color.drip.coral)

            if analyzer == nil, isComposing {
                Text("Every answer is computed from your own runs first, then put into words. Pick a question below, or write your own.")
                    .font(.dripBody(14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isComposing { suggestionRail }

            if AskFeature.freeTextEnabled {
                freeTextField
            }
        }
    }

    /// The standing rail, built from the server's `__catalog__` response.
    /// Tapping a chip runs Layer 1 directly — no router, and free — which is
    /// why this is the path we put first.
    @ViewBuilder
    private var suggestionRail: some View {
        if service.catalog.isEmpty {
            Text("The question list loads from the analysis service. It fills in once you're online.")
                .font(.dripBody(13.5))
                .foregroundStyle(Color.drip.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else if showAllSuggestions {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(service.groupedCatalog, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.title.uppercased())
                            .font(.dripEyebrow(9))
                            .tracking(1.2)
                            .foregroundStyle(Color.drip.textTertiary)
                        FlowRow(spacing: 6) {
                            ForEach(group.analyzers) { analyzer in
                                AskChip(label: analyzer.label) {
                                    ask(analyzer)
                                }
                            }
                        }
                    }
                }
                disclosureButton(
                    title: "Show fewer",
                    isExpanded: true
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("START HERE")
                    .font(.dripEyebrow(9))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
                FlowRow(spacing: 6) {
                    ForEach(Array(service.catalog.prefix(Self.suggestionPreviewCount))) { analyzer in
                        AskChip(label: analyzer.label) {
                            ask(analyzer)
                        }
                    }
                }
                if service.catalog.count > Self.suggestionPreviewCount {
                    disclosureButton(
                        title: "All \(service.catalog.count) questions",
                        isExpanded: false
                    )
                }
            }
        }
    }

    /// Deliberately not a `DripTextLink` — that primitive is coral, and the
    /// eyebrow already spends this cluster's one coral element.
    private func disclosureButton(title: String, isExpanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showAllSuggestions.toggle()
                if !isExpanded { detent = .large }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(1.1)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.drip.textSecondary)
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }

    private var freeTextField: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isComposing, !service.catalog.isEmpty {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 1)
                    Text("OR ASK IN YOUR OWN WORDS")
                        .font(.dripEyebrow(9))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textTertiary)
                        .fixedSize()
                    Rectangle()
                        .fill(Color.drip.divider)
                        .frame(height: 1)
                }
                .padding(.vertical, 2)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.dripBody(16))
                    .foregroundStyle(Color.drip.textPrimary)
                    .tint(Color.drip.coral)
                    .focused($fieldFocused)
                    .frame(minHeight: 68)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)

                if text.isEmpty {
                    // Hard rule #8 in spirit: an empty field says what it is
                    // for rather than sitting blank.
                    Text("Was last Tuesday's tempo actually faster, or just cooler out?")
                        .font(.dripBody(16))
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineSpacing(2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        fieldFocused ? Color.drip.textSecondary : Color.drip.divider,
                        lineWidth: 1
                    )
            )
            .onChange(of: fieldFocused) { _, focused in
                // The keyboard eats a half-height sheet. Go tall so the
                // field, the button and the answer all stay reachable.
                if focused { detent = .large }
            }

            if AskFeature.isEnabled || CoachAskFeature.isEnabled {
                askButton
            } else {
                Text("Answers aren't live yet — this is the question we'll ask once the analysis surface ships.")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// An ink capsule, not a coral one. `.buttonStyle(.plain)` does not dim a
    /// custom background when disabled, so the disabled state is drawn
    /// explicitly — the old version rendered full-saturation coral while
    /// inert, which read as tappable and did nothing.
    private var askButton: some View {
        Button {
            fieldFocused = false
            Task { await ask() }
        } label: {
            Text(phase == .loading ? "Asking…" : "Ask")
                .font(.dripLabel(15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(canAsk ? Color.drip.textPrimary : Color.drip.paperDeep)
                )
                .foregroundStyle(canAsk ? Color.drip.background : Color.drip.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!canAsk)
        .animation(.easeInOut(duration: 0.15), value: canAsk)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.drip.coral)
            Text(analyzer == nil ? "Reading…" : "Running the numbers…")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.dripBody(14))
                .lineSpacing(3)
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { phase = .compose }
            } label: {
                Text("TRY ANOTHER QUESTION")
                    .font(.dripEyebrow(9))
                    .tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.drip.cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    /// Names the computed card as evidence for the paragraph above it rather
    /// than a second, competing answer. The eyebrow is ink, not coral — the
    /// header already spent this cluster's one coral (design-system/README.md).
    private var receiptsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            EditorialRule()
            Text("THE NUMBERS BEHIND IT")
                .font(.dripEyebrow(10))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    /// The prose answer, unchanged from the editorial Read's shape.
    private func replyView(_ read: CoachRead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialRule()
            Text(read.headline)
                .font(.dripDisplay(22))
                .foregroundStyle(Color.drip.textPrimary)
            Text(plainText(read))
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(4)
            Text("\(read.confidence.level.rawValue) · \(read.confidence.sub)")
                .font(.dripEyebrow(10))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    // MARK: - Actions

    /// A chip on the standing rail. Fills the field with the question it
    /// stands for so the athlete can see what was asked, then runs it.
    private func ask(_ analyzer: AskAnalyzer) {
        fieldFocused = false
        text = analyzer.label
        detent = .large
        Task { await run(analyzerId: analyzer.id, question: analyzer.label) }
    }

    /// Run one analyzer by id — the chip and follow-up path.
    private func run(analyzerId: String, question: String) async {
        phase = .loading
        do {
            let response = try await AskService.shared.resolve(analyzerId: analyzerId)
            phase = .analyzed(question: question, response: response)
            detent = .large
        } catch {
            phase = .failed(AskService.message(for: error))
        }
    }

    /// Re-run the current analyzer against another of its variants — the zone
    /// switcher on the answer card.
    ///
    /// Deliberately does NOT pass through `.loading`: the athlete is comparing
    /// bands, and blanking the card between taps makes that comparison harder
    /// than it needs to be. A failure leaves the existing answer up and only
    /// clears the pending mark, because losing a good answer to a failed
    /// switch would be the worse outcome.
    private func switchTo(
        _ variant: AskVariant,
        of response: AskResponse,
        question: String
    ) async {
        guard !variant.active, pendingVariant == nil else { return }
        pendingVariant = variant.label
        defer { pendingVariant = nil }
        do {
            let next = try await AskService.shared.resolve(variant: variant, of: response)
            phase = .analyzed(question: next.resolvedTitle ?? question, response: next)
        } catch {
            phase = .failed(AskService.message(for: error))
        }
    }

    /// Free text.
    ///
    /// INVERTED 2026-08-10 (`UNBOUND_ANSWERS`). This used to try the registry
    /// first and only speak to the coach when nothing fit — so a question the
    /// router happened to match could never get a conversational answer, and
    /// one it didn't match reported "NO ANALYZER" at the athlete. Now the
    /// conversational answer leads for every typed question, and a matched
    /// analyzer rides underneath it as receipts.
    ///
    /// The two halves fail independently and on purpose: the computed card is
    /// worth nothing if it costs the athlete their answer, and the answer is
    /// still an answer with no card under it.
    private func ask() async {
        let question = trimmed
        guard !question.isEmpty else { return }
        fieldFocused = false
        phase = .loading
        detent = .large

        var card: AskResponse?

        if AskFeature.isEnabled {
            do {
                let response = try await AskService.shared.resolve(question: question)
                // A server that has re-bound `UNBOUND_ANSWERS` answers the old
                // way, and this client honours it: the card IS the answer.
                guard response.conversational else {
                    phase = .analyzed(question: question, response: response)
                    return
                }
                // Keep it as evidence only if it actually computed something —
                // a prose/ambiguous envelope carries no facts to show.
                if response.mode == .analyzed, !response.facts.isEmpty {
                    card = response
                }
            } catch {
                // Swallowed by design. Under the old order this was fatal
                // because the card was the only answer; now it just means the
                // paragraph arrives without receipts.
                Log.coach.error("ask: computed half failed, continuing to prose — \(error.localizedDescription)")
            }
        }

        guard CoachAskFeature.isEnabled else {
            phase = .failed("That one needs the coach, and coach replies aren't live yet.")
            return
        }

        do {
            let read = try await DailyReadService.shared.ask(question)
            phase = .answered(question: question, read: read, card: card)
        } catch {
            // Losing the coach doesn't have to mean losing a computed answer
            // we already hold.
            if let card {
                phase = .analyzed(question: question, response: card)
            } else {
                phase = .failed("Couldn't reach the coach just now. Try again in a moment.")
            }
        }
    }

    /// Flatten the reply to its prose (citations rendered inline are a
    /// future refinement; this strips them to plain text for now).
    private func plainText(_ read: CoachRead) -> String {
        read.paragraph
            .compactMap { if case let .text(s) = $0 { return s } else { return nil } }
            .joined()
    }
}
