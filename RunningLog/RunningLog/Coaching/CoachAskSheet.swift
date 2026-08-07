//
//  CoachAskSheet.swift
//  RunningLog
//
//  The Ask surface. Presented from the `AskBar` at the foot of Trends, and
//  from any surface that stages a question via `CoachAskContext` (e.g. a
//  chart scrub pre-seeding "the week of May 26").
//
//  TWO ANSWER PATHS, tried in that order:
//
//    1. COMPUTED (`ask` edge function). The question routes to one analyzer
//       in `_shared/analyzers/`, which runs real math over the athlete's own
//       rows and returns fact lines, a chart spec and a coverage statement.
//       A model then writes two sentences over those facts and is
//       mechanically forbidden from speaking a number that isn't in them.
//       Chips take this path with no router involved at all.
//
//    2. PROSE (`coaching-agent`, via `DailyReadService.ask`). When the
//       registry has no analyzer for the question — "what should I eat before
//       a long run" — the endpoint says so (`mode: "prose"`) and we hand the
//       question to the editorial agent instead. This is the pre-existing
//       behaviour, now reached deliberately rather than by default.
//
//  The fallthrough is what makes free text safe to ship: the worst case for
//  an unroutable question is today's product, never a wrong number.
//
//  `CoachAskFeature.isEnabled` still gates the prose path (it depends on the
//  editorial Read's eval coverage). The computed path has its own gate,
//  `AskFeature.isEnabled`, because its prompt is guarded differently — every
//  numeric token is checked against the facts before the sentence renders.
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
        /// The prose fallthrough — no analyzer fit.
        case reply(CoachRead)
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
                        AskAnswerCard(question: question, response: response) { followup in
                            Task { await run(analyzerId: followup.id, question: followup.label) }
                        }
                    case let .reply(read):
                        replyView(read)
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

    /// Free text. Tries the registry first, falls through to the coaching
    /// agent when nothing fits.
    private func ask() async {
        let question = trimmed
        guard !question.isEmpty else { return }
        phase = .loading
        detent = .large

        if AskFeature.isEnabled {
            do {
                let response = try await AskService.shared.resolve(question: question)
                if response.mode != .prose {
                    phase = .analyzed(question: question, response: response)
                    return
                }
                // No analyzer fit — fall through to prose below.
            } catch {
                phase = .failed(AskService.message(for: error))
                return
            }
        }

        guard CoachAskFeature.isEnabled else {
            phase = .failed("That one needs the coach, and coach replies aren't live yet.")
            return
        }

        do {
            let read = try await DailyReadService.shared.ask(question)
            phase = .reply(read)
        } catch {
            phase = .failed("Couldn't reach the coach just now. Try again in a moment.")
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
