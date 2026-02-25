//
//  ImportWeekSheet.swift
//  RunningLog
//
//  Sheet for importing a training week from pasted text via AI extraction.
//

import SwiftUI

// MARK: - ImportWeekSheet

struct ImportWeekSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TrainingPlanViewModel
    let weekNumber: Int

    @State private var inputText = ""
    @State private var showPreview = false
    @State private var applied = false
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                if applied {
                    // Success state
                    successView
                } else if showPreview, let days = viewModel.importedWorkouts {
                    // Preview state
                    previewView(days: days)
                } else {
                    // Input state
                    inputView
                }
            }
            .navigationTitle(showPreview ? "Review Workouts" : "Import Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(applied ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }

                if showPreview && !applied {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") {
                            withAnimation(.spring(response: 0.3)) {
                                showPreview = false
                            }
                        }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.drip.coral)

                Text("Paste your training week")
                    .font(.dripLabel(18))
                    .foregroundStyle(Color.drip.textPrimary)

                Text("Type or paste your weekly training schedule and AI will extract structured workouts")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 16)

            // Text Editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isTextEditorFocused)
                    .frame(minHeight: 200)
                    .padding(12)

                if inputText.isEmpty {
                    Text("Mon: 5mi easy\nTue: 2mi WU, 8x800m at 5K pace w/ 400m jog, 2mi CD\nWed: off\nThu: 6mi easy + strides\nFri: rest\nSat: 18mi long run\nSun: 4mi recovery")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isTextEditorFocused ? Color.drip.coral.opacity(0.5) : Color.drip.divider, lineWidth: 1)
            )
            .padding(.horizontal, 20)

            // Error message
            if let error = viewModel.importError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                    Text(error)
                        .font(.dripCaption(12))
                }
                .foregroundStyle(Color.drip.injured)
                .padding(.horizontal, 20)
            }

            Spacer()

            // Extract button
            Button {
                isTextEditorFocused = false
                Task {
                    await viewModel.parseWeekFromText(inputText)
                    if viewModel.importedWorkouts != nil {
                        withAnimation(.spring(response: 0.3)) {
                            showPreview = true
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isParsingImport {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                    }
                    Text(viewModel.isParsingImport ? "Extracting..." : "Extract Workouts")
                        .font(.dripLabel(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isParsingImport
                        ? Color.drip.textTertiary
                        : Color.drip.coral
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isParsingImport)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Preview View

    private func previewView(days: [ImportedDayWorkout]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    // Week header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WEEK \(weekNumber)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)

                            let workoutCount = days.filter { $0.workoutType != "rest" }.count
                            let totalMiles = days.compactMap(\.totalDistanceMiles).reduce(0, +)
                            Text("\(workoutCount) workouts · \(String(format: "%.1f", totalMiles)) mi")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Day cards
                    ForEach(days) { day in
                        ImportDayPreviewRow(day: day)
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 100)
                }
            }

            // Apply button
            VStack {
                Button {
                    Task {
                        await viewModel.applyImportedWorkouts()
                        withAnimation(.spring(response: 0.3)) {
                            applied = true
                        }
                        // Auto-dismiss after short delay
                        try? await Task.sleep(for: .seconds(1.5))
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                        }
                        Text(viewModel.isSaving ? "Applying..." : "Apply to Week \(weekNumber)")
                            .font(.dripLabel(16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.drip.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(viewModel.isSaving)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(
                Color.drip.background
                    .shadow(color: .black.opacity(0.2), radius: 8, y: -4)
            )
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.drip.positive.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.drip.positive)
            }

            Text("Week Updated!")
                .font(.dripLabel(20))
                .foregroundStyle(Color.drip.textPrimary)

            Text("Your training week has been imported successfully")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
    }
}

// MARK: - ImportDayPreviewRow

struct ImportDayPreviewRow: View {
    let day: ImportedDayWorkout

    private var workoutType: ScheduledWorkoutType {
        ScheduledWorkoutType.fromImportString(day.workoutType)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Day indicator
            VStack(spacing: 2) {
                Text(String(day.dayName.prefix(3)).uppercased())
                    .font(.dripCaption(9))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 32)

            // Workout type icon
            ZStack {
                Circle()
                    .fill(workoutType.color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: workoutType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(workoutType.color)
            }

            // Workout info
            VStack(alignment: .leading, spacing: 3) {
                Text(day.name)
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.textPrimary)

                HStack(spacing: 8) {
                    if let miles = day.totalDistanceMiles {
                        Text(String(format: "%.1f mi", miles))
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }

                    if let mins = day.estimatedDurationMinutes {
                        Text(mins >= 60
                            ? "\(Int(mins) / 60)h \(Int(mins) % 60)m"
                            : "\(Int(mins)) min"
                        )
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                    }

                    if !day.steps.isEmpty {
                        Text("\(day.steps.filter { $0.stepType == "active" }.count) steps")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            }

            Spacer()

            // Workout type badge
            Text(workoutType.shortName)
                .font(.dripCaption(10))
                .foregroundStyle(workoutType.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(workoutType.color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    ImportWeekSheet(
        viewModel: TrainingPlanViewModel(),
        weekNumber: 5
    )
}
