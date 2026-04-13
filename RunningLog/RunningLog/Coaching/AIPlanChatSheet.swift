//
//  AIPlanChatSheet.swift
//  RunningLog
//
//  AI marathon coach: welcome screen for context, then coaching chat.
//

import SwiftUI

// MARK: - AIPlanChatSheet

struct AIPlanChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel

    // Phase: welcome screen vs chat
    @State private var showChat = false

    // Welcome screen inputs
    @State private var planName: String = ""
    @State private var selectedRaceDistance: RaceDistance = .marathon
    @State private var startDate: Date = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysUntilMonday = weekday == 2 ? 0 : ((9 - weekday) % 7)
        return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
    }()
    @State private var raceDate = Date().addingTimeInterval(86400 * 112)
    @State private var hasGoalTime = false
    @State private var goalTimeHours = 3
    @State private var goalTimeMinutes = 30
    @State private var goalTimeSeconds = 0
    @State private var currentMileage: Double = 25

    // Chat state
    @State private var messages: [ChatMessage] = []
    @State private var userInput = ""
    @State private var conversationId: String?
    @State private var aiService = AITrainingPlanService()
    @State private var generatedPlan: AIPlanData?
    @State private var isApplying = false
    @State private var applyError: String?
    @FocusState private var isInputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: String
        let text: String
    }

    private var goalTimeInSeconds: Int? {
        guard hasGoalTime else { return nil }
        return goalTimeHours * 3600 + goalTimeMinutes * 60
    }

    private var racePacePerMile: String {
        guard let seconds = goalTimeInSeconds else { return "--:--/mi" }
        let distanceMiles = 26.2188
        let paceSeconds = Double(seconds) / distanceMiles
        let mins = Int(paceSeconds) / 60
        let secs = Int(paceSeconds) % 60
        return "\(mins):\(String(format: "%02d", secs))/mi"
    }

    private var formattedGoalTime: String {
        guard hasGoalTime else { return "--:--" }
        return String(format: "%d:%02d", goalTimeHours, goalTimeMinutes)
    }

    private var formattedRaceDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: raceDate)
    }

    private var totalWeeks: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeks = calendar.dateComponents([.weekOfYear], from: today, to: raceDate).weekOfYear ?? 0
        return max(1, weeks + 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if showChat {
                    chatView
                } else {
                    welcomeView
                }
            }
            .navigationTitle(showChat ? "Training Coach" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Welcome Screen

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.drip.coral)

                    Text("New Training Plan")
                        .font(.dripStat(24))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Tell me the basics, then we'll chat about your training")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.bottom, 8)

                // Race Date
                VStack(alignment: .leading, spacing: 10) {
                    Text("RACE DATE")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.drip.coral)

                            Text("Race Day")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                        }

                        Spacer()

                        DatePicker("", selection: $raceDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.drip.coral)
                    }
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("\(totalWeeks) weeks of training")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                .padding(.horizontal, 20)

                // Goal Time
                VStack(alignment: .leading, spacing: 10) {
                    Text("GOAL MARATHON TIME")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation { hasGoalTime = false }
                            } label: {
                                Text("Not sure yet")
                                    .font(.dripLabel(13))
                                    .foregroundStyle(!hasGoalTime ? .white : Color.drip.textPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(!hasGoalTime ? Color.drip.coral : Color.drip.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Button {
                                withAnimation { hasGoalTime = true }
                            } label: {
                                Text("I have a goal")
                                    .font(.dripLabel(13))
                                    .foregroundStyle(hasGoalTime ? .white : Color.drip.textPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(hasGoalTime ? Color.drip.coral : Color.drip.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        if hasGoalTime {
                            HStack(spacing: 0) {
                                TimePickerColumn(
                                    value: $goalTimeHours,
                                    range: 2...6,
                                    label: "hrs"
                                )

                                Text(":")
                                    .font(.dripStat(28))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .padding(.horizontal, 4)

                                TimePickerColumn(
                                    value: $goalTimeMinutes,
                                    range: 0...59,
                                    label: "min"
                                )
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .background(Color.drip.divider)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("RACE PACE")
                                        .font(.dripCaption(10))
                                        .foregroundStyle(Color.drip.textTertiary)
                                        .tracking(0.5)

                                    Text(racePacePerMile)
                                        .font(.dripStat(22))
                                        .foregroundStyle(Color.drip.energized)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("GOAL TIME")
                                        .font(.dripCaption(10))
                                        .foregroundStyle(Color.drip.textTertiary)
                                        .tracking(0.5)

                                    Text(formattedGoalTime)
                                        .font(.dripStat(22))
                                        .foregroundStyle(Color.drip.coral)
                                }
                            }
                        } else {
                            Text("Your coach will help you set a goal")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                // Current Weekly Mileage
                VStack(alignment: .leading, spacing: 10) {
                    Text("CURRENT WEEKLY MILEAGE")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    VStack(spacing: 12) {
                        HStack {
                            Text("\(Int(currentMileage))")
                                .font(.dripStat(32))
                                .foregroundStyle(Color.drip.textPrimary)

                            Text("miles/week")
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textSecondary)

                            Spacer()
                        }

                        Slider(value: $currentMileage, in: 5...80, step: 5)
                            .tint(Color.drip.coral)

                        HStack {
                            Text("5 mi")
                                .font(.dripCaption(10))
                            Spacer()
                            Text("80 mi")
                                .font(.dripCaption(10))
                        }
                        .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                // Start button
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showChat = true
                    }
                    sendInitialMessage()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))

                        Text("Start Coaching Chat")
                            .font(.dripLabel(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            PlanChatBubble(message: message)
                        }

                        if aiService.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(Color.drip.coral)

                                Text("Coach is thinking...")
                                    .font(.dripCaption(13))
                                    .foregroundStyle(Color.drip.textTertiary)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .id("loading")
                        }

                        if let plan = generatedPlan {
                            PlanReadyBanner(
                                plan: plan,
                                isApplying: isApplying,
                                onApply: { applyPlan(plan) }
                            )
                            .id("plan")
                        }

                        if let error = applyError {
                            Text(error)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.coral)
                                .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 8)
                            .id("bottom")
                    }
                    .padding(.top, 16)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: aiService.isLoading) {
                    if aiService.isLoading {
                        withAnimation {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            if generatedPlan == nil {
                ChatInputBar(
                    text: $userInput,
                    isLoading: aiService.isLoading,
                    isFocused: $isInputFocused,
                    placeholder: "Message your coach...",
                    onSend: sendMessage
                )
            }
        }
    }

    // MARK: - Actions

    private func sendInitialMessage() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let raceDateStr = dateFormatter.string(from: raceDate)

        var greeting = "I want to build a marathon training plan. My race is on \(raceDateStr), currently running \(Int(currentMileage)) miles/week."
        if hasGoalTime {
            greeting = "I want to build a marathon training plan. My race is on \(raceDateStr), goal time \(formattedGoalTime), currently running \(Int(currentMileage)) miles/week."
        }
        messages.append(ChatMessage(role: "user", text: greeting))

        let startDate = {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let weekday = cal.component(.weekday, from: today)
            let daysUntilMonday = weekday == 2 ? 0 : ((9 - weekday) % 7)
            return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
        }()

        Task {
            do {
                let response = try await aiService.sendMessage(
                    greeting,
                    conversationId: nil,
                    startDate: startDate,
                    raceDate: raceDate,
                    goalTimeSeconds: goalTimeInSeconds,
                    currentWeeklyMileage: currentMileage
                )
                conversationId = response.conversationId
                messages.append(ChatMessage(role: "assistant", text: response.message))

                if response.type == "plan", let planData = response.planData {
                    generatedPlan = planData
                }
            } catch {
                messages.append(ChatMessage(
                    role: "assistant",
                    text: "Sorry, I couldn't connect right now. Please try again."
                ))
            }
        }
    }

    private func sendMessage() {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        userInput = ""
        messages.append(ChatMessage(role: "user", text: text))

        Task {
            do {
                let response = try await aiService.sendMessage(
                    text,
                    conversationId: conversationId
                )
                conversationId = response.conversationId
                messages.append(ChatMessage(role: "assistant", text: response.message))

                if response.type == "plan", let planData = response.planData {
                    generatedPlan = planData
                }
            } catch {
                messages.append(ChatMessage(
                    role: "assistant",
                    text: "Something went wrong. Could you try sending that again?"
                ))
            }
        }
    }

    private func applyPlan(_ planData: AIPlanData) {
        isApplying = true
        applyError = nil

        Task {
            let importResponse = aiService.toImportedPlanResponse(planData)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            guard let startDate = formatter.date(from: planData.plan.startDate),
                  let _ = formatter.date(from: planData.plan.endDate) else {
                applyError = "Could not parse plan dates"
                isApplying = false
                return
            }

            let goalTime = planData.plan.targetTimeSeconds ?? goalTimeInSeconds ?? (3 * 3600 + 30 * 60)
            let raceDistance = planData.plan.targetRaceDistance ?? "marathon"

            viewModel.importService.importedPlanResponse = importResponse

            let success = await viewModel.importService.applyImportedPlan(
                name: planData.plan.name,
                startDate: startDate,
                raceDistance: raceDistance,
                goalTimeSeconds: goalTime
            )

            if success {
                await viewModel.loadActivePlan()
                dismiss()
            } else {
                applyError = "Failed to save the plan. Please try again."
            }

            isApplying = false
        }
    }
}

// MARK: - Chat Bubble

private struct PlanChatBubble: View {
    let message: AIPlanChatSheet.ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.coral)

                        Text("Coach")
                            .font(.dripCaption(10))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                Text(message.text)
                    .font(.dripBody(14))
                    .foregroundStyle(isUser ? .white : Color.drip.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.drip.coral : Color.drip.cardBackground)
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Plan Ready Banner

private struct PlanReadyBanner: View {
    let plan: AIPlanData
    let isApplying: Bool
    let onApply: () -> Void

    private var totalWeeks: Int {
        Set(plan.workouts.map(\.weekNumber)).count
    }

    private var workoutDays: Int {
        plan.workouts.filter { $0.workoutType != "rest" }.count
    }

    private var totalMiles: Double {
        plan.workouts.compactMap(\.totalDistanceMiles).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.drip.positive)

                Text("Plan Ready")
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()
            }

            HStack(spacing: 0) {
                PlanStatItem(value: "\(totalWeeks)", label: "Weeks")
                PlanStatItem(value: "\(workoutDays)", label: "Workouts")
                PlanStatItem(value: String(format: "%.0f mi", totalMiles), label: "Total")
            }

            Text(plan.plan.name)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            DripButton("Apply Plan", icon: "sparkles", style: .primary, isLoading: isApplying) {
                onApply()
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.positive.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}

private struct PlanStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dripStat(18))
                .foregroundStyle(Color.drip.textPrimary)

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    AIPlanChatSheet(viewModel: TrainingPlanViewModel())
}
