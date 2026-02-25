import PostgREST
import Supabase
import SwiftUI

// MARK: - ManualWorkoutView

struct ManualWorkoutView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var distanceMiles: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0
    @State private var workoutDate: Date = .init()
    @State private var notes: String = ""
    @State private var selectedMood: String?
    @State private var isUploading = false
    @State private var showSuccess = false

    private let moods = [
        ("energized", "bolt.fill", Color.drip.energized),
        ("good", "hand.thumbsup.fill", Color.drip.success),
        ("tired", "zzz", Color.drip.textSecondary),
        ("sluggish", "tortoise.fill", Color.drip.injured)
    ]

    private var durationMinutes: Double {
        Double(hours * 60) + Double(minutes) + Double(seconds) / 60.0
    }

    private var distanceValue: Double? {
        Double(distanceMiles)
    }

    private var canSave: Bool {
        guard let distance = distanceValue else { return false }
        return distance > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Distance Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Distance")

                            HStack(spacing: 12) {
                                TextField("0.00", text: $distanceMiles)
                                    .font(.dripStat(40))
                                    .foregroundStyle(Color.drip.textPrimary)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)

                                Text("miles")
                                    .font(.dripBody(18))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                            .padding(20)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }

                        // Duration Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Duration")

                            HStack(spacing: 8) {
                                DurationPicker(value: $hours, label: "hr", range: 0 ... 23)
                                Text(":")
                                    .font(.dripStat(24))
                                    .foregroundStyle(Color.drip.textSecondary)
                                DurationPicker(value: $minutes, label: "min", range: 0 ... 59)
                                Text(":")
                                    .font(.dripStat(24))
                                    .foregroundStyle(Color.drip.textSecondary)
                                DurationPicker(value: $seconds, label: "sec", range: 0 ... 59)
                            }
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )

                            // Calculated pace
                            if let distance = distanceValue, distance > 0, durationMinutes > 0 {
                                let totalSecs = Int(((durationMinutes / distance) * 60).rounded())
                                let paceMin = totalSecs / 60
                                let paceSec = totalSecs % 60

                                HStack(spacing: 6) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 12))
                                    Text("Pace: \(paceMin):\(String(format: "%02d", paceSec)) /mi")
                                        .font(.dripCaption(13))
                                }
                                .foregroundStyle(Color.drip.energized)
                                .padding(.top, 4)
                            }
                        }

                        // Date Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Date")

                            DatePicker(
                                "Workout Date",
                                selection: $workoutDate,
                                in: ...Date(),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.graphical)
                            .tint(Color.drip.coral)
                            .colorScheme(.dark)
                            .padding(16)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }

                        // Mood Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("How did you feel?")

                            HStack(spacing: 12) {
                                ForEach(moods, id: \.0) { mood in
                                    MoodButton(
                                        name: mood.0,
                                        icon: mood.1,
                                        color: mood.2,
                                        isSelected: selectedMood == mood.0
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedMood = selectedMood == mood.0 ? nil : mood.0
                                        }
                                    }
                                }
                            }
                        }

                        // Notes Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Notes (optional)")

                            ZStack(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("How did your run go?")
                                        .font(.dripBody(15))
                                        .foregroundStyle(Color.drip.textTertiary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                }

                                TextEditor(text: $notes)
                                    .font(.dripBody(15))
                                    .foregroundStyle(Color.drip.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .frame(minHeight: 100)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }

                        // Save Button
                        DripButton(
                            "Save Workout",
                            icon: "checkmark.circle.fill",
                            isLoading: isUploading
                        ) {
                            saveWorkout()
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
                .scrollDismissesKeyboard(.interactively)

                if showSuccess {
                    ManualWorkoutSuccessOverlay()
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func saveWorkout() {
        guard let distance = distanceValue, distance > 0 else { return }

        isUploading = true

        Task {
            do {
                var insertData = TrainingLogInsert()
                insertData.workoutDate = workoutDate
                insertData.workoutDistanceMiles = distance
                if durationMinutes > 0 {
                    insertData.workoutDurationMinutes = durationMinutes
                }
                if !notes.isEmpty {
                    insertData.notes = notes
                }

                try await supabase
                    .from("training_logs")
                    .insert(insertData)
                    .execute()

                // If we have a mood, update the record
                // Note: mood field may need to be added to TrainingLogInsert if not present

                await MainActor.run {
                    isUploading = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        showSuccess = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    // Could show error alert here
                }
            }
        }
    }
}

// MARK: - DurationPicker

struct DurationPicker: View {
    @Binding var value: Int
    let label: String
    let range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 4) {
            Picker(label, selection: $value) {
                ForEach(range, id: \.self) { num in
                    Text(String(format: "%02d", num))
                        .foregroundStyle(Color.drip.textPrimary)
                        .tag(num)
                }
            }
            .pickerStyle(.wheel)
            .colorScheme(.dark)
            .frame(width: 60, height: 100)
            .clipped()

            Text(label)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}

// MARK: - MoodButton

struct MoodButton: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color.opacity(0.2) : Color.drip.cardBackground)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? color : Color.drip.textSecondary)
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? color : Color.drip.divider, lineWidth: isSelected ? 2 : 1)
                )

                Text(name.capitalized)
                    .font(.dripCaption(11))
                    .foregroundStyle(isSelected ? color : Color.drip.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ManualWorkoutSuccessOverlay

struct ManualWorkoutSuccessOverlay: View {
    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        ZStack {
            Color.drip.background.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.drip.energized)
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.drip.energized.opacity(0.5), radius: 20, x: 0, y: 10)

                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.black)
                        .scaleEffect(checkmarkScale)
                }

                VStack(spacing: 8) {
                    Text("Workout Saved!")
                        .font(.dripDisplay(28))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Your workout has been logged")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                checkmarkScale = 1
            }
        }
    }
}

#Preview {
    ManualWorkoutView()
}
