import Auth
import Supabase
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
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var fitnessPredictor = FitnessPredictorService()
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
            .task {
                if healthKitManager.recentWorkouts.isEmpty {
                    _ = await healthKitManager.requestAuthorization()
                    let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 30)
                    await MainActor.run { healthKitManager.recentWorkouts = workouts }
                }
                await trainingPlanVM.loadActivePlan()
                await fitnessPredictor.predictFitness(
                    plan: trainingPlanVM.activePlan,
                    healthKitManager: healthKitManager
                )
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

        var payload: [String: Any] = [
            "message": message
        ]
        if let convId = conversationId {
            payload["conversationId"] = convId
        }
        let summary = buildWorkoutSummary()
        if !summary.isEmpty {
            payload["workoutSummary"] = summary
        }
        let planContext = buildTrainingPlanContext()
        if !planContext.isEmpty {
            payload["trainingPlanContext"] = planContext
        }
        let fitnessPreds = buildFitnessPredictions()
        if !fitnessPreds.isEmpty {
            payload["fitnessPredictions"] = fitnessPreds
        }

        do {
            let token = (try? await supabase.auth.session)?.accessToken ?? supabaseAnonKey
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    private func buildWorkoutSummary() -> String {
        let workouts = healthKitManager.recentWorkouts
        guard !workouts.isEmpty else { return "" }

        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recent = workouts.filter { $0.startDate >= fourWeeksAgo }
        guard !recent.isEmpty else { return "" }

        // Summary stats
        let totalMiles = recent.reduce(0.0) { $0 + $1.distanceMiles }
        let totalMinutes = recent.reduce(0.0) { $0 + $1.durationMinutes }
        let avgPace = totalMiles > 0 ? totalMinutes / totalMiles : 0

        // Find fastest paces
        let paces = recent.filter { $0.distanceMiles > 0.5 }
            .map { $0.durationMinutes / $0.distanceMiles }
            .sorted()

        var lines: [String] = []
        lines.append("Last 4 weeks: \(recent.count) runs, \(String(format: "%.1f", totalMiles)) mi total, avg pace \(formatPace(avgPace))/mi")

        if let fastest = paces.first {
            lines.append("Fastest avg pace: \(formatPace(fastest))/mi")
        }

        // Last 5 individual workouts
        lines.append("Recent runs:")
        for workout in recent.prefix(5) {
            let pace = workout.distanceMiles > 0 ? workout.durationMinutes / workout.distanceMiles : 0
            let dateStr = workout.shortDate
            lines.append("  \(dateStr): \(workout.formattedDistance) in \(workout.formattedDuration) (\(formatPace(pace))/mi)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatPace(_ paceMinPerMile: Double) -> String {
        guard paceMinPerMile > 0 else { return "--:--" }
        let totalSeconds = Int((paceMinPerMile * 60).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func buildTrainingPlanContext() -> String {
        guard let plan = trainingPlanVM.activePlan else { return "" }

        var lines: [String] = []

        // A. Plan overview
        lines.append("Plan: \(plan.name)")
        lines.append("Target: \(plan.targetRaceDistance) in \(plan.formattedGoalTime) (race pace \(plan.formattedRacePace))")
        lines.append("Week \(plan.currentWeek) of \(plan.totalWeeks), \(plan.daysRemaining) days to race")
        let weeksOut = plan.totalWeeks - plan.currentWeek
        let phase = CanovaTrainingPhase.fromWeeksOut(weeksOut)
        lines.append("Phase: \(phase.displayName)")

        // B. Training pace zones — both /mi and /km
        if let paces = trainingPlanVM.equivalentPaces {
            let mp = paces.mpPace
            let fmtMi = EquivalentPaces.formatPace
            let fmtKm = PaceCalculator.formatPaceKm

            lines.append("")
            lines.append("Training pace zones (use ONLY these values, never calculate your own):")
            lines.append("  Easy: \(fmtMi(mp / 0.75)) (\(fmtKm(mp / 0.75))/km) or slower — for easy runs, recovery, warm-up/cool-down")
            lines.append("  Moderate: \(fmtMi(mp / 0.75)) - \(fmtMi(mp / 0.85)) (\(fmtKm(mp / 0.75)) - \(fmtKm(mp / 0.85))/km) — for general aerobic, long runs")
            lines.append("  Steady: \(fmtMi(mp / 0.85)) - \(fmtMi(mp / 0.95)) (\(fmtKm(mp / 0.85)) - \(fmtKm(mp / 0.95))/km) — for steady state runs")
            lines.append("  MP: \(fmtMi(mp)) (\(fmtKm(mp))/km) — marathon pace")
            lines.append("  HMP: \(fmtMi(paces.hmPace)) (\(fmtKm(paces.hmPace))/km) — half marathon pace, use for TEMPO and THRESHOLD runs")
            lines.append("  10K: \(fmtMi(paces.tenKPace)) (\(fmtKm(paces.tenKPace))/km) — for longer intervals (800m-mile repeats)")
            lines.append("  5K: \(fmtMi(paces.fiveKPace)) (\(fmtKm(paces.fiveKPace))/km) — for short intervals and reps (200-400m)")

            // C. Pre-computed splits
            let fmtSplit = PaceCalculator.formatSplit
            let mpSplits = PaceCalculator.calculateSplits(paceSecondsPerMile: mp)
            let hmpSplits = PaceCalculator.calculateSplits(paceSecondsPerMile: paces.hmPace)
            let tenKSplits = PaceCalculator.calculateSplits(paceSecondsPerMile: paces.tenKPace)
            let fiveKSplits = PaceCalculator.calculateSplits(paceSecondsPerMile: paces.fiveKPace)

            lines.append("")
            lines.append("Pre-computed splits (use ONLY these, never calculate):")
            lines.append("  MP splits: 400m=\(fmtSplit(mpSplits.fourHundred)), 1K=\(fmtSplit(mpSplits.oneK)), mile=\(fmtSplit(mpSplits.mile))")
            lines.append("  HMP/Tempo splits: 400m=\(fmtSplit(hmpSplits.fourHundred)), 1K=\(fmtSplit(hmpSplits.oneK)), mile=\(fmtSplit(hmpSplits.mile))")
            lines.append("  10K splits: 400m=\(fmtSplit(tenKSplits.fourHundred)), 1K=\(fmtSplit(tenKSplits.oneK)), mile=\(fmtSplit(tenKSplits.mile))")
            lines.append("  5K splits: 400m=\(fmtSplit(fiveKSplits.fourHundred)), 1K=\(fmtSplit(fiveKSplits.oneK)), mile=\(fmtSplit(fiveKSplits.mile))")
        }

        // D. Goal vs fitness comparison
        if let predictions = fitnessPredictor.predictions {
            let planDistance = plan.targetRaceDistance.lowercased()
            if let matchingRace = predictions.races.first(where: { $0.distance.lowercased() == planDistance || (planDistance == "marathon" && $0.distance == "MARATHON") || (planDistance == "half" && $0.distance == "HALF") }) {
                let predictedSeconds = parseTimeToSeconds(matchingRace.time)
                let planSeconds = plan.targetTimeSeconds
                lines.append("")
                lines.append("Goal vs current fitness:")
                lines.append("  Plan target: \(plan.raceDistance.displayName) in \(plan.formattedGoalTime) (\(plan.formattedRacePace))")
                lines.append("  Predicted fitness: \(plan.raceDistance.displayName) in \(matchingRace.time) (\(matchingRace.pace))")
                if let predicted = predictedSeconds {
                    if predicted < Int(Double(planSeconds) * 0.97) {
                        lines.append("  Status: Fitness exceeds plan target — ahead of schedule")
                    } else if predicted > Int(Double(planSeconds) * 1.03) {
                        lines.append("  Status: Fitness is behind plan target — may need to adjust expectations")
                    } else {
                        lines.append("  Status: On track — fitness matches plan target")
                    }
                }
            }
        }

        // E. This week's schedule
        let weekWorkouts = trainingPlanVM.currentWeekWorkouts
        if !weekWorkouts.isEmpty {
            lines.append("")
            lines.append("This week's schedule:")
            for w in weekWorkouts {
                var detail = "  \(w.shortDayName): \(w.workoutType.displayName)"
                if let cw = w.workout, let dist = cw.totalDistanceMiles {
                    detail += " (\(String(format: "%.1f", dist)) mi)"
                }
                if w.status == .completed {
                    detail += " [done]"
                }
                lines.append(detail)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildFitnessPredictions() -> String {
        guard let predictions = fitnessPredictor.predictions else { return "" }

        var lines: [String] = []
        lines.append("Confidence: \(predictions.dataSources.confidence) (\(predictions.dataSources.workoutCount) workouts analyzed)")
        lines.append("Predicted race times (use ONLY these values):")
        for race in predictions.races {
            if race.distance == "MILE" { continue }
            if let secs = parsePaceToSeconds(race.pace) {
                lines.append("  \(race.distance): \(race.time) (\(race.pace), \(PaceCalculator.formatPaceKm(secs))/km)")
            } else {
                lines.append("  \(race.distance): \(race.time) (\(race.pace))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func parsePaceToSeconds(_ paceString: String) -> Double? {
        let cleaned = paceString.replacingOccurrences(of: "/mi", with: "")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let mins = Double(parts[0]),
              let secs = Double(parts[1]) else { return nil }
        return mins * 60 + secs
    }

    private func parseTimeToSeconds(_ timeString: String) -> Int? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        } else if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return nil
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
