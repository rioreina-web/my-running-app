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

// MARK: - Coach Check-In

struct CheckInContext {
    let logId: UUID
    let mood: String
    let cleanedNotes: String?
    let coachInsight: String?
}

@Observable
final class CoachCheckInManager {
    var pendingCheckIn: CheckInContext?
    var showBanner = false

    static let triggerMoods: Set<String> = ["tired", "struggling", "injured"]

    func trigger(logId: UUID, mood: String, cleanedNotes: String?, coachInsight: String?) {
        guard Self.triggerMoods.contains(mood) else { return }
        guard UserDefaults.standard.bool(forKey: "coachCheckInsEnabled") else { return }
        pendingCheckIn = CheckInContext(logId: logId, mood: mood, cleanedNotes: cleanedNotes, coachInsight: coachInsight)
        showBanner = true
    }

    func dismiss() {
        showBanner = false
        pendingCheckIn = nil
    }

    func consume() -> CheckInContext? {
        let ctx = pendingCheckIn
        dismiss()
        return ctx
    }
}

// MARK: - CoachView

struct CoachView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(CoachCheckInManager.self) private var checkInManager
    @Environment(VitalManager.self) private var vitalManager
    @State private var trainingPlanVM = TrainingPlanViewModel()
    @State private var fitnessPredictor = FitnessPredictorService()
    @State private var chat = CoachChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        mainContent
            .background(DripBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(
                    text: $chat.inputText,
                    isLoading: chat.isLoading,
                    isFocused: $isInputFocused,
                    onSend: {
                        chat.sendMessage(
                            workoutSummary: buildWorkoutSummary(),
                            planContext: buildTrainingPlanContext(),
                            fitnessPredictions: buildFitnessPredictions()
                        )
                    }
                )
            }
            .navigationTitle("")
            .toolbar { toolbarContent }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { keyboardToolbar }
            .alert("Daily Limit Reached", isPresented: Binding(get: { chat.showRateLimitAlert }, set: { chat.showRateLimitAlert = $0 })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(chat.rateLimitMessage)
            }
            .task {
                if healthKitManager.recentWorkouts.isEmpty {
                    _ = await healthKitManager.requestAuthorization()
                    let workouts = await healthKitManager.fetchRecentRunningWorkouts(limit: 30)
                    await MainActor.run { healthKitManager.recentWorkouts = workouts }
                }
                await trainingPlanVM.loadActivePlan()
                await fitnessPredictor.predictFitness(
                    plan: trainingPlanVM.activePlan
                )
                // Handle pending proactive check-in
                if let ctx = checkInManager.consume() {
                    await chat.initiateProactiveCheckIn(
                        ctx,
                        workoutSummary: buildWorkoutSummary(),
                        planContext: buildTrainingPlanContext(),
                        fitnessPredictions: buildFitnessPredictions()
                    )
                }
            }
            .onChange(of: checkInManager.pendingCheckIn != nil) { _, hasPending in
                if hasPending {
                    Task {
                        if let ctx = checkInManager.consume() {
                            await chat.initiateProactiveCheckIn(
                                ctx,
                                workoutSummary: buildWorkoutSummary(),
                                planContext: buildTrainingPlanContext(),
                                fitnessPredictions: buildFitnessPredictions()
                            )
                        }
                    }
                }
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
            .onChange(of: chat.messages.count) { scrollToLastMessage(proxy: proxy) }
            .onChange(of: chat.isLoading) { scrollToLoading(proxy: proxy) }
            .onChange(of: isInputFocused) { scrollToBottom(proxy: proxy) }
        }
    }

    private var messagesListView: some View {
        LazyVStack(spacing: 16) {
            if chat.messages.isEmpty, !chat.isLoading {
                WelcomeCard()
                    .padding(.top, 40)
            }

            ForEach(chat.messages) { message in
                ChatBubble(message: message, conversationId: chat.conversationId) { rating in
                    Task { await sendFeedback(rating: rating, message: message) }
                }
                    .id(message.id)
            }

            if chat.isLoading {
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

            if chat.rateLimit.remaining < 999 {
                Text("\(chat.rateLimit.remaining)/\(chat.rateLimit.limit) today")
                    .font(.dripCaption(9))
                    .foregroundStyle(chat.rateLimit.remaining <= 1 ? Color.drip.coral : Color.drip.textTertiary)
            }
        }
    }

    private var newConversationButton: some View {
        Button { chat.startNewConversation() } label: {
            Image(systemName: "plus.bubble")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.drip.coral)
        }
    }

    // MARK: - Scroll Helpers

    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        if let lastMessage = chat.messages.last {
            withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
        }
    }

    private func scrollToLoading(proxy: ScrollViewProxy) {
        if chat.isLoading {
            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if isInputFocused {
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // Context builders remain here since they reference view-level dependencies

    private func buildWorkoutSummary() -> String {
        // Use Vital workouts (from Garmin) if available, fall back to HealthKit
        let vitalWorkouts = vitalManager.recentWorkouts
        let workouts = vitalWorkouts.isEmpty ? healthKitManager.recentWorkouts : vitalWorkouts
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

        // This week effort zone distribution (from cached Vital stream data)
        var weekStart = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date())
        weekStart.calendar = calendar
        weekStart.calendar?.firstWeekday = 2
        let startOfWeek = weekStart.date ?? Date()
        let thisWeek = recent.filter { $0.startDate >= startOfWeek }
        if !thisWeek.isEmpty {
            let weekMiles = thisWeek.reduce(0.0) { $0 + $1.distanceMiles }
            let weekRuns = thisWeek.count
            lines.append("")
            lines.append("This week (Mon-Sun): \(weekRuns) runs, \(String(format: "%.1f", weekMiles)) mi")

            // Add per-workout zone breakdown from cached summaries
            if let zoneBreakdown = buildWeeklyZoneBreakdown(thisWeek) {
                lines.append(zoneBreakdown)
            }
        }

        // Last 5 individual workouts with details
        lines.append("")
        lines.append("Recent runs:")
        for workout in recent.prefix(5) {
            let pace = workout.distanceMiles > 0 ? workout.durationMinutes / workout.distanceMiles : 0
            let dateStr = workout.shortDate
            var line = "  \(dateStr): \(workout.formattedDistance) in \(workout.formattedDuration) (\(formatPace(pace))/mi)"

            // Add HR if available from Vital summary
            if let vitalId = workout.vitalWorkoutId,
               let summary = vitalManager.getSummary(for: vitalId) {
                if let avgHR = summary.averageHr, let maxHR = summary.maxHr {
                    line += " | HR avg \(avgHR) max \(maxHR)"
                }
                if let elevGain = summary.totalElevationGain {
                    line += " | elev +\(Int(elevGain * 3.28084))ft"
                }
            }

            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    /// Build weekly effort zone breakdown from Vital workout summaries
    private func buildWeeklyZoneBreakdown(_ weekWorkouts: [RunningWorkout]) -> String? {
        let paces = trainingPlanVM.equivalentPaces
        var zoneMiles: [PaceZone: Double] = [:]

        for workout in weekWorkouts {
            if let vitalId = workout.vitalWorkoutId,
               let summary = vitalManager.getSummary(for: vitalId),
               let avgSpeed = summary.averageSpeed {
                let zone = PaceZone.from(velocity: avgSpeed, paces: paces)
                zoneMiles[zone, default: 0] += workout.distanceMiles
            } else {
                let velocity = workout.distanceMiles > 0
                    ? (workout.distanceMiles * 1609.34) / (workout.durationMinutes * 60)
                    : 0
                let zone = PaceZone.from(velocity: velocity, paces: paces)
                zoneMiles[zone, default: 0] += workout.distanceMiles
            }
        }

        guard !zoneMiles.isEmpty else { return nil }

        var parts: [String] = ["Effort distribution:"]
        for zone in PaceZone.allCases {
            if let miles = zoneMiles[zone], miles > 0.1 {
                parts.append("  \(zone.label): \(String(format: "%.1f", miles)) mi")
            }
        }
        return parts.count > 1 ? parts.joined(separator: "\n") : nil
    }

    private func formatPace(_ paceMinPerMile: Double) -> String {
        guard paceMinPerMile > 0 else { return "--:--" }
        return PaceCalculator.formatPaceFromMinutes(paceMinPerMile)
    }

    private func buildTrainingPlanContext() -> String {
        guard let plan = trainingPlanVM.activePlan else { return "" }

        var lines: [String] = []

        // A. Plan overview
        lines.append("Plan: \(plan.name)")
        lines.append("Target: \(plan.targetRaceDistance) in \(plan.formattedGoalTime) (race pace \(plan.formattedRacePace))")
        lines.append("Week \(plan.currentWeek) of \(plan.totalWeeks)")
        let weeksOut = plan.totalWeeks - plan.currentWeek
        let phase = TrainingPhase.fromWeeksOut(weeksOut)
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

    private func sendFeedback(rating: Int, message: ChatMessage) async {
        guard let convId = chat.conversationId else { return }
        do {
            _ = try await callEdgeFunction(
                name: "coaching-feedback",
                body: [
                    "conversationId": convId,
                    "messageId": message.id.uuidString,
                    "rating": rating,
                    "messageContent": String(message.content.prefix(200)),
                ]
            )
        } catch {
            print("[Coach] Feedback send failed: \(error.localizedDescription)")
        }
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
    var conversationId: String?
    var onFeedback: ((Int) -> Void)?

    @State private var feedbackGiven: Int? = nil

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

                // Feedback buttons for assistant messages
                if message.role == .assistant {
                    HStack(spacing: 12) {
                        Button {
                            feedbackGiven = 1
                            onFeedback?(1)
                        } label: {
                            Image(systemName: feedbackGiven == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12))
                                .foregroundStyle(feedbackGiven == 1 ? Color.drip.energized : Color.drip.textTertiary)
                        }

                        Button {
                            feedbackGiven = -1
                            onFeedback?(-1)
                        } label: {
                            Image(systemName: feedbackGiven == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 12))
                                .foregroundStyle(feedbackGiven == -1 ? Color.drip.struggling : Color.drip.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
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

#Preview {
    NavigationStack {
        CoachView()
    }
}
