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

import SwiftUI

struct CoachAskSheet: View {
    let focus: String?
    /// When non-nil the sheet skips the composer and runs this analyzer on
    /// appear — the chip path. The athlete already said what they wanted.
    let analyzer: AskAnalyzer?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var phase: Phase = .compose

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
    }

    private var eyebrow: String {
        if let focus { return "ASK · \(focus.uppercased())" }
        return analyzer == nil ? "ASK THE COACH" : "ASK"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(eyebrow)
                        .font(.dripEyebrow(10))
                        .tracking(1.3)
                        .foregroundStyle(Color.drip.coral)

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
                        Text(message)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.tired)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.drip.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .task {
            guard let analyzer, phase == .compose else { return }
            await run(analyzerId: analyzer.id, question: analyzer.label)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .font(.dripBody(16))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )

            if AskFeature.isEnabled || CoachAskFeature.isEnabled {
                Button {
                    Task { await ask() }
                } label: {
                    Text("Ask")
                        .font(.dripLabel(15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.coral)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || phase == .loading
                )
            } else {
                Text("Answers aren't live yet — this is the question we'll ask once the analysis surface ships.")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.drip.coral)
            Text(analyzer == nil ? "Reading…" : "Running the numbers…")
                .font(.dripBody(14))
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

    /// Run one analyzer by id — the chip and follow-up path.
    private func run(analyzerId: String, question: String) async {
        phase = .loading
        do {
            let response = try await AskService.shared.resolve(analyzerId: analyzerId)
            phase = .analyzed(question: question, response: response)
        } catch {
            phase = .failed(AskService.message(for: error))
        }
    }

    /// Free text. Tries the registry first, falls through to the coaching
    /// agent when nothing fits.
    private func ask() async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        phase = .loading

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
