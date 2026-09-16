//
//  AdjustFitnessSheet.swift
//  RunningLog
//
//  "Adjust fitness" — when the auto projection is off, the athlete states a
//  recent effort (distance + time). It's saved as the manual pace anchor via
//  the `set-fitness-anchor` edge function, which overrides every auto-derived
//  source and re-derives the whole zone ladder. A live, local projection
//  preview (PaceCalculator) shows what the effort implies BEFORE saving — so
//  the athlete confirms the corrected fitness, never a silent write.
//

import SwiftUI

struct AdjustFitnessSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Distances the athlete can anchor on. `anchorKey` = the edge function /
    /// pace-engine RaceKey; `calcKey` = PaceCalculator's ratio-table key.
    enum EffortDistance: String, CaseIterable, Identifiable {
        case fiveK, tenK, half, marathon, mile
        var id: String { rawValue }
        var label: String {
            switch self {
            case .fiveK: return "5K"
            case .tenK: return "10K"
            case .half: return "Half"
            case .marathon: return "Marathon"
            case .mile: return "Mile"
            }
        }
        var anchorKey: String { rawValue } // matches RaceKey (fiveK/tenK/half/marathon/mile)
        var calcKey: String {
            switch self {
            case .fiveK: return "5K"
            case .tenK: return "10K"
            case .half: return "half"
            case .marathon: return "marathon"
            case .mile: return "mile"
            }
        }
    }

    @State private var distance: EffortDistance = .tenK
    @State private var timeText: String = ""
    @State private var effortDate: Date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// `effort_date` wire format expected by `set-fitness-anchor` ("YYYY-MM-DD").
    /// POSIX locale + local timezone so the athlete's chosen calendar day is
    /// what lands in the `manual_anchor_date` DATE column.
    private static let anchorDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Parsed effort time in seconds, or nil when the input isn't valid yet.
    private var parsedSeconds: Int? {
        let parts = timeText.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        let nums = parts.compactMap { Int($0) }
        let secs: Int
        switch nums.count {
        case 3: secs = nums[0] * 3600 + nums[1] * 60 + nums[2]
        case 2: secs = nums[0] * 60 + nums[1]
        default: return nil // bare number is ambiguous — require at least M:SS
        }
        return (secs >= 30 && secs <= 36000) ? secs : nil
    }

    /// Live projection: the derived MP / LT-ish / 5K the effort implies.
    private var projection: (marathon: Double, tenK: Double, fiveK: Double)? {
        guard let secs = parsedSeconds else { return nil }
        let paces = PaceCalculator.calculateEquivalentPaces(fromDistance: distance.calcKey, totalSeconds: secs)
        guard let mp = paces["marathon"], let tk = paces["10K"], let fk = paces["5K"] else { return nil }
        return (mp, tk, fk)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Tell us a recent hard effort — a race or a solid time trial. We'll re-anchor your paces on it. This overrides the auto estimate until you change it.")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                            .lineSpacing(3)

                        // Distance
                        VStack(alignment: .leading, spacing: 8) {
                            DripEyebrow(text: "DISTANCE")
                            Picker("Distance", selection: $distance) {
                                ForEach(EffortDistance.allCases) { d in
                                    Text(d.label).tag(d)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Time
                        VStack(alignment: .leading, spacing: 8) {
                            DripEyebrow(text: "TIME")
                            TextField(distance == .marathon || distance == .half ? "H:MM:SS" : "MM:SS", text: $timeText)
                                .font(.dripStat(28))
                                .foregroundStyle(Color.drip.textPrimary)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(.plain)
                            DripHairline()
                        }

                        // Date — when the effort happened. Anchors fade with
                        // age, so the pace engine needs to know how recent it is.
                        VStack(alignment: .leading, spacing: 8) {
                            DripEyebrow(text: "DATE")
                            DatePicker(
                                "Effort date",
                                selection: $effortDate,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.drip.coral)
                        }

                        // Live projection preview
                        if let p = projection {
                            VStack(alignment: .leading, spacing: 8) {
                                DripEyebrow(text: "THIS PROJECTS", coral: true)
                                HStack(spacing: 20) {
                                    projRow("MP", p.marathon)
                                    projRow("10K", p.tenK)
                                    projRow("5K", p.fiveK)
                                }
                            }
                            .transition(.opacity)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.dripBody(12).italic())
                                .foregroundStyle(Color.drip.coral)
                        }

                        // Reset to auto
                        Button {
                            Task { await reset() }
                        } label: {
                            Text("Reset to auto estimate")
                                .font(.dripCaption(11))
                                .tracking(1.0)
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Adjust fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(parsedSeconds == nil || isSaving)
                }
            }
        }
    }

    private func projRow(_ label: String, _ paceSec: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.dripCaption(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
            Text(formatPace(paceSec)).font(.dripStat(17)).foregroundStyle(Color.drip.textPrimary)
        }
    }

    private func formatPace(_ sec: Double) -> String {
        let total = Int(sec.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func save() async {
        guard let secs = parsedSeconds else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await callEdgeFunction(
                name: "set-fitness-anchor",
                body: ["distance": distance.anchorKey, "time_seconds": secs]
            )
            try? await PaceZonesService.shared.refresh()
            dismiss()
        } catch {
            errorMessage = "Couldn't save — check your connection and try again."
        }
    }

    private func reset() async {
        isSaving = true
        defer { isSaving = false }
        _ = try? await callEdgeFunction(name: "set-fitness-anchor", body: ["clear": true])
        try? await PaceZonesService.shared.refresh()
        dismiss()
    }
}
