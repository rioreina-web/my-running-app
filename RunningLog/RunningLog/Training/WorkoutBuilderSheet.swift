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

    /// What the numbers mean. Goal and Current swap the table underneath the
    /// zones; Fixed freezes them into typed paces. See `WorkoutPaceBasis`.
    @State private var paceBasis: WorkoutPaceBasis = .goal
    /// The relative basis Fixed was frozen from, so leaving Fixed lands back
    /// where the athlete was rather than always on Goal.
    @State private var basisBeforeFixed: WorkoutPaceBasis = .goal

    // Natural-language entry
    @State private var nlInput = ""
    @State private var nlResult: ShorthandParseResult?
    @State private var nlError: String?
    @State private var isParsing = false

    // MARK: - Derived

    private var defaultEquivalentPaces: EquivalentPaces {
        EquivalentPaces(raceDistance: .marathon, goalTimeSeconds: 14400)
    }

    /// Zones off the goal race time — the plan's target, not today's fitness.
    private var goalPaces: EquivalentPaces {
        viewModel.equivalentPaces ?? defaultEquivalentPaces
    }

    /// Zones off the athlete's pace profile. Nil until a fitness read exists,
    /// which is why Current can be an unavailable basis.
    private var currentFitnessPaces: EquivalentPaces? {
        EquivalentPaces.fromCurrentFitness(
            AthletePaceProfileService.shared.profile,
            disabledPaces: goalPaces.disabledPaces
        )
    }

    /// The table every zone chip, resolved pace and save reads against.
    /// In Fixed the steps carry their own numbers, but the table still backs
    /// the "= LT / LT +6s" orientation line, so it stays on whatever relative
    /// basis the freeze came from.
    private var equivalentPaces: EquivalentPaces {
        switch paceBasis {
        case .goal: return goalPaces
        case .current: return currentFitnessPaces ?? goalPaces
        case .fixed: return table(for: basisBeforeFixed)
        }
    }

    private func table(for basis: WorkoutPaceBasis) -> EquivalentPaces {
        switch basis {
        case .goal:
            return goalPaces
        case .current:
            return currentFitnessPaces ?? goalPaces
        case .fixed:
            // Resolved without recursing back through `basisBeforeFixed` — it
            // is only ever assigned a relative basis today, and a table lookup
            // is the wrong place to be relying on that.
            return basisBeforeFixed == .current ? (currentFitnessPaces ?? goalPaces) : goalPaces
        }
    }

    private var unavailableBases: Set<WorkoutPaceBasis> {
        currentFitnessPaces == nil ? [.current] : []
    }

    private var unavailableNote: String? {
        currentFitnessPaces == nil
            ? "Current paces need a fitness read. Log a few runs and they'll turn on."
            : nil
    }

    /// One line naming what the active basis is anchored to. Real numbers, so
    /// the athlete can see the two bases disagree rather than take it on faith.
    private var basisCaption: String {
        let mp = EquivalentPaces.formatPace(equivalentPaces.mpPace)
        switch paceBasis {
        case .goal:
            let goal = goalPaces
            let time = PaceCalculator.formatTime(goal.goalTimeSeconds)
            return "Zones off the goal: \(time) \(goal.goalRaceDistance.displayName), MP \(mp)."
        case .current:
            guard currentFitnessPaces != nil else {
                return "No fitness read yet, so these are still goal zones."
            }
            return "Zones off your current fitness, MP \(mp). Moves as your fitness moves."
        case .fixed:
            return "Every step carries a typed pace. Nothing re-derives it when the goal or your fitness changes."
        }
    }

    /// Coach-issued when the row is a coach prescription or the active
    /// plan came from a coach template. Drives the "Customize" posture.
    private var isCoachIssued: Bool {
        scheduledWorkout.source == "coach_locked"
            || (viewModel.activePlan?.isCoachPlan ?? false)
    }

    private var summaryLine: String? {
        WorkoutLabelGrammar.summaryLine(steps: steps, equivalentPaces: equivalentPaces)
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

                        BuilderPaceBasisRow(
                            basis: $paceBasis,
                            caption: basisCaption,
                            unavailable: unavailableBases,
                            unavailableNote: unavailableNote
                        )
                        .padding(.horizontal, 20)

                        if paceBasis.isRelative {
                            BuilderZoneChipRow(
                                selectedZone: $defaultZone,
                                equivalentPaces: equivalentPaces
                            )
                            .padding(.horizontal, 20)
                        }

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
            .onChange(of: paceBasis) { previous, next in
                applyBasisChange(from: previous, to: next)
            }
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
                VStack(alignment: .leading, spacing: 6) {
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

                    // A step the parser built but could not pace is the
                    // dangerous kind: it looks complete in the editor. Say it
                    // here, before the fill, rather than letting a default
                    // pass for something the athlete wrote.
                    if let unpaced = unresolvedNote(result) {
                        Text(unpaced)
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
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
                            paceBasis: paceBasis,
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
        if let dominant = WorkoutLabelGrammar.dominantZone(in: steps, equivalentPaces: equivalentPaces) {
            defaultZone = dominant
        }
        paceBasis = inferredBasis()
    }

    /// A workout whose every pace target is a typed number was built in Fixed,
    /// so it reopens there. Anything with a zone in it reopens relative — the
    /// zones are what would have moved, and the athlete should see them moving.
    ///
    /// Goal and Current aren't distinguishable from the saved steps (both write
    /// zones), so a reopened relative workout lands on Goal and one tap moves
    /// it. Writing the basis into the step JSON would fix that; it isn't worth
    /// a schema shape the web and the coach portal don't read yet.
    private func inferredBasis() -> WorkoutPaceBasis {
        let targeted = steps.filter { $0.paceSelection != .none }
        guard !targeted.isEmpty else { return .goal }
        let allFixed = targeted.allSatisfy {
            if case .fixed = $0.paceSelection { return true }
            return false
        }
        return allFixed ? .fixed : .goal
    }

    /// Rewrite every step for a change of basis, then remember where a freeze
    /// came from so leaving Fixed returns there rather than always to Goal.
    private func applyBasisChange(from previous: WorkoutPaceBasis, to next: WorkoutPaceBasis) {
        guard previous != next else { return }
        let outgoing = table(for: previous)
        if next == .fixed, previous.isRelative { basisBeforeFixed = previous }
        let incoming = table(for: next)

        withAnimation {
            steps = steps.map {
                $0.switchingBasis(
                    from: previous,
                    to: next,
                    outgoing: outgoing,
                    incoming: incoming,
                    racePaceSeconds: racePaceSeconds
                )
            }
        }
    }

    /// A selection expressed in the active basis: a zone while relative, the
    /// number that zone currently resolves to while fixed.
    private func selection(forZone zone: NamedPace) -> EditableWorkoutStep.PaceSelection {
        let zoned = EditableWorkoutStep.PaceSelection.namedPace(zone)
        guard paceBasis == .fixed else { return zoned }
        return zoned.frozen(with: equivalentPaces, racePaceSeconds: racePaceSeconds)
    }

    private func addStep() {
        var newStep = EditableWorkoutStep(order: steps.count)
        newStep.paceSelection = selection(forZone: defaultZone)
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
                // Send the ACTIVE table, not the goal one — otherwise
                // "20min @ marathon pace" typed under Current fitness gets its
                // duration estimated off goal MP.
                let equiv = equivalentPaces
                let paceZones: [String: Any] = [
                    "easy": equiv.paceSeconds(for: .easy),
                    "moderate": equiv.paceSeconds(for: .moderate),
                    "steady": equiv.paceSeconds(for: .steady),
                    "marathon": equiv.paceSeconds(for: .mp),
                    "half": equiv.paceSeconds(for: .hm),
                    "10k": equiv.paceSeconds(for: .tenK),
                    "5k": equiv.paceSeconds(for: .fiveK),
                    "mile": equiv.paceSeconds(for: .mile),
                ]

                let body: [String: Any] = [
                    "input": trimmed,
                    "paceZones": paceZones,
                    // The server's deterministic grammar scores 12% against
                    // this coach's real plans and cannot read a pace offset at
                    // all; the model layer reads both. Cost is bounded
                    // server-side by `llmBudgetAllows`, which falls back to
                    // the grammar rather than failing, so the button always
                    // does something.
                    "useModel": true,
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
        // The structured shape is already one row per step, with its pace and
        // its repeats intact, so it needs none of the collapsing below — and
        // it is the only shape that carries an offset. Alternations arrive
        // here as N legs with alternating adjustments; writing them out is
        // the correct reading, not a failure to compress.
        if let structured = result.structuredSteps, !structured.isEmpty {
            applyStructuredSteps(structured)
            return
        }
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

                var step = EditableWorkoutStep(legacyShorthand: raw, order: built.count)
                if count > 1 {
                    step.repeats = count
                    if let rec = recoveryRaw {
                        step.recovery = EditableWorkoutStep.EditableRecovery(
                            durationType: EditableWorkoutStep.durationType(fromShorthand: rec.durationType),
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

            built.append(EditableWorkoutStep(legacyShorthand: raw, order: built.count))
            i += 1
        }

        if let dominant = WorkoutLabelGrammar.dominantZone(in: built, equivalentPaces: equivalentPaces) {
            defaultZone = dominant
        }
        // The parser only speaks zones. Under Fixed those become numbers on
        // arrival, so a filled-in workout matches the basis it landed in.
        if paceBasis == .fixed {
            let table = equivalentPaces
            built = built.map {
                $0.switchingBasis(
                    from: basisBeforeFixed,
                    to: .fixed,
                    outgoing: table,
                    incoming: table,
                    racePaceSeconds: racePaceSeconds
                )
            }
        }
        withAnimation {
            steps = built
            normalizeOrder()
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

    /// "2 steps need a pace" — or nil when every step carries the one the
    /// coach wrote.
    private func unresolvedNote(_ result: ShorthandParseResult) -> String? {
        guard let structured = result.structuredSteps else { return nil }
        let count = structured.filter { $0.unresolvedReason != nil }.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 step needs a pace" : "\(count) steps need a pace"
    }

    private func applyStructuredSteps(_ structured: [ShorthandStructuredStep]) {
        var built = structured.enumerated().map { index, raw in
            EditableWorkoutStep(shorthand: raw, order: index)
        }

        if let dominant = WorkoutLabelGrammar.dominantZone(in: built, equivalentPaces: equivalentPaces) {
            defaultZone = dominant
        }
        if paceBasis == .fixed {
            let table = equivalentPaces
            built = built.map {
                $0.switchingBasis(
                    from: basisBeforeFixed,
                    to: .fixed,
                    outgoing: table,
                    incoming: table,
                    racePaceSeconds: racePaceSeconds
                )
            }
        }
        withAnimation {
            steps = built
            normalizeOrder()
        }
        nlResult = nil
    }

    // The wire → editor mapping lives in `ShorthandStepMapping.swift`, shared
    // with DayDetailSheet's workshop. It used to be five private copies here.

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
