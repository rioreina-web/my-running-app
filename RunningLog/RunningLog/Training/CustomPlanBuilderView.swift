//
//  CustomPlanBuilderView.swift
//  RunningLog
//
//  Two-way chat interface for building custom training plans.
//  Users describe their plan via text or file attachments, the AI
//  asks clarifying questions, and the result is a real TrainingPlan.
//

import os
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

struct PlanBuilderMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()
    var attachmentNames: [String] = []
    var planPreview: PlanPreviewData?

    enum MessageRole {
        case user
        case assistant
    }
}

struct PlanAttachment: Identifiable {
    let id = UUID()
    let fileName: String
    let fileType: AttachmentFileType
    let data: Data

    enum AttachmentFileType: String {
        case image
        case pdf
        case text
    }

    var base64String: String {
        data.base64EncodedString()
    }
}

struct PlanPreviewData {
    let name: String
    let raceDistance: String?
    let startDate: Date
    let endDate: Date
    let targetTimeSeconds: Int
    let totalWeeks: Int
    let workoutCount: Int
    // Raw data for saving
    let importedWorkouts: [ImportedDayWorkout]
    let workoutDates: [Date]
}

// MARK: - Edge Function Response

private struct PlanBuilderResponse: Codable {
    let type: String
    let message: String?
    let conversationId: String?
    let planData: PlanDataResponse?
    let error: String?
}

private struct PlanDataResponse: Codable {
    let plan: PlanMetadata
    let workouts: [WorkoutResponse]
}

private struct PlanMetadata: Codable {
    let name: String
    let startDate: String
    let endDate: String
    let targetRaceDistance: String?
    let targetTimeSeconds: Int?
}

private struct WorkoutResponse: Codable {
    let date: String
    let dayOfWeek: Int
    let weekNumber: Int
    let workoutType: String
    let name: String
    let description: String
    let totalDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let steps: [StepResponse]
}

private struct StepResponse: Codable {
    let stepType: String
    let durationType: String
    let durationValue: Double
    let pacePercentage: Double?
    let notes: String?
    let order: Int?
}

// MARK: - CustomPlanBuilderView

struct CustomPlanBuilderView: View {
    @Bindable var trainingPlanViewModel: TrainingPlanViewModel

    @State private var messages: [PlanBuilderMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var conversationId: String?
    @State private var pendingAttachments: [PlanAttachment] = []
    @State private var showAttachmentMenu = false
    @State private var showFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isSavingPlan = false
    @State private var showSaveSuccess = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        mainContent
            .background(DripBackground().ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PLAN BUILDER")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isInputFocused = false }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog("Add Attachment", isPresented: $showAttachmentMenu) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Text("Photo Library")
                }
                Button("Choose File") { showFilePicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .plainText, .image],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: selectedPhotoItem) {
                if let item = selectedPhotoItem {
                    loadPhoto(from: item)
                    selectedPhotoItem = nil
                }
            }
            .alert("Plan Saved", isPresented: $showSaveSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your training plan has been saved and is now active in the Plan tab.")
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
                welcomeCard
                    .padding(.top, 40)
            }

            ForEach(messages) { message in
                messageBubble(message)
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

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.drip.coral.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.drip.coral)
            }

            VStack(spacing: 8) {
                Text("Plan Builder")
                    .font(.dripDisplay(24))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Describe your training plan or upload one. I'll ask a few questions and build it for you.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 12) {
                suggestionChip("I have a coach's plan to import")
                suggestionChip("Build me a marathon training plan")
                suggestionChip("I want a half marathon plan")
            }
            .padding(.top, 12)
        }
        .padding(24)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
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
        .buttonStyle(.plain)
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: PlanBuilderMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.drip.coral)
                }
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Attachment badges
                if !message.attachmentNames.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachmentNames, id: \.self) { name in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 10))
                                Text(name)
                                    .font(.dripCaption(11))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.drip.coral.opacity(0.6))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Message text
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

                // Plan preview card
                if let preview = message.planPreview {
                    planPreviewCard(preview)
                }
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
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

    // MARK: - Plan Preview Card

    private func planPreviewCard(_ preview: PlanPreviewData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.drip.positive.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.drip.positive)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan Ready")
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(preview.name)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            // Plan details
            VStack(spacing: 8) {
                if let distance = preview.raceDistance, distance != "general" {
                    planDetailRow(icon: "flag.fill", label: "Distance", value: formatRaceDistance(distance))
                }
                if preview.targetTimeSeconds > 0 {
                    planDetailRow(icon: "clock.fill", label: "Goal Time", value: formatGoalTime(preview.targetTimeSeconds))
                }
                planDetailRow(icon: "calendar", label: "Duration", value: "\(preview.totalWeeks) weeks")
                planDetailRow(icon: "figure.run", label: "Workouts", value: "\(preview.workoutCount) days")
            }

            // Save button
            Button {
                Task { await savePlan(preview) }
            } label: {
                HStack {
                    if isSavingPlan {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isSavingPlan ? "Saving..." : "Save to My Plans")
                        .font(.dripLabel(15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSavingPlan)

            if let error = errorMessage {
                Text(error)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.injured)
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.positive.opacity(0.3), lineWidth: 1)
        )
    }

    private func planDetailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 20)

            Text(label)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()

            Text(value)
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Pending attachments strip
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachmentIcon(for: attachment.fileType))
                                    .font(.system(size: 11))
                                Text(attachment.fileName)
                                    .font(.dripCaption(11))
                                    .lineLimit(1)

                                Button {
                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.drip.textTertiary)
                                }
                            }
                            .foregroundStyle(Color.drip.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.drip.cardBackgroundElevated)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }

            // Input bar
            HStack(spacing: 10) {
                // Attachment button
                Button {
                    showAttachmentMenu = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                        .frame(width: 36, height: 36)
                }

                // Text field
                TextField("Describe your plan...", text: $inputText, axis: .vertical)
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
                    .focused($isInputFocused)
                    .lineLimit(1 ... 5)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)

                // Send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Color.drip.coral : Color.drip.textTertiary)
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
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color.drip.background
                    .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
            )
        }
    }

    private var canSend: Bool {
        !isLoading && (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
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
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !pendingAttachments.isEmpty else { return }

        let attachmentNames = pendingAttachments.map(\.fileName)
        let userMessage = PlanBuilderMessage(
            role: .user,
            content: trimmedText.isEmpty ? "Here's my plan" : trimmedText,
            attachmentNames: attachmentNames
        )
        messages.append(userMessage)

        let messageToSend = trimmedText.isEmpty ? "Please analyze the attached file(s) and help me build a training plan from them." : trimmedText
        let attachmentsToSend = pendingAttachments
        inputText = ""
        pendingAttachments = []
        isLoading = true

        Task {
            await callPlanBuilder(message: messageToSend, attachments: attachmentsToSend)
        }
    }

    private func callPlanBuilder(message: String, attachments: [PlanAttachment]) async {
        do {
            // Build payload
            var payload: [String: Any] = ["message": message]
            if let convId = conversationId {
                payload["conversationId"] = convId
            }

            // Add attachments
            if !attachments.isEmpty {
                let attachmentDicts: [[String: Any]] = attachments.map { att in
                    [
                        "fileName": att.fileName,
                        "fileType": att.fileType.rawValue,
                        "base64Data": att.base64String,
                    ]
                }
                payload["attachments"] = attachmentDicts
            }

            let data = try await callEdgeFunction(name: "custom-plan-builder", body: payload)

            let rawPreview = String(data: data.prefix(500), encoding: .utf8) ?? "n/a"
            Log.coach.info("Plan builder response (\(data.count) bytes): \(rawPreview)")

            let response: PlanBuilderResponse
            do {
                response = try JSONDecoder().decode(PlanBuilderResponse.self, from: data)
            } catch {
                Log.coach.error("Failed to decode plan builder response: \(error)")
                await MainActor.run {
                    isLoading = false
                    appendErrorMessage("The response couldn't be processed. Please try again.")
                }
                return
            }

            if let error = response.error {
                await MainActor.run {
                    isLoading = false
                    appendErrorMessage(error)
                }
                return
            }

            await MainActor.run {
                if let convId = response.conversationId {
                    conversationId = convId
                }

                let responseText = response.message ?? "I'm working on your plan..."

                if response.type == "plan", let planData = response.planData {
                    // Parse plan data into preview
                    if let preview = parsePlanPreview(planData) {
                        let assistantMessage = PlanBuilderMessage(
                            role: .assistant,
                            content: responseText,
                            planPreview: preview
                        )
                        messages.append(assistantMessage)
                    } else {
                        let assistantMessage = PlanBuilderMessage(
                            role: .assistant,
                            content: responseText + "\n\n(Plan data could not be parsed. Please try again.)"
                        )
                        messages.append(assistantMessage)
                    }
                } else {
                    let assistantMessage = PlanBuilderMessage(
                        role: .assistant,
                        content: responseText
                    )
                    messages.append(assistantMessage)
                }

                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                appendErrorMessage("Sorry, something went wrong. Please try again.")
            }
        }
    }

    private func appendErrorMessage(_ text: String) {
        let errorMsg = PlanBuilderMessage(role: .assistant, content: text)
        messages.append(errorMsg)
    }

    // MARK: - Parse Plan Preview

    private func parsePlanPreview(_ planData: PlanDataResponse) -> PlanPreviewData? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        guard let startDate = dateFormatter.date(from: planData.plan.startDate),
              let endDate = dateFormatter.date(from: planData.plan.endDate)
        else { return nil }

        let totalWeeks = max(1, (Calendar.current.dateComponents([.weekOfYear], from: startDate, to: endDate).weekOfYear ?? 0) + 1)

        // Convert to ImportedDayWorkout + dates
        var importedWorkouts: [ImportedDayWorkout] = []
        var workoutDates: [Date] = []

        for workout in planData.workouts {
            let steps = workout.steps.map { step in
                ImportedDayWorkout.ImportedStep(
                    stepType: step.stepType,
                    durationType: step.durationType,
                    durationValue: step.durationValue,
                    pacePercentage: step.pacePercentage,
                    notes: step.notes,
                    order: step.order
                )
            }

            let imported = ImportedDayWorkout(
                dayOfWeek: workout.dayOfWeek,
                dayName: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][max(0, min(6, workout.dayOfWeek - 1))],
                session: 1,
                workoutType: workout.workoutType,
                name: workout.name,
                description: workout.description,
                totalDistanceMiles: workout.totalDistanceMiles,
                estimatedDurationMinutes: workout.estimatedDurationMinutes,
                steps: steps
            )
            importedWorkouts.append(imported)

            if let date = dateFormatter.date(from: workout.date) {
                workoutDates.append(date)
            } else {
                workoutDates.append(startDate)
            }
        }

        let nonRestCount = planData.workouts.filter { $0.workoutType != "rest" }.count

        return PlanPreviewData(
            name: planData.plan.name,
            raceDistance: planData.plan.targetRaceDistance,
            startDate: startDate,
            endDate: endDate,
            targetTimeSeconds: planData.plan.targetTimeSeconds ?? 0,
            totalWeeks: totalWeeks,
            workoutCount: nonRestCount,
            importedWorkouts: importedWorkouts,
            workoutDates: workoutDates
        )
    }

    // MARK: - Save Plan

    private func savePlan(_ preview: PlanPreviewData) async {
        isSavingPlan = true
        errorMessage = nil

        let success = await trainingPlanViewModel.importService.importCustomPlan(
            name: preview.name,
            startDate: preview.startDate,
            endDate: preview.endDate,
            targetRaceDistance: preview.raceDistance ?? "general",
            targetTimeSeconds: preview.targetTimeSeconds,
            importedWorkouts: preview.importedWorkouts,
            workoutDates: preview.workoutDates
        )

        isSavingPlan = false

        if success {
            showSaveSuccess = true
        } else {
            errorMessage = trainingPlanViewModel.errorMessage ?? "Failed to save plan. Please try again."
        }
    }

    // MARK: - Attachment Handling

    private func loadPhoto(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let attachment = PlanAttachment(
                fileName: "photo.jpg",
                fileType: .image,
                data: data
            )
            await MainActor.run {
                pendingAttachments.append(attachment)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                let fileType: PlanAttachment.AttachmentFileType

                if url.pathExtension.lowercased() == "pdf" {
                    fileType = .pdf
                } else if ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) {
                    fileType = .image
                } else {
                    fileType = .text
                }

                let attachment = PlanAttachment(
                    fileName: fileName,
                    fileType: fileType,
                    data: data
                )
                pendingAttachments.append(attachment)
            } catch {
                appendErrorMessage("Could not read the selected file.")
            }
        case .failure:
            break
        }
    }

    // MARK: - Helpers

    private func attachmentIcon(for type: PlanAttachment.AttachmentFileType) -> String {
        switch type {
        case .image: return "photo"
        case .pdf: return "doc.fill"
        case .text: return "doc.text"
        }
    }

    private func formatRaceDistance(_ distance: String) -> String {
        switch distance.lowercased() {
        case "5k": return "5K"
        case "10k": return "10K"
        case "half_marathon": return "Half Marathon"
        case "marathon": return "Marathon"
        case "ultra": return "Ultra"
        default: return distance.capitalized
        }
    }

    private func formatGoalTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            if secs > 0 {
                return String(format: "%d:%02d:%02d", hours, mins, secs)
            }
            return String(format: "%d:%02d", hours, mins)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    NavigationStack {
        CustomPlanBuilderView(trainingPlanViewModel: TrainingPlanViewModel())
    }
}
