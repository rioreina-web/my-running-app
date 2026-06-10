//
//  WorkoutChatSheet.swift
//  RunningLog
//
//  AI chat for restructuring individual workouts.
//

import SwiftUI

// MARK: - WorkoutChatSheet

struct WorkoutChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let scheduledWorkout: ScheduledWorkout
    let racePaceSeconds: Double
    let onWorkoutUpdated: () -> Void

    @State private var messages: [WorkoutChatMessage] = []
    @State private var inputText = ""
    @State private var aiService = AITrainingPlanService()
    @State private var conversationId: String?
    @State private var pendingPlanData: AIPlanData?
    @State private var isApplying = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                workoutSummaryCard
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)

                                ForEach(messages) { msg in
                                    WorkoutChatBubble(text: msg.text, isUser: msg.role == "user")
                                        .id(msg.id)
                                }

                                if aiService.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .tint(Color.drip.coral)
                                        Text("Thinking...")
                                            .font(.dripCaption(12))
                                            .foregroundStyle(Color.drip.textTertiary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }

                                if pendingPlanData != nil {
                                    applyButton
                                        .padding(.horizontal, 20)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    ChatInputBar(
                        text: $inputText,
                        isLoading: aiService.isLoading,
                        isFocused: $isInputFocused,
                        placeholder: "e.g., Change to 6x800m with 60s rest",
                        onSend: sendMessage
                    )
                }
            }
            .navigationTitle("Restructure Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Workout Summary Card

    private var workoutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: scheduledWorkout.workoutType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(scheduledWorkout.workoutType.color)

                Text(scheduledWorkout.workout?.name ?? scheduledWorkout.workoutType.displayName)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                Text("Week \(scheduledWorkout.weekNumber)")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            if let desc = scheduledWorkout.workout?.description, !desc.isEmpty {
                Text(desc)
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            if let workout = scheduledWorkout.workout, let dist = workout.formattedTotalDistance {
                Text(dist)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Divider().background(Color.drip.divider)

            Text("Tell the AI how you'd like to change this workout")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Diff View + Apply Button

    private var applyButton: some View {
        VStack(spacing: 12) {
            // Show diff: original → proposed
            if let planData = pendingPlanData,
               let original = scheduledWorkout.workout {
                let aiWorkout = findMatchedWorkout(in: planData)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PROPOSED CHANGES")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    // Name change
                    if let aw = aiWorkout, aw.name != original.name {
                        DiffRow(label: "Name", from: original.name, to: aw.name)
                    }

                    // Step count change
                    if let aw = aiWorkout, aw.steps.count != original.steps.count {
                        DiffRow(
                            label: "Steps",
                            from: "\(original.steps.count) steps",
                            to: "\(aw.steps.count) steps"
                        )
                    }

                    // Distance change
                    if let aw = aiWorkout,
                       let newDist = aw.totalDistanceMiles,
                       let oldDist = original.totalDistanceMiles,
                       abs(newDist - oldDist) >= 0.3 {
                        DiffRow(
                            label: "Distance",
                            from: String(format: "%.1f mi", oldDist),
                            to: String(format: "%.1f mi", newDist)
                        )
                    }

                    // Show key step changes
                    if let aw = aiWorkout {
                        let activeOriginal = original.steps.filter { $0.stepType == .active }
                        let activeNew = aw.steps.filter { $0.stepType == "active" }
                        let maxSteps = min(3, max(activeOriginal.count, activeNew.count))

                        ForEach(0..<maxSteps, id: \.self) { i in
                            if i < activeOriginal.count && i < activeNew.count {
                                let orig = activeOriginal[i]
                                let new_ = activeNew[i]
                                let origDesc = "\(orig.formattedDuration) \(orig.notes ?? "")"
                                let newDesc = "\(new_.durationValue) \(new_.notes ?? new_.stepType)"
                                if origDesc != newDesc {
                                    DiffRow(label: "Step \(i + 1)", from: origDesc, to: newDesc)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Apply/Reject buttons
            HStack(spacing: 12) {
                Button {
                    pendingPlanData = nil
                    messages.append(WorkoutChatMessage(
                        role: "assistant",
                        text: "No problem — what would you like instead?"
                    ))
                } label: {
                    Text("Reject")
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                }

                Button { applyChanges() } label: {
                    HStack(spacing: 8) {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text("Apply")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isApplying)
            }
        }
    }

    private func findMatchedWorkout(in planData: AIPlanData) -> AIPlanWorkout? {
        let targetDay = scheduledWorkout.dayOfWeek
        let fillerTypes = ["easy", "rest", "strides"]
        let isQualityOriginal = !fillerTypes.contains(scheduledWorkout.workoutType.rawValue.lowercased())

        if isQualityOriginal {
            return planData.workouts.first(where: { $0.dayOfWeek == targetDay && !fillerTypes.contains($0.workoutType.lowercased()) })
                ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
        } else {
            return planData.workouts.first(where: { $0.dayOfWeek == targetDay })
                ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
                ?? planData.workouts.first
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        pendingPlanData = nil

        messages.append(WorkoutChatMessage(role: "user", text: text))

        let contextMessage: String
        if conversationId == nil {
            // First message: include full workout context
            var parts = [
                "I want to modify a single workout in my training plan.",
                "Current workout: \(scheduledWorkout.workout?.name ?? "Unknown")",
                "Description: \(scheduledWorkout.workout?.description ?? "")",
                "Total distance: \(scheduledWorkout.workout?.formattedTotalDistance ?? "N/A")",
                "Date: \(scheduledWorkout.formattedFullDate), Week \(scheduledWorkout.weekNumber)",
            ]

            if let steps = scheduledWorkout.workout?.steps, !steps.isEmpty {
                let stepDescs = steps.enumerated().map { i, s in
                    "\(i + 1). \(s.stepType.displayName): \(s.formattedDuration) - \(s.notes ?? "")"
                }
                parts.append("Current steps:\n\(stepDescs.joined(separator: "\n"))")
            }

            parts.append("")
            parts.append("Modification: \(text)")
            parts.append("")
            parts.append("Return the modified workout in <<<PLAN>>> format with 1 week containing just this workout. Use the correct workout code from the library if applicable. Keep dayOfWeek \(scheduledWorkout.dayOfWeek) and weekNumber \(scheduledWorkout.weekNumber).")

            contextMessage = parts.joined(separator: "\n")
        } else {
            contextMessage = text
        }

        Task {
            do {
                let goalTime = viewModel.marathonGoalTime
                let response = try await aiService.sendMessage(
                    contextMessage,
                    conversationId: conversationId,
                    goalTimeSeconds: goalTime
                )

                conversationId = response.conversationId

                if let planData = response.planData {
                    // Find the actual modified workout — match by dayOfWeek, or pick the non-filler workout
                    let targetDay = scheduledWorkout.dayOfWeek
                    let fillerTypes = ["easy", "rest", "strides"]
                    let isQualityOriginal = !fillerTypes.contains(scheduledWorkout.workoutType.rawValue.lowercased())

                    // For quality workouts, prefer a quality match on the right day
                    let matchedWorkout: AIPlanWorkout?
                    if isQualityOriginal {
                        matchedWorkout = planData.workouts.first(where: { $0.dayOfWeek == targetDay && !fillerTypes.contains($0.workoutType.lowercased()) })
                            ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
                    } else {
                        matchedWorkout = planData.workouts.first(where: { $0.dayOfWeek == targetDay })
                            ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
                            ?? planData.workouts.first
                    }

                    if let workout = matchedWorkout {
                        pendingPlanData = planData
                        let name = workout.name
                        let stepCount = workout.steps.count
                        messages.append(WorkoutChatMessage(
                            role: "assistant",
                            text: "\(response.message)\n\nNew workout: \(name) (\(stepCount) steps). Tap 'Apply Changes' to update."
                        ))
                    } else {
                        messages.append(WorkoutChatMessage(role: "assistant", text: response.message))
                    }
                } else {
                    messages.append(WorkoutChatMessage(role: "assistant", text: response.message))
                }
            } catch {
                messages.append(WorkoutChatMessage(
                    role: "assistant",
                    text: "Something went wrong: \(error.localizedDescription)"
                ))
            }
        }
    }

    // MARK: - Apply Changes

    private func applyChanges() {
        guard let planData = pendingPlanData else { return }

        // Find the actual modified workout — match by dayOfWeek, or pick the non-filler workout
        let targetDay = scheduledWorkout.dayOfWeek
        let fillerTypes = ["easy", "rest", "strides"]
        let isQualityOriginal = !fillerTypes.contains(scheduledWorkout.workoutType.rawValue.lowercased())

        let aiWorkout: AIPlanWorkout?
        if isQualityOriginal {
            aiWorkout = planData.workouts.first(where: { $0.dayOfWeek == targetDay && !fillerTypes.contains($0.workoutType.lowercased()) })
                ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
        } else {
            aiWorkout = planData.workouts.first(where: { $0.dayOfWeek == targetDay })
                ?? planData.workouts.first(where: { !fillerTypes.contains($0.workoutType.lowercased()) })
                ?? planData.workouts.first
        }
        guard let aiWorkout else { return }

        isApplying = true

        // Convert to ImportedDayWorkout so we can use the existing
        // toPlannedWorkout pipeline. Critical: pass through `repeats` and
        // `recovery` — without these, an AI-generated "2 × 3mi w/ 0.5mi
        // float" gets collapsed into a single 5mi block (the description
        // says one thing, the steps say another).
        let importedSteps = aiWorkout.steps.map { step -> ImportedDayWorkout.ImportedStep in
            let recovery: ImportedDayWorkout.ImportedStepRecovery? = step.recovery.map { r in
                ImportedDayWorkout.ImportedStepRecovery(
                    durationType: r.durationType,
                    durationValue: r.durationValue,
                    paceSecondsPerKm: nil,
                    pacePercentage: r.pacePercentage
                )
            }
            return ImportedDayWorkout.ImportedStep(
                stepType: step.stepType,
                durationType: step.durationType,
                durationValue: step.durationValue,
                pacePercentage: step.pacePercentage,
                paceReference: step.paceZone,
                repeats: step.repeats,
                recovery: recovery,
                notes: step.notes,
                order: step.order
            )
        }

        let importedDay = ImportedDayWorkout(
            dayOfWeek: aiWorkout.dayOfWeek,
            dayName: aiWorkout.dayName ?? scheduledWorkout.dayName,
            session: 1,
            workoutType: aiWorkout.workoutType,
            name: aiWorkout.name,
            description: aiWorkout.description,
            totalDistanceMiles: aiWorkout.totalDistanceMiles,
            estimatedDurationMinutes: aiWorkout.estimatedDurationMinutes,
            steps: importedSteps
        )

        let phase = scheduledWorkout.workout?.trainingPhase ?? viewModel.currentPhase
        let newWorkout = importedDay.toPlannedWorkout(
            phase: phase,
            racePaceSecondsPerMile: racePaceSeconds
        )

        var updatedScheduled = scheduledWorkout
        updatedScheduled.workout = newWorkout
        updatedScheduled.status = .modified

        // Map workoutType from AI response
        let mappedType: ScheduledWorkoutType = switch aiWorkout.workoutType {
        case "easy", "recovery": .easy
        case "long_run": .longRun
        case "workout", "intervals": .intervals
        case "tempo": .tempo
        case "strides": .strides
        case "rest": .rest
        case "race": .race
        default: scheduledWorkout.workoutType
        }
        updatedScheduled.workoutType = mappedType

        Task {
            await viewModel.updateWorkout(updatedScheduled)
            isApplying = false
            onWorkoutUpdated()
            dismiss()
        }
    }
}

// MARK: - Chat Message Model

struct WorkoutChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

// MARK: - Diff Row

struct DiffRow: View {
    let label: String
    let from: String
    let to: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.6)

            HStack(spacing: 8) {
                Text(from)
                    .font(.dripBody(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .strikethrough(true, color: Color.drip.textTertiary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.drip.coral)

                Text(to)
                    .font(.dripLabel(12))
                    .foregroundStyle(Color.drip.coral)
            }
        }
    }
}

// MARK: - Chat Bubble

struct WorkoutChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(text)
                .font(.dripBody(14))
                .foregroundStyle(isUser ? .white : Color.drip.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 20)
    }
}
