import Foundation

// MARK: - parse-workout-shorthand wire shapes → the editor's step model
//
// One mapping, two callers. `WorkoutBuilderSheet` and `DayDetailSheet`'s
// workshop both turn a shorthand parse into steps, and until now each carried
// its own copy. They had drifted badly apart:
//
//   - the builder read `structuredSteps` and kept the zone, the offset and any
//     absolute written pace;
//   - the workshop read the legacy `steps` projection and rebuilt a
//     `PaceIntensity` from `pacePercentage` — a field the server hardcodes to
//     null (`parse-workout-shorthand/index.ts`, `toLegacyStep`). That `.map`
//     never fired, so every workout written into the PLAN from that screen
//     saved with no pace at all: no zone, no offset, no intensity. Its only
//     record of a pace was the English sentence "@ marathon pace" in `notes`.
//
// Keeping the reading here means the next surface to parse shorthand inherits
// the lossless one rather than whichever copy it was pasted from.

extension EditableWorkoutStep {

    /// Editable steps for a parse, preferring the shape that can express a pace
    /// in full.
    ///
    /// `structuredSteps` is the canonical shape from
    /// `_shared/workout-step-validator.ts`, and the only one that can carry a
    /// zone PLUS an offset ("MP-10", "MP-3%") or an absolute written pace. The
    /// server emits it only when the caller asked for the model layer, so a
    /// caller that omits `useModel` silently gets the weaker reading below.
    ///
    /// `steps` is the legacy projection, kept as a fallback for a response that
    /// came from the deterministic grammar. Its pace vocabulary is a bare zone
    /// name, so an offset has nowhere to live and does not survive the trip.
    static func steps(fromShorthand result: ShorthandParseResult) -> [EditableWorkoutStep] {
        if let structured = result.structuredSteps, !structured.isEmpty {
            return structured.enumerated().map {
                EditableWorkoutStep(shorthand: $1, order: $0)
            }
        }
        return result.steps
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { EditableWorkoutStep(legacyShorthand: $1, order: $0) }
    }

    /// The canonical reading: zone, offset, exact pace, repeats and recovery all
    /// survive.
    init(shorthand raw: ShorthandStructuredStep, order: Int) {
        let type = EditableWorkoutStep.stepType(fromShorthand: raw.stepType)
        self.init(order: order, stepType: type)

        durationType = EditableWorkoutStep.durationType(fromShorthand: raw.durationType)
        durationValue = raw.durationValue
        paceSelection = EditableWorkoutStep.paceSelection(
            zone: raw.paceZone,
            adjustment: raw.paceAdjustment,
            exactPaceSecPerMile: raw.exactPaceSecPerMile,
            stepType: type
        )
        if let repeats = raw.repeats, repeats > 1 { self.repeats = repeats }
        if let rec = raw.recovery {
            recovery = EditableRecovery(
                durationType: EditableWorkoutStep.durationType(fromShorthand: rec.durationType),
                durationValue: rec.durationValue,
                paceSelection: rec.isJog ? .namedPace(.recovery) : .none
            )
        }
        notes = raw.note ?? ""
    }

    /// The legacy reading. A zone name and — where the server sent one — an
    /// absolute pace. No offset: the wire shape cannot express one.
    ///
    /// `absolutePaceSecPerMile` is read here deliberately. It is the one part of
    /// a written pace ("6x800 @ 3:00") that DOES survive into the legacy
    /// projection, and both previous copies of this mapping ignored it, so a
    /// number the coach wrote on purpose was dropped one field short of the
    /// editor.
    init(legacyShorthand raw: ShorthandStep, order: Int) {
        let type = EditableWorkoutStep.stepType(fromShorthand: raw.stepType)
        self.init(order: order, stepType: type)

        durationType = EditableWorkoutStep.durationType(fromShorthand: raw.durationType)
        durationValue = raw.durationValue
        paceSelection = EditableWorkoutStep.paceSelection(
            zone: EditableWorkoutStep.namedPace(fromShorthandReference: raw.paceReference)?.rawValue,
            adjustment: nil,
            exactPaceSecPerMile: raw.absolutePaceSecPerMile,
            stepType: type
        )
        if let reps = raw.repCount, reps > 1 { repeats = reps }
        notes = raw.notes ?? ""
    }

    // MARK: - Field mappings

    static func stepType(fromShorthand raw: String) -> PlannedWorkoutStep.StepType {
        switch raw {
        case "warmup": return .warmup
        case "cooldown": return .cooldown
        case "recovery": return .recovery
        case "rest": return .rest
        default: return .active
        }
    }

    static func durationType(fromShorthand raw: String) -> PlannedWorkoutStep.DurationType {
        switch raw {
        case "distance_km": return .distanceKm
        case "distance_meters": return .distanceMeters
        case "time_seconds": return .timeSeconds
        default: return .distanceMiles
        }
    }

    /// The parser's pace vocabulary → the editor's.
    ///
    /// An unresolved pace stays visibly unresolved: it lands on the step type's
    /// default and the calling sheet says so above the steps, rather than
    /// passing off a guess as the coach's prescription. The reason code travels
    /// separately on `ShorthandStructuredStep.unresolvedReason` — this function
    /// deliberately cannot see it, because a default that looked like an answer
    /// is exactly the failure being guarded against.
    static func paceSelection(
        zone: String?,
        adjustment: ShorthandStructuredStep.Adjustment?,
        exactPaceSecPerMile: Double?,
        stepType: PlannedWorkoutStep.StepType
    ) -> PaceSelection {
        // A written number is the prescription, not a hint toward a zone —
        // folding it into the nearest zone reintroduces the drift the coach
        // avoided by writing a number in the first place.
        if let exact = exactPaceSecPerMile, exact > 0 { return .fixed(exact) }
        guard let zone, let named = NamedPace(rawValue: zone) else {
            switch stepType {
            case .warmup, .cooldown: return .namedPace(.easy)
            case .recovery, .rest: return .none
            default: return .namedPace(stepType.defaultPace)
            }
        }
        guard let adjustment, adjustment.value != 0 else { return .namedPace(named) }
        switch adjustment.type {
        case "percent": return .namedPacePercentOffset(named, adjustment.value)
        case "seconds_per_mile": return .namedPaceOffset(named, adjustment.value)
        default: return .namedPace(named)
        }
    }

    /// The legacy `paceReference` vocabulary is race-name based ("marathon",
    /// "half"); `NamedPace` speaks the canonical zone keys. One map, matching
    /// `LEGACY_PACE` in `parse-workout-shorthand/index.ts` in the other
    /// direction.
    static func namedPace(fromShorthandReference ref: String?) -> NamedPace? {
        switch ref {
        case "easy": return .easy
        case "recovery": return .recovery
        case "moderate": return .moderate
        case "steady": return .steady
        case "marathon": return .mp
        case "half": return .hm
        case "threshold": return .threshold
        case "10k": return .tenK
        case "5k": return .fiveK
        case "3k": return .threeK
        case "mile": return .mile
        default: return nil
        }
    }
}
