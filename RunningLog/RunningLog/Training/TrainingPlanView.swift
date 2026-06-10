//
//  TrainingPlanView.swift
//  RunningLog
//
//  Main view for the training plan calendar system.
//

import SwiftUI

// MARK: - TrainingPlanView

struct TrainingPlanView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var viewModel = TrainingPlanViewModel()
    @State private var viewMode: CalendarViewMode = .week
    @State private var selectedWorkout: ScheduledWorkout?
    @State private var showPlanSettings = false
    @State private var showImportWeek = false
    @State private var showImportPlan = false
    @State private var selectedLogEntry: TrainingLog?
    @State private var dayLogEntries: [TrainingLog] = []
    @State private var showDayLogPicker = false
    @State private var showWeeklyReport = false
    @State private var showReschedule = false
    // Build Adaptive Plan is suspended — see docs/build-adaptive-plan-suspension.md.
    // When re-enabling, restore `showAdaptiveBuilder` + the sheet presentation below.
    @State private var showJoinCoachPlan = false
    @State private var showEditGoal = false
    @State private var showRecomputePrompt = false
    @State private var showDeleteConfirm = false
    // AO-5 — "Edit preferences" reopens the join sheet in edit mode.
    @State private var editPreferencesPayload: JoinCoachPlanEditMode?
    @State private var coachViewModel = CoachViewModel()

    var body: some View {
        ZStack {
            DripBackground()

            if viewModel.isLoadingPlan {
                LoadingPlanView()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // ── Goal one-liner (compact) ───────────────────
                        nsGoalLine
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // ── Pace ladder (4-column hairline strip) ──────
                        if PaceZonesService.shared.zones != nil || viewModel.equivalentPaces != nil {
                            nsPaceLadderStrip
                                .padding(.horizontal, 20)
                                .padding(.top, 18)
                        }

                        // ── Mode toggle (WEEK | MONTH) ─────────────────
                        if viewModel.activePlan != nil {
                            nsCalendarModeToggle
                                .padding(.horizontal, 20)
                                .padding(.top, 22)
                        }

                        // ── Calendar content — Plate 12 (WEEK) or Plate 13 (MONTH) ──
                        if viewModel.activePlan != nil {
                            if viewMode == .week {
                                PlanWeekListView(
                                    viewModel: viewModel,
                                    onDayTap: { workout in
                                        selectedWorkout = workout
                                    }
                                )
                                .padding(.top, 4)
                            } else {
                                PlanMonthSummaryView(
                                    viewModel: viewModel,
                                    onWeekTap: { _ in
                                        // Jump to week view when a week row is tapped.
                                        // Future: scroll to that specific week.
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            viewMode = .week
                                        }
                                    }
                                )
                                .padding(.top, 4)
                            }
                        }

                        // ── Empty state (no plan) ──────────────────────
                        if viewModel.activePlan == nil {
                            nsEmptyPlanPrompt
                                .padding(.horizontal, 20)
                                .padding(.top, 32)
                        }

                        Spacer()
                            .frame(height: 100)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("TRAINING PLAN")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.activePlan != nil {
                    Menu {
                        Button {
                            showJoinCoachPlan = true
                        } label: {
                            Label("Join Coach's Plan", systemImage: "person.badge.shield.checkmark")
                        }

                        Button {
                            showImportPlan = true
                        } label: {
                            Label("Import Plan", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            showImportWeek = true
                        } label: {
                            Label("Import Week", systemImage: "doc.text")
                        }

                        Divider()

                        Button {
                            showReschedule = true
                        } label: {
                            Label("AI Reschedule", systemImage: "sparkles")
                        }

                        Button {
                            showWeeklyReport = true
                        } label: {
                            Label("Weekly Analysis", systemImage: "waveform.path.ecg")
                        }

                        Button {
                            showEditGoal = true
                        } label: {
                            Label("Edit Goal", systemImage: "target")
                        }

                        // Edit subscription preferences — only meaningful
                        // for plans subscribed from a coach template.
                        if viewModel.activePlan?.planTemplateId != nil {
                            Button {
                                Task { await openEditPreferences() }
                            } label: {
                                Label("Edit Preferences", systemImage: "slider.horizontal.3")
                            }
                        }

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task {
                await viewModel.loadActivePlan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingPlanDidChange)) { _ in
            Task { await viewModel.loadActivePlan() }
        }
        .sheet(isPresented: $showJoinCoachPlan) {
            JoinCoachPlanSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editPreferencesPayload) { payload in
            JoinCoachPlanSheet(editMode: payload)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportWeek) {
            ImportWeekSheet(
                viewModel: viewModel,
                importService: viewModel.importService,
                initialWeekNumber: viewModel.selectedWeek
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportPlan) {
            ImportTrainingPlanSheet(viewModel: viewModel, importService: viewModel.importService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedWorkout) { workout in
            DayDetailSheet(
                viewModel: viewModel,
                scheduledWorkout: workout,
                racePaceSeconds: viewModel.racePaceSecondsPerMile ?? 480
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLogEntry) { entry in
            HistoryDetailSheet(entry: entry) {
                Task { await viewModel.loadMoodDataForCurrentMonth() }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDayLogPicker) {
            DayLogPickerSheet(entries: dayLogEntries) { entry in
                showDayLogPicker = false
                selectedLogEntry = entry
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyCoachingReportSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReschedule) {
            RescheduleSheet(viewModel: viewModel, initialScope: .remainingPlan)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Training Plan", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deletePlan()
                }
            }
        } message: {
            Text("Are you sure you want to delete this training plan? This action cannot be undone.")
        }
        .sheet(isPresented: $showEditGoal) {
            // EditGoalSheet now accepts a nil plan — used by GoalAndPacesCard's
            // empty state to set an athlete-level goal before subscribing.
            EditGoalSheet(viewModel: viewModel, plan: viewModel.activePlan, onSaved: {
                // After a successful goal save against an active plan, surface
                // the soft-ask about recomputing future workout paces. The
                // sheet skips this callback when there's no plan.
                showRecomputePrompt = true
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showRecomputePrompt) {
            if let plan = viewModel.activePlan {
                RecomputePacesSheet(plan: plan, onComplete: {
                    await viewModel.loadActivePlan()
                })
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    /// Load the plan template + the athlete's existing subscription,
    /// then present JoinCoachPlanSheet in edit mode. Quietly drops if
    /// the subscription or template can't be located — fall back to the
    /// (still-functional) Edit Goal path.
    @MainActor
    private func openEditPreferences() async {
        guard let plan = viewModel.activePlan,
              let templateId = plan.planTemplateId else { return }
        async let templatePromise = coachViewModel.loadPlanTemplate(id: templateId)
        async let subPromise = coachViewModel.loadActiveSubscription(forTrainingPlanId: plan.id)
        let (template, subscription) = await (templatePromise, subPromise)
        guard let template, let subscription else { return }
        editPreferencesPayload = JoinCoachPlanEditMode(plan: template, subscription: subscription)
    }

    // MARK: - Negative Splits — top-of-page elements

    /// One-line goal summary. Tap to edit.
    @ViewBuilder
    private var nsGoalLine: some View {
        Button {
            showEditGoal = true
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("GOAL  ·  \(goalDistanceLabel)")
                    .font(.dripCaption(11))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.coral)
                Text(goalSummaryLine)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textPrimary)
                    .padding(.leading, 6)
                Spacer()
                HStack(spacing: 4) {
                    Text("EDIT")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var goalDistanceLabel: String {
        let raw = viewModel.activePlan?.targetRaceDistance ?? "MARATHON"
        return raw.uppercased()
    }

    private var goalSummaryLine: String {
        let goalSeconds: Int? = viewModel.activePlan?.targetTimeSeconds
            ?? viewModel.marathonGoalTime
        var parts: [String] = []
        if let g = goalSeconds, g > 0 {
            parts.append(formatGoalTime(g))
        } else {
            return "Tap to set a goal"
        }
        if let plan = viewModel.activePlan {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            parts.append(f.string(from: plan.endDate))
            if plan.daysRemaining > 0 {
                parts.append("\(plan.daysRemaining) days out")
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    private func formatGoalTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Pace ladder — four hairline-divided columns: EASY / MP / LT / 5K.
    /// Sources from `PaceZonesService.shared.zones` (engine output) first;
    /// falls back to `viewModel.equivalentPaces` only when the engine has
    /// not loaded the user's zones yet.
    @ViewBuilder
    private var nsPaceLadderStrip: some View {
        if let cells = paceLadderCells {
            VStack(spacing: 0) {
                Rectangle().fill(Color.drip.divider).frame(height: 1)
                HStack(spacing: 0) {
                    nsPaceCell(label: "EASY",  paceSeconds: cells.easy,      color: Color.drip.energized)
                    nsPaceCellDivider
                    nsPaceCell(label: "MP",    paceSeconds: cells.mp,        color: Color.drip.textSecondary)
                    nsPaceCellDivider
                    nsPaceCell(label: "LT",    paceSeconds: cells.threshold, color: Color.drip.coral)
                    nsPaceCellDivider
                    nsPaceCell(label: "5K",    paceSeconds: cells.fiveK,     color: Color.drip.textPrimary)
                }
                Rectangle().fill(Color.drip.divider).frame(height: 1)
            }
        }
    }

    /// Resolve the four ladder values, preferring the pace engine and
    /// falling back to the legacy goal-derived values when the engine has
    /// not yet computed zones for this athlete.
    private var paceLadderCells: (easy: Double, mp: Double, threshold: Double, fiveK: Double)? {
        if let z = PaceZonesService.shared.zones,
           let easy = z.easyMidpoint,
           let mp = z.marathon?.pace,
           let threshold = z.thresholdPace,
           let fiveK = z.fiveK?.pace {
            return (easy, mp, threshold, fiveK)
        }
        if let p = viewModel.equivalentPaces {
            return (p.easyPace, p.mpPace, p.thresholdPace, p.fiveKPace)
        }
        return nil
    }

    private var nsPaceCellDivider: some View {
        Rectangle()
            .fill(Color.drip.divider)
            .frame(width: 1, height: 36)
    }

    @ViewBuilder
    private func nsPaceCell(label: String, paceSeconds: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(color)
            Text(formatPaceSeconds(paceSeconds))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func formatPaceSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// WEEK | MONTH toggle — text + amber underline. Same pattern as the
    /// Log tab's mode toggle.
    @ViewBuilder
    private var nsCalendarModeToggle: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.drip.divider).frame(height: 1)
            HStack(spacing: 0) {
                nsToggleButton(label: "WEEK", active: viewMode == .week) {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = .week }
                }
                nsToggleButton(label: "MONTH", active: viewMode == .month) {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = .month }
                }
            }
            Rectangle().fill(Color.drip.divider).frame(height: 1)
        }
    }

    @ViewBuilder
    private func nsToggleButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(active ? Color.drip.coral : Color.drip.textSecondary)
                    .padding(.top, 12)
                Rectangle()
                    .fill(active ? Color.drip.coral : Color.clear)
                    .frame(height: 2)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Empty-plan prompt — quieter than the original two-button stack.
    @ViewBuilder
    private var nsEmptyPlanPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PICK A STARTING POINT")
                .font(.dripCaption(11))
                .tracking(1.2)
                .foregroundStyle(Color.drip.textSecondary)

            Text("Join your coach's plan, or import one you've built.")
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Color.drip.textSecondary)

            Rectangle().fill(Color.drip.divider).frame(height: 1)
                .padding(.top, 4)

            Button {
                showJoinCoachPlan = true
            } label: {
                HStack {
                    Text("JOIN COACH'S PLAN")
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.coral)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.drip.divider).frame(height: 1)

            Button {
                showImportPlan = true
            } label: {
                HStack {
                    Text("IMPORT PLAN")
                        .font(.dripCaption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.drip.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.drip.textPrimary)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Loading Plan View

struct LoadingPlanView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.drip.coral)

            Text("Loading your training plan...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }
}

// MARK: - Day Log Picker Sheet

struct DayLogPickerSheet: View {
    let entries: [TrainingLog]
    let onSelect: (TrainingLog) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 12) {
                        if let mood = entry.mood {
                            MoodBadge(mood: mood)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let type = entry.workoutType {
                                Text(type.capitalized)
                                    .font(.dripLabel(14))
                                    .foregroundStyle(Color.drip.textPrimary)
                            }

                            HStack(spacing: 8) {
                                if let miles = entry.workoutDistanceMiles, miles > 0 {
                                    Text(String(format: "%.1f mi", miles))
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                                if let mins = entry.workoutDurationMinutes, mins > 0 {
                                    Text(String(format: "%.0f min", mins))
                                        .font(.dripCaption(12))
                                        .foregroundStyle(Color.drip.textSecondary)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TrainingPlanView()
    }
}
