//
//  RescheduleSheet.swift
//  RunningLog
//
//  AI-powered reschedule sheet with context gathering, preview, and apply flow.
//

import SwiftUI

// MARK: - RescheduleSheet

struct RescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let initialScope: RescheduleScope
    let targetDate: Date?

    @State private var service = RescheduleService()
    @State private var scope: RescheduleScope
    @State private var selectedReason: RescheduleReason?
    @State private var reasonText = ""
    @State private var step: RescheduleStep = .context
    @State private var refineFeedback = ""
    @State private var editingChangeId: UUID?
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isRefineFocused: Bool

    init(viewModel: TrainingPlanViewModel, initialScope: RescheduleScope = .week, targetDate: Date? = nil) {
        self.viewModel = viewModel
        self.initialScope = initialScope
        self.targetDate = targetDate
        self._scope = State(initialValue: initialScope)
    }

    enum RescheduleStep {
        case context
        case loading
        case preview
        case applying
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                switch step {
                case .context:
                    contextView
                case .loading:
                    loadingView
                case .preview:
                    if let preview = service.preview {
                        previewView(preview)
                    }
                case .applying:
                    applyingView
                case .done:
                    doneView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AI RESCHEDULE")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Step 1: Context

    private var contextView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.drip.coral)

                    Text("Reschedule Your Plan")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Tell me what happened and I'll reorganize your workouts.")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Scope selector
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCOPE")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    HStack(spacing: 8) {
                        ForEach(RescheduleScope.allCases, id: \.rawValue) { s in
                            ScopeChip(scope: s, isSelected: scope == s) {
                                scope = s
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Reason selector
                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT HAPPENED?")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    FlowLayout(spacing: 8) {
                        ForEach(RescheduleReason.allCases, id: \.rawValue) { reason in
                            ReasonChip(reason: reason, isSelected: selectedReason == reason) {
                                selectedReason = reason
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Details text field
                VStack(alignment: .leading, spacing: 10) {
                    Text("DETAILS (OPTIONAL)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    TextField("e.g., missed 3 days with a cold...", text: $reasonText, axis: .vertical)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(3...5)
                        .padding(12)
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.drip.divider, lineWidth: 1)
                        )
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)

                // Error message
                if let error = service.errorMessage {
                    Text(error)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.injured)
                        .padding(.horizontal, 20)
                }

                // Submit button
                Button {
                    submitReschedule()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Reschedule")
                            .font(.dripLabel(15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedReason != nil ? Color.drip.coral : Color.drip.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedReason == nil)
                .padding(.horizontal, 20)

                Spacer().frame(height: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 2: Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .tint(Color.drip.coral)
                .scaleEffect(1.2)

            Text("Rethinking your plan...")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textSecondary)

            Text("Analyzing training load, recovery needs, and upcoming goals")
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Step 3: Preview

    private func previewView(_ preview: ReschedulePreview) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Coach message
                if !preview.coachMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.drip.coral)
                            Text("COACH")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)
                        }

                        Text(preview.coachMessage)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textPrimary)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.drip.coral.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.drip.coral.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                // Summary stats
                HStack(spacing: 12) {
                    RescheduleStatCard(
                        value: "\(preview.approvedCount)",
                        label: "Approved"
                    )
                    RescheduleStatCard(
                        value: "\(preview.changes.count - preview.approvedCount)",
                        label: "Rejected"
                    )
                }
                .padding(.horizontal, 20)

                // Changes list with approval toggles
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PROPOSED CHANGES")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        Spacer()

                        // Bulk actions
                        Button {
                            toggleAllChanges(approved: true)
                        } label: {
                            Text("All")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.coral)
                        }

                        Text("/")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)

                        Button {
                            toggleAllChanges(approved: false)
                        } label: {
                            Text("None")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)

                    ForEach(Array(preview.changes.enumerated()), id: \.element.id) { index, change in
                        RescheduleChangeCard(
                            change: change,
                            isEditing: editingChangeId == change.id,
                            onToggleApproval: {
                                service.preview?.changes[index].isApproved.toggle()
                            },
                            onTapEdit: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingChangeId = editingChangeId == change.id ? nil : change.id
                                }
                            },
                            onChangeType: { newType in
                                service.preview?.changes[index].after.workoutType = newType
                                service.preview?.changes[index].after.name = newType.displayName
                            }
                        )
                    }
                    .padding(.horizontal, 20)
                }

                // Refine with feedback
                VStack(alignment: .leading, spacing: 10) {
                    Text("REFINE")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(1.2)

                    HStack(spacing: 8) {
                        TextField("e.g., keep the long run on Saturday...", text: $refineFeedback)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                            .padding(10)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                            .focused($isRefineFocused)

                        Button {
                            refineReschedule()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(refineFeedback.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(refineFeedback.isEmpty)
                    }
                }
                .padding(.horizontal, 20)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        applyReschedule(preview)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Apply \(preview.approvedCount) Change\(preview.approvedCount == 1 ? "" : "s")")
                                .font(.dripLabel(15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(preview.approvedCount > 0 ? Color.drip.coral : Color.drip.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(preview.approvedCount == 0)

                    Button {
                        step = .context
                        service.preview = nil
                        refineFeedback = ""
                        editingChangeId = nil
                    } label: {
                        Text("Start Over")
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer().frame(height: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Step 4: Applying

    private var applyingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: Double(service.applyProgress), total: Double(max(1, service.applyTotal)))
                .tint(Color.drip.coral)
                .frame(width: 200)

            Text("Applying changes...")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textSecondary)

            Text("\(service.applyProgress) of \(service.applyTotal)")
                .font(.dripCaption(13))
                .foregroundStyle(Color.drip.textTertiary)

            Spacer()
        }
    }

    // MARK: - Step 5: Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.drip.energized)

            Text("Plan Updated")
                .font(.dripDisplay(24))
                .foregroundStyle(Color.drip.textPrimary)

            Text("Your training plan has been rescheduled.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.dripLabel(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Actions

    private func submitReschedule() {
        guard let reason = selectedReason,
              let plan = viewModel.service.activePlan
        else { return }

        isTextFieldFocused = false
        step = .loading

        let details = reasonText.isEmpty ? reason.displayName : reasonText

        Task {
            await service.requestReschedule(
                scope: scope,
                reason: details,
                reasonCategory: reason,
                plan: plan,
                allWorkouts: viewModel.service.allScheduledWorkouts,
                targetDate: targetDate
            )

            if service.preview != nil {
                step = .preview
            } else {
                step = .context
            }
        }
    }

    private func toggleAllChanges(approved: Bool) {
        guard var preview = service.preview else { return }
        for i in preview.changes.indices {
            preview.changes[i].isApproved = approved
        }
        service.preview = preview
    }

    private func refineReschedule() {
        guard let plan = viewModel.service.activePlan,
              let reason = selectedReason
        else { return }

        isRefineFocused = false
        let feedback = refineFeedback
        refineFeedback = ""
        editingChangeId = nil
        step = .loading

        // Combine original reason with refinement feedback
        let originalReason = reasonText.isEmpty ? reason.displayName : reasonText
        let combinedReason = "\(originalReason). REFINEMENT: \(feedback)"

        Task {
            await service.requestReschedule(
                scope: scope,
                reason: combinedReason,
                reasonCategory: reason,
                plan: plan,
                allWorkouts: viewModel.service.allScheduledWorkouts,
                targetDate: targetDate
            )

            if service.preview != nil {
                step = .preview
            } else {
                step = .context
            }
        }
    }

    private func applyReschedule(_ preview: ReschedulePreview) {
        step = .applying

        Task {
            let success = await service.applyChanges(
                preview: preview,
                allWorkouts: viewModel.service.allScheduledWorkouts,
                planService: viewModel.service
            )

            if success {
                // Reload the plan data
                await viewModel.service.loadScheduledWorkouts()
                step = .done
            } else {
                step = .preview
            }
        }
    }
}

// MARK: - Supporting Views

struct ScopeChip: View {
    let scope: RescheduleScope
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: scope.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(scope.displayName)
                    .font(.dripCaption(12))
            }
            .foregroundStyle(isSelected ? .white : Color.drip.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReasonChip: View {
    let reason: RescheduleReason
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: reason.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(reason.displayName)
                    .font(.dripCaption(12))
            }
            .foregroundStyle(isSelected ? .white : Color.drip.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RescheduleStatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.coral)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

struct RescheduleChangeCard: View {
    let change: ReschedulePreview.WorkoutChange
    var isEditing: Bool = false
    var onToggleApproval: (() -> Void)?
    var onTapEdit: (() -> Void)?
    var onChangeType: ((ScheduledWorkoutType) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header with approval toggle
            HStack {
                // Approval toggle
                Button {
                    onToggleApproval?()
                } label: {
                    Image(systemName: change.isApproved ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(change.isApproved ? Color.drip.positive : Color.drip.textTertiary)
                }
                .buttonStyle(.plain)

                Text(change.date, format: .dateTime.weekday(.wide))
                    .font(.dripLabel(14))
                    .foregroundStyle(change.isApproved ? Color.drip.textPrimary : Color.drip.textTertiary)

                Text(change.date, format: .dateTime.month(.abbreviated).day())
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()

                // Edit button
                Button {
                    onTapEdit?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isEditing ? Color.drip.coral : Color.drip.textTertiary)
                }
                .buttonStyle(.plain)

                Text("Wk \(change.weekNumber)")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            // Before → After
            HStack(spacing: 12) {
                // Before
                VStack(alignment: .leading, spacing: 4) {
                    Text("BEFORE")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(change.before.workoutType.color.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(change.before.name ?? change.before.workoutType.displayName)
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textTertiary)
                            .strikethrough()
                    }

                    if let miles = change.before.totalDistanceMiles, miles > 0 {
                        Text(String(format: "%.1f mi", miles))
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(change.isApproved ? Color.drip.coral : Color.drip.textTertiary)

                // After
                VStack(alignment: .leading, spacing: 4) {
                    Text("AFTER")
                        .font(.dripCaption(9))
                        .foregroundStyle(change.isApproved ? Color.drip.coral : Color.drip.textTertiary)
                        .tracking(0.8)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(change.after.workoutType.color)
                            .frame(width: 8, height: 8)
                        Text(change.after.name ?? change.after.workoutType.displayName)
                            .font(.dripBody(13))
                            .foregroundStyle(change.isApproved ? Color.drip.textPrimary : Color.drip.textTertiary)
                    }

                    if let miles = change.after.totalDistanceMiles, miles > 0 {
                        Text(String(format: "%.1f mi", miles))
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(change.isApproved ? 1.0 : 0.5)

            // Inline workout type picker (when editing)
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHANGE TYPE")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    FlowLayout(spacing: 6) {
                        ForEach(ScheduledWorkoutType.allCases, id: \.rawValue) { type in
                            Button {
                                onChangeType?(type)
                            } label: {
                                Text(type.displayName)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(change.after.workoutType == type ? .white : type.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(change.after.workoutType == type ? type.color : type.color.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Notes
            if let notes = change.notes, !notes.isEmpty {
                Text(notes)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .italic()
            }
        }
        .padding(16)
        .background(change.isApproved ? Color.drip.cardBackground : Color.drip.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(change.isApproved ? Color.drip.coral.opacity(0.3) : Color.drip.divider, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: change.isApproved)
    }
}

// FlowLayout is defined in WeeklyCoachingReportSheet.swift
