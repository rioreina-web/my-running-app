//
//  AddInjurySheet.swift
//  RunningLog
//
//  Sheet for manually adding a new injury record.
//

import SwiftUI

// MARK: - AddInjurySheet

struct AddInjurySheet: View {
    @Bindable var injuryService: InjuryService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBodyArea: BodyArea?
    @State private var selectedSide = "unknown"
    @State private var severity: Double = 5
    @State private var description = ""
    @State private var isSaving = false
    @State private var showError = false

    let sides = ["left", "right", "both", "unknown"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Body area picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BODY AREA")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                            ], spacing: 8) {
                                ForEach(BodyArea.allCases, id: \.self) { area in
                                    Button {
                                        selectedBodyArea = area
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: area.icon)
                                                .font(.system(size: 16))
                                            Text(area.displayName)
                                                .font(.dripCaption(11))
                                        }
                                        .foregroundStyle(selectedBodyArea == area ? .white : Color.drip.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedBodyArea == area ? Color.drip.coral : Color.drip.cardBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Side picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SIDE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                ForEach(sides, id: \.self) { side in
                                    Button {
                                        selectedSide = side
                                    } label: {
                                        Text(side == "unknown" ? "N/A" : side.capitalized)
                                            .font(.dripLabel(13))
                                            .foregroundStyle(selectedSide == side ? .white : Color.drip.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selectedSide == side ? Color.drip.coral : Color.drip.cardBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Severity
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SEVERITY")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .tracking(1.2)

                                Spacer()

                                Text("\(Int(severity))/10")
                                    .font(.dripStat(16))
                                    .foregroundStyle(severityColor)
                            }

                            Slider(value: $severity, in: 1 ... 10, step: 1)
                                .tint(severityColor)
                        }
                        .padding(.horizontal, 20)

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESCRIPTION (optional)")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            TextField("What happened? How does it feel?", text: $description, axis: .vertical)
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineLimit(3 ... 5)
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        // Medical disclaimer
                        MedicalDisclaimerBanner(text: MedicalDisclaimer.short, isCompact: true)
                            .padding(.horizontal, 20)

                        // Save button
                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                }
                                Text("Add Injury")
                                    .font(.dripLabel(15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedBodyArea != nil ? Color.drip.coral : Color.drip.coral.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(selectedBodyArea == nil || isSaving)
                        .padding(.horizontal, 20)

                        Spacer().frame(height: 40)
                    }
                    .padding(.top, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("ADD INJURY")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                        .tracking(2)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(injuryService.errorMessage ?? "Could not save injury.")
            }
        }
    }

    private var severityColor: Color {
        switch Int(severity) {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }

    private func save() async {
        guard let area = selectedBodyArea else { return }
        isSaving = true

        let success = await injuryService.createInjury(
            bodyArea: area.rawValue,
            side: selectedSide,
            severity: Int(severity),
            description: description.isEmpty ? nil : description
        )

        isSaving = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }
}
