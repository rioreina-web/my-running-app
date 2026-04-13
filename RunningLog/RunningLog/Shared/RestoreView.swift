//
//  RestoreView.swift
//  RunningLog
//
//  UI for importing a JSON backup file to restore user data.
//

import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var restoreService = RestoreService()
    @State private var showFilePicker = false
    @State private var restoreSummary: RestoreSummary?
    @State private var showConfirmation = false
    @State private var selectedFileURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.drip.coral)
                                .padding(16)
                                .background(Color.drip.coral.opacity(0.1))
                                .clipShape(Circle())

                            Text("Restore Data")
                                .font(.dripLabel(18))
                                .foregroundStyle(Color.drip.textPrimary)

                            Text("Import a previously exported JSON backup")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(.top, 8)

                        // Warning
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.drip.energized)
                            Text("Existing records with the same ID will be overwritten. New records will be added. This cannot be undone.")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(14)
                        .background(Color.drip.energized.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Progress
                        if restoreService.isImporting {
                            VStack(spacing: 8) {
                                ProgressView(
                                    value: Double(restoreService.tablesCompleted),
                                    total: Double(RestoreService.totalTables)
                                )
                                .tint(Color.drip.coral)

                                Text(restoreService.progress)
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                            .padding(.horizontal, 4)
                        }

                        // Success summary
                        if let summary = restoreSummary {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.drip.positive)
                                    Text("Restored \(summary.totalRecords) records")
                                        .font(.dripLabel(15))
                                        .foregroundStyle(Color.drip.textPrimary)
                                }

                                VStack(spacing: 0) {
                                    ForEach(Array(summary.breakdown.enumerated()), id: \.offset) { index, item in
                                        HStack {
                                            Text(item.label)
                                                .font(.dripBody(14))
                                                .foregroundStyle(Color.drip.textPrimary)
                                            Spacer()
                                            Text("\(item.count)")
                                                .font(.dripStat(14))
                                                .foregroundStyle(Color.drip.textSecondary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)

                                        if index < summary.breakdown.count - 1 {
                                            Divider().background(Color.drip.divider)
                                        }
                                    }
                                }
                                .background(Color.drip.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }

                        // Import button
                        if restoreSummary == nil {
                            DripButton(
                                "Select Backup File",
                                icon: "folder",
                                isLoading: restoreService.isImporting
                            ) {
                                showFilePicker = true
                            }
                        }

                        // Error
                        if let error = restoreService.importError {
                            Text(error)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.injured)
                                .multilineTextAlignment(.center)
                        }

                        // Footer
                        Text("Only import files created by this app's Backup feature.")
                            .font(.dripCaption(11))
                            .foregroundStyle(Color.drip.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.coral)
                }
            }
            .toolbarBackground(Color.drip.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    selectedFileURL = url
                    showConfirmation = true
                case .failure(let error):
                    restoreService.importError = error.localizedDescription
                }
            }
            .alert("Restore Data?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { selectedFileURL = nil }
                Button("Restore", role: .destructive) { startRestore() }
            } message: {
                Text("This will import all data from the backup file. Existing records with the same ID will be overwritten.")
            }
        }
    }

    private func startRestore() {
        guard let url = selectedFileURL else { return }
        Task {
            do {
                let summary = try await restoreService.importBackup(from: url)
                restoreSummary = summary
            } catch {
                // Error already set on restoreService
            }
        }
    }
}
