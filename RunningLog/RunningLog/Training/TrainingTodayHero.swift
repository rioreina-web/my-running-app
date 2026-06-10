//
//  TrainingTodayHero.swift
//  RunningLog
//
//  Today's session, set as an editorial headline rather than a card.
//  Four things only:
//
//      TODAY · WED · APR 29                            11 MI · MP
//      Marathon-pace 11.
//      2 MI WU  ·  8 MI @ MP  ·  1 MI CD
//      Mark complete ↗
//
//  Coral discipline: the coral eyebrow ("TODAY · WED · APR 29") and the
//  coral "Mark complete ↗" link belong to the same cluster — they
//  reinforce, they don't compete. Nothing else here is coral.
//
//  Rest-day empty state per the redesign handoff: italic-serif "Rest
//  day. Walk or stretch — nothing to log." No CTA.
//

import SwiftUI

struct TrainingTodayHero: View {
    /// Today's planned workout, if one exists in the active plan. When
    /// nil, the hero renders the rest-day empty state.
    let workout: ScheduledWorkout?
    let onMarkComplete: () -> Void

    var body: some View {
        if let workout, workout.workoutType != .rest {
            session(workout)
        } else {
            restDayEmpty
        }
    }

    // MARK: Session

    @ViewBuilder
    private func session(_ workout: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row — coral left, neutral right.
            HStack(alignment: .firstTextBaseline) {
                Text(todayEyebrow)
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.coral)
                Spacer(minLength: 12)
                Text(metaEyebrow(workout))
                    .font(.dripEyebrow(11))
                    .tracking(1.3)
                    .foregroundStyle(Color.drip.textSecondary)
            }

            // Editorial headline — `<type sentence-case> <distance>.`
            Text(headline(workout))
                .font(.dripDisplay(30))
                .tracking(-0.36)  // ~-0.012em at 30pt
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 6)

            // Mono prescription line. One line only — TARGET pace and
            // EXEC time live on Workout Detail, not here.
            if let prescription = prescriptionLine(workout) {
                Text(prescription)
                    .font(.dripEyebrow(11))
                    .tracking(1.1)  // 0.10em
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 10)
            }

            // Coral text link — opens the same workout-completion flow
            // Day Detail uses.
            Button(action: onMarkComplete) {
                Text("Mark complete ↗")
                    .font(.custom("CrimsonPro-Regular", size: 14).weight(.semibold))
                    .foregroundStyle(Color.drip.coral)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.drip.coral)
                            .frame(height: 1)
                            .offset(y: 2)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Rest day empty

    private var restDayEmpty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(todayEyebrow)
                .font(.dripEyebrow(11))
                .tracking(1.3)
                .foregroundStyle(Color.drip.textSecondary)
            Text("Rest day. Walk or stretch — nothing to log.")
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Formatting

    private var todayEyebrow: String {
        let f = DateFormatter()
        f.dateFormat = "EEE  ·  MMM d"
        return "TODAY  ·  \(f.string(from: Date()).uppercased())"
    }

    private func metaEyebrow(_ workout: ScheduledWorkout) -> String {
        var parts: [String] = []
        if let miles = workout.workout?.totalDistanceMiles, miles > 0 {
            parts.append("\(Int(miles.rounded())) MI")
        }
        parts.append(typeShortLabel(workout.workoutType))
        return parts.joined(separator: "  ·  ")
    }

    /// Sentence-case workout type for the headline. Per the handoff
    /// voice spec: `Marathon-pace 11.`, `Tempo 8.`, `Long run 20.`,
    /// `Easy 6.`, `Recovery 4.`
    private func headline(_ workout: ScheduledWorkout) -> String {
        let type = typeHeadlineLabel(workout.workoutType)
        if let miles = workout.workout?.totalDistanceMiles, miles > 0 {
            let n = Int(miles.rounded())
            return "\(type) \(n)."
        }
        return "\(type)."
    }

    private func typeHeadlineLabel(_ t: ScheduledWorkoutType) -> String {
        switch t {
        case .rest:          return "Rest"
        case .easy:          return "Easy"
        case .tempo:         return "Tempo"
        case .intervals:     return "Intervals"
        case .longRun:       return "Long run"
        case .recovery:      return "Recovery"
        case .race:          return "Race"
        case .progression:   return "Progression"
        case .strides:       return "Strides"
        case .strength:      return "Strength"
        case .crossTraining: return "Cross training"
        }
    }

    private func typeShortLabel(_ t: ScheduledWorkoutType) -> String {
        switch t {
        case .rest:          return "REST"
        case .easy:          return "EASY"
        case .tempo:         return "TEMPO"
        case .intervals:     return "INTV"
        case .longRun:       return "LONG"
        case .recovery:      return "RECOV"
        case .race:          return "RACE"
        case .progression:   return "PROG"
        case .strides:       return "STRIDE"
        case .strength:      return "STR"
        case .crossTraining: return "XT"
        }
    }

    /// One-line mono prescription. Tries the workout's authored
    /// description first (e.g. "2 mi WU · 8 mi @ MP · 1 mi CD"); falls
    /// back to a step-summary when description is empty.
    private func prescriptionLine(_ workout: ScheduledWorkout) -> String? {
        if let desc = workout.workout?.description,
           !desc.trimmingCharacters(in: .whitespaces).isEmpty {
            return desc.uppercased()
        }
        if let name = workout.workout?.name,
           !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name.uppercased()
        }
        return nil
    }
}
