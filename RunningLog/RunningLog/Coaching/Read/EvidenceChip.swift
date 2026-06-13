//
//  EvidenceChip.swift
//  RunningLog
//
//  The ◆ workout-citation chip used by the Coach Read. Two forms:
//
//    - `.inline(workout:)`  — kerned mono chip with coral wash. Lives
//                             inline in `ReadProse`, on the text baseline.
//                             Never wraps mid-chip (`.fixedSize`).
//    - `.expanded(workout:)` — full workout card with mono day+type
//                             eyebrow, display title, mono meta line,
//                             and a trailing `↗`. Lives in the Sources
//                             panel.
//
//  Tap action: writes the workout's id to a `Binding<UUID?>` on the
//  parent. Sheet routing (i.e., presenting the workout detail surface)
//  is the parent's responsibility — `CoachReadView` (Phase 4.1) owns
//  the navigation.
//
//  Phase 3.1 of coach-the-read-prompts.md.
//

import SwiftUI

struct EvidenceChip: View {
    enum Form {
        case inline
        case expanded
    }

    let form: Form
    let workout: TrainingLog
    @Binding var selectedWorkoutId: UUID?

    /// Canonical label/title/meta for this run. Classifies against the
    /// athlete's engine-computed zones (the single source of truth) —
    /// see `WorkoutPresentation`.
    private var presentation: WorkoutPresentation {
        WorkoutPresentation(log: workout, zones: PaceZonesService.shared.zones)
    }

    // MARK: - Convenience initializers

    /// Kerned inline chip — sits on the paragraph's text baseline.
    static func inline(
        workout: TrainingLog,
        selectedWorkoutId: Binding<UUID?>
    ) -> EvidenceChip {
        EvidenceChip(
            form: .inline,
            workout: workout,
            selectedWorkoutId: selectedWorkoutId
        )
    }

    /// Full workout card — used inside the Sources panel.
    static func expanded(
        workout: TrainingLog,
        selectedWorkoutId: Binding<UUID?>
    ) -> EvidenceChip {
        EvidenceChip(
            form: .expanded,
            workout: workout,
            selectedWorkoutId: selectedWorkoutId
        )
    }

    // MARK: - Body

    var body: some View {
        switch form {
        case .inline: inlineChip
        case .expanded: expandedCard
        }
    }

    // MARK: - Inline chip

    private var inlineChip: some View {
        Button {
            selectedWorkoutId = workout.id
        } label: {
            Text("◆ \(presentation.label) \(workout.coachReadShortDay)")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.coral)
                .tracking(1.1) // 0.10em × 11pt
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.drip.coral.opacity(0.12))
                .cornerRadius(4) // 4pt is the chip/pill radius; cards use 12
        }
        .buttonStyle(.plain)
        // Don't let the chip wrap mid-token. The whole "◆ TEMPO TUE"
        // string is a single visual unit — wrapping breaks the eyebrow
        // contract that runners read at a glance.
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Expanded card

    private var expandedCard: some View {
        Button {
            selectedWorkoutId = workout.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Mono day + zone eyebrow.
                    Text(
                        "\(workout.coachReadShortDay) · \(presentation.label)"
                    )
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.coral)
                    .tracking(1.0) // 0.10em × 10pt — stat-tile label tracking

                    // Display title (e.g., "6.6 mi · MP"). Never sourced
                    // from workout_notes — see WorkoutPresentation.
                    Text(presentation.title)
                        .font(.dripDisplay(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Mono meta line (distance · pace · duration).
                    if let meta = presentation.metaLine {
                        Text(meta)
                            .font(.dripStat(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                Text("↗")
                    .font(.dripStat(14))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.drip.cardBackgroundElevated)
            .overlay(
                // Cards use 12pt radius (--r-card) per tokens.css —
                // 4pt is reserved for tight pills like the inline chip.
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.coral.opacity(0.18), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TrainingLog helpers (Coach Read surface only)

/// Display helpers used exclusively by the Coach Read chip variants.
/// Kept here (file-local) rather than on `TrainingLog` itself so the
/// Coach Read surface owns its own copy semantics without coupling the
/// shared model to view concerns.
private extension TrainingLog {

    /// 3-letter weekday abbreviation in the device's current locale,
    /// uppercased. Pulls from `workoutDate` (the date the run happened);
    /// falls back to `createdAt` so chips never show "—".
    ///
    /// The label / title / meta helpers that used to live here were
    /// removed in the 2026-06-12 effectiveness pass — they asserted the
    /// retired tempo/threshold vocabulary and sourced titles from
    /// `workout_notes`. All three now come from `WorkoutPresentation`.
    var coachReadShortDay: String {
        let date = workoutDate ?? createdAt
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Preview

#Preview("EvidenceChip — both forms") {
    PreviewHost()
        .padding()
        .background(Color.drip.background)
}

private struct PreviewHost: View {
    @State private var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Inline form, on a baseline of body text.
            VStack(alignment: .leading, spacing: 8) {
                Text("INLINE")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(0.8)
                HStack(spacing: 6) {
                    Text("Three good weeks in a row.")
                        .font(.dripBody(16))
                    EvidenceChip.inline(
                        workout: Self.mockWorkout,
                        selectedWorkoutId: $selected
                    )
                }
            }

            // Expanded form, as it'd render in the Sources panel.
            VStack(alignment: .leading, spacing: 8) {
                Text("EXPANDED")
                    .font(.dripStat(10))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(0.8)
                EvidenceChip.expanded(
                    workout: Self.mockWorkout,
                    selectedWorkoutId: $selected
                )
            }

            // Selection feedback for the preview.
            Text("tapped id: \(selected?.uuidString.prefix(8) ?? "—")")
                .font(.dripStat(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let mockWorkout: TrainingLog = {
        let now = Date()
        // Build via a JSON fixture so we don't have to recite every
        // TrainingLog initializer field. The decoder ignores fields we
        // don't supply; defaults handle the rest.
        let iso = ISO8601DateFormatter().string(from: now)
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "created_at": "\(iso)",
          "workout_date": "\(iso.prefix(10))",
          "workout_type": "tempo",
          "workout_distance_miles": 6.0,
          "workout_duration_minutes": 44.5,
          "workout_pace_per_mile": "7:25",
          "workout_notes": "6 × 1mi tempo, 90s recovery",
          "mood": "positive"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Fall back to a minimal mock if the decode somehow fails (e.g.
        // model schema drifted). Previews shouldn't crash.
        if let log = try? decoder.decode(TrainingLog.self, from: data) {
            return log
        }
        // Unreachable in practice; kept so the preview always renders.
        fatalError("Preview mock decode failed — TrainingLog schema drift?")
    }()
}
