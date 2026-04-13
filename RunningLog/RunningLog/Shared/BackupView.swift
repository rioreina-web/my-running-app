//
//  BackupView.swift
//  RunningLog
//
//  UI for exporting all user data as a JSON backup.
//

import SwiftUI

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var backupService = BackupService()
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    private let dataItems: [(icon: String, label: String)] = [
        ("figure.run", "Training logs & voice memos"),
        ("calendar", "Training plans & scheduled workouts"),
        ("target", "Goals"),
        ("cross.case", "Injuries"),
        ("waveform.path.ecg", "Fitness snapshots"),
        ("figure.walk.motion", "Biomechanics analyses"),
        ("checkmark.seal", "Form checks"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "externaldrive.badge.checkmark")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.drip.coral)
                                .padding(16)
                                .background(Color.drip.coral.opacity(0.1))
                                .clipShape(Circle())

                            Text("Backup All Data")
                                .font(.dripLabel(18))
                                .foregroundStyle(Color.drip.textPrimary)

                            Text("Export everything as a single JSON file")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(.top, 8)

                        // What's included
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INCLUDED")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textTertiary)
                                .tracking(1.2)

                            VStack(spacing: 0) {
                                ForEach(Array(dataItems.enumerated()), id: \.offset) { index, item in
                                    HStack(spacing: 12) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.drip.coral)
                                            .frame(width: 24)
                                        Text(item.label)
                                            .font(.dripBody(14))
                                            .foregroundStyle(Color.drip.textPrimary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)

                                    if index < dataItems.count - 1 {
                                        Divider().background(Color.drip.divider)
                                    }
                                }
                            }
                            .background(Color.drip.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        // Progress
                        if backupService.isExporting {
                            VStack(spacing: 8) {
                                ProgressView(
                                    value: Double(backupService.tablesCompleted),
                                    total: Double(BackupService.totalTables)
                                )
                                .tint(Color.drip.coral)

                                Text(backupService.progress)
                                    .font(.dripCaption(12))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                            .padding(.horizontal, 4)
                        }

                        // Export button
                        DripButton(
                            "Export All Data",
                            icon: "square.and.arrow.down",
                            isLoading: backupService.isExporting
                        ) {
                            startBackup()
                        }

                        // Error
                        if let error = backupService.exportError {
                            Text(error)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.injured)
                                .multilineTextAlignment(.center)
                        }

                        // Footer note
                        Text("Audio and video files are not included — only metadata and analysis results.")
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
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func startBackup() {
        Task {
            do {
                let url = try await backupService.exportAllData()
                exportedFileURL = url
                showShareSheet = true
            } catch {
                // Error already set on backupService
            }
        }
    }
}
