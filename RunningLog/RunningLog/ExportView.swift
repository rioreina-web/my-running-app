import SwiftUI

// MARK: - ExportView

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportService = ExportService()

    @State private var options = ExportOptions()
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header illustration
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.drip.coral.opacity(0.15))
                                    .frame(width: 100, height: 100)

                                Image(systemName: "tablecells")
                                    .font(.system(size: 40, weight: .medium))
                                    .foregroundStyle(Color.drip.coral)
                            }

                            VStack(spacing: 4) {
                                Text("Export Training Data")
                                    .font(.dripDisplay(24))
                                    .foregroundStyle(Color.drip.textPrimary)

                                Text("Export your training logs as a CSV file")
                                    .font(.dripBody(14))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)

                        // Date Range Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Date Range")

                            VStack(spacing: 8) {
                                ForEach(ExportOptions.DateRange.allCases, id: \.self) { range in
                                    DateRangeOption(
                                        title: range.rawValue,
                                        isSelected: options.dateRange == range
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            options.dateRange = range
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Include Options Section
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Include in Export")

                            VStack(spacing: 0) {
                                ExportToggleRow(
                                    title: "Workout Stats",
                                    subtitle: "Distance, duration, pace",
                                    icon: "figure.run",
                                    isOn: $options.includeWorkouts
                                )

                                Divider()
                                    .background(Color.drip.divider)

                                ExportToggleRow(
                                    title: "AI Transcriptions",
                                    subtitle: "Voice memo summaries",
                                    icon: "waveform",
                                    isOn: $options.includeTranscriptions
                                )
                            }
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                        }
                        .padding(.horizontal, 24)

                        // Export Button
                        VStack(spacing: 12) {
                            DripButton(
                                "Export CSV",
                                icon: "tablecells",
                                isLoading: exportService.isExporting
                            ) {
                                exportData()
                            }

                            Text("Your CSV will be ready to share or import")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        Spacer()
                            .frame(height: 40)
                    }
                }
            }
            .navigationTitle("Export")
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
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportService.exportError ?? "An error occurred while exporting.")
            }
        }
    }

    private func exportData() {
        Task {
            do {
                let url = try await exportService.exportTrainingLogs(options: options)
                await MainActor.run {
                    exportedFileURL = url
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    exportService.exportError = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - DateRangeOption

struct DateRangeOption: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.drip.coral : Color.drip.divider, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? Color.drip.coral.opacity(0.1) : Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.drip.coral.opacity(0.5) : Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ExportToggleRow

struct ExportToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn ? Color.drip.coral : Color.drip.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)

                Text(subtitle)
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .tint(Color.drip.coral)
                .labelsHidden()
        }
        .padding(16)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView()
}
