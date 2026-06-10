//
//  DayDetailSheet.swift
//  RunningLog
//
//  Detail sheet for viewing and editing a scheduled workout day.
//

import SwiftUI
import Supabase
import PostgREST
import os

// MARK: - DayDetailSheet

struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VitalManager.self) private var vitalManager
    @Bindable var viewModel: TrainingPlanViewModel
    let scheduledWorkout: ScheduledWorkout
    let racePaceSeconds: Double

    /// App-wide heat-adjustment preference. Same @AppStorage key used by
    /// HeatCalculatorCard so both views stay in sync. When off, the
    /// step rows below also hide their adjusted-pace lines — flipping
    /// the toggle on the calculator silences ALL heat-adjusted UI on
    /// this sheet.
    @AppStorage("heatAdjustmentEnabled") private var heatAdjustmentEnabled: Bool = true

    /// Live view of the workout — looks up the latest version from the
    /// service cache by id every render. The `scheduledWorkout` let is
    /// a snapshot taken when the sheet was presented; without this
    /// indirection, mutations from `updateScheduledTime` (new
    /// scheduled_hour + refreshed weather_forecast) wouldn't appear in
    /// the sheet until the athlete dismissed and reopened it.
    private var liveWorkout: ScheduledWorkout {
        viewModel.service.allScheduledWorkouts
            .first(where: { $0.id == scheduledWorkout.id }) ?? scheduledWorkout
    }

    /// Forecast to pass to step rows. Nil when the athlete has disabled
    /// heat adjustment so the step-level "adjusted pace" line stays
    /// hidden too.
    private var effectiveForecast: WorkoutForecast? {
        heatAdjustmentEnabled ? liveWorkout.weatherForecast : nil
    }

    @State private var showSwapPicker = false
    @State private var showAddWorkoutPicker = false
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var showExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage: String?

    // Edit mode state
    @State private var isEditing = false
    @State private var editableSteps: [EditableWorkoutStep] = []
    @State private var isSavingEdits = false
    @State private var showZoneAdjustment = false
    @State private var showWorkoutChat = false
    @State private var showReschedule = false

    // Workshop mode (for creating/replacing workouts)
    @State private var showWorkshop = false
    @State private var workshopTab: WorkshopTab = .build
    @State private var shorthandInput = ""
    @State private var shorthandResult: ShorthandParseResult?
    @State private var isParsingShorthand = false
    @State private var shorthandDebounceTask: Task<Void, Never>?

    // Vital completed workout data
    @State private var completedVitalWorkouts: [RunningWorkout] = []
    @State private var showVitalDetail = false
    @State private var selectedVitalWorkout: RunningWorkout?

    /// Server-generated coaching insight for the linked training_logs row.
    /// Populated in `.task` when the sheet appears. Trimmed to a single
    /// sentence to match the Today home treatment.
    @State private var aiInsight: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Day Header (Plate 22 — editorial). Stat strip
                        // sits directly below for non-rest, non-edit, non-
                        // workshop reads. Both replace the previous
                        // sans-serif title + pill chrome.
                        VStack(alignment: .leading, spacing: 16) {
                            DD22Header(workout: scheduledWorkout)
                            if !scheduledWorkout.isRestDay,
                               !showWorkshop,
                               !isEditing,
                               scheduledWorkout.workout != nil {
                                DD22StatStrip(workout: scheduledWorkout)
                            }
                        }
                        .padding(.horizontal, 20)

                        if scheduledWorkout.isRestDay || showWorkshop {
                            // Workshop: create or replace a workout right here
                            WorkshopView(
                                viewModel: viewModel,
                                scheduledWorkout: scheduledWorkout,
                                racePaceSeconds: racePaceSeconds,
                                selectedTab: $workshopTab,
                                shorthandInput: $shorthandInput,
                                shorthandResult: $shorthandResult,
                                isParsingShorthand: $isParsingShorthand,
                                onWorkoutApplied: {
                                    showWorkshop = false
                                    dismiss()
                                },
                                onCancel: scheduledWorkout.isRestDay ? nil : { showWorkshop = false }
                            )
                            .padding(.horizontal, 20)
                        } else if let workout = scheduledWorkout.workout {
                            // Workout details — Plate 22 editorial layout.
                            //
                            // The previous `WorkoutDetailHeader` (which carried
                            // a duplicate distance / duration / steps icon-card
                            // tile) is intentionally NOT rendered here — its
                            // role was already taken over by `DD22Header` +
                            // `DD22StatStrip` above. Bringing it back would
                            // double up the stat slot and break the editorial
                            // rhythm.
                            if !isEditing {
                                // ── rule between header/stat strip and heat ──
                                DD22EditorialRule()
                                    .padding(.horizontal, 20)

                                // Unified heat calculator: time picker +
                                // conditions + per-pace impact in one block.
                                HeatCalculatorCard(
                                    scheduledHour: liveWorkout.scheduledHour,
                                    forecast: liveWorkout.weatherForecast,
                                    equivalentPaces: viewModel.equivalentPaces,
                                    fetchError: viewModel.service.lastForecastFetchError,
                                    onTimeChange: { newHour in
                                        Task { @MainActor in
                                            await viewModel.service.updateScheduledTime(
                                                workoutId: liveWorkout.id,
                                                scheduledHour: newHour
                                            )
                                        }
                                    },
                                    onRefresh: {
                                        Task { @MainActor in
                                            await viewModel.service.refreshForecastForWorkout(
                                                workoutId: liveWorkout.id
                                            )
                                        }
                                    }
                                )
                                .padding(.horizontal, 20)
                                .task(id: liveWorkout.id) {
                                    // Auto-fetch the forecast when the
                                    // sheet opens with an hour set but no
                                    // weather data yet. Without this the
                                    // athlete sees the placeholder card
                                    // and has no way to recover other
                                    // than tapping the time pill.
                                    if liveWorkout.scheduledHour != nil,
                                       liveWorkout.weatherForecast == nil {
                                        await viewModel.service.refreshForecastForWorkout(
                                            workoutId: liveWorkout.id
                                        )
                                    }
                                }

                                // Pace Labels popover removed — the only
                                // toggles inside were 5K Pace and 10K Pace,
                                // and neither is wired to anything an
                                // athlete acts on. If we re-introduce a
                                // pace-display config later, it should
                                // hang off Settings rather than per-day.
                            }

                            // ── rule between heat and AI insight / structure ──
                            if !isEditing {
                                DD22EditorialRule()
                                    .padding(.horizontal, 20)
                            }

                            // AI Insight — only renders when the workout
                            // was completed and the linked training_logs
                            // row carries a coach_insight. Same editorial
                            // blockquote treatment as the Today home so
                            // both surfaces feel consistent.
                            if let insight = aiInsight, !insight.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("AI INSIGHT")
                                        .font(.dripCaption(10))
                                        .tracking(1.4)
                                        .foregroundStyle(Color.drip.coral)
                                    Text(insight)
                                        .font(.dripBody(15))
                                        .foregroundStyle(Color.drip.textPrimary)
                                        .lineSpacing(4)
                                }
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.drip.coral.opacity(0.4))
                                        .frame(width: 2)
                                }
                                .padding(.horizontal, 20)
                            }

                            // Workout Steps
                            VStack(alignment: .leading, spacing: 16) {
                                if isEditing {
                                    Text("EDIT STEPS")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .tracking(1.2)
                                        .padding(.horizontal, 20)
                                } else {
                                    DD22StructureEyebrow()
                                        .padding(.horizontal, 20)
                                }

                                if isEditing {
                                    // Editable steps
                                    VStack(spacing: 12) {
                                        ForEach($editableSteps) { $step in
                                            EditableWorkoutStepRow(
                                                step: $step,
                                                equivalentPaces: viewModel.equivalentPaces ?? defaultEquivalentPaces,
                                                racePaceSeconds: racePaceSeconds,
                                                onDelete: {
                                                    withAnimation {
                                                        editableSteps.removeAll { $0.id == step.id }
                                                        reorderSteps()
                                                    }
                                                }
                                            )
                                        }

                                        // Add step button
                                        Button {
                                            addNewStep()
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 16))
                                                Text("Add Step")
                                                    .font(.dripLabel(14))
                                            }
                                            .foregroundStyle(Color.drip.coral)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color.drip.coral.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                } else {
                                    // Read-only steps — live on the bone
                                    // background, no card wrapper. Plate 22
                                    // editorial vocabulary; the rule lines
                                    // inside WorkoutStepRow handle separation
                                    // between rows.
                                    VStack(spacing: 0) {
                                        ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                                            WorkoutStepRow(
                                                step: step,
                                                stepNumber: index + 1,
                                                totalSteps: workout.steps.count,
                                                racePaceSeconds: racePaceSeconds,
                                                equivalentPaces: viewModel.equivalentPaces,
                                                weatherForecast: effectiveForecast
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }

                            // Coach's notes — italic-serif quote section.
                            // Renders only when the scheduled workout has a
                            // non-empty notes field. Sits between the steps
                            // and the action strip, separated by an
                            // editorial rule above it for breathing room.
                            if !isEditing,
                               let notes = scheduledWorkout.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !notes.isEmpty {
                                DD22EditorialRule()
                                    .padding(.horizontal, 20)
                                DD22CoachNote(notes: notes)
                                    .padding(.horizontal, 20)
                            }

                            if !isEditing {
                                // Plate 22 action strip — primary "Mark
                                // complete ↗" + small mono text-link
                                // secondary actions. Replaces the previous
                                // pill-button row.
                                //
                                // Note: Delete is intentionally omitted from
                                // the visible row to keep the editorial line
                                // calm. The scheduled-workout delete affordance
                                // can move into a long-press / overflow menu
                                // in a follow-up; until then, athletes who
                                // need to delete go through Reschedule and
                                // skip. The original `showDeleteConfirmation`
                                // sheet binding stays wired so future surface
                                // can re-expose it.
                                DD22ActionStrip(
                                    workout: scheduledWorkout,
                                    isExporting: isExporting,
                                    onMarkComplete: { markComplete() },
                                    onSkip: { markSkipped() },
                                    onSwap: { showSwapPicker = true },
                                    onRestructure: { showWorkshop = true },
                                    onReschedule: { showReschedule = true },
                                    onExport: { exportWorkout() }
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        // Completed Vital workout data
                        if !completedVitalWorkouts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.drip.positive)
                                    Text("COMPLETED RUN")
                                        .font(.dripCaption(11))
                                        .foregroundStyle(Color.drip.textSecondary)
                                        .tracking(1.2)
                                }

                                ForEach(completedVitalWorkouts) { vitalWorkout in
                                    Button {
                                        selectedVitalWorkout = vitalWorkout
                                        showVitalDetail = true
                                    } label: {
                                        VStack(spacing: 12) {
                                            HStack(spacing: 0) {
                                                WorkoutStat(value: vitalWorkout.formattedDistance, label: "DISTANCE")
                                                Divider().frame(height: 32).background(Color.drip.divider)
                                                WorkoutStat(value: vitalWorkout.formattedDuration, label: "TIME")
                                                Divider().frame(height: 32).background(Color.drip.divider)
                                                WorkoutStat(value: vitalWorkout.formattedPace, label: "PACE")
                                            }

                                            HStack(spacing: 6) {
                                                Text("View details")
                                                    .font(.dripLabel(13))
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundStyle(Color.drip.coral)
                                        }
                                        .padding(16)
                                        .background(Color.drip.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.drip.positive.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle(scheduledWorkout.formattedFullDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !scheduledWorkout.isRestDay && scheduledWorkout.workout != nil {
                        Button(isEditing ? "Cancel" : "Edit") {
                            if isEditing {
                                withAnimation(.spring(response: 0.3)) {
                                    isEditing = false
                                }
                            } else {
                                enterEditMode()
                            }
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(isEditing ? Color.drip.textSecondary : Color.drip.coral)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button {
                            Task { await saveEdits() }
                        } label: {
                            if isSavingEdits {
                                ProgressView()
                                    .tint(Color.drip.coral)
                            } else {
                                Text("Save")
                                    .font(.dripLabel(15))
                                    .foregroundStyle(Color.drip.coral)
                            }
                        }
                        .disabled(isSavingEdits)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.coral)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showSwapPicker) {
                SwapWorkoutSheet(
                    viewModel: viewModel,
                    sourceWorkout: scheduledWorkout,
                    onSwap: { dismiss() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAddWorkoutPicker) {
                AddWorkoutSheet(
                    viewModel: viewModel,
                    restDay: scheduledWorkout,
                    onAdd: { dismiss() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showWorkoutChat) {
                WorkoutChatSheet(
                    viewModel: viewModel,
                    scheduledWorkout: scheduledWorkout,
                    racePaceSeconds: racePaceSeconds,
                    onWorkoutUpdated: { dismiss() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReschedule) {
                RescheduleSheet(
                    viewModel: viewModel,
                    initialScope: .day,
                    targetDate: scheduledWorkout.date
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Delete Workout", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Convert to Rest Day", role: .destructive) {
                    convertToRestDay()
                }
            } message: {
                Text("This will convert this day to a rest day. This action cannot be undone.")
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "An error occurred while exporting")
            }
            .sheet(isPresented: $showVitalDetail) {
                if let vitalWorkout = selectedVitalWorkout,
                   let vitalId = vitalWorkout.vitalWorkoutId
                {
                    VitalWorkoutDetailView(workout: vitalWorkout, vitalWorkoutId: vitalId)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .task {
                // Load completed Vital workouts for this day
                let workouts = await vitalManager.fetchRunningWorkouts(for: scheduledWorkout.date)
                await MainActor.run {
                    completedVitalWorkouts = workouts
                }

                // Load the AI insight for the linked training_logs row,
                // if the workout has been completed. Mirrors the home —
                // when the row exists with a non-empty coach_insight we
                // render the editorial blockquote up top.
                if let logId = scheduledWorkout.completedWorkoutId {
                    let insight = await fetchInsightForLog(logId: logId)
                    await MainActor.run {
                        aiInsight = insight
                    }
                }
            }
        }
    }

    // MARK: - Insight fetch

    /// Pulls `coach_insight` from `training_logs`, trimmed to a single
    /// sentence. Returns nil for the empty / not-yet-generated case so
    /// the section gracefully hides.
    private func fetchInsightForLog(logId: UUID) async -> String? {
        struct Row: Decodable {
            let coach_insight: String?
        }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs")
                .select("coach_insight")
                .eq("id", value: logId.uuidString)
                .limit(1)
                .execute()
                .value
            guard let raw = rows.first?.coach_insight?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            for terminator in [". ", "? ", "! "] {
                if let r = raw.range(of: terminator) {
                    return String(raw[..<r.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return raw
        } catch {
            Log.coach.error("DayDetailSheet insight fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - Actions

    private func markComplete() {
        Task {
            await viewModel.markWorkoutComplete(scheduledWorkout)
            dismiss()
        }
    }

    private func markSkipped() {
        Task {
            await viewModel.markWorkoutSkipped(scheduledWorkout)
            dismiss()
        }
    }

    private func convertToRestDay() {
        Task {
            await viewModel.convertToRestDay(scheduledWorkout)
            dismiss()
        }
    }

    private func exportWorkout() {
        guard let workout = scheduledWorkout.workout else { return }
        isExporting = true

        Task {
            do {
                let fitService = FITExportService()
                let url = try await fitService.exportWorkout(workout, racePaceSeconds: racePaceSeconds)

                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showExportSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            }
        }
    }

    // MARK: - Edit Mode

    private var defaultEquivalentPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 14400)
    }

    private func enterEditMode() {
        guard let workout = scheduledWorkout.workout else { return }
        editableSteps = workout.steps.map { step in
            EditableWorkoutStep(
                from: step,
                equivalentPaces: viewModel.equivalentPaces,
                racePaceSeconds: racePaceSeconds
            )
        }
        withAnimation(.spring(response: 0.3)) {
            isEditing = true
        }
    }

    private func addNewStep() {
        let newStep = EditableWorkoutStep(order: editableSteps.count)
        withAnimation {
            editableSteps.append(newStep)
        }
    }

    private func reorderSteps() {
        for i in editableSteps.indices {
            editableSteps[i].order = i
        }
    }

    private func saveEdits() async {
        guard let workout = scheduledWorkout.workout else { return }
        let equiv = viewModel.equivalentPaces ?? defaultEquivalentPaces

        isSavingEdits = true

        let updatedSteps = editableSteps.enumerated().map { index, editable in
            var step = editable
            step.order = index
            return step.toWorkoutStep(
                racePaceSeconds: racePaceSeconds,
                equivalentPaces: equiv
            )
        }

        // Calculate total distance from steps
        let totalMiles = updatedSteps.reduce(0.0) { total, step in
            switch step.durationType {
            case .distanceMiles:
                return total + step.durationValue
            case .distanceKm:
                return total + step.durationValue / 1.60934
            case .distanceMeters:
                return total + step.durationValue / 1609.34
            default:
                return total
            }
        }

        let updatedWorkout = PlannedWorkout(
            id: workout.id,
            name: workout.name,
            category: workout.category,
            trainingPhase: workout.trainingPhase,
            description: workout.description,
            steps: updatedSteps,
            totalDistanceMiles: totalMiles > 0 ? totalMiles : workout.totalDistanceMiles,
            estimatedDurationMinutes: workout.estimatedDurationMinutes,
            signatureType: workout.signatureType,
            createdAt: workout.createdAt
        )

        var updatedScheduled = scheduledWorkout
        updatedScheduled.workout = updatedWorkout
        updatedScheduled.status = .modified

        await viewModel.updateWorkout(updatedScheduled)

        isSavingEdits = false
        withAnimation(.spring(response: 0.3)) {
            isEditing = false
        }
    }
}

// MARK: - Day Detail Header

struct DayDetailHeader: View {
    let workout: ScheduledWorkout

    var body: some View {
        HStack(spacing: 14) {
            // Day and date
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.dayName.uppercased())
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.5)

                Text(workout.formattedShortDate)
                    .font(.dripStat(24))
                    .foregroundStyle(workout.isToday ? Color.drip.coral : Color.drip.textPrimary)
            }

            Spacer()

            // Workout type badge
            HStack(spacing: 6) {
                Image(systemName: workout.workoutType.icon)
                    .font(.system(size: 14))

                Text(workout.workoutType.displayName)
                    .font(.dripLabel(14))
            }
            .foregroundStyle(workout.workoutType.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(workout.workoutType.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    workout.isToday ? Color.drip.coral.opacity(0.3) : Color.drip.divider,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Rest Day Detail Content

struct RestDayDetailContent: View {
    let workout: ScheduledWorkout
    let onAddWorkout: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Rest day illustration
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.drip.textTertiary.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                VStack(spacing: 6) {
                    Text("Rest Day")
                        .font(.dripLabel(18))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Recovery is when your body adapts and gets stronger. Use this time to stretch, hydrate, and prepare for your next session.")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Recovery tips
            VStack(alignment: .leading, spacing: 12) {
                Text("RECOVERY TIPS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)

                VStack(spacing: 10) {
                    RecoveryTipRow(icon: "drop.fill", text: "Stay hydrated - aim for 8+ glasses of water")
                    RecoveryTipRow(icon: "moon.stars.fill", text: "Get 7-9 hours of quality sleep")
                    RecoveryTipRow(icon: "figure.flexibility", text: "Light stretching or yoga can help recovery")
                    RecoveryTipRow(icon: "fork.knife", text: "Focus on protein and anti-inflammatory foods")
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Add workout option
            Button(action: onAddWorkout) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))

                    Text("Add Workout Instead")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(Color.drip.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Recovery Tip Row

struct RecoveryTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.drip.coral)
                .frame(width: 20)

            Text(text)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Workout Action Buttons

struct WorkoutActionButtons: View {
    let workout: ScheduledWorkout
    let isExporting: Bool
    let onMarkComplete: () -> Void
    let onMarkSkipped: () -> Void
    let onSwap: () -> Void
    let onRestructure: () -> Void
    let onReschedule: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Primary actions based on status
            if workout.status == .scheduled {
                HStack(spacing: 12) {
                    Button(action: onMarkComplete) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Mark Complete")
                                .font(.dripLabel(14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.positive)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onMarkSkipped) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16))
                            Text("Skip")
                                .font(.dripLabel(14))
                        }
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
                }
            } else {
                // Status indicator
                HStack(spacing: 8) {
                    Image(systemName: workout.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16))

                    Text(workout.status == .completed ? "Completed" : "Skipped")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(workout.status == .completed ? Color.drip.positive : Color.drip.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (workout.status == .completed ? Color.drip.positive : Color.drip.textTertiary)
                        .opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Secondary actions
            HStack(spacing: 12) {
                ActionButton(
                    icon: "arrow.triangle.swap",
                    label: "Swap",
                    action: onSwap
                )

                ActionButton(
                    icon: "square.and.pencil",
                    label: "Replace",
                    action: onRestructure
                )

                ActionButton(
                    icon: "calendar.badge.clock",
                    label: "Reschedule",
                    action: onReschedule
                )

                ActionButton(
                    icon: "square.and.arrow.up",
                    label: "Export",
                    isLoading: isExporting,
                    action: onExport
                )

                ActionButton(
                    icon: "trash",
                    label: "Delete",
                    isDestructive: true,
                    action: onDelete
                )
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    var isLoading: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(Color.drip.textSecondary)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }

                Text(label)
                    .font(.dripCaption(11))
            }
            .foregroundStyle(isDestructive ? Color.drip.injured : Color.drip.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .disabled(isLoading)
    }
}

// MARK: - Workshop Tab

enum WorkshopTab: String, CaseIterable {
    case build = "Build"
    case template = "Template"
    case chat = "Chat"

    var icon: String {
        switch self {
        case .build: "text.cursor"
        case .template: "square.grid.2x2"
        case .chat: "sparkles"
        }
    }
}

// MARK: - Shorthand Parse Result

struct ShorthandParseResult: Codable {
    let steps: [ShorthandStep]
    let totalDistanceMiles: Double
    let estimatedDurationMinutes: Int?
    let workoutType: String
    let name: String
    let description: String
    let errors: [String]
}

struct ShorthandStep: Codable, Identifiable {
    var id: String { "\(order)-\(stepType)-\(durationValue)" }
    let stepType: String
    let durationType: String
    let durationValue: Double
    let paceReference: String?
    let paceRangeHigh: String?
    let pacePercentage: Double?
    let notes: String?
    let order: Int
    let repCount: Int?
    let recoveryType: String?
}

// MARK: - Workshop View

struct WorkshopView: View {
    @Bindable var viewModel: TrainingPlanViewModel
    let scheduledWorkout: ScheduledWorkout
    let racePaceSeconds: Double
    @Binding var selectedTab: WorkshopTab
    @Binding var shorthandInput: String
    @Binding var shorthandResult: ShorthandParseResult?
    @Binding var isParsingShorthand: Bool
    let onWorkoutApplied: () -> Void
    let onCancel: (() -> Void)?

    @State private var showWorkoutChat = false
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 16) {
            // Tab picker
            HStack(spacing: 0) {
                ForEach(WorkshopTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.dripLabel(13))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : Color.drip.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? Color.drip.coral : Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(3)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Tab content
            switch selectedTab {
            case .build:
                buildTab
            case .template:
                templateTab
            case .chat:
                chatTab
            }

            // Cancel button (when replacing an existing workout)
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    // MARK: - Build Tab (Shorthand Parser)

    private var buildTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TYPE YOUR WORKOUT")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            TextField("e.g. 6x800 @ 5K pace / 90s jog", text: $shorthandInput, axis: .vertical)
                .font(.dripBody(15))
                .padding(14)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: shorthandInput) { _, newValue in
                    parseShorthandDebounced(newValue)
                }

            if isParsingShorthand {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.drip.coral)
                    Text("Parsing...")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if let result = shorthandResult {
                // Parsed workout card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(result.name)
                            .font(.dripLabel(15))
                            .foregroundStyle(Color.drip.textPrimary)
                        Spacer()
                        Text(result.workoutType.replacingOccurrences(of: "_", with: " "))
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.coral)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.drip.coral.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 16) {
                        if result.totalDistanceMiles > 0 {
                            statPill(value: String(format: "%.1f mi", result.totalDistanceMiles), label: "Distance")
                        }
                        if let dur = result.estimatedDurationMinutes, dur > 0 {
                            statPill(value: "\(dur) min", label: "Est. Time")
                        }
                        statPill(value: "\(result.steps.filter { $0.stepType == "active" }.count)", label: "Segments")
                    }

                    // Step preview
                    ForEach(result.steps) { step in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(stepColor(step.stepType))
                                .frame(width: 6, height: 6)
                            Text(stepDescription(step))
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }

                    if !result.errors.isEmpty {
                        ForEach(result.errors, id: \.self) { error in
                            Text(error)
                                .font(.dripCaption(11))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Apply button
                    Button {
                        Task { await applyShorthandWorkout(result) }
                    } label: {
                        HStack {
                            if isApplying { ProgressView().tint(.white) }
                            Text("Apply to \(scheduledWorkout.dayName)")
                                .font(.dripLabel(14))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.drip.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isApplying || result.steps.isEmpty)
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Examples hint
            if shorthandInput.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXAMPLES")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .tracking(0.8)

                    ForEach([
                        "2mi wu, 6x800 @ 5K pace / 90s jog, 2mi cd",
                        "3x1600 @ 10K pace / 400 jog",
                        "20min @ marathon pace",
                        "Progressive 10mi: 6mi easy, 2mi @ MP, 2mi @ half pace",
                    ], id: \.self) { example in
                        Button {
                            shorthandInput = example
                        } label: {
                            Text(example)
                                .font(.dripBody(12))
                                .foregroundStyle(Color.drip.coral)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Template Tab

    private var templateTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEMPLATES")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            Text("Template library coming soon. Use Build or Chat to create a workout.")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Chat Tab

    private var chatTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DESCRIBE YOUR WORKOUT")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            Button {
                showWorkoutChat = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                    Text("Open AI Workout Builder")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(Color.drip.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.drip.coral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .sheet(isPresented: $showWorkoutChat) {
                WorkoutChatSheet(
                    viewModel: viewModel,
                    scheduledWorkout: scheduledWorkout,
                    racePaceSeconds: racePaceSeconds,
                    onWorkoutUpdated: onWorkoutApplied
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Helpers

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textPrimary)
            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }

    private func stepColor(_ stepType: String) -> Color {
        switch stepType {
        case "warmup", "cooldown": return Color.drip.positive
        case "active": return Color.drip.coral
        case "recovery", "rest": return Color.drip.textTertiary
        default: return Color.drip.textSecondary
        }
    }

    private func stepDescription(_ step: ShorthandStep) -> String {
        var parts: [String] = []
        let typeLabel: String = {
            switch step.stepType {
            case "warmup": return "Warmup"
            case "cooldown": return "Cooldown"
            case "recovery": return step.recoveryType?.capitalized ?? "Recovery"
            case "active": return ""
            default: return step.stepType.capitalized
            }
        }()

        if !typeLabel.isEmpty { parts.append(typeLabel) }
        if let notes = step.notes { parts.append(notes) }
        if let pace = step.paceReference { parts.append("@ \(pace) pace") }

        return parts.joined(separator: " ")
    }

    private func parseShorthandDebounced(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else {
            shorthandResult = nil
            return
        }

        isParsingShorthand = true

        // Debounce: try local parse first (no network for simple inputs)
        // For now, always call the edge function
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard shorthandInput == input else { return } // stale

            do {
                // Build pace zones from current plan context
                var paceZones: [String: Any] = [:]
                if let equiv = viewModel.equivalentPaces {
                    paceZones["easy"] = equiv.paceSeconds(for: .easy)
                    paceZones["marathon"] = equiv.paceSeconds(for: .mp)
                    paceZones["half"] = equiv.paceSeconds(for: .hm)
                    paceZones["10k"] = equiv.paceSeconds(for: .tenK)
                    paceZones["5k"] = equiv.paceSeconds(for: .fiveK)
                    paceZones["mile"] = equiv.paceSeconds(for: .mile)
                    paceZones["moderate"] = equiv.paceSeconds(for: .moderate)
                    paceZones["steady"] = equiv.paceSeconds(for: .steady)
                }

                let body: [String: Any] = [
                    "input": input,
                    "paceZones": paceZones,
                ]

                let data = try await callEdgeFunction(name: "parse-workout-shorthand", body: body)
                let result = try JSONDecoder().decode(ShorthandParseResult.self, from: data)

                await MainActor.run {
                    shorthandResult = result
                    isParsingShorthand = false
                }
            } catch {
                await MainActor.run {
                    isParsingShorthand = false
                }
            }
        }
    }

    private func applyShorthandWorkout(_ result: ShorthandParseResult) async {
        isApplying = true

        let steps = result.steps.enumerated().map { index, step in
            let stepType: PlannedWorkoutStep.StepType = {
                switch step.stepType {
                case "warmup": return .warmup
                case "cooldown": return .cooldown
                case "recovery", "rest": return .recovery
                default: return .active
                }
            }()

            let durationType: PlannedWorkoutStep.DurationType = {
                switch step.durationType {
                case "distance_meters": return .distanceMeters
                case "time_seconds": return .timeSeconds
                default: return .distanceMiles
                }
            }()

            return PlannedWorkoutStep(
                id: UUID(),
                stepType: stepType,
                durationType: durationType,
                durationValue: step.durationValue,
                // TODO(adaptive-plan-1.8): STOP constructing PaceIntensity from a percentage here.
                //   Use step.paceSecondsPerKm or resolve via AthletePaceProfileService when only
                //   a pace_reference is set. See: adaptive-plan-loop-prompts.md § Prompt 1.8
                targetPaceIntensity: step.pacePercentage.map { PaceIntensity(percentage: $0 / 100.0) },
                notes: [step.notes, step.paceReference.map { "@ \($0) pace" }]
                    .compactMap { $0 }.joined(separator: " "),
                order: index
            )
        }

        let workoutType = ScheduledWorkoutType(rawValue: result.workoutType) ?? .intervals

        let workout = PlannedWorkout(
            id: UUID(),
            name: result.name,
            category: workoutType == .intervals ? .specific : .fundamental,
            trainingPhase: viewModel.currentPhase,
            description: result.description,
            steps: steps,
            totalDistanceMiles: result.totalDistanceMiles > 0 ? result.totalDistanceMiles : nil,
            estimatedDurationMinutes: result.estimatedDurationMinutes.map { Double($0) },
            signatureType: nil,
            createdAt: Date()
        )

        var updated = scheduledWorkout
        updated.workout = workout
        updated.workoutType = workoutType
        updated.status = .modified

        await viewModel.updateWorkout(updated)
        isApplying = false
        onWorkoutApplied()
    }
}

// MARK: - HeatCalculatorCard

/// Single unified card combining run time + conditions + per-pace impact.
///
/// Replaces the disconnected "Add run time" pill and "Heat banner" that
/// confused the relationship between the time, the forecast, and what
/// shows up in the workout step rows. Layout from top to bottom:
///
///   1. Section header with thermometer icon
///   2. "Run at" row with inline time picker
///   3. Conditions line (temp · dew · humidity), only when a forecast
///      has been fetched
///   4. Per-pace impact table (MP, LT, Easy) with original → adjusted,
///      only when conditions are meaningful (≥5 sec/mi)
///
/// When no forecast has loaded yet, the card still renders the time
/// picker plus a "We'll fetch the forecast for this hour" line so the
/// athlete understands cause and effect.
private struct HeatCalculatorCard: View {
    let scheduledHour: Int?
    let forecast: WorkoutForecast?
    let equivalentPaces: EquivalentPaces?
    /// Last error from the forecast fetch, if any. When set + forecast is
    /// nil, the card renders an explicit failure state with a Refresh
    /// button so the athlete can self-recover instead of staring at a
    /// permanent "We'll pull the forecast" placeholder.
    let fetchError: String?
    let onTimeChange: (Int?) -> Void
    /// Manual retry. The card calls this when the athlete taps Refresh in
    /// the failure state.
    let onRefresh: () -> Void

    @State private var showPicker = false
    @State private var draft: Date = Date()
    @State private var isRefreshing = false

    /// App-wide preference. Defaults to ON (existing behavior). Stored in
    /// UserDefaults so the choice persists across sessions and applies
    /// to every workout. Athletes who train by feel and don't want pace
    /// targets shifting can flip it off once and forget about it.
    @AppStorage("heatAdjustmentEnabled") private var heatAdjustmentEnabled: Bool = true

    /// Reference pace used to express adjustment in seconds/mile units.
    /// The percentage is identical regardless of base pace.
    private static let referencePaceSeconds: Double = 420  // 7:00/mi

    private var adjustment: DewPointAdjustment? {
        guard let forecast, let dp = forecast.dewPointF else { return nil }
        return PaceCalculator.calculateDewPointAdjustment(
            paceSeconds: Self.referencePaceSeconds,
            temperatureF: forecast.temperatureF,
            dewPointF: dp
        )
    }

    private var isMeaningful: Bool {
        forecast?.isMeaningful() ?? false
    }

    // MARK: - Body
    //
    // Negative Splits redesign: no orange card chrome, no SF Symbol
    // thermometer. Section is signalled by the eyebrow + accent toggle
    // alone. The accent appears once per composition — on the toggle and
    // on the (+delta) figures in the pace impact rows.

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header — eyebrow + on/off toggle
            HStack {
                NSEyebrow("HEAT  ·  COMPENSATION")
                Spacer()
                NSAccentToggle(isOn: $heatAdjustmentEnabled)
            }

            if heatAdjustmentEnabled {
                enabledBody
            } else {
                // Off state — italic annotation, no time picker, no impact
                // table. Pace targets stay at coach's prescription
                // throughout the workout view.
                Text("Heat adjustment off. Targets stay at coach's prescription.")
                    .font(.nsAnnotation(15))
                    .foregroundStyle(Color.ns.slate)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            timePickerSheet
        }
    }

    @ViewBuilder
    private var enabledBody: some View {
        // ── Run time row — serif title with caret ───────────────
        HStack(alignment: .firstTextBaseline) {
            Button {
                draft = draftFromHour(scheduledHour ?? 7)
                showPicker = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Run at \(timeLabel)")
                        .font(.dripDisplay(22))
                        .foregroundStyle(Color.ns.ink)
                    NSCaretDown(size: 8, color: .ns.slate)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if scheduledHour != nil {
                Button {
                    onTimeChange(nil)
                } label: {
                    Text("RESET")
                        .font(.nsMono(11))
                        .tracking(1.0)
                        .foregroundStyle(Color.ns.slate)
                }
                .buttonStyle(.plain)
            }
        }

        // ── Conditions strip / quiet error ──────────────────────
        if let forecast {
            conditionsStrip(forecast)
        } else if let err = fetchError {
            // Specific failure surfaced from refreshForecastForWorkout.
            // Common cases: "No location available", "Forecast service
            // unavailable". Rendered as an italic annotation + tappable
            // mono link rather than a shouty alert block.
            NSQuietError(
                message: lowercaseFirst(err),
                actionLabel: isRefreshing ? "Fetching…" : "Refresh forecast",
                action: triggerRefresh
            )
        } else {
            // No forecast yet, no error — likely still fetching or the
            // cron hasn't run for this date. Same quiet treatment.
            NSQuietError(
                message: "no forecast yet for this hour.",
                actionLabel: isRefreshing ? "Fetching…" : "Refresh forecast",
                action: triggerRefresh
            )
        }

        // ── Pace impact ─────────────────────────────────────────
        // Only render when conditions are meaningful AND we have pace
        // data to project. On a cool day we show an explicit "no
        // adjustment needed" line so the athlete knows the calculator
        // ran.
        if let forecast, isMeaningful, let paces = equivalentPaces {
            NSHairline().padding(.top, 4)
            paceImpactSection(forecast: forecast, paces: paces)
        } else if forecast != nil, !isMeaningful {
            NSHairline().padding(.top, 4)
            HStack(spacing: 10) {
                NSEyebrow("CHECK", color: .ns.greenOk, size: 10)
                Text("No heat adjustment needed today.")
                    .font(.nsAnnotation(15))
                    .foregroundStyle(Color.ns.slate)
                Spacer()
            }
        }
    }

    // MARK: - Subviews

    /// Three labelled columns separated by hairlines — replaces the
    /// inline `82°F · dew 58°F · 65% humidity` string.
    @ViewBuilder
    private func conditionsStrip(_ f: WorkoutForecast) -> some View {
        let dewLabel = f.dewPointF.map { "\(Int($0))°" }
        let humLabel = f.humidity.map { "\($0)%" }
        HStack(spacing: 0) {
            condColumn(label: "TEMP", value: "\(Int(f.temperatureF))°")
            if let dewLabel {
                Rectangle().fill(Color.ns.hair).frame(width: 1, height: 36)
                condColumn(label: "DEW", value: dewLabel)
            }
            if let humLabel {
                Rectangle().fill(Color.ns.hair).frame(width: 1, height: 36)
                condColumn(label: "HUMIDITY", value: humLabel)
            }
        }
    }

    private func condColumn(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            NSEyebrow(label, color: .ns.slateLight, size: 10)
            Text(value)
                .font(.dripStat(18))
                .foregroundStyle(Color.ns.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// Pace impact — eyebrow + percentage on one line, then three pace
    /// rows. Hairline divider between them lives at the call site.
    @ViewBuilder
    private func paceImpactSection(forecast: WorkoutForecast, paces: EquivalentPaces) -> some View {
        let pct = adjustment?.adjustmentPercent ?? 0
        let pctRounded = Int((pct * 100).rounded())

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NSEyebrow("PACE IMPACT")
                Spacer()
                NSEyebrow("+\(pctRounded)%  SLOWER", color: .ns.amber)
            }
            VStack(spacing: 8) {
                paceRow(label: "MP",   original: paces.mpPace,        forecast: forecast)
                paceRow(label: "LT",   original: paces.thresholdPace, forecast: forecast)
                paceRow(label: "EASY", original: paces.easyPace,      forecast: forecast)
            }
        }
    }

    private func paceRow(label: String, original: Double, forecast: WorkoutForecast) -> some View {
        let adjusted = forecast.adjust(paceSecondsPerMile: original)
        let delta = Int((adjusted - original).rounded())
        return HStack(spacing: 12) {
            NSEyebrow(label, color: .ns.slate)
                .frame(width: 50, alignment: .leading)

            Text(formatPace(original))
                .font(.dripStat(14))
                .foregroundStyle(Color.ns.slateLight)
                .strikethrough(true, color: Color.ns.slateLight.opacity(0.5))
                .monospacedDigit()

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.ns.slateLight)

            Text(formatPace(adjusted))
                .font(.dripStat(14))
                .foregroundStyle(Color.ns.ink)
                .monospacedDigit()

            Text("+\(delta)s")
                .font(.nsMono(11))
                .foregroundStyle(Color.ns.amber)

            Spacer()
        }
    }

    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "Run time",
                    selection: $draft,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()

                Text("Hour-resolution only — drives the heat forecast for this workout.")
                    .font(.nsAnnotation(14))
                    .foregroundStyle(Color.ns.slate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("Run Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showPicker = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let hour = Calendar.current.component(.hour, from: draft)
                        onTimeChange(hour)
                        showPicker = false
                    }
                    .fontWeight(.medium)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Helpers

    /// Spin a manual refresh. Same fire-and-forget semantics as the
    /// previous `refreshButton` — the parent's `onRefresh` is async and
    /// updates the @Observable forecast property reactively. The 600ms
    /// sleep keeps the spinner visible long enough that a fast network
    /// fetch doesn't flicker.
    private func triggerRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            onRefresh()
            try? await Task.sleep(nanoseconds: 600_000_000)
            isRefreshing = false
        }
    }

    private var timeLabel: String {
        guard let h = scheduledHour else { return "7 AM (default)" }
        var comps = DateComponents()
        comps.hour = h
        comps.minute = 0
        guard let date = Calendar.current.date(from: comps) else { return "\(h):00" }
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date)
    }

    private func formatPace(_ secondsPerMile: Double) -> String {
        let total = Int(secondsPerMile.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func draftFromHour(_ h: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = h
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }

    /// Lowercase only the first letter so "No location available" reads
    /// as "no location available" inside an italic-annotation sentence.
    private func lowercaseFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

// MARK: - Preview

#Preview {
    DayDetailSheet(
        viewModel: TrainingPlanViewModel(),
        scheduledWorkout: ScheduledWorkout.sample,
        racePaceSeconds: 480
    )
}
