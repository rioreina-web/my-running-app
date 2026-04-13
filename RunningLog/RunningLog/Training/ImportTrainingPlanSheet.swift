//
//  ImportTrainingPlanSheet.swift
//  RunningLog
//
//  Import a full multi-week training plan from text, file, or photo.
//

import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportTrainingPlanSheet

struct ImportTrainingPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    @Bindable var importService: PlanImportService

    // Flow state
    @State private var step: ImportStep = .input
    @State private var applied = false

    // Start date for new plan (defaults to next Monday)
    @State private var selectedStartDate: Date = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // Next Monday: weekday 1=Sun, 2=Mon, ..., 7=Sat
        let daysUntilMonday = weekday == 2 ? 7 : ((9 - weekday) % 7)
        return cal.date(byAdding: .day, value: daysUntilMonday, to: today) ?? today
    }()
    @State private var latestSnapshot: FitnessSnapshot?

    // Input
    @State private var inputMode: InputMode = .text
    @State private var inputText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var fileData: Data?
    @State private var fileType: String?
    @State private var fileName: String?
    @State private var showFilePicker = false
    @FocusState private var isTextEditorFocused: Bool

    // Clarification answers
    @State private var clarificationAnswers: [String: String] = [:]

    enum ImportStep {
        case input
        case clarifying
        case preview
    }

    enum InputMode: String, CaseIterable {
        case text = "Text"
        case file = "File"
        case photo = "Photo"

        var icon: String {
            switch self {
            case .text: "doc.text"
            case .file: "doc.fill"
            case .photo: "camera.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                switch step {
                case .input:
                    inputView
                case .clarifying:
                    if let clarifications = importService.importedPlanResponse?.clarifications, !clarifications.isEmpty {
                        clarifyingView(clarifications: clarifications)
                    }
                case .preview:
                    if let response = importService.importedPlanResponse {
                        previewView(response: response)
                    }
                }

                if applied {
                    successView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: step) {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(applied ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }

                if step != .input && !applied {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation(.spring(response: 0.3)) {
                                switch step {
                                case .preview:
                                    if let clarifications = importService.importedPlanResponse?.clarifications, !clarifications.isEmpty {
                                        step = .clarifying
                                    } else {
                                        step = .input
                                    }
                                case .clarifying:
                                    step = .input
                                default:
                                    step = .input
                                }
                            }
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextEditorFocused = false
                    }
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .commaSeparatedText, .plainText, .spreadsheet, .init("org.openxmlformats.spreadsheetml.sheet")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .input: "Import Plan"
        case .clarifying: "Quick Questions"
        case .preview: "Review Plan"
        }
    }

    // MARK: - Input View

    private func dismissKeyboard() {
        isTextEditorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var inputView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.drip.coral)

                    Text("Import Training Plan")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Paste text, import a file, or take a photo of your training plan")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 16)

                // Input mode picker
                HStack(spacing: 0) {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inputMode = mode
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(mode.rawValue)
                                    .font(.dripLabel(13))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(inputMode == mode ? Color.drip.coral : Color.clear)
                            .foregroundStyle(inputMode == mode ? .white : Color.drip.textSecondary)
                        }
                    }
                }
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.drip.divider, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                // Input content
                Group {
                    switch inputMode {
                    case .text:
                        textInputView
                    case .file:
                        fileInputView
                    case .photo:
                        photoInputView
                    }
                }

                // Error
                if let error = importService.planImportError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                        Text(error)
                            .font(.dripCaption(12))
                    }
                    .foregroundStyle(Color.drip.injured)
                    .padding(.horizontal, 20)
                }

                Spacer()
                    .frame(height: 80)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            // Extract button
            Button {
                dismissKeyboard()
                Task { await parseInput() }
            } label: {
                HStack(spacing: 10) {
                    if importService.isParsingPlanImport {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                    }
                    Text(importService.isParsingPlanImport ? "Parsing Plan..." : "Extract Training Plan")
                        .font(.dripLabel(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canParse && !importService.isParsingPlanImport ? Color.drip.coral : Color.drip.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canParse || importService.isParsingPlanImport)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Color.drip.background
                    .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
            )
        }
    }

    private var canParse: Bool {
        switch inputMode {
        case .text: !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file: fileData != nil
        case .photo: imageData != nil
        }
    }

    // MARK: - Text Input

    private var textInputView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $inputText)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isTextEditorFocused)
                .frame(minHeight: 200)
                .padding(12)

            if inputText.isEmpty {
                Text("Week 1:\nMon: 5mi easy\nTue: 8x800m at 5K pace\nWed: off\n...\n\nWeek 2:\nMon: 6mi easy\n...")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textTertiary)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTextEditorFocused ? Color.drip.coral.opacity(0.5) : Color.drip.divider, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - File Input

    private var fileInputView: some View {
        VStack(spacing: 16) {
            if let fileName {
                // File selected
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.drip.coral)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textPrimary)

                        if let data = fileData {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        fileData = nil
                        fileType = nil
                        self.fileName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // No file yet
                Button {
                    showFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.drip.coral)

                        Text("Choose File")
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text("PDF, CSV, Excel, or text files")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Photo Input

    private var photoInputView: some View {
        VStack(spacing: 16) {
            if let imageData, let uiImage = UIImage(data: imageData) {
                // Image selected
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        self.imageData = nil
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding(8)
                }
            } else {
                // No photo yet
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.drip.coral)

                        Text("Choose Photo")
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text("Photo of a printed or handwritten training plan")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.drip.divider, style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Clarifying Questions View

    private func clarifyingView(clarifications: [ImportedPlanResponse.Clarification]) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.drip.coral)

                    Text("A few quick questions")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Help us parse your plan more accurately")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                VStack(spacing: 20) {
                    ForEach(clarifications) { clarification in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(clarification.question)
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)

                            if let options = clarification.options, !options.isEmpty {
                                // Option buttons
                                HStack(spacing: 8) {
                                    ForEach(options, id: \.self) { option in
                                        Button {
                                            clarificationAnswers[clarification.id] = option
                                        } label: {
                                            Text(option)
                                                .font(.dripBody(13))
                                                .foregroundStyle(
                                                    clarificationAnswers[clarification.id] == option
                                                        ? .white
                                                        : Color.drip.textPrimary
                                                )
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    clarificationAnswers[clarification.id] == option
                                                        ? Color.drip.coral
                                                        : Color.drip.cardBackground
                                                )
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(
                                                            clarificationAnswers[clarification.id] == option
                                                                ? Color.clear
                                                                : Color.drip.divider,
                                                            lineWidth: 1
                                                        )
                                                )
                                        }
                                    }
                                }
                            } else {
                                // Free text input
                                TextField("Your answer", text: Binding(
                                    get: { clarificationAnswers[clarification.id] ?? "" },
                                    set: { clarificationAnswers[clarification.id] = $0 }
                                ))
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.drip.divider, lineWidth: 1)
                                )
                            }
                        }
                        .padding(16)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Button {
                    Task { await reParseWithClarifications() }
                } label: {
                    HStack(spacing: 10) {
                        if importService.isParsingPlanImport {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text(importService.isParsingPlanImport ? "Re-parsing..." : "Continue")
                            .font(.dripLabel(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(allClarificationsAnswered && !importService.isParsingPlanImport ? Color.drip.coral : Color.drip.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!allClarificationsAnswered || importService.isParsingPlanImport)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(
                Color.drip.background
                    .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
            )
        }
    }

    private var allClarificationsAnswered: Bool {
        guard let clarifications = importService.importedPlanResponse?.clarifications else { return true }
        return clarifications.allSatisfy { c in
            guard let answer = clarificationAnswers[c.id] else { return false }
            return !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }


    // MARK: - Preview View

    private func previewView(response: ImportedPlanResponse) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Plan summary
                    VStack(spacing: 4) {
                        Text(viewModel.activePlan?.name ?? (response.planName ?? "Training Plan"))
                            .font(.dripDisplay(24))
                            .foregroundStyle(Color.drip.textPrimary)

                        let totalWorkouts = response.weeks.flatMap(\.days).filter { $0.workoutType != "rest" }.count
                        let totalMiles = response.weeks.flatMap(\.days).compactMap(\.totalDistanceMiles).reduce(0, +)
                        Text("\(response.totalWeeks) weeks · \(totalWorkouts) workouts · \(String(format: "%.0f", totalMiles)) mi")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(0.5)
                    }
                    .padding(.top, 12)

                    // Start date picker (only for new plans, not when adding to existing)
                    if viewModel.activePlan == nil {
                        HStack {
                            Text("Starts")
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)

                            Spacer()

                            DatePicker("", selection: $selectedStartDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(Color.drip.coral)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Weeks
                    ForEach(response.weeks) { week in
                        ImportWeekPreviewCard(week: week)
                    }

                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, 20)
            }
            .task { await loadLatestFitnessSnapshot() }

            // Apply button
            VStack {
                if let error = importService.planImportError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                        Text(error)
                            .font(.dripCaption(12))
                    }
                    .foregroundStyle(Color.drip.injured)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Button {
                    Task {
                        importService.planImportError = nil
                        let success: Bool
                        if viewModel.activePlan != nil {
                            success = await importService.applyImportedWorkoutsToActivePlan()
                        } else {
                            // No active plan — use detected metadata with sensible defaults
                            let name = response.planName ?? "Imported Training"
                            let dist = response.detectedMeta?.raceDistance ?? "marathon"
                            let goalTime = goalTimeForImport(detectedGoalTime: response.detectedMeta?.goalTime, raceDistance: dist)
                            success = await importService.applyImportedPlan(
                                name: name,
                                startDate: selectedStartDate,
                                raceDistance: dist,
                                goalTimeSeconds: goalTime
                            )
                        }
                        if success {
                            withAnimation(.spring(response: 0.3)) {
                                applied = true
                            }
                            try? await Task.sleep(for: .seconds(1.5))
                            dismiss()
                        } else {
                            importService.planImportError = viewModel.errorMessage ?? "Failed to apply training plan. Please try again."
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isGeneratingPlan {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text(viewModel.isGeneratingPlan ? "Applying..." : "Apply Training")
                            .font(.dripLabel(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.isGeneratingPlan)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(
                Color.drip.background
                    .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
            )
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.drip.success.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.drip.success)
            }

            Text("Plan Imported!")
                .font(.dripDisplay(22))
                .foregroundStyle(Color.drip.textPrimary)

            if let response = importService.importedPlanResponse {
                Text("\(response.totalWeeks) weeks of training ready to go")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func goalTimeForImport(detectedGoalTime: String?, raceDistance: String) -> Int {
        // 1. Use AI-detected goal time if available
        if let detected = detectedGoalTime {
            let parsed = parseGoalTimeSeconds(from: detected)
            if parsed != 14400 { return parsed } // Only use if actually parsed (not default)
        }
        // 2. Use fitness prediction if available
        if let snapshot = latestSnapshot {
            let dist = RaceDistance.from(legacyString: raceDistance) ?? .marathon
            switch dist {
            case .mile1500: return snapshot.predictedMileSeconds
            case .fiveK: return snapshot.predicted5kSeconds
            case .tenK: return snapshot.predicted10kSeconds
            case .halfMarathon: return snapshot.predictedHalfSeconds
            case .marathon: return snapshot.predictedMarathonSeconds
            }
        }
        // 3. Fallback
        return 14400
    }

    private func loadLatestFitnessSnapshot() async {
        do {
            let snapshots: [FitnessSnapshot] = try await supabase
                .from("fitness_snapshots")
                .select()
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            latestSnapshot = snapshots.first
        } catch {
            // Non-critical — we'll fall back to defaults
        }
    }

    private func parseGoalTimeSeconds(from timeString: String?) -> Int {
        guard let time = timeString else { return 14400 } // default 4:00:00
        let parts = time.split(separator: ":")
        if parts.count == 3,
           let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) {
            return h * 3600 + m * 60 + s
        } else if parts.count == 2,
                  let m = Int(parts[0]), let s = Int(parts[1]) {
            return m * 60 + s
        }
        return 14400
    }

    private func parseInput() async {
        var text: String? = nil
        var imgBase64: String? = nil
        var imgMime: String? = nil
        var fBase64: String? = nil
        var fType: String? = nil

        switch inputMode {
        case .text:
            text = inputText
        case .file:
            if let data = fileData {
                fBase64 = data.base64EncodedString()
                fType = fileType
            }
        case .photo:
            if let data = imageData {
                imgBase64 = data.base64EncodedString()
                imgMime = "image/jpeg"
            }
        }

        await importService.parseFullPlan(
            text: text,
            imageBase64: imgBase64,
            imageMimeType: imgMime,
            fileBase64: fBase64,
            fileType: fType
        )

        if let response = importService.importedPlanResponse {
            if let clarifications = response.clarifications, !clarifications.isEmpty {
                withAnimation(.spring(response: 0.3)) {
                    step = .clarifying
                }
            } else {
                withAnimation(.spring(response: 0.3)) {
                    step = .preview
                }
            }
        }
    }

    private func reParseWithClarifications() async {
        let answers = clarificationAnswers.map { ["id": $0.key, "answer": $0.value] }

        var text: String? = nil
        var imgBase64: String? = nil
        var imgMime: String? = nil
        var fBase64: String? = nil
        var fType: String? = nil

        switch inputMode {
        case .text:
            text = inputText
        case .file:
            if let data = fileData {
                fBase64 = data.base64EncodedString()
                fType = fileType
            }
        case .photo:
            if let data = imageData {
                imgBase64 = data.base64EncodedString()
                imgMime = "image/jpeg"
            }
        }

        await importService.parseFullPlan(
            text: text,
            imageBase64: imgBase64,
            imageMimeType: imgMime,
            fileBase64: fBase64,
            fileType: fType,
            clarificationAnswers: answers
        )

        if importService.importedPlanResponse != nil {
            withAnimation(.spring(response: 0.3)) {
                step = .preview
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if let data = try? Data(contentsOf: url) {
                fileData = data
                fileName = url.lastPathComponent

                let ext = url.pathExtension.lowercased()
                switch ext {
                case "pdf": fileType = "application/pdf"
                case "csv": fileType = "text/csv"
                case "txt": fileType = "text/plain"
                case "xlsx": fileType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                case "xls": fileType = "application/vnd.ms-excel"
                case "docx": fileType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                default: fileType = "application/octet-stream"
                }
            }
        case .failure(let error):
            importService.planImportError = error.localizedDescription
        }
    }
}

// MARK: - ImportWeekPreviewCard

struct ImportWeekPreviewCard: View {
    let week: ImportedWeek
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Week header (always visible)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEK \(week.weekNumber)")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        if let label = week.label {
                            Text(label)
                                .font(.dripLabel(14))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                    }

                    Spacer()

                    let workoutCount = week.days.filter { $0.workoutType != "rest" }.count
                    let totalMiles = week.days.compactMap(\.totalDistanceMiles).reduce(0, +)
                    Text("\(workoutCount) runs · \(String(format: "%.0f", totalMiles)) mi")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(14)
            }

            // Expanded days
            if isExpanded {
                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(height: 1)

                VStack(spacing: 2) {
                    ForEach(week.days) { day in
                        ImportDayPreviewRow(day: day)
                    }
                }
                .padding(8)
            }
        }
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - UTType Extensions

extension UTType {
    static let spreadsheet = UTType("com.microsoft.excel.xls") ?? .data
}

// MARK: - Preview

#Preview {
    let vm = TrainingPlanViewModel()
    ImportTrainingPlanSheet(viewModel: vm, importService: vm.importService)
}
