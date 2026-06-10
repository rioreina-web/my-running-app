//
//  JoinCoachPlanSheet.swift
//  RunningLog
//
//  Athlete onboarding into a coach's plan. Two stages in one sheet:
//
//    1. Code entry — athlete types the 6-char join code. As soon as it
//       matches a published plan template we transition to stage 2.
//
//    2. Configure — six sections (goal, rest days, quality days, volume,
//       shape, start date) with defaults pre-filled from the template
//       and the athlete's recent log history. A live preview of week 1
//       sits at the bottom; the materializer behind it is intentionally
//       crude (AO-1 scope) — AO-3 will replace it with a real port of
//       the edge function's materializer.
//
//  Calls subscribe-to-plan on submit, with the new
//  `subscription_preferences` body field. The edge function will start
//  honoring those preferences once AO-2 lands; until then the iOS
//  ships the payload and the field is ignored server-side.
//
//  See athlete-onboarding-redesign.md and athlete-onboarding-prompts.md.
//

import HealthKit
import SwiftUI

extension Notification.Name {
    static let trainingPlanDidChange = Notification.Name("trainingPlanDidChange")
}

/// Pre-loaded payload for opening the sheet in "edit preferences" mode
/// (AO-5). When set, the join-code stage is skipped; the configure stage
/// renders with state seeded from the existing subscription, and submit
/// posts a rematerialize request instead of creating a new subscription.
struct JoinCoachPlanEditMode: Identifiable {
    let plan: PlanTemplate
    let subscription: AthletePlanSubscription
    var id: UUID { subscription.id }
}

struct JoinCoachPlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editMode: JoinCoachPlanEditMode?

    init(editMode: JoinCoachPlanEditMode? = nil) {
        self.editMode = editMode
    }

    // ── Stage 1: code entry ──────────────────────────────────────
    @State private var joinCode = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?

    // ── Stage 2: configure (only meaningful once `loadedPlan` is set) ──
    @State private var loadedPlan: PlanTemplate?

    // ── Edit-mode submit confirmation ────────────────────────────
    @State private var showRematerializeConfirm = false

    // Goal section
    @State private var goalUseCoach: Bool = true
    @State private var goalHours: Int = 3
    @State private var goalMinutes: Int = 30
    @State private var goalSeconds: Int = 0
    @State private var goalDistance: String = "marathon"

    // Rest / quality / long run
    @State private var selectedRestDows: Set<Int> = []
    @State private var selectedQualityDows: Set<Int> = []
    @State private var longRunDow: Int = 5    // Saturday default

    // Volume
    @State private var currentWeeklyMileage: Double = 0
    @State private var rampStartMileage: Double = 0
    @State private var useFullRangeFromWeek1: Bool = false

    // Shape
    @State private var stridesPreQuality: Bool = true
    @State private var recoveryAfterLong: Bool = true
    @State private var doublesOnEasy: Bool = false

    // Start date
    @State private var startDate: Date = Calendar.current.nextMonday() ?? Date()

    // Submission
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var viewModel = CoachViewModel()

    // Day 0 = Monday, …, 6 = Sunday throughout this view.
    private let dayShortLabels = ["M", "T", "W", "Th", "F", "Sa", "Su"]
    private let dayLongLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            ZStack {
                DripBackground().ignoresSafeArea()
                ScrollView {
                    if let plan = loadedPlan {
                        configureStage(plan: plan)
                    } else {
                        codeEntryStage
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .onAppear {
                if editMode != nil && loadedPlan == nil {
                    Task { await applyEditMode() }
                }
            }
            .alert("Rebuild your plan?", isPresented: $showRematerializeConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Update", role: .destructive) {
                    Task { await submit() }
                }
            } message: {
                Text("This will rebuild your plan from this week forward. Past workouts stay as-is.")
            }
        }
    }

    private var navTitle: String {
        if editMode != nil { return "Edit Preferences" }
        return loadedPlan == nil ? "Join Plan" : "Configure"
    }

    // MARK: - Stage 1: code entry

    private var codeEntryStage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.drip.coral)
                }
                Text("Join a Coach Plan")
                    .font(.dripLabel(20))
                    .foregroundStyle(Color.drip.textPrimary)
                Text("Enter the 6-character code your coach shared with you.")
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("JOIN CODE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                TextField("e.g. AB3X9Z", text: $joinCode)
                    .font(.dripStat(28))
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .onChange(of: joinCode) { _, val in
                        joinCode = String(val.uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(joinCode.count == 6 ? Color.drip.coral : Color.drip.divider,
                                    lineWidth: joinCode.count == 6 ? 2 : 1)
                    )
            }

            if let err = lookupError {
                errorBanner(err)
            }

            Button {
                Task { await loadPlan() }
            } label: {
                HStack(spacing: 8) {
                    if isLookingUp {
                        ProgressView().tint(.white).scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                    Text(isLookingUp ? "Looking up..." : "Continue")
                        .font(.dripLabel(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(joinCode.count < 6 ? Color.drip.textTertiary : Color.drip.coral)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(joinCode.count < 6 || isLookingUp)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    // MARK: - Stage 2: configure

    private func configureStage(plan: PlanTemplate) -> some View {
        VStack(spacing: 24) {
            stageHeader(plan: plan)

            // Goal + start-date sections are hidden in edit mode. Goal
            // edits happen through the dedicated Edit Goal sheet (AO-4)
            // because they may also update training_plans + paces; start
            // date is fixed once a plan is live.
            if editMode == nil {
                section1Goal(plan: plan)
            }
            section2RestDays
            section3QualityDays(plan: plan)
            section4Volume(plan: plan)
            section5Shape
            if editMode == nil {
                section6StartDate
            }

            weekPreview(plan: plan)

            if let err = errorMessage {
                errorBanner(err).padding(.horizontal, 20)
            }
            if let success = successMessage {
                successBanner(success).padding(.horizontal, 20)
            }

            submitButton
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
    }

    private func stageHeader(plan: PlanTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUBSCRIBE TO PLAN")
                .font(.dripCaption(12))
                .tracking(1.4)
                .foregroundStyle(Color.drip.textSecondary)
            Text("\(plan.name) · \(plan.targetDistanceDisplay) · \(plan.durationWeeks) weeks")
                .font(.dripDisplay(20))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Section 1: Goal

    private func section1Goal(plan: PlanTemplate) -> some View {
        sectionCard(number: 1, title: "YOUR GOAL") {
            VStack(alignment: .leading, spacing: 10) {
                Text(coachGoalDescription(plan: plan))
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                radio(label: "Train at coach's paces (recommended)",
                      selected: goalUseCoach,
                      action: { goalUseCoach = true })

                radio(label: "My goal is...",
                      selected: !goalUseCoach,
                      action: { goalUseCoach = false })

                if !goalUseCoach {
                    // Two rows so the time stepper + distance picker don't
                    // overflow on narrow screens. The previous single HStack
                    // pushed `distancePicker` past the right edge of the
                    // section card and clipped it.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text("Time")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                                .frame(width: 56, alignment: .leading)
                            timeStepper(value: $goalHours, range: 0...10)
                            Text(":").font(.dripStat(14)).foregroundStyle(Color.drip.textSecondary)
                            timeStepper(value: $goalMinutes, range: 0...59)
                            Text(":").font(.dripStat(14)).foregroundStyle(Color.drip.textSecondary)
                            timeStepper(value: $goalSeconds, range: 0...59)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 6) {
                            Text("Distance")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                                .frame(width: 56, alignment: .leading)
                            distancePicker
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }

    // MARK: - Section 2: Rest days

    private var section2RestDays: some View {
        sectionCard(number: 2, title: "REST DAYS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick zero, one, or many. Your call.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                HStack(spacing: 6) {
                    ForEach(0..<7) { dow in
                        dayPill(label: dayShortLabels[dow],
                                selected: selectedRestDows.contains(dow)) {
                            if selectedRestDows.contains(dow) {
                                selectedRestDows.remove(dow)
                            } else {
                                selectedRestDows.insert(dow)
                            }
                        }
                    }
                }

                if selectedRestDows.isEmpty {
                    Text("No rest is fine — adaptive plans don't require one.")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }

    // MARK: - Section 3: Quality days

    private func section3QualityDays(plan: PlanTemplate) -> some View {
        let qualityCount = inferQualityDayCount(plan: plan)
        return sectionCard(number: 3, title: "YOUR QUALITY DAYS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coach calls for \(qualityCount) quality day\(qualityCount == 1 ? "" : "s") per week.\nPick when you can do them.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                HStack(spacing: 6) {
                    ForEach(0..<7) { dow in
                        dayPill(label: dayShortLabels[dow],
                                selected: selectedQualityDows.contains(dow)) {
                            if selectedQualityDows.contains(dow) {
                                selectedQualityDows.remove(dow)
                            } else {
                                selectedQualityDows.insert(dow)
                            }
                        }
                    }
                }

                HStack {
                    Text("Long run lands on:")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                    Picker("Long run day", selection: $longRunDow) {
                        ForEach(0..<7) { dow in
                            Text(dayLongLabels[dow]).tag(dow)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.drip.coral)
                }
            }
        }
    }

    // MARK: - Section 4: Volume

    private func section4Volume(plan: PlanTemplate) -> some View {
        let (lower, upper) = coachWeeklyMileageRange(plan: plan)
        return sectionCard(number: 4, title: "STARTING VOLUME") {
            VStack(alignment: .leading, spacing: 12) {
                Text(lower == upper
                     ? "Coach prescribes \(Int(lower)) mi/week."
                     : "Coach prescribes \(Int(lower))–\(Int(upper)) mi/week.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What's your current weekly mileage?")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                    HStack(spacing: 4) {
                        TextField("0", value: $currentWeeklyMileage, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(8)
                            .background(Color.drip.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(width: 80)
                        Text("mi/week")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text("We pre-fill from your last 4 weeks of logs when available.")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                Divider().background(Color.drip.divider)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Ramp from")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                        TextField("0", value: $rampStartMileage, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(6)
                            .background(Color.drip.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(width: 56)
                        Text(lower == upper
                             ? "mi to coach's \(Int(lower))"
                             : "mi to coach's \(Int(lower))–\(Int(upper))")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    Text("over the first 4 weeks")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .padding(.leading, 4)

                    Toggle(isOn: $useFullRangeFromWeek1) {
                        Text("Use coach's full range from Week 1")
                            .font(.dripBody(13))
                    }
                    .tint(Color.drip.coral)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Section 5: Shape

    private var section5Shape: some View {
        sectionCard(number: 5, title: "WORKOUT SHAPE") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional shape preferences. Defaults are coach's.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                Toggle(isOn: $stridesPreQuality) {
                    Text("Strides on the day before quality").font(.dripBody(13))
                }.tint(Color.drip.coral)

                Toggle(isOn: $recoveryAfterLong) {
                    Text("Easy recovery after long run").font(.dripBody(13))
                }.tint(Color.drip.coral)

                Toggle(isOn: $doublesOnEasy) {
                    Text("Add a second easy run on non-quality days").font(.dripBody(13))
                }.tint(Color.drip.coral)
            }
        }
    }

    // MARK: - Section 6: Start date

    private var section6StartDate: some View {
        sectionCard(number: 6, title: "START DATE") {
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.drip.coral)
                Text("Plans always start on a Monday — we'll snap to the nearest one.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
    }

    // MARK: - Week 1 preview (real materializer — see PlanPreviewMaterializer.swift)

    private func weekPreview(plan: PlanTemplate) -> some View {
        let days = previewDays(plan: plan)
        let total = PlanPreviewMaterializer.totalMiles(days)
        return VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW WEEK 1")
                .font(.dripCaption(12))
                .tracking(1.4)
                .foregroundStyle(Color.drip.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { idx, day in
                    previewRow(day: day)
                    if idx < days.count - 1 {
                        Divider().background(Color.drip.divider)
                    }
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            previewFooter(days: days, totalMiles: total)
        }
        .padding(.horizontal, 20)
    }

    private func previewRow(day: PlanPreviewDay) -> some View {
        let highlighted = day.type == .quality || day.type == .longRun
        return HStack(alignment: .firstTextBaseline) {
            Text(dayLongLabels[day.dow])
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 36, alignment: .leading)
            Text(day.label)
                .font(.dripBody(13))
                .foregroundStyle(highlighted ? Color.drip.textPrimary : Color.drip.textSecondary)
                .fontWeight(highlighted ? .medium : .regular)
            Spacer()
            if let pace = day.paceLabel {
                Text(pace)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func previewFooter(days: [PlanPreviewDay], totalMiles: Double) -> some View {
        let restCount = days.filter { $0.type == .rest }.count
        let warning: String? = {
            if totalMiles <= 0 {
                return "Week 1 mileage is 0 — check your starting volume."
            }
            if restCount == 0 {
                return "No rest day — your call."
            }
            return nil
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("≈ \(formatTotalMiles(totalMiles)) mi this week")
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
            if let warning {
                Text(warning)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.coral)
            }
        }
        .padding(.leading, 4)
    }

    private func previewDays(plan: PlanTemplate) -> [PlanPreviewDay] {
        PlanPreviewMaterializer.materializeWeek1(
            plan: plan,
            preferences: currentPreferences(),
            paceLadder: currentPaceLadder(plan: plan)
        )
    }

    private func currentPreferences() -> SubscriptionPreferences {
        SubscriptionPreferences(
            restDows: Array(selectedRestDows).sorted(),
            preferredQualityDows: Array(selectedQualityDows).sorted(),
            longRunDow: longRunDow,
            volumeRamp: VolumeRamp(
                startMileage: rampStartMileage,
                rampToCoachTarget: !useFullRangeFromWeek1,
                rampWeeks: 4
            ),
            shapePrefs: ShapePrefs(
                stridesPreQuality: stridesPreQuality,
                recoveryAfterLong: recoveryAfterLong,
                doublesOnEasyDays: doublesOnEasy
            ),
            currentWeeklyMileage: currentWeeklyMileage > 0 ? currentWeeklyMileage : nil
        )
    }

    /// Pace ladder for the preview. Source order:
    ///   - goalUseCoach == false → derive from athlete's chosen goal
    ///     (the same time the user is editing in section 1).
    ///   - goalUseCoach == true → use the same chosen goal too. We don't
    ///     decode the template's paceAnchor here; the seeded goalHours/Min/Sec
    ///     came from `defaultGoalTime(for: plan.targetDistance)` and we treat
    ///     it as a sensible stand-in. Net effect for the athlete: the preview
    ///     paces match what `subscribe-to-plan` will resolve once the coach
    ///     anchor is applied.
    private func currentPaceLadder(plan: PlanTemplate) -> PaceLadder? {
        let totalSeconds = goalHours * 3600 + goalMinutes * 60 + goalSeconds
        let distance = goalUseCoach ? plan.targetDistance : goalDistance
        return PaceLadder.derive(distance: distance, goalSeconds: totalSeconds)
    }

    private func formatTotalMiles(_ miles: Double) -> String {
        if miles < 0.05 { return "0" }
        if miles == miles.rounded() { return String(format: "%.0f", miles) }
        return String(format: "%.1f", miles)
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            if editMode != nil {
                showRematerializeConfirm = true
            } else {
                Task { await submit() }
            }
        } label: {
            HStack(spacing: 6) {
                if isJoining {
                    ProgressView().tint(.white).scaleEffect(0.85)
                }
                Text(isJoining ? submitInFlightLabel : submitIdleLabel)
                    .font(.dripLabel(15))
                if !isJoining {
                    Image(systemName: "arrow.right").font(.system(size: 12))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(submitDisabled ? Color.drip.textTertiary : Color.drip.coral)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(submitDisabled)
    }

    private var submitDisabled: Bool {
        isJoining || selectedQualityDows.isEmpty
    }

    private var submitIdleLabel: String {
        editMode == nil ? "Subscribe to plan" : "Update preferences"
    }
    private var submitInFlightLabel: String {
        editMode == nil ? "Subscribing..." : "Updating..."
    }

    // MARK: - Actions

    @MainActor
    private func loadPlan() async {
        lookupError = nil
        isLookingUp = true
        defer { isLookingUp = false }

        guard let plan = await viewModel.lookupPlanByCode(joinCode) else {
            lookupError = viewModel.error ?? "Plan not found. Check the join code and try again."
            return
        }

        // Hydrate stage-2 state from the template + athlete history.
        applyDefaults(plan: plan)
        await prefillCurrentMileage(plan: plan)
        loadedPlan = plan
    }

    @MainActor
    private func submit() async {
        guard let plan = loadedPlan else { return }
        errorMessage = nil
        successMessage = nil
        isJoining = true
        defer { isJoining = false }

        let prefs = currentPreferences()

        if editMode != nil {
            let success = await viewModel.rematerializePlan(
                planTemplateId: plan.id,
                preferences: prefs
            )
            if success {
                successMessage = "Preferences updated. Future workouts have been rebuilt."
                NotificationCenter.default.post(name: .trainingPlanDidChange, object: nil)
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                }
            } else {
                errorMessage = viewModel.error ?? "Failed to update preferences. Try again."
            }
            return
        }

        let goalSecs: Int? = goalUseCoach
            ? nil
            : (goalHours * 3600 + goalMinutes * 60 + goalSeconds)

        let success = await viewModel.joinLoadedPlan(
            plan,
            startDate: startDate,
            goalTimeSeconds: goalSecs,
            targetRaceDistance: goalUseCoach ? nil : goalDistance,
            preferences: prefs
        )

        if success {
            successMessage = "You've joined the plan! It will appear in your Training tab."
            NotificationCenter.default.post(name: .trainingPlanDidChange, object: nil)
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        } else {
            errorMessage = viewModel.error ?? "Failed to subscribe. Try again."
        }
    }

    /// Edit-mode entry: skip the join-code stage and seed every section
    /// from the existing subscription so the athlete sees their last
    /// answers, not coach defaults.
    @MainActor
    private func applyEditMode() async {
        guard let editMode else { return }
        let plan = editMode.plan
        let sub = editMode.subscription

        // Coach-side defaults first (mirrors the create flow), then layer
        // the saved subscription on top.
        applyDefaults(plan: plan)

        if let rest = sub.restDows {
            selectedRestDows = Set(rest)
        }
        if let quality = sub.preferredQualityDows {
            selectedQualityDows = Set(quality)
        }
        if let lr = sub.longRunDow {
            longRunDow = lr
        }
        if let ramp = sub.volumeRamp {
            rampStartMileage = ramp.startMileage
            useFullRangeFromWeek1 = !ramp.rampToCoachTarget
        }
        if let shape = sub.shapePrefs {
            stridesPreQuality = shape.stridesPreQuality
            recoveryAfterLong = shape.recoveryAfterLong
            doublesOnEasy = shape.doublesOnEasyDays
        }
        if let recent = sub.currentWeeklyMileage {
            currentWeeklyMileage = recent
        }
        // No need to refresh from HealthKit — the athlete's last answer
        // already reflects what they explicitly entered.
        loadedPlan = plan
    }

    // MARK: - Defaults / pre-fill

    private func applyDefaults(plan: PlanTemplate) {
        // Goal: default to coach's anchor when the template carries one;
        // otherwise prompt the athlete to set their own.
        goalUseCoach = templateHasPaceAnchor(plan)

        // Goal distance + reasonable default split
        goalDistance = plan.targetDistance
        let (h, m, s) = defaultGoalTime(for: plan.targetDistance)
        goalHours = h
        goalMinutes = m
        goalSeconds = s

        // Quality days from the coach's first-week pattern. Long run dow
        // becomes whichever quality slot has the longest planned distance,
        // falling back to Saturday.
        let week1 = plan.weeks.first { $0.weekNumber == 1 } ?? plan.weeks.first
        if let week1 {
            let qualityDows = week1.workouts
                .filter { isQualityType($0.workoutType) }
                .map { $0.dayOfWeek }
            selectedQualityDows = Set(qualityDows)

            if let lr = week1.workouts
                .filter({ $0.workoutType == .longRun || $0.workoutType == .race })
                .max(by: { ($0.workoutData?.effectiveDistanceMiles ?? 0)
                          < ($1.workoutData?.effectiveDistanceMiles ?? 0) }) {
                longRunDow = lr.dayOfWeek
            }
        }

        // Volume defaults: ramp start = coach's lower bound (if known).
        // currentWeeklyMileage gets refined by prefillCurrentMileage().
        let (lower, _) = coachWeeklyMileageRange(plan: plan)
        rampStartMileage = lower
        currentWeeklyMileage = lower

        // Start date: next Monday after today.
        startDate = Calendar.current.nextMonday() ?? Date()
    }

    @MainActor
    private func prefillCurrentMileage(plan: PlanTemplate) async {
        // Best-effort HealthKit pull. If unauthorized or no recent runs,
        // keep the coach's lower bound the applyDefaults() seeded.
        let now = Date()
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now
        let workouts = await HealthKitManager.shared.fetchRecentRunningWorkouts(limit: 200)
        let recent = workouts.filter { $0.startDate >= fourWeeksAgo && $0.startDate <= now }
        guard !recent.isEmpty else { return }

        let totalMiles = recent.reduce(0.0) { $0 + $1.distanceMiles }
        let avg = totalMiles / 4.0
        currentWeeklyMileage = (avg * 10).rounded() / 10
        // Ramp start = athlete's avg + a small buffer, capped at coach's lower
        // bound. Prevents starting BELOW current capacity.
        let (lower, _) = coachWeeklyMileageRange(plan: plan)
        let buffer = min(avg + 3, lower)
        rampStartMileage = (buffer * 10).rounded() / 10
    }

    // MARK: - Plan template helpers

    /// Decode `phase_config` JSON to detect whether the template was authored
    /// with a coach pace anchor. The iOS PhaseConfigData type doesn't model
    /// the `paceAnchor` sub-object — it's only consumed server-side — so we
    /// re-decode the JSONB into a flexible dictionary just for this check.
    private func templateHasPaceAnchor(_ plan: PlanTemplate) -> Bool {
        guard let config = plan.phaseConfig else { return false }
        guard let data = try? JSONEncoder().encode(config),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anchor = dict["paceAnchor"] as? [String: Any] else {
            return false
        }
        if let secs = anchor["goalRaceSeconds"] as? Double, secs > 0 { return true }
        if let secs = anchor["goalRaceSeconds"] as? Int, secs > 0 { return true }
        return false
    }

    private func coachGoalDescription(plan: PlanTemplate) -> String {
        if templateHasPaceAnchor(plan) {
            return "This plan is built around the coach's prescribed paces."
        }
        return "No coach goal time set — pick your own."
    }

    private func coachWeeklyMileageRange(plan: PlanTemplate) -> (Double, Double) {
        // 1. Preferred source: per-week min/max set by the coach in the
        //    plan-builder (the "RANGE 60 - 70 mpw" inputs). This is the
        //    canonical volume target — what the coach typed in. Take the
        //    overall min and max across all weeks so the athlete sees
        //    "Coach prescribes 60–70 mi/week" even if individual weeks
        //    step up.
        let weekRanges: [(Double, Double)] = plan.weeks.compactMap { week in
            guard let lo = week.targetMilesMin,
                  let hi = week.targetMilesMax,
                  hi > 0 else { return nil }
            return (lo, hi)
        }
        if !weekRanges.isEmpty {
            let lo = weekRanges.map { $0.0 }.min() ?? 0
            let hi = weekRanges.map { $0.1 }.max() ?? 0
            return (lo, hi)
        }

        // 2. Older templates may use a flat `weekly_mileage_targets` array.
        if let targets = plan.weeklyMileageTargets, !targets.isEmpty {
            let miles = targets.map { Double($0.targetMiles) }.filter { $0 > 0 }
            if let lo = miles.min(), let hi = miles.max(), hi > 0 {
                return (lo, hi)
            }
        }

        // 3. Last fallback: derive from authored workouts. Imprecise — the
        //    coach can leave easy days as "Auto · per athlete" with no
        //    explicit miles, so this undercounts. Only used when the coach
        //    skipped both prior fields.
        let weekTotals = plan.weeks
            .map { $0.totalPlannedMiles }
            .filter { $0 > 0 }
        guard !weekTotals.isEmpty,
              let lo = weekTotals.min(),
              let hi = weekTotals.max() else {
            return (0, 0)
        }
        return (lo.rounded(), hi.rounded())
    }

    private func inferQualityDayCount(plan: PlanTemplate) -> Int {
        let week1 = plan.weeks.first { $0.weekNumber == 1 } ?? plan.weeks.first
        guard let week1 else { return 2 }
        let count = week1.workouts.filter { isQualityType($0.workoutType) }.count
        return max(1, count)
    }

    private func isQualityType(_ type: ScheduledWorkoutType?) -> Bool {
        switch type {
        case .tempo, .intervals, .longRun, .race, .progression: return true
        default: return false
        }
    }

    private func defaultGoalTime(for distance: String) -> (Int, Int, Int) {
        switch distance.lowercased() {
        case "marathon":           return (3, 30, 0)
        case "half_marathon":      return (1, 40, 0)
        case "10k":                return (0, 45, 0)
        case "5k":                 return (0, 22, 0)
        case "mile":               return (0, 5, 30)
        default:                   return (3, 30, 0)
        }
    }

    // MARK: - Reusable controls

    private func sectionCard<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section heading — was caption(11) + textTertiary which fell off
            // the page on the cream background. Bumped to caption(12) +
            // textSecondary so the section labels actually read.
            HStack(spacing: 8) {
                Text("\(number).")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                Text(title)
                    .font(.dripCaption(12))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textSecondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private func radio(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color.drip.coral : Color.drip.divider, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if selected {
                        Circle().fill(Color.drip.coral).frame(width: 8, height: 8)
                    }
                }
                Text(label)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func dayPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dripCaption(12))
                .foregroundStyle(selected ? .white : Color.drip.textSecondary)
                .frame(width: 36, height: 36)
                .background(selected ? Color.drip.coral : Color.drip.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.drip.coral : Color.drip.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Number stepper using Menu instead of Picker(.menu). The Picker
    /// approach was rendering the selected value invisibly on this
    /// background — Menu lets us paint the label as an explicit Text we
    /// fully control.
    private func timeStepper(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Menu {
            ForEach(range, id: \.self) { v in
                Button(String(format: "%02d", v)) {
                    value.wrappedValue = v
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(format: "%02d", value.wrappedValue))
                    .font(.dripStat(18))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.drip.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 56)
            .background(Color.drip.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var distancePicker: some View {
        Picker("Distance", selection: $goalDistance) {
            Text("Marathon").tag("marathon")
            Text("Half").tag("half_marathon")
            Text("10K").tag("10k")
            Text("5K").tag("5k")
        }
        .pickerStyle(.menu)
        .tint(Color.drip.coral)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.drip.injured)
            Text(text)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.injured)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.drip.injured.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func successBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.drip.positive)
            Text(text)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.positive)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.drip.positive.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Calendar helper

private extension Calendar {
    func nextMonday(from date: Date = Date()) -> Date? {
        let components = DateComponents(weekday: 2)  // Monday = 2 in Calendar
        return self.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }
}
