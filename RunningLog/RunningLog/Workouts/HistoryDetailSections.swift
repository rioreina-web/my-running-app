//
//  HistoryDetailSections.swift
//  RunningLog
//
//  Supporting section views and extensions for history detail views.
//

// `os`, `Supabase` and `Auth` were only needed by the two removed sections
// (they called the coaching-agent edge function directly). What's left is pure
// SwiftUI + Foundation.
import SwiftUI

// NOTE (log-detail redesign): `CoachInsightSection` and `WorkoutNotesSection`
// were removed from here. Both were defined and never referenced anywhere in
// the app — the live journal entry sheet builds these sections itself in
// `HistoryDetailSheet+Editorial.swift` (the coach insight now lives behind the
// "✦ READ THE INSIGHT" row; workout notes behind "＋ ADD A NOTE").
//
// What is still live in this file: EditableMoodPicker, EditableWorkoutTypeSection,
// EditableWorkoutStatsSection, and the Date/String extensions below.


// MARK: - EditableMoodPicker

struct EditableMoodPicker: View {
    @Binding var selectedMood: String

    private let moods = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "energized": return Color.drip.energized
        case "positive": return Color.drip.positive
        case "neutral": return Color.drip.neutral
        case "tired": return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured": return Color.drip.injured
        default: return Color.drip.neutral
        }
    }

    // Mood pills follow the design-system spec: tracked uppercase label
    // with a color dot, no SF Symbol icons. The `moodIcon` helper that
    // used to live here was a direct violation of the "no emoji, no
    // faces" rule — deleted.

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    Button {
                        selectedMood = selectedMood == mood ? "" : mood
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(selectedMood == mood ? .white : moodColor(mood))
                                .frame(width: 5, height: 5)
                            Text(mood.uppercased())
                                .font(.dripEyebrow(11))
                                .tracking(1.1)  // 0.10em caption tracking at 11pt
                        }
                        .foregroundStyle(selectedMood == mood ? .white : moodColor(mood))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedMood == mood ? moodColor(mood) : moodColor(mood).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - EditableWorkoutTypeSection

struct EditableWorkoutTypeSection: View {
    @Binding var selectedType: String

    /// The type this entry arrived with, captured once. Seeding the legacy
    /// appendix from `selectedType` instead would make the legacy chip vanish
    /// the moment you tap a canonical one — with no way back to it.
    @State private var arrivedAs: String?

    /// Was a private 6-key list of its own — the one that wrote `"interval"`
    /// while the receipt's picker wrote `"intervals"`, leaving 14 rows under
    /// one spelling and 9 under the other. Single source of truth since
    /// 2026-08-07: `WorkoutLabel.offered`, which also carries the retirement of
    /// "Tempo"/"Threshold" this list predated.
    private var workoutTypes: [(String, String)] {
        WorkoutLabel.options(including: arrivedAs ?? selectedType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("WORKOUT TYPE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workoutTypes, id: \.0) { type, label in
                        Button {
                            selectedType = selectedType == type ? "" : type
                        } label: {
                            Text(label)
                                .font(.dripCaption(12))
                                .fontWeight(.medium)
                                .foregroundStyle(selectedType == type ? .white : Color.drip.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selectedType == type ? Color.drip.coral : Color.drip.coral.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .onAppear { if arrivedAs == nil { arrivedAs = selectedType } }
    }
}

// MARK: - EditableWorkoutStatsSection

struct EditableWorkoutStatsSection: View {
    @Binding var distanceText: String
    @Binding var durationText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("WORKOUT STATS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distance (mi)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0.00", text: $distanceText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration (m:ss)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0:00", text: $durationText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
            }

            // Computed pace display
            if let distance = Double(distanceText),
               let duration = parseDurationToMinutes(durationText),
               distance > 0 {
                let totalSecs = Int(((duration / distance) * 60).rounded())
                let paceMinutes = totalSecs / 60
                let paceSeconds = totalSecs % 60
                Text("Pace: \(String(format: "%d:%02d", paceMinutes, paceSeconds)) /mi")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.energized.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.energized.opacity(0.3), lineWidth: 1)
        )
    }

    private func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: return parts[0] + parts[1] / 60.0
        case 1: return parts[0]
        default: return nil
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var dayOfWeekString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: self)
    }

    var dayNumberString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    func containsAny(_ substrings: [String]) -> Bool {
        substrings.contains { self.contains($0) }
    }
}
