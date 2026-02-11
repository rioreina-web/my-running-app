import SwiftUI

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var sources: [DocumentSource]?

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), sources: [DocumentSource]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sources = sources
    }
}

// MARK: - DocumentSource

struct DocumentSource: Codable {
    let title: String
    let category: String
}

// MARK: - CoachResponse

struct CoachResponse: Codable {
    let response: String?
    let conversationId: String?
    let sources: [DocumentSource]?
    let error: String?
    let remaining: Int?
    let resetAt: String?
    let limit: Int?
    let cached: Bool?
    let model: String?
    let processingTime: Int?
}

// MARK: - RateLimitState

struct RateLimitState {
    var remaining: Int = 999
    var limit: Int = 5
    var resetAt: Date?
    var isLimited: Bool {
        remaining <= 0
    }
}

// MARK: - CoachView

struct CoachView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var conversationId: String?
    @State private var rateLimit = RateLimitState()
    @State private var showRateLimitAlert = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        mainContent
            .background(DripBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(
                    text: $inputText,
                    isLoading: isLoading,
                    isFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
            .navigationTitle("")
            .toolbar { toolbarContent }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { keyboardToolbar }
            .alert("Daily Limit Reached", isPresented: $showRateLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rateLimitMessage)
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messagesListView
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { isInputFocused = false }
            .onChange(of: messages.count) { scrollToLastMessage(proxy: proxy) }
            .onChange(of: isLoading) { scrollToLoading(proxy: proxy) }
            .onChange(of: isInputFocused) { scrollToBottom(proxy: proxy) }
        }
    }

    private var messagesListView: some View {
        LazyVStack(spacing: 16) {
            if messages.isEmpty, !isLoading {
                WelcomeCard()
                    .padding(.top, 40)
            }

            ForEach(messages) { message in
                ChatBubble(message: message)
                    .id(message.id)
            }

            if isLoading {
                TypingIndicator()
                    .id("loading")
            }

            Color.clear
                .frame(height: 20)
                .id("bottom")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SidebarMenuButton()
        }
        ToolbarItem(placement: .principal) {
            titleView
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                PaceChartView()
            } label: {
                Image(systemName: "speedometer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.drip.coral)
            }
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { isInputFocused = false }
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.coral)
        }
    }

    private var titleView: some View {
        VStack(spacing: 2) {
            Text("COACH")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(2)

            if rateLimit.remaining < 999 {
                Text("\(rateLimit.remaining)/\(rateLimit.limit) today")
                    .font(.dripCaption(9))
                    .foregroundStyle(rateLimit.remaining <= 1 ? Color.drip.coral : Color.drip.textTertiary)
            }
        }
    }

    private var newConversationButton: some View {
        Button { startNewConversation() } label: {
            Image(systemName: "plus.bubble")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.drip.coral)
        }
    }

    private var rateLimitMessage: String {
        if let resetAt = rateLimit.resetAt {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "You've used all \(rateLimit.limit) questions for today. Questions reset at \(formatter.string(from: resetAt))."
        }
        return "You've used all \(rateLimit.limit) questions for today. Questions reset at midnight UTC."
    }

    // MARK: - Scroll Helpers

    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
        }
    }

    private func scrollToLoading(proxy: ScrollViewProxy) {
        if isLoading {
            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isInputFocused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)

        let messageToSend = inputText
        inputText = ""
        isLoading = true

        Task {
            await callCoachingAgent(message: messageToSend)
        }
    }

    private func callCoachingAgent(message: String) async {
        guard let url = URL(string: "\(supabaseURL)/functions/v1/coaching-agent") else {
            await MainActor.run {
                isLoading = false
                appendErrorMessage("Unable to connect to coach")
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        // Include a pseudo userId for rate limiting (in production, use actual user ID)
        var payload: [String: Any] = [
            "message": message,
            "userId": UIDevice.current.identifierForVendor?.uuidString ?? "anonymous"
        ]
        if let convId = conversationId {
            payload["conversationId"] = convId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            let coachResponse = try JSONDecoder().decode(CoachResponse.self, from: data)

            // Handle rate limiting (429)
            if httpResponse?.statusCode == 429 {
                await MainActor.run {
                    isLoading = false
                    rateLimit.remaining = 0

                    // Parse reset time if available
                    if let resetAtString = coachResponse.resetAt {
                        let formatter = ISO8601DateFormatter()
                        rateLimit.resetAt = formatter.date(from: resetAtString)
                    }

                    if let limit = coachResponse.limit {
                        rateLimit.limit = limit
                    }

                    showRateLimitAlert = true
                    appendErrorMessage("You've reached your daily limit. Your questions reset at midnight UTC.")
                }
                return
            }

            // Handle server errors
            guard httpResponse?.statusCode == 200 else {
                throw NSError(
                    domain: "CoachError",
                    code: httpResponse?.statusCode ?? 500,
                    userInfo: [NSLocalizedDescriptionKey: coachResponse.error ?? "Server error"]
                )
            }

            // Handle error in response body
            if let error = coachResponse.error {
                await MainActor.run {
                    isLoading = false
                    appendErrorMessage(error)
                }
                return
            }

            await MainActor.run {
                // Update rate limit state
                if let remaining = coachResponse.remaining {
                    rateLimit.remaining = remaining
                }

                // Update conversation
                if let convId = coachResponse.conversationId {
                    conversationId = convId
                }

                // Add response message
                if let responseText = coachResponse.response {
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: responseText,
                        sources: coachResponse.sources
                    )
                    messages.append(assistantMessage)
                }

                isLoading = false
            }

        } catch {
            await MainActor.run {
                isLoading = false
                appendErrorMessage("Sorry, I couldn't process that. Please try again.")
            }
        }
    }

    private func appendErrorMessage(_ text: String) {
        let errorMessage = ChatMessage(role: .assistant, content: text)
        messages.append(errorMessage)
    }

    private func startNewConversation() {
        messages = []
        conversationId = nil
        inputText = ""
    }
}

// MARK: - WelcomeCard

struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("Hey, I'm Coach")
                    .font(.dripDisplay(24))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Your AI running coach. Ask me about training, recovery, mindset, or anything running-related.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 12) {
                SuggestionChip(text: "How should I recover after a long run?")
                SuggestionChip(text: "I'm feeling tired lately, should I rest?")
                SuggestionChip(text: "Tips for race day nerves?")
            }
            .padding(.top, 12)

            // Quick Links
            VStack(spacing: 10) {
                // Fitness Predictor Link
                NavigationLink {
                    FitnessPredictorView(trainingViewModel: TrainingPlanViewModel())
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fitness Predictor")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("AI-powered race time predictions")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(14)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Pace Chart Link
                NavigationLink {
                    PaceChartView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pace Chart")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("View training paces based on your goal")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(14)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - SuggestionChip

struct SuggestionChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(Color.drip.coral)

            Text(text)
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(Capsule())
    }
}

// MARK: - ChatBubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Coach avatar
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: "figure.run")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                }
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .font(.dripBody(15))
                    .foregroundStyle(message.role == .user ? .white : Color.drip.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user
                            ? Color.drip.coral
                            : Color.drip.cardBackground
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                message.role == .user ? Color.clear : Color.drip.divider,
                                lineWidth: 1
                            )
                    )

                // Sources badge for assistant messages
                if message.role == .assistant, let sources = message.sources, !sources.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 10))
                        Text("Based on: \(sources.map(\.title).joined(separator: ", "))")
                            .font(.dripCaption(10))
                    }
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                // User avatar
                ZStack {
                    Circle()
                        .fill(Color.drip.energized.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.drip.energized)
                }
            } else {
                Spacer()
            }
        }
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Coach avatar
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
            }

            HStack(spacing: 4) {
                ForEach(0 ..< 3) { index in
                    Circle()
                        .fill(Color.drip.textSecondary)
                        .frame(width: 8, height: 8)
                        .opacity(dotOpacity[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )

            Spacer()
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0 ..< 3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.15)
            ) {
                dotOpacity[i] = 1.0
            }
        }
    }
}

// MARK: - ChatInputBar

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask your coach...", text: $text, axis: .vertical)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .focused(isFocused)
                .lineLimit(1 ... 5)
                .submitLabel(.send)
                .onSubmit(onSend)

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? Color.drip.textTertiary
                            : Color.drip.coral)
                        .frame(width: 44, height: 44)

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.drip.background
                .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
        )
    }
}

#Preview {
    NavigationStack {
        CoachView()
    }
}
