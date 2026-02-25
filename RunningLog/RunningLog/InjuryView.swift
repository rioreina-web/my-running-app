import SwiftUI

// MARK: - InjuryListView

struct InjuryListView: View {
    @State private var injuryService = InjuryService()
    @State private var selectedInjury: Injury?
    @State private var showAddInjury = false

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Medical disclaimer
                    MedicalDisclaimerBanner(text: MedicalDisclaimer.short, isCompact: true)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Active injuries
                    if !injuryService.activeInjuries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Active (\(injuryService.activeInjuries.count))")
                                .padding(.horizontal, 20)

                            LazyVStack(spacing: 10) {
                                ForEach(injuryService.activeInjuries) { injury in
                                    InjuryCard(injury: injury)
                                        .onTapGesture { selectedInjury = injury }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Resolved injuries
                    if !injuryService.resolvedInjuries.isEmpty {
                        ResolvedInjuriesSection(
                            injuries: injuryService.resolvedInjuries,
                            onSelect: { selectedInjury = $0 }
                        )
                    }

                    // Empty state
                    if injuryService.injuries.isEmpty && !injuryService.isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.drip.positive.opacity(0.5))

                            Text("No injuries tracked")
                                .font(.dripBody(16))
                                .foregroundStyle(Color.drip.textSecondary)

                            Text("Injuries detected in voice memos or coaching will appear here automatically. You can also add them manually.")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.top, 60)
                    }

                    Spacer().frame(height: 80)
                }
            }

            // Floating add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showAddInjury = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.drip.coral)
                            .clipShape(Circle())
                            .shadow(color: Color.drip.coral.opacity(0.4), radius: 8, y: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }

            if injuryService.isLoading {
                ProgressView()
                    .tint(Color.drip.coral)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("INJURIES")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await injuryService.fetchInjuries() }
        }
        .sheet(item: $selectedInjury) { injury in
            InjuryDetailSheet(injury: injury, injuryService: injuryService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddInjury) {
            AddInjurySheet(injuryService: injuryService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - InjuryCard

struct InjuryCard: View {
    let injury: Injury

    var body: some View {
        HStack(spacing: 14) {
            // Severity indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(injury.severityColor)
                .frame(width: 4, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(injury.displayName)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    // Status badge
                    HStack(spacing: 3) {
                        Image(systemName: injury.status.icon)
                            .font(.system(size: 8))
                        Text(injury.status.displayName.uppercased())
                            .font(.dripCaption(9))
                            .tracking(0.5)
                    }
                    .foregroundStyle(injury.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(injury.status.color.opacity(0.12))
                    .clipShape(Capsule())

                    Spacer()

                    // Source icon
                    Image(systemName: injury.source.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                HStack(spacing: 12) {
                    // Severity
                    HStack(spacing: 4) {
                        SeverityDots(severity: injury.severity)
                        Text("\(injury.severity)/10")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    // Duration
                    Text("\(injury.daysSinceReported)d")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)

                    if let desc = injury.description, !desc.isEmpty {
                        Text(desc)
                            .font(.dripBody(12))
                            .foregroundStyle(Color.drip.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - SeverityDots

struct SeverityDots: View {
    let severity: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1 ... 10, id: \.self) { level in
                Circle()
                    .fill(level <= severity ? colorForLevel(level) : Color.drip.textTertiary.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

// MARK: - ResolvedInjuriesSection

struct ResolvedInjuriesSection: View {
    let injuries: [Injury]
    let onSelect: (Injury) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("RESOLVED")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(1.2)

                    Text("\(injuries.count)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.drip.textTertiary.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 20)

            if isExpanded {
                LazyVStack(spacing: 8) {
                    ForEach(injuries) { injury in
                        InjuryCard(injury: injury)
                            .opacity(0.7)
                            .onTapGesture { onSelect(injury) }
                    }
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - InjuryDetailSheet

struct InjuryDetailSheet: View {
    let injury: Injury
    @Bindable var injuryService: InjuryService
    @Environment(\.dismiss) private var dismiss

    @State private var editedSeverity: Double
    @State private var editedDescription: String
    @State private var editedStatus: InjuryStatus
    @State private var showDeleteConfirmation = false
    @State private var hasChanges = false

    init(injury: Injury, injuryService: InjuryService) {
        self.injury = injury
        self.injuryService = injuryService
        _editedSeverity = State(initialValue: Double(injury.severity))
        _editedDescription = State(initialValue: injury.description ?? "")
        _editedStatus = State(initialValue: injury.status)
    }

    /// Live injury from the service array — reflects updates (e.g. AI analysis) in real time.
    private var currentInjury: Injury {
        injuryService.injuries.first { $0.id == injury.id } ?? injury
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text(injury.displayName)
                                .font(.dripDisplay(28))
                                .foregroundStyle(Color.drip.textPrimary)

                            HStack(spacing: 12) {
                                Label(injury.source.displayName, systemImage: injury.source.icon)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)

                                Text("\(injury.daysSinceReported) days")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                        .padding(.top, 8)

                        // Status picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STATUS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                ForEach(InjuryStatus.allCases, id: \.self) { status in
                                    Button {
                                        editedStatus = status
                                        hasChanges = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: status.icon)
                                                .font(.system(size: 11))
                                            Text(status.displayName)
                                                .font(.dripLabel(12))
                                        }
                                        .foregroundStyle(editedStatus == status ? .white : status.color)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(editedStatus == status ? status.color : status.color.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Severity slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SEVERITY")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .tracking(1.2)

                                Spacer()

                                Text("\(Int(editedSeverity))/10 — \(severityLabelForValue(Int(editedSeverity)))")
                                    .font(.dripStat(14))
                                    .foregroundStyle(severityColorForValue(Int(editedSeverity)))
                            }

                            Slider(value: $editedSeverity, in: 1 ... 10, step: 1) {
                                Text("Severity")
                            }
                            .tint(severityColorForValue(Int(editedSeverity)))
                            .onChange(of: editedSeverity) { hasChanges = true }

                            // Severity reference
                            HStack {
                                Text("Mild")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.positive)
                                Spacer()
                                Text("Moderate")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.tired)
                                Spacer()
                                Text("Severe")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.injured)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            TextField("Describe the injury...", text: $editedDescription, axis: .vertical)
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineLimit(3 ... 6)
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onChange(of: editedDescription) { hasChanges = true }
                        }
                        .padding(.horizontal, 20)

                        // Save button
                        if hasChanges {
                            Button {
                                Task { await saveChanges() }
                            } label: {
                                Text("Save Changes")
                                    .font(.dripLabel(14))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.drip.coral)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 20)
                        }

                        // AI Analysis section
                        InjuryAnalysisSection(injury: currentInjury, injuryService: injuryService)
                            .padding(.horizontal, 20)

                        // Timeline
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIMELINE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            VStack(alignment: .leading, spacing: 6) {
                                TimelineRow(label: "First reported", date: injury.firstReportedAt)
                                if let resolved = injury.resolvedAt {
                                    TimelineRow(label: "Resolved", date: resolved)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        // Delete
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                Text("Delete Injury")
                                    .font(.dripBody(13))
                            }
                            .foregroundStyle(Color.drip.injured.opacity(0.7))
                        }
                        .padding(.top, 8)

                        Spacer().frame(height: 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
        }
        .alert("Delete Injury?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    _ = await injuryService.deleteInjury(id: injury.id)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently remove this injury record.")
        }
    }

    private func saveChanges() async {
        let newStatus: InjuryStatus? = editedStatus != injury.status ? editedStatus : nil
        let newSeverity: Int? = Int(editedSeverity) != injury.severity ? Int(editedSeverity) : nil
        let newDescription: String? = editedDescription != (injury.description ?? "") ? editedDescription : nil

        _ = await injuryService.updateInjury(
            id: injury.id,
            severity: newSeverity,
            status: newStatus,
            description: newDescription
        )
        hasChanges = false
    }

    private func severityLabelForValue(_ value: Int) -> String {
        switch value {
        case 1 ... 3: return "Mild"
        case 4 ... 6: return "Moderate"
        case 7 ... 8: return "Severe"
        case 9 ... 10: return "Critical"
        default: return ""
        }
    }

    private func severityColorForValue(_ value: Int) -> Color {
        switch value {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

// MARK: - TimelineRow

struct TimelineRow: View {
    let label: String
    let date: Date

    var body: some View {
        HStack {
            Text(label)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(date, style: .date)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - InjuryAnalysisSection

struct InjuryAnalysisSection: View {
    let injury: Injury
    @Bindable var injuryService: InjuryService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI ANALYSIS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(1.2)

                Spacer()

                if let analysisDate = injury.aiAnalysisAt {
                    Text(analysisDate, style: .relative)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if let analysis = injury.aiAnalysis {
                AnalysisResultView(analysis: analysis)
            } else if injuryService.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.drip.coral)
                    Text("Analyzing injury...")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                if let error = injuryService.errorMessage {
                    Text(error)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.injured)
                        .padding(.bottom, 4)
                }

                Button {
                    Task { _ = await injuryService.analyzeInjury(injuryId: injury.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Analyze Injury")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.drip.coral.opacity(0.3), lineWidth: 1)
                    )
                }
            }

            MedicalDisclaimerBanner(text: MedicalDisclaimer.aiAnalysis, isCompact: true)
        }
    }
}

// MARK: - AnalysisResultView

struct AnalysisResultView: View {
    let analysis: InjuryAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary
            if let summary = analysis.summary {
                Text(summary)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(3)
            }

            // Risk level
            if let risk = analysis.riskLevel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(analysis.riskColor)
                        .frame(width: 8, height: 8)
                    Text("Risk: \(risk.capitalized)")
                        .font(.dripLabel(13))
                        .foregroundStyle(analysis.riskColor)
                }
            }

            // Recurring injury warning
            if analysis.isRecurring == true {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Recurring injury pattern detected")
                        .font(.dripLabel(12))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Recovery timeline
            if let timeline = analysis.recoveryTimelineDays {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOVERY TIMELINE")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 16) {
                        if let opt = timeline.optimistic {
                            TimelineStatView(label: "Best", days: opt, color: Color.drip.positive)
                        }
                        if let typ = timeline.typical {
                            TimelineStatView(label: "Typical", days: typ, color: Color.drip.tired)
                        }
                        if let con = timeline.conservative {
                            TimelineStatView(label: "Conservative", days: con, color: Color.drip.injured)
                        }
                    }
                }
            }

            // Likely causes
            if let causes = analysis.likelyCauses, !causes.isEmpty {
                AnalysisListSection(title: "LIKELY CAUSES", items: causes, icon: "arrow.right.circle.fill", color: Color.drip.textSecondary)
            }

            // Recommended actions
            if let actions = analysis.recommendedActions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECOMMENDED ACTIONS")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    ForEach(actions) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Text(action.priorityLabel)
                                .font(.dripCaption(9))
                                .foregroundStyle(action.priorityColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(action.priorityColor.opacity(0.12))
                                .clipShape(Capsule())
                                .frame(width: 52)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.action)
                                    .font(.dripLabel(12))
                                    .foregroundStyle(Color.drip.textPrimary)
                                Text(action.detail)
                                    .font(.dripBody(11))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }
                    }
                }
            }

            // Warning signs
            if let warnings = analysis.warningSigns, !warnings.isEmpty {
                AnalysisListSection(title: "SEEK MEDICAL ATTENTION IF", items: warnings, icon: "exclamationmark.triangle.fill", color: Color.drip.injured)
            }

            // Return to running
            if let criteria = analysis.returnToRunningCriteria, !criteria.isEmpty {
                AnalysisListSection(title: "RETURN TO RUNNING WHEN", items: criteria, icon: "checkmark.circle.fill", color: Color.drip.positive)
            }

            // Goal impact
            if let goalImpact = analysis.goalImpact, !goalImpact.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GOAL IMPACT")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    Text(goalImpact)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AnalysisListSection

struct AnalysisListSection: View {
    let title: String
    let items: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.8)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                        .padding(.top, 2)
                    Text(item)
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }
}

// MARK: - TimelineStatView

struct TimelineStatView: View {
    let label: String
    let days: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(days)")
                .font(.dripStat(18))
                .foregroundStyle(color)
            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - AddInjurySheet

struct AddInjurySheet: View {
    @Bindable var injuryService: InjuryService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBodyArea: BodyArea?
    @State private var selectedSide = "unknown"
    @State private var severity: Double = 5
    @State private var description = ""
    @State private var isSaving = false
    @State private var showError = false

    let sides = ["left", "right", "both", "unknown"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Body area picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BODY AREA")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], spacing: 8) {
                                ForEach(BodyArea.allCases, id: \.self) { area in
                                    Button {
                                        selectedBodyArea = area
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: area.icon)
                                                .font(.system(size: 16))
                                            Text(area.displayName)
                                                .font(.dripCaption(11))
                                        }
                                        .foregroundStyle(selectedBodyArea == area ? .white : Color.drip.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedBodyArea == area ? Color.drip.coral : Color.drip.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Side picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SIDE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                ForEach(sides, id: \.self) { side in
                                    Button {
                                        selectedSide = side
                                    } label: {
                                        Text(side == "unknown" ? "N/A" : side.capitalized)
                                            .font(.dripLabel(13))
                                            .foregroundStyle(selectedSide == side ? .white : Color.drip.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selectedSide == side ? Color.drip.coral : Color.drip.cardBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Severity
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SEVERITY")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .tracking(1.2)

                                Spacer()

                                Text("\(Int(severity))/10")
                                    .font(.dripStat(16))
                                    .foregroundStyle(severityColor)
                            }

                            Slider(value: $severity, in: 1 ... 10, step: 1)
                                .tint(severityColor)
                        }
                        .padding(.horizontal, 20)

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESCRIPTION (optional)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            TextField("What happened? How does it feel?", text: $description, axis: .vertical)
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineLimit(3 ... 5)
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        // Medical disclaimer
                        MedicalDisclaimerBanner(text: MedicalDisclaimer.short, isCompact: true)
                            .padding(.horizontal, 20)

                        // Save button
                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                }
                                Text("Add Injury")
                                    .font(.dripLabel(15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedBodyArea != nil ? Color.drip.coral : Color.drip.coral.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selectedBodyArea == nil || isSaving)
                        .padding(.horizontal, 20)

                        Spacer().frame(height: 40)
                    }
                    .padding(.top, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("ADD INJURY")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(injuryService.errorMessage ?? "Could not save injury.")
            }
        }
    }

    private var severityColor: Color {
        switch Int(severity) {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }

    private func save() async {
        guard let area = selectedBodyArea else { return }
        isSaving = true

        let success = await injuryService.createInjury(
            bodyArea: area.rawValue,
            side: selectedSide,
            severity: Int(severity),
            description: description.isEmpty ? nil : description
        )

        isSaving = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }
}

// MARK: - MedicalDisclaimerBanner

struct MedicalDisclaimerBanner: View {
    let text: String
    var isCompact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.circle.fill")
                .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                .foregroundStyle(Color.drip.injured)

            Text(text)
                .font(isCompact ? .dripCaption(11) : .dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.injured.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.injured.opacity(0.2), lineWidth: 1)
        )
    }
}
