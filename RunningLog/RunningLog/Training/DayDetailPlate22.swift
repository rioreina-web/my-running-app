//
//  DayDetailPlate22.swift
//  RunningLog
//
//  Plate 22 redesign of the Plan → Day Detail sheet.
//
//  This file holds the *new* editorial pieces — header, stat strip,
//  structure eyebrow, coach-note, action strip — that DayDetailSheet
//  composes into its read-only path. Edit mode, workshop mode, the
//  heat calculator, and the existing WorkoutStepRow stay where they
//  are; we just replace the cards that wrap them with the editorial
//  vocabulary used by the rest of the trend mockups.
//
//  Section order on the sheet (top → bottom):
//    1. DD22Header        — TUESDAY · PLAN eyebrow + "May 5" display
//                            + italic-serif workout-type tagline
//    2. DD22StatStrip     — DISTANCE · DURATION (two slots, no Load —
//                            Load is a retrospective metric, doesn't
//                            belong on a planning surface)
//    3. (Heat calculator stays — its own component)
//    4. DD22StructureEyebrow — "STRUCTURE" caption above the step list
//    5. (WorkoutStepRow loop stays — existing component)
//    6. DD22CoachNote     — italic-serif quote section, only when the
//                            scheduled workout has a notes field set
//    7. DD22ActionStrip   — "Mark complete ↗" primary + small text-link
//                            secondary actions row
//

import SwiftUI

// MARK: - Editorial rule

/// Three-part editorial divider — line · dot · line. Used to separate
/// sections of the day-detail sheet (header → heat → structure → coach
/// note → actions) so the sheet reads as a series of editorial beats
/// instead of one continuous wall.
struct DD22EditorialRule: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 3, height: 3)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Header

/// Editorial header for the day detail sheet.
///
/// Replaces the previous `DayDetailHeader` which leaned on a sans-serif
/// title and an orange "Tempo Run" pill. This version hands the screen
/// to the date — Crimson Pro display, monospaced eyebrow above, italic
/// serif tagline below.
struct DD22Header: View {
    let workout: ScheduledWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)
            Text(dateLine)
                .font(.dripDisplay(40))
                .foregroundStyle(Color.drip.textPrimary)
            if let tagline = tagline {
                Text(tagline)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.drip.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let weekday = f.string(from: workout.date).uppercased()
        return "\(weekday)  ·  PLAN"
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: workout.date)
    }

    /// Italic-serif tagline. Format: "Type · Distance" (e.g. "MP rhythm session · 11 mi").
    /// Falls back to just the workout-type display name when distance is unknown.
    private var tagline: String? {
        let typeName = displayTypeName(workout)
        guard let miles = workout.workout?.totalDistanceMiles, miles > 0 else {
            return typeName
        }
        let str = miles == miles.rounded()
            ? String(format: "%.0f", miles)
            : String(format: "%.1f", miles)
        return "\(typeName)  ·  \(str) mi"
    }

    private func displayTypeName(_ w: ScheduledWorkout) -> String {
        // Prefer the planner-given name if present (e.g. "MP Rhythm Session"),
        // else fall back to the workout-type enum's title.
        if let name = w.workout?.name, !name.isEmpty {
            return name
        }
        return w.workoutType.displayName
    }
}

// MARK: - Stat strip

/// Two-slot stat strip. Distance · Duration. Mirrors the same pattern
/// used in the other trend plates so the sheet reads as part of the
/// same visual family.
struct DD22StatStrip: View {
    let workout: ScheduledWorkout

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
            HStack(spacing: 0) {
                statCell(label: "DISTANCE", value: distanceValue, unit: "mi")
                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(width: 1, height: 56)
                statCell(label: "DURATION", value: durationValue, unit: "min")
            }
            .padding(.vertical, 16)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)
        }
    }

    private func statCell(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.dripDisplay(28))
                    .foregroundStyle(Color.drip.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var distanceValue: String {
        guard let miles = workout.workout?.totalDistanceMiles, miles > 0
        else { return "—" }
        return miles == miles.rounded()
            ? String(format: "%.0f", miles)
            : String(format: "%.1f", miles)
    }

    /// Estimated duration in minutes. Prefers the workout's
    /// `estimatedDurationMinutes`; falls back to a coarse pace-based
    /// estimate when only distance is set.
    private var durationValue: String {
        if let est = workout.workout?.estimatedDurationMinutes, est > 0 {
            return String(format: "%.0f", est)
        }
        return "—"
    }
}

// MARK: - Structure eyebrow

/// Tiny caption-only header that sits above the existing WorkoutStepRow
/// list. Replaces the previous "WORKOUT STEPS" caption + rounded card
/// wrapper so the steps live on the bone background like everywhere else.
struct DD22StructureEyebrow: View {
    var body: some View {
        Text("STRUCTURE")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.0)
            .foregroundStyle(Color.drip.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Coach note

/// Italic-serif quote section that surfaces the coach's notes for this
/// scheduled workout. Renders only when notes is non-empty — empty notes
/// shouldn't reserve space.
struct DD22CoachNote: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FROM YOUR COACH")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
            Text("\u{201C}\(notes)\u{201D}")
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Color.drip.textPrimary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Action strip

/// Editorial replacement for `WorkoutActionButtons`. Primary "Mark
/// complete ↗" set in serif AMBER with a small underline accent; the
/// secondary actions live as a row of small monospaced text links
/// separated by middots.
struct DD22ActionStrip: View {
    let workout: ScheduledWorkout
    let isExporting: Bool
    let onMarkComplete: () -> Void
    let onSkip: () -> Void
    let onSwap: () -> Void
    let onRestructure: () -> Void
    let onReschedule: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 1)

            // Primary action — "Mark complete ↗" in AMBER serif.
            // Hidden once the workout is already completed.
            if workout.status != .completed {
                Button(action: onMarkComplete) {
                    HStack(spacing: 8) {
                        Text("Mark complete")
                            .font(.dripDisplay(20))
                            .foregroundStyle(Color.drip.coral)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.drip.coral)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.drip.coral)
                            .frame(height: 2)
                            .offset(y: 4)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Completed")
                    .font(.dripDisplay(20))
                    .foregroundStyle(Color.drip.positive)
            }

            // Secondary actions — small monospaced text links.
            HStack(spacing: 0) {
                actionLink("Skip", action: onSkip)
                middot()
                actionLink("Swap", action: onSwap)
                middot()
                actionLink("Replace", action: onRestructure)
                middot()
                actionLink("Reschedule", action: onReschedule)
                middot()
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color.drip.textSecondary)
                } else {
                    actionLink("Export", action: onExport)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func actionLink(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func middot() -> some View {
        Text("·")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.drip.textTertiary)
            .padding(.horizontal, 10)
    }
}
