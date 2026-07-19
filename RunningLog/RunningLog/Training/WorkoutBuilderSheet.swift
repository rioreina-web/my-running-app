//
//  WorkoutBuilderSheet.swift
//  RunningLog
//
//  Build, edit, and customize a structured workout. One sheet, two
//  postures:
//
//    · Self-coached day → "Edit workout". The athlete owns the plan;
//      the save is logged (yellow-tier plan_adjustment) but the sheet
//      carries no coach chrome.
//    · Coach-issued day → "Customize". Same builder, plus one quiet
//      line up top: the coach will see the change. AI advises, never
//      acts — and the coach never silently loses sight of their plan.
//
//  Natural-language entry sits at the top: the athlete types (or
//  dictates — the mic key on the keyboard is free) "6x800 at 5K with
//  400 jog", we call parse-workout-shorthand, and the parsed structure
//  PRE-FILLS the step editor for review. Parsing never saves.
//
//  Saves route through the edit-scheduled-workout edge function
//  (service-role, ownership-checked, future-only) via
//  TrainingPlanService.submitWorkoutEdit — the same audited path the
//  inline day-detail editor uses.
//
//  Design: Post Run Drip / Plate 22 vocabulary. Mono eyebrows, Crimson
//  display date, italic-serif summary line, hairline rules, coral as
//  punctuation (one per cluster).
//

import SwiftUI

struct WorkoutBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let scheduledWorkout: ScheduledWorkout
    let racePaceSeconds: Double
    /// Called after a successful save, before the sheet dismisses.
    let onSaved: () -> Void

    // MARK: - State

    @State private var steps: [EditableWorkoutStep] = []
    @State private var defaultZone: NamedPace = .mp
    @State private var isSaving = false

    // Natural-language entry
    @State private var nlInput = ""
    @State private var nlResult: ShorthandParseResult?
    @State private var nlError: String?
    @State private var isParsing = false

    // MARK: - Derived

    private var defaultEquivalentPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 14400)
    }

    private var equivalentPaces: EquivalentPaces {
        viewModel.equivalentPaces ?? defaultEquivalentPaces
    }

    /// Coach-issued when the row is a coach prescription or the active
    /// plan came from a coach template. Drives the "Customize" posture.
    private var isCoachIssued: Bool {
        scheduledWorkout.source == "coach_locked"
            || (viewModel.activePlan?.isCoachPlan ?? false)
    }

    private var summaryLine: String? {
        WorkoutLabelGrammar.summaryLine(steps: steps)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .padding(.horizontal, 20)

                        if isCoachIssued {
                            coachNotice
                                .padding(.horizontal, 20)
                        }

                        DD22EditorialRule()
                            .padding(.horizontal, 20)

                        nlEntrySection
                            .padding(.horizontal, 20)

                        DD22EditorialRule()
                            .padding(.horizontal, 20)

                        BuilderZoneChipRow(
                            selectedZone: $defaultZone,
                            equivalentPaces: equivalentPaces
                        )
                        .padding(.horizontal, 20)

                        stepsSection
                            .padding(.horizontal, 20)

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
                    Button("Cancel") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .tint(Color.drip.coral)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .font(.dripLabel(15))
                        .foregroundStyle(steps.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                        .disabled(steps.isEmpty)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear(perform: seedFromWorkout)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrowText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text(dateLine)
                .font(.dripDisplay(34))
                .foregroundStyle(Color.drip.textPrimary)
            if let summary = summaryLine {
                // Live label — the same grammar the plan surfaces use.
                // "5K 5×1km", "MP 7 mi". Updates as the steps change.
                Text(summary)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrowText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let weekday = f.string(from: scheduledWorkout.date).uppercased()
        return "\(weekday)  ·  \(isCoachIssued ? "CUSTOMIZE" : "BUILD")"
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: scheduledWorkout.date)
    }

    /// One quiet line. Not a warning banner — a statement of how the
    /// relationship works.
    private var coachNotice: some View {
        Text("This is a coach-issued workout. Your coach will see this change.")
            .font(.system(size: 13, design: .serif).italic())
            .foregroundStyle(Color.drip.textSecondary)
    }

    // MARK: - Natural-language entry

    private var nlEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE IT")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)

            TextField(
                "e.g. 6x800 @ 5K pace / 400 jog",
                text: $nlInput,
                axis: .vertical
            )
            .font(.dripBody(15))
            .foregroundStyle(Color.drip.textPrimary)
            .padding(14)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: nlInput) { _, newValue in
                parseShorthandDebounced(newValue)
            }

            if isParsing {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.drip.coral)
                    Text("Reading…")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            if let error = nlError {
                BuilderQuietError(
                    message: error,
                    actionLabel: "Try again",
                    action: { parseShorthandDebounced(nlInput) }
                )
            }

            if let result = nlResult, nlError == nil {
                // Parsed preview — pre-fill only. Nothing is saved until
                // the athlete reviews the steps and taps Save.
                Button {
                    applyParsedResult(result)
                } label: {
                    HStack(spacing: 6) {
                        Text("Fill in \(result.steps.count) steps")
                            .font(.system(size: 12, design: .monospaced))
                        Text("\u{2197}")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
            }

            if nlInput.isEmpty && steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        "2mi wu, 6x800 @ 5K pace / 90s jog, 2mi cd",
                        "3x1600 @ 10K pace / 400 jog",
                        "20min @ marathon pace",
                    ], id: \.self) { example in
                        Button {
                            nlInput = example
                        } label: {
                            Text(example)
                                .font(.dripBody(12))
                                .foregroundStyle(Color.drip.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if steps.isEmpty {
                BuilderEmptyState(onAddStep: addStep)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("STRUCTURE")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    let miles = WorkoutLabelGrammar.totalMiles(of: steps)
                    if miles > 0 {
                        Text(String(format: "%.1f MI TOTAL", miles))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }

                VStack(spacing: 16) {
                    ForEach($steps) { $step in
                        BuilderStepCard(
                            step: $step,
                            equivalentPaces: equivalentPaces,
                            racePaceSeconds: racePaceSeconds,
                            isFirst: steps.first?.id == step.id,
                            isLast: steps.last?.id == step.id,
                            onMoveUp: { move(step.id, by: -1) },
                            onMoveDown: { move(step.id, by: 1) },
                            onDuplicate: { duplicateStep(step.id) },
                            onDelete: { deleteStep(step.id) }
                        )
                    }
                }

                Button(action: addStep) {
                    HStack(spacing: 6) {
                        Text("Add step")
                            .font(.system(size: 12, design: .monospaced))
                        Text("\u{2197}")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.drip.coral)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Step mutations

    private func seedFromWorkout() {
        guard steps.isEmpty, let workout = scheduledWorkout.workout else { return }
        steps = workout.steps.map { step in
            EditableWorkoutStep(
                from: step,
                equivalentPaces: viewModel.equivalentPaces,
                racePaceSeconds: racePaceSeconds
            )
        }
        if let dominant = WorkoutLabelGrammar.dominantZone(in: steps) {
            defaultZone = dominant
        }
    }

    private func addStep() {
        var newStep = EditableWorkoutStep(order: steps.count)
        newStep.paceSelection = .namedPace(defaultZone)
        withAnimation {
            steps.append(newStep)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        withAnimation {
            steps.swapAt(index, target)
            normalizeOrder()
        }
    }

    private func duplicateStep(_ id: UUID) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let source = steps[index]
        var copy = EditableWorkoutStep(order: source.order + 1, stepType: source.stepType)
        copy.durationType = source.durationType
        copy.durationValue = source.durationValue
        copy.paceSelection = source.paceSelection
        copy.hrTarget = source.hrTarget
        copy.notes = source.notes
        copy.repeats = source.repeats
        copy.recovery = source.recovery
        withAnimation {
            steps.insert(copy, at: index + 1)
            normalizeOrder()
        }
    }

    private func deleteStep(_ id: UUID) {
        withAnimation {
            steps.removeAll { $0.id == id }
            normalizeOrder()
        }
    }

    private func normalizeOrder() {
        for i in steps.indices {
            steps[i].order = i
        }
    }

    // MARK: - Shorthand parsing (pre-fill, never save)

    private func parseShorthandDebounced(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nlResult = nil
            nlError = nil
            return
        }

        isParsing = true
        nlError = nil

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms debounce
            guard nlInput == input else { return } // stale keystroke

            do {
                // Same pace-zone payload the day-detail workshop sends —
                // lets the parser estimate a duration for time targets.
                var paceZones: [String: Any] = [:]
                if let equiv = viewModel.equivalentPaces {
                    paceZones["easy"] = equiv.paceSeconds(for: .easy)
                    paceZones["moderate"] = equiv.paceSeconds(for: .moderate)
                    paceZones["steady"] = equiv.paceSeconds(for: .steady)
                    paceZones["marathon"] = equiv.paceSeconds(for: .mp)
                    paceZones["half"] = equiv.paceSeconds(for: .hm)
                    paceZones["10k"] = equiv.paceSeconds(for: .tenK)
                    paceZones["5k"] = equiv.paceSeconds(for: .fiveK)
                    paceZones["mile"] = equiv.paceSeconds(for: .mile)
                }

                let body: [String: Any] = [
                    "input": trimmed,
                    "paceZones": paceZones,
                ]
                let data = try await callEdgeFunction(name: "parse-workout-shorthand", body: body)
                let result = try JSONDecoder().decode(ShorthandParseResult.self, from: data)

                await MainActor.run {
                    isParsing = false
                    guard nlInput == input else { return }
                    if result.steps.isEmpty {
                        nlResult = nil
                        nlError = "couldn't read that. Try something like \u{201C}6x800 @ 5K pace / 400 jog\u{201D}."
                    } else if !result.errors.isEmpty {
                        // Partial parse — show what tripped, keep the fill
                        // affordance so the athlete can review the rest.
                        nlResult = result
                        nlError = result.errors.joined(separator: " ")
                    } else {
                        nlResult = result
                        nlError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isParsing = false
                    guard nlInput == input else { return }
                    nlResult = nil
                    nlError = "couldn't reach the parser. Check your connection."
                }
            }
        }
    }

    /// Replace the editor's steps with the parsed structure. Consecutive
    /// identical actives separated by an identical recovery collapse into
    /// one interval set (repeats + recovery) so "6x800 / 400 jog" arrives
    /// as one editable block, not eleven rows.
    private func applyParsedResult(_ result: ShorthandParseResult) {
        let parsed = result.steps.sorted { $0.order < $1.order }
        var built: [EditableWorkoutStep] = []
        var i = 0

        while i < parsed.count {
            let raw = parsed[i]

            if raw.stepType == "active" {
                // Look ahead for [A, R, A, R, … A] where every A matches
                // and every R matches.
                var count = 1
                var recoveryRaw: ShorthandStep?
                var j = i + 1
                while j + 1 < parsed.count,
                      isRecovery(parsed[j]),
                      activesMatch(parsed[j + 1], raw),
                      recoveryMatches(parsed[j], recoveryRaw) {
                    if recoveryRaw == nil { recoveryRaw = parsed[j] }
                    count += 1
                    j += 2
                }
                // Trailing rep without a recovery after it.
                while j < parsed.count, activesMatch(parsed[j], raw) {
                    count += 1
                    j += 1
                }

                var step = makeEditableStep(from: raw, order: built.count)
                if count > 1 {
                    step.repeats = count
                    if let rec = recoveryRaw {
                        step.recovery = EditableWorkoutStep.EditableRecovery(
                            durationType: durationType(from: rec.durationType),
                            durationValue: rec.durationValue,
                            paceSelection: rec.recoveryType == "jog"
                                ? .namedPace(.recovery)
                                : .none
                        )
                    }
                }
                built.append(step)
                i = count > 1 ? j : i + 1
                continue
            }

            built.append(makeEditableStep(from: raw, order: built.count))
            i += 1
        }

        withAnimation {
            steps = built
            normalizeOrder()
        }
        if let dominant = WorkoutLabelGrammar.dominantZone(in: steps) {
            defaultZone = dominant
        }
        nlResult = nil
    }

    private func isRecovery(_ step: ShorthandStep) -> Bool {
        step.stepType == "recovery" || step.stepType == "rest"
    }

    private func activesMatch(_ a: ShorthandStep, _ b: ShorthandStep) -> Bool {
        a.stepType == "active"
            && a.durationType == b.durationType
            && a.durationValue == b.durationValue
            && a.paceReference == b.paceReference
    }

    private func recoveryMatches(_ candidate: ShorthandStep, _ reference: ShorthandStep?) -> Bool {
        guard let reference else { return true }
        return candidate.durationType == reference.durationType
            && candidate.durationValue == reference.durationValue
            && candidate.recoveryType == reference.recoveryType
    }

    private func makeEditableStep(from raw: ShorthandStep, order: Int) -> EditableWorkoutStep {
        let stepType: PlannedWorkoutStep.StepType = {
            switch raw.stepType {
            case "warmup": return .warmup
            case "cooldown": return .cooldown
            case "recovery": return .recovery
            case "rest": return .rest
            default: return .active
            }
        }()

        var step = EditableWorkoutStep(order: order, stepType: stepType)
        step.durationType = durationType(from: raw.durationType)
        step.durationValue = raw.durationValue
        if let zone = namedPace(fromReference: raw.paceReference) {
            step.paceSelection = .namedPace(zone)
        } else if stepType == .warmup || stepType == .cooldown {
            step.paceSelection = .namedPace(.easy)
        } else if stepType == .recovery || stepType == .rest {
            step.paceSelection = .none
        }
        return step
    }

    private func durationType(from raw: String) -> PlannedWorkoutStep.DurationType {
        switch raw {
        case "distance_meters": return .distanceMeters
        case "time_seconds": return .timeSeconds
        default: return .distanceMiles
        }
    }

    /// parse-workout-shorthand's paceReference vocabulary → NamedPace.
    private func namedPace(fromReference ref: String?) -> NamedPace? {
        switch ref {
        case "easy": return .easy
        case "moderate": return .moderate
        case "steady": return .steady
        case "marathon": return .mp
        case "half": return .hm
        case "10k": return .tenK
        case "5k": return .fiveK
        case "mile": return .mile
        default: return nil
        }
    }

    // MARK: - Save

    /// Persist through the audited edge-function path. For coach-issued
    /// workouts the function writes the yellow-tier plan_adjustments row
    /// server-side — the coach sees the before/after. On failure the sheet
    /// stays open so nothing the athlete built is lost.
    private func save() async {
        guard !steps.isEmpty else { return }
        isSaving = true

        let equiv = equivalentPaces
        let updatedSteps = steps.enumerated().map { index, editable in
            var step = editable
            step.order = index
            return step.toWorkoutStep(
                racePaceSeconds: racePaceSeconds,
                equivalentPaces: equiv
            )
        }

        let totalMiles = WorkoutLabelGrammar.totalMiles(of: steps)
        let name = summaryLine ?? scheduledWorkout.workout?.name ?? "Workout"
        let existing = scheduledWorkout.workout

        let updatedWorkout = PlannedWorkout(
            id: existing?.id ?? UUID(),
            name: name,
            category: existing?.category ?? .specific,
            trainingPhase: existing?.trainingPhase ?? viewModel.currentPhase,
            description: existing?.description ?? name,
            steps: updatedSteps,
            totalDistanceMiles: totalMiles > 0 ? totalMiles : existing?.totalDistanceMiles,
            estimatedDurationMinutes: existing?.estimatedDurationMinutes,
            signatureType: existing?.signatureType,
            createdAt: existing?.createdAt ?? Date()
        )

        var updatedScheduled = scheduledWorkout
        updatedScheduled.workout = updatedWorkout
        updatedScheduled.status = .modified

        let ok = await viewModel.submitWorkoutEdit(updatedScheduled)
        isSaving = false
        if ok {
            onSaved()
            dismiss()
        }
    }
}
