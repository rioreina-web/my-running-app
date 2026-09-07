//
//  AskWildHomeView.swift
//  RunningLog · Analysis · Ask
//
//  The Ask tab. Replaces `AskTipsView` (2026-08-31).
//
//  WHAT CHANGED AND WHY. The old tab landed on four tips, with the chat one
//  tap down and the composer three screens deep — on a surface whose entire
//  job is letting the athlete ask something. Two things lead here instead:
//
//    A · The question. The field is the first thing on the screen and the
//        composer is live at the foot of every state. A cycling example
//        shows the range without fixing a list; there is no menu to get past.
//    B · Pulls. The handful of questions worth keeping, as blocks that
//        recompute from the athlete's own rows and can be taken apart —
//        metric, window, comparison, chart, name, order.
//
//  Direction I throughout (`POSTRUNDRIPSYSTEM.md`), which makes Ask the
//  second tab on the new system after Log. Rendered unconditionally rather
//  than behind `DripSkinStore`: this REPLACES the old tab, so there is no
//  editorial variant to fall back to. `AskTipsView` stays in the repo,
//  unlinked, as `AskBar` and `WelcomeCard` did before it.
//
//  COMPOSER PLACEMENT IS LOAD-BEARING. It sits in a `.safeAreaInset`, not a
//  `VStack` with the scroll view. A vertical-axis `TextField` that grows its
//  own height, put opposite a ScrollView in a VStack, negotiates height
//  forever and spins the app at 97% CPU — that is a real outage this app has
//  had (see `CoachView`). The `.padding(.bottom, 56)` clears `DripTabBar`,
//  whose own inset does not reach inside a tab's NavigationStack.
//

import Combine
import SwiftUI

struct AskWildHomeView: View {

    @State private var service = AskPullService.shared
    @State private var store = AskPullStore.shared
    @State private var chat = CoachChatViewModel()
    @State private var editingPull: UUID?
    @FocusState private var composerFocused: Bool

    private var isEmpty: Bool { chat.messages.isEmpty && !chat.isLoading }

    /// What the composer suggests when it is empty. A SINGLE fixed example —
    /// no auto-rotation. This used to cycle through six questions on a 3.4s
    /// timer; asked to stop, and correctly: an input field that keeps
    /// changing what it says while you're deciding what to type is a bigger
    /// ask on attention than a placeholder should ever be.
    private var placeholder: String {
        // Neutral and open, not a diagnostic. "Am I ramping too fast?" put a
        // worry in the athlete's head before they had one, and a leading
        // question is a fixed list of one. This asks for the whole picture and
        // leaves what matters to them.
        isEmpty ? "How is my training going right now?" : "Ask about your training"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead
                    if isEmpty {
                        askHero
                        pullsSection
                        // Nothing is pinned to the bottom in this state, so
                        // the scroll has to clear DripTabBar itself.
                        Color.clear.frame(height: 96)
                    } else {
                        thread
                    }
                    Color.clear.frame(height: 24).id("bottom")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(Color.wild.paper.ignoresSafeArea())
        // THE COMPOSER MOVES. Empty, it is the hero at the top of the page and
        // there is no bottom bar at all — a thin input pinned under three
        // charts makes the charts the subject and asking an afterthought.
        // Once a thread exists the question has been asked, the answers are
        // the subject, and the composer belongs back at the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isEmpty {
                // Background outside the tab-bar padding: inside it, the 56pt
                // gap is transparent and the scroll view shows through.
                bottomComposer
                    .padding(.bottom, 56)
                    .background(Color.wild.paper)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { await service.load() }
        .refreshable { await service.load(force: true) }
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                // The reset used to be a bare "new" text label tucked after
                // the coverage stat on the row below — real, but nothing
                // about it read as "back", so asking a question felt like a
                // one-way door. A leading chevron in the conventional
                // top-left spot is the one affordance nobody has to be told
                // about.
                if !chat.messages.isEmpty {
                    Button { chat.startNewConversation() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Ask")
                                .font(.wildDisplay(22))
                                .tracking(22 * -0.035)
                        }
                        .foregroundStyle(Color.wild.ink)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Ask")
                        .font(.wildDisplay(22))
                        .tracking(22 * -0.035)
                        .foregroundStyle(Color.wild.ink)
                }
                Spacer()
                WildLabel(Self.today, size: 9, tracking: 0.18)
            }
            HStack(spacing: 8) {
                Circle().fill(Color.wild.red).frame(width: 5, height: 5)
                Text(service.coverage)
                    .font(.wildData(10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.wild.ink2)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.top, 6)
            WildRule(strong: true).padding(.top, 9)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    private static var today: String {
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d"
        return f.string(from: Date())
    }

    // MARK: Hero — the ask leads

    /// The ask, as the page's hero.
    ///
    /// TYPE ROLES, because this block got them wrong twice.
    ///
    ///   • The HEADLINE is Instrument Sans. Direction I's hierarchy is built
    ///     on a tight grotesk display against everything else; a hero whose
    ///     largest element was 27pt Crimson had no display voice at all and
    ///     read soft. Scale comes from the display face, never from inflating
    ///     another role past its spec.
    ///   • The INPUT is Crimson at 20, which is the prose role at its stated
    ///     size (`POSTRUNDRIPSYSTEM.md` §1: 20px/1.48). Prose is right here
    ///     because this is the athlete writing — the same call, for the same
    ///     reason, as the voice-log writing surface in `LogWildView`, which
    ///     sets its "How did the run feel?" prompt in prose and says in a
    ///     comment why it is not mono italic.
    ///   • The DEK is Times italic, the one role it has.
    ///
    /// The headline is a question rather than a label so it does not become
    /// the fourth "Ask" on a screen that already carries it in the masthead
    /// and the tab bar.
    private var askHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you want to know?")
                .font(.wildDisplay(31))
                .tracking(31 * -0.035)
                .lineSpacing(-2)
                .foregroundStyle(Color.wild.ink)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.wild.red)
                .frame(width: 34, height: 3)
                .padding(.top, 16)

            HStack(alignment: .bottom, spacing: 12) {
                TextField(placeholder, text: $chat.inputText, axis: .vertical)
                    .font(.wildProse(20))
                    .foregroundStyle(Color.wild.ink)
                    .tint(Color.wild.red)
                    .focused($composerFocused)
                    .lineLimit(1 ... 4)
                    .submitLabel(.send)
                    .onSubmit { ask(chat.inputText) }
                sendButton(size: 48, red: true)
            }
            .padding(.top, 20)

            Text("Every answer is computed from your own runs, and shows the rows it read.")
                .font(.wildDek(16))
                .foregroundStyle(Color.wild.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private func sendButton(size: CGFloat, red: Bool) -> some View {
        let idle = chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isLoading
        return Button { ask(chat.inputText) } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(Color.wild.paper)
                .frame(width: size, height: size)
                .background(Circle().fill(
                    idle ? Color.wild.ink3 : (red ? Color.wild.red : Color.wild.ink)))
        }
        .buttonStyle(.plain)
        .disabled(idle)
        .accessibilityLabel("Ask")
    }

    // MARK: Pulls

    private var pullsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No "edit" here. It opened the first pull's editor, which is
            // exactly what that pull's own ··· does — a second control for a
            // job one control already has, the same duplication as the
            // "ask about this ›" that used to sit under every block. The slot
            // still earns its keep as the load indicator.
            sectionHead("Your pulls",
                        trailing: service.isLoading ? "loading" : "",
                        action: nil)

            ForEach(Array(store.pulls.enumerated()), id: \.element.id) { index, pull in
                AskPullBlock(
                    reading: service.reading(for: pull),
                    isEditing: editingPull == pull.id,
                    canMoveUp: index > 0,
                    canMoveDown: index < store.pulls.count - 1,
                    onOpenEditor: { editingPull = editingPull == pull.id ? nil : pull.id },
                    onAsk: { ask(Self.question(for: pull)) },
                    onChange: { updated in
                        if let i = store.pulls.firstIndex(where: { $0.id == updated.id }) {
                            store.pulls[i] = updated
                        }
                    },
                    onMove: { up in store.move(pull.id, up: up) },
                    onRemove: { editingPull = nil; store.remove(pull.id) },
                    onDone: { editingPull = nil }
                )
            }

            if !store.unusedMetrics.isEmpty {
                Button {
                    guard let next = store.unusedMetrics.first else { return }
                    store.add(next)
                    editingPull = store.pulls.last?.id
                } label: {
                    Text("＋ NEW PULL")
                        .font(.wildLabel(9))
                        .tracking(9 * 0.18)
                        .foregroundStyle(Color.wild.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(Rectangle().strokeBorder(Color.wild.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // MARK: Suggested
    //
    // REMOVED 2026-09-01. A standing "Suggested pulls" section put three more
    // questions under the three seeded ones, so the tab opened on six things
    // to read before the composer. The remaining metrics are still one tap
    // away behind "New pull", which is the same discovery without the
    // standing cost — a suggestion the athlete has to scroll past every visit
    // is not a suggestion, it is furniture.

    private func sectionHead(_ title: String, trailing: String, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WildRule(strong: true)
            HStack {
                WildLabel(title, size: 10, tracking: 0.18)
                Spacer()
                if let action {
                    Button(action: action) {
                        WildLabel(trailing, size: 9, tracking: 0.18, color: Color.wild.redText)
                    }
                    .buttonStyle(.plain)
                } else {
                    WildLabel(trailing, size: 9, tracking: 0.18)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: Thread

    private var thread: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(chat.messages) { message in
                if message.role == .user {
                    VStack(alignment: .leading, spacing: 0) {
                        // The athlete's own words, in Crimson.
                        Text(message.content)
                            .font(.wildProse(20))
                            .foregroundStyle(Color.wild.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 12)
                        WildRule()
                    }
                    .padding(.top, 20)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        // Roman mono is the machine. Never Crimson (that would
                        // read as a person's own conclusion) and never italic
                        // (that borrows the athlete's voice).
                        Text(message.content)
                            .font(.wildMachine(13))
                            .lineSpacing(3)
                            .foregroundStyle(Color.wild.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if let metric = Self.metric(for: message.content),
                           !store.pulls.contains(where: { $0.metric == metric }) {
                            Button { store.add(metric) } label: {
                                Text("＋ PIN \(metric.short.uppercased()) AS A PULL")
                                    .font(.wildLabel(9)).tracking(9 * 0.16)
                                    .foregroundStyle(Color.wild.redText)
                                    .padding(.horizontal, 11).padding(.vertical, 7)
                                    .overlay(Capsule().strokeBorder(Color.wild.red, lineWidth: 1))
                            }
                            .buttonStyle(.plain).frame(minHeight: 0)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }

            if chat.isLoading {
                HStack(spacing: 7) {
                    Circle().fill(Color.wild.red).frame(width: 5, height: 5)
                    WildLabel("Reading your rows", size: 9, tracking: 0.18)
                }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: Composer

    private var bottomComposer: some View {
        VStack(spacing: 0) {
            WildRule(strong: true)
            HStack(spacing: 8) {
                TextField(placeholder, text: $chat.inputText, axis: .vertical)
                    .font(.wildProse(18))
                    .foregroundStyle(Color.wild.ink)
                    .focused($composerFocused)
                    .lineLimit(1 ... 5)
                    .submitLabel(.send)
                    .onSubmit { ask(chat.inputText) }
                    .padding(.leading, 12)
                    .padding(.vertical, 6)
                sendButton(size: 44, red: false)
                    .padding(.trailing, 4)
            }
            .padding(.vertical, 5)
            .overlay(Rectangle().strokeBorder(Color.wild.rule, lineWidth: 1))
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(Color.wild.paper)
    }

    // MARK: Asking

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chat.isLoading else { return }
        chat.inputText = trimmed
        composerFocused = false
        // The context is the same figures the athlete's own pulls are showing,
        // so a reply that contradicts the screen is visible immediately.
        chat.sendMessage(workoutSummary: service.contextBlock(),
                         planContext: "",
                         fitnessPredictions: "")
    }

    /// The question a pull asks when tapped. Phrased as the athlete would.
    private static func question(for pull: AskPull) -> String {
        switch pull.metric {
        case .weeklyMiles:      return "Am I ramping too fast?"
        case .acwr:             return "What is my acute to chronic ratio doing?"
        case .longRunShare:     return "Is my long run too big a slice of the week?"
        case .easyShare:        return "Are my easy days actually easy?"
        case .thresholdMinutes: return "How much threshold work am I doing?"
        case .qualityLoad:      return "How hard have my key sessions been?"
        case .sleepHours:       return "How has my sleep been?"
        case .restingHR:        return "What is my resting heart rate doing?"
        case .bodyMentions:     return "What have I been saying about my body?"
        }
    }

    /// Cheap keyword map so an answer worth keeping can become a pull without
    /// a builder. Deliberately conservative: no match means no chip, rather
    /// than pinning something the athlete did not ask about.
    private static func metric(for reply: String) -> AskMetric? {
        let s = reply.lowercased()
        if s.contains("resting heart") || s.contains("resting hr") { return .restingHR }
        if s.contains("sleep") { return .sleepHours }
        if s.contains("acute") || s.contains("acwr") { return .acwr }
        if s.contains("threshold") { return .thresholdMinutes }
        if s.contains("quality load") { return .qualityLoad }
        if s.contains("long run") { return .longRunShare }
        if s.contains("easy day") || s.contains("easy run") { return .easyShare }
        if s.contains("mileage") || s.contains("weekly volume") { return .weeklyMiles }
        return nil
    }
}
