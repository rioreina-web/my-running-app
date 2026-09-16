//
//  AskTipsView.swift
//  RunningLog · Analysis · Tips
//
//  The Ask tab's landing surface: three or four things that would move the
//  goal, drawn from what the athlete has actually run.
//
//  Replaces the analyzer-chip idea that Ask was originally going to carry. A
//  chip per metric answers "what is my X" — useful, but it puts the work of
//  deciding what matters back on the athlete. This answers "what would help",
//  which is the question they actually arrived with.
//
//  The free-text chat (`CoachView`) is still here, one tap down, for anything
//  the tips don't cover. Moving it behind a tap also defers its HealthKit
//  authorisation prompt, which is why `AskTabView` used to need a lazy-mount
//  flag.
//
//  Self-contained styling on purpose: the `Week*` primitives would do, but
//  they are named for another surface and this one shouldn't inherit its
//  layout decisions.
//

import SwiftUI

struct AskTipsView: View {

    @State private var engine = TipEngine.shared
    @State private var showChat = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if engine.isLoading && engine.tips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if engine.tips.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(engine.tips.prefix(TipEngine.slots).enumerated()),
                            id: \.element.id) { index, tip in
                        tipCard(tip, number: index + 1)
                    }
                }

                chatCard
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(Color.drip.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await engine.refresh() }
        .refreshable { await engine.refresh(force: true) }
        .navigationDestination(isPresented: $showChat) { CoachView() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow("What would move the goal", tint: Color.drip.coral)

            Text(titleLine)
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let goal = engine.goal {
                Text(goalLine(goal))
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textSecondary)
            } else {
                Text("Set a goal and these get sharper — right now they read your training on its own terms.")
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleLine: String {
        guard let goal = engine.goal else { return "Four things." }
        return goal.title.isEmpty ? "\(goal.timeLabel) \(goal.raceLabel)." : "\(goal.title)."
    }

    private func goalLine(_ goal: TipGoal) -> String {
        var parts: [String] = ["\(goal.racePaceLabel)/mi"]
        if let weeks = goal.weeksOut { parts.append("\(weeks) weeks out") }
        parts.append("from your last 4 weeks of running")
        return parts.joined(separator: " · ")
    }

    // MARK: Tip card

    private func tipCard(_ tip: TrainingTip, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(tip.category.label.uppercased())
                    .font(.dripEyebrow(9))
                    .tracking(0.9)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tip.category.tint))
                Spacer()
                Text("\(number)")
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Text(tip.headline)
                .font(.dripDisplay(21))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Text(tip.observation)
                .font(.dripBody(13.5))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            // The action, on a coral spine — the one thing to take away.
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.drip.coral)
                    .frame(width: 2)
                Text(tip.action)
                    .font(.dripBody(13.5))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

            if !tip.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tip.evidence, id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tip.category.tint)
                                .frame(width: 5, height: 5)
                            Text(line.uppercased())
                                .font(.dripEyebrow(9))
                                .tracking(0.7)
                                .foregroundStyle(Color.drip.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .padding(.top, 14)
    }

    // MARK: States

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing worth flagging.")
                .font(.dripDisplay(21))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Either there isn't enough training on file yet, or none of the checks found a gap big enough to be worth your attention. Both are honest answers, and the second one is a good one.")
                .font(.dripBody(13.5))
                .italic()
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 16)
    }

    private var chatCard: some View {
        Button {
            showChat = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow("Something else", tint: Color.drip.textSecondary)
                    Text("Ask anything")
                        .font(.dripDisplay(19))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
    }

    private func eyebrow(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.dripEyebrow(11))
            .tracking(1.3)
            .foregroundStyle(tint)
    }
}
