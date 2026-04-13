//
//  FitnessAssessmentComponents.swift
//  RunningLog
//
//  Reusable form components for the fitness assessment questionnaire.
//

import SwiftUI

// MARK: - StepHeader

struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)

            Text(subtitle)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }
}

// MARK: - QuestionSection

struct QuestionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            content
        }
    }
}

// MARK: - SelectableRow

struct SelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.drip.coral)
                } else {
                    Circle()
                        .stroke(Color.drip.divider, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(14)
            .background(isSelected ? Color.drip.coral.opacity(0.1) : Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.drip.coral : Color.clear, lineWidth: 1)
            )
        }
    }
}

// MARK: - SelectableChip

struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dripLabel(14))
                .foregroundStyle(isSelected ? .white : Color.drip.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - MultiSelectChip

struct MultiSelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.dripLabel(13))
            }
            .foregroundStyle(isSelected ? .white : Color.drip.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.drip.coral : Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - MileageSlider

struct MileageSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(Int(value))")
                    .font(.dripStat(32))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(label)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textSecondary)

                Spacer()
            }

            Slider(value: $value, in: range, step: 5)
                .tint(Color.drip.coral)

            HStack {
                Text("\(Int(range.lowerBound))")
                    .font(.dripCaption(10))
                Spacer()
                Text("\(Int(range.upperBound))")
                    .font(.dripCaption(10))
            }
            .foregroundStyle(Color.drip.textTertiary)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - TimeInputRow

struct TimeInputRow: View {
    let label: String
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    var showHours: Bool = true

    var body: some View {
        HStack {
            Text(label)
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textPrimary)

            Spacer()

            HStack(spacing: 4) {
                if showHours {
                    TimeField(value: $hours, range: 0 ... 6)
                    Text(":")
                        .foregroundStyle(Color.drip.textSecondary)
                }
                TimeField(value: $minutes, range: 0 ... 59)
                Text(":")
                    .foregroundStyle(Color.drip.textSecondary)
                TimeField(value: $seconds, range: 0 ... 59)
            }
            .font(.dripStat(18))
        }
        .padding(12)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - TimeField

struct TimeField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        TextField("", value: $value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.drip.textPrimary)
            .frame(width: 36)
            .onChange(of: value) { _, newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
            }
    }
}

// MARK: - InfoCard

struct InfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.energized)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dripLabel(13))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(message)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(14)
        .background(Color.drip.energized.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
