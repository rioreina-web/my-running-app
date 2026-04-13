//
//  InjuryDetailSheet.swift
//  RunningLog
//
//  Detail sheet for viewing and editing a single injury record.
//

import SwiftUI

// MARK: - InjuryDetailSheet

struct InjuryDetailSheet: View {
    let injury: Injury
    @Bindable var injuryService: InjuryService
    @Environment(\.dismiss) private var dismiss

    @State private var editedSeverity: Double
    @State private var editedDescription: String
    @State private var editedStatus: InjuryStatus
    @State private var showDeleteConfirmation = false
    @State private var hasChanges = false

    init(injury: Injury, injuryService: InjuryService) {
        self.injury = injury
        self.injuryService = injuryService
        _editedSeverity = State(initialValue: Double(injury.severity))
        _editedDescription = State(initialValue: injury.description ?? "")
        _editedStatus = State(initialValue: injury.status)
    }

    /// Live injury from the service array — reflects updates (e.g. AI analysis) in real time.
    private var currentInjury: Injury {
        injuryService.injuries.first { $0.id == injury.id } ?? injury
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Text(injury.displayName)
                                .font(.dripDisplay(28))
                                .foregroundStyle(Color.drip.textPrimary)

                            HStack(spacing: 12) {
                                Label(injury.source.displayName, systemImage: injury.source.icon)
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)

                                Text("\(injury.daysSinceReported) days")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                        .padding(.top, 8)

                        // Status picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STATUS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                ForEach(InjuryStatus.allCases, id: \.self) { status in
                                    Button {
                                        editedStatus = status
                                        hasChanges = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: status.icon)
                                                .font(.system(size: 11))
                                            Text(status.displayName)
                                                .font(.dripLabel(12))
                                        }
                                        .foregroundStyle(editedStatus == status ? .white : status.color)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(editedStatus == status ? status.color : status.color.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Severity slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SEVERITY")
                                    .font(.dripCaption(11))
                                    .foregroundStyle(Color.drip.textTertiary)
                                    .tracking(1.2)

                                Spacer()

                                Text("\(Int(editedSeverity))/10 — \(severityLabelForValue(Int(editedSeverity)))")
                                    .font(.dripStat(14))
                                    .foregroundStyle(severityColorForValue(Int(editedSeverity)))
                            }

                            Slider(value: $editedSeverity, in: 1 ... 10, step: 1) {
                                Text("Severity")
                            }
                            .tint(severityColorForValue(Int(editedSeverity)))
                            .onChange(of: editedSeverity) { hasChanges = true }

                            // Severity reference
                            HStack {
                                Text("Mild")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.positive)
                                Spacer()
                                Text("Moderate")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.tired)
                                Spacer()
                                Text("Severe")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.injured)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            TextField("Describe the injury...", text: $editedDescription, axis: .vertical)
                                .font(.dripBody(14))
                                .foregroundStyle(Color.drip.textPrimary)
                                .lineLimit(3 ... 6)
                                .padding(12)
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onChange(of: editedDescription) { hasChanges = true }
                        }
                        .padding(.horizontal, 20)

                        // Save button
                        if hasChanges {
                            Button {
                                Task { await saveChanges() }
                            } label: {
                                Text("Save Changes")
                                    .font(.dripLabel(14))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.drip.coral)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 20)
                        }

                        // AI Analysis section
                        InjuryAnalysisSection(injury: currentInjury, injuryService: injuryService)
                            .padding(.horizontal, 20)

                        // Timeline
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIMELINE")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            VStack(alignment: .leading, spacing: 6) {
                                TimelineRow(label: "First reported", date: injury.firstReportedAt)
                                if let resolved = injury.resolvedAt {
                                    TimelineRow(label: "Resolved", date: resolved)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)

                        // Delete
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                Text("Delete Injury")
                                    .font(.dripBody(13))
                            }
                            .foregroundStyle(Color.drip.injured.opacity(0.7))
                        }
                        .padding(.top, 8)

                        Spacer().frame(height: 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }
        }
        .alert("Delete Injury?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    _ = await injuryService.deleteInjury(id: injury.id)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently remove this injury record.")
        }
    }

    private func saveChanges() async {
        let newStatus: InjuryStatus? = editedStatus != injury.status ? editedStatus : nil
        let newSeverity: Int? = Int(editedSeverity) != injury.severity ? Int(editedSeverity) : nil
        let newDescription: String? = editedDescription != (injury.description ?? "") ? editedDescription : nil

        _ = await injuryService.updateInjury(
            id: injury.id,
            severity: newSeverity,
            status: newStatus,
            description: newDescription
        )
        hasChanges = false
    }

    private func severityLabelForValue(_ value: Int) -> String {
        switch value {
        case 1 ... 3: return "Mild"
        case 4 ... 6: return "Moderate"
        case 7 ... 8: return "Severe"
        case 9 ... 10: return "Critical"
        default: return ""
        }
    }

    private func severityColorForValue(_ value: Int) -> Color {
        switch value {
        case 1 ... 3: return Color.drip.positive
        case 4 ... 5: return Color.drip.tired
        case 6 ... 7: return .orange
        case 8 ... 10: return Color.drip.injured
        default: return Color.drip.textSecondary
        }
    }
}

// MARK: - TimelineRow

struct TimelineRow: View {
    let label: String
    let date: Date

    var body: some View {
        HStack {
            Text(label)
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
            Spacer()
            Text(date, style: .date)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textTertiary)
        }
    }
}
