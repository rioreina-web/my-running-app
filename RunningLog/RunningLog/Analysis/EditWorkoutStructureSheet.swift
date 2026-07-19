//
//  EditWorkoutStructureSheet.swift
//  RunningLog
//
//  Athlete-facing correction for a mis-parsed workout.
//
//  The auto-parser segments a run from the GPS stream by where you slowed down.
//  When it gets the rep structure wrong — a warmup + tempo merged into one long
//  block, or two interval sets collapsed into one — this sheet lets you fix the
//  breakdown by hand: relabel a block, split one block into several, merge two
//  together, reorder, or delete. The correction is saved back to
//  `parsed_structure` (flagged edited_by_user) so it shows everywhere and the
//  auto-parser never overwrites it.
//
//  Backend: supabase/functions/correct-workout-structure (save | restore).
//  Validation/normalization: supabase/functions/_shared/structureOverride.ts.
//
//  "AI advises, never acts": the auto-parse is a suggestion; your correction is
//  the verdict.
//

import SwiftUI
import Supabase
import os

// MARK: - Editable model

/// One editable segment of the workout. Mirrors a `parsed_structure` block but
/// holds raw meters/seconds so split/merge math stays exact.
struct EditableBlock: Identifiable, Equatable {
    let id = UUID()
    var role: Role
    var distanceMeters: Double
    var durationS: Double
    var hr: Int?

    enum Role: String, CaseIterable {
        case warmup, work_rep, recovery, cooldown
        var label: String {
            switch self {
            case .warmup:   return "Warm-up"
            case .work_rep: return "Work rep"
            case .recovery: return "Recovery"
            case .cooldown: return "Cool-down"
            }
        }
        var chip: String {
            switch self {
            case .warmup:   return "WARM"
            case .work_rep: return "WORK"
            case .recovery: return "REST"
            case .cooldown: return "COOL"
            }
        }
        var color: Color {
            switch self {
            case .work_rep: return Color.drip.coral
            case .recovery: return Color.drip.textTertiary
            default:        return Color.drip.textSecondary
            }
        }
    }

    var paceSecPerMile: Double? {
        let miles = distanceMeters / 1609.344
        return miles > 0 && durationS > 0 ? durationS / miles : nil
    }
}

// MARK: - Sheet

struct EditWorkoutStructureSheet: View {
    let workoutId: UUID
    /// Current reps as the chart already loaded them (avoids a refetch). Roles
    /// are inferred: rest laps → recovery, everything else → work rep. You then
    /// relabel the first/last as warm-up / cool-down if needed.
    let initialLaps: [WorkoutLapRow]
    let initialIntent: String?
    /// Called after a successful save or restore so the caller can refresh.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var blocks: [EditableBlock] = []
    @State private var intent: String = ""
    @State private var editMode: EditMode = .inactive
    @State private var saving = false
    @State private var restoring = false
    @State private var errorMsg: String?
    @State private var showRestoreConfirm = false

    // Custom-distance entry (number + unit) for a specific block.
    enum DistUnit: String, CaseIterable, Identifiable { case meters = "m", km = "km", mi = "mi"; var id: String { rawValue } }
    @State private var customForID: UUID?
    @State private var customAmount: String = ""
    @State private var customUnit: DistUnit = .meters

    // Gemini-led fix: describe the workout in plain language, AI reconciles it
    // with the GPS and fills the rep list for review.
    @State private var aiDescription: String = ""
    @State private var aiLoading = false

    private static let distanceOptions: [(String, Double)] = [
        ("200m", 200), ("300m", 300), ("400m", 400), ("600m", 600), ("800m", 800),
        ("1K", 1000), ("1200m", 1200), ("1 mi", 1609.344), ("2K", 2000),
        ("3K", 3000), ("2 mi", 3218.69), ("5K", 5000),
    ]

    var body: some View {
        NavigationStack {
            List {
                aiFixSection
                headerSection
                blocksSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.drip.background.ignoresSafeArea())
            .environment(\.editMode, $editMode)
            .navigationTitle("Fix structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.drip.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    if saving {
                        ProgressView().tint(Color.drip.coral)
                    } else {
                        Button("Save") { Task { await save() } }
                            .foregroundStyle(Color.drip.coral)
                            .disabled(workBlockCount == 0)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton().foregroundStyle(Color.drip.coral)
                }
            }
            .onAppear(perform: seed)
            .confirmationDialog(
                "Discard your edits and re-detect from the GPS?",
                isPresented: $showRestoreConfirm, titleVisibility: .visible
            ) {
                Button("Restore auto-detected", role: .destructive) { Task { await restore() } }
                Button("Keep editing", role: .cancel) {}
            }
            .sheet(isPresented: Binding(
                get: { customForID != nil },
                set: { if !$0 { customForID = nil } }
            )) {
                customDistanceSheet
            }
        }
    }

    // Custom distance entry: a number + a unit (m / km / mi). Sets the chosen
    // block's distance exactly, for reps that aren't a standard label.
    private var customDistanceSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Distance", text: $customAmount)
                        .keyboardType(.decimalPad)
                        .font(.dripBody(17))
                    Picker("Unit", selection: $customUnit) {
                        ForEach(DistUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Custom distance")
                }
            }
            .navigationTitle("Custom distance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { customForID = nil }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Set") { applyCustomDistance() }
                        .foregroundStyle(Color.drip.coral)
                        .disabled((Double(customAmount) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private func applyCustomDistance() {
        guard let id = customForID, let amt = Double(customAmount), amt > 0,
              let i = blocks.firstIndex(where: { $0.id == id }) else { customForID = nil; return }
        let meters: Double
        switch customUnit {
        case .meters: meters = amt
        case .km:     meters = amt * 1000
        case .mi:     meters = amt * 1609.344
        }
        blocks[i].distanceMeters = meters
        customForID = nil
    }

    // MARK: Sections

    private var aiFixSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("DESCRIBE IT")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
                Text("Tell the coach what the workout actually was — it'll rebuild the reps from your GPS for you to review.")
                    .font(.dripBody(12.5))
                    .foregroundStyle(Color.drip.textSecondary)
                TextField("e.g. 3k tempo, then 3 × (1k @ 10K, 600m @ 5K) with jog recoveries", text: $aiDescription, axis: .vertical)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1...4)
                Button {
                    Task { await reconcileWithAI() }
                } label: {
                    HStack(spacing: 6) {
                        if aiLoading {
                            ProgressView().tint(Color.drip.coral)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                        }
                        Text(aiLoading ? "Reconciling…" : "Reconcile with AI").font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.drip.coralWash)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(aiLoading || aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.drip.cardBackground)
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("HEADLINE")
                    .font(.dripStat(10)).tracking(1.1)
                    .foregroundStyle(Color.drip.coral)
                TextField("e.g. 3k tempo + 3 × (1k, 600m)", text: $intent, axis: .vertical)
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineLimit(1...3)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.drip.cardBackground)
        } footer: {
            Text("Each row is one segment. Swipe a row to split, merge, or delete. Tap Edit to reorder. Taller/faster reps come straight from your GPS.")
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private var blocksSection: some View {
        Section {
            ForEach($blocks) { $block in
                blockRow($block)
                    .listRowBackground(Color.drip.cardBackground)
            }
            .onMove { from, to in blocks.move(fromOffsets: from, toOffset: to) }
            .onDelete { idx in blocks.remove(atOffsets: idx) }

            Button {
                blocks.append(EditableBlock(role: .work_rep, distanceMeters: 1000, durationS: 200, hr: nil))
            } label: {
                Label("Add a rep", systemImage: "plus.circle")
                    .font(.dripLabel(14))
                    .foregroundStyle(Color.drip.coral)
            }
            .listRowBackground(Color.drip.cardBackground)
        } header: {
            Text("\(workBlockCount) work rep\(workBlockCount == 1 ? "" : "s")")
                .font(.dripStat(10)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private func blockRow(_ block: Binding<EditableBlock>) -> some View {
        let b = block.wrappedValue
        return HStack(spacing: 12) {
            // Role chip (tap to change)
            Menu {
                ForEach(EditableBlock.Role.allCases, id: \.self) { r in
                    Button(r.label) { block.wrappedValue.role = r }
                }
            } label: {
                Text(b.role.chip)
                    .font(.dripStat(10)).tracking(1.0)
                    .foregroundStyle(b.role.color)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(b.role.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Distance (tap to relabel — keeps measured time, recomputes pace)
            Menu {
                ForEach(Self.distanceOptions, id: \.0) { opt in
                    Button(opt.0) { block.wrappedValue.distanceMeters = opt.1 }
                }
                Divider()
                Button("Custom…") {
                    let id = block.wrappedValue.id
                    customAmount = String(format: "%.0f", block.wrappedValue.distanceMeters)
                    customUnit = .meters
                    customForID = id
                }
            } label: {
                Text(distanceLabel(b.distanceMeters))
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let p = b.paceSecPerMile {
                    Text(paceString(p) + "/mi")
                        .font(.dripStat(12)).foregroundStyle(Color.drip.textPrimary)
                }
                Text(durationString(b.durationS))
                    .font(.dripStat(10)).foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { split(block.wrappedValue.id, into: 2) } label: {
                Label("Split", systemImage: "scissors")
            }.tint(Color.drip.coral)
            Button { split(block.wrappedValue.id, into: 3) } label: {
                Label("÷3", systemImage: "scissors")
            }.tint(Color.drip.coralLight)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(block.wrappedValue.id) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { mergeUp(block.wrappedValue.id) } label: {
                Label("Merge ↑", systemImage: "arrow.up.to.line")
            }.tint(Color.drip.textSecondary)
        }
    }

    private var actionsSection: some View {
        Section {
            Button { showRestoreConfirm = true } label: {
                HStack {
                    if restoring { ProgressView().tint(Color.drip.textSecondary) }
                    Text("Restore auto-detected")
                        .font(.dripLabel(14))
                }
                .foregroundStyle(Color.drip.textSecondary)
            }
            .disabled(restoring || saving)
            .listRowBackground(Color.drip.cardBackground)

            if let err = errorMsg {
                Text(err)
                    .font(.dripStat(11))
                    .foregroundStyle(Color.drip.struggling)
                    .listRowBackground(Color.drip.cardBackground)
            }
        }
    }

    // MARK: Mutations

    private func seed() {
        guard blocks.isEmpty else { return }
        intent = initialIntent ?? ""
        let ordered = initialLaps.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) }
        blocks = ordered.map { lap in
            EditableBlock(
                role: lap.is_rest == true ? .recovery : .work_rep,
                distanceMeters: lap.distance_meters ?? 0,
                durationS: Double(lap.moving_time_seconds ?? 0),
                hr: lap.avg_heart_rate
            )
        }
        if blocks.isEmpty {
            blocks = [EditableBlock(role: .work_rep, distanceMeters: 1000, durationS: 200, hr: nil)]
        }
    }

    private var workBlockCount: Int { blocks.filter { $0.role == .work_rep }.count }

    private func delete(_ id: UUID) {
        blocks.removeAll { $0.id == id }
    }

    /// Split one block into `n` equal parts (distance + time divided evenly, so
    /// pace is preserved). The common fix when the parser merged several reps.
    private func split(_ id: UUID, into n: Int) {
        guard n >= 2, let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let src = blocks[i]
        let parts = (0..<n).map { _ in
            EditableBlock(
                role: src.role,
                distanceMeters: src.distanceMeters / Double(n),
                durationS: src.durationS / Double(n),
                hr: src.hr
            )
        }
        blocks.replaceSubrange(i...i, with: parts)
    }

    /// Merge a block into the one above it (distance + time summed, time-weighted
    /// HR, the upper block's role kept). Undoes an over-split.
    private func mergeUp(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let prev = blocks[i - 1], cur = blocks[i]
        let dur = prev.durationS + cur.durationS
        let hr: Int? = {
            let a = prev.hr.map { Double($0) * max(prev.durationS, 1) }
            let b = cur.hr.map { Double($0) * max(cur.durationS, 1) }
            let w = (a ?? 0) + (b ?? 0)
            let t = (prev.hr != nil ? max(prev.durationS, 1) : 0) + (cur.hr != nil ? max(cur.durationS, 1) : 0)
            return t > 0 ? Int((w / t).rounded()) : nil
        }()
        blocks[i - 1] = EditableBlock(
            role: prev.role,
            distanceMeters: prev.distanceMeters + cur.distanceMeters,
            durationS: dur,
            hr: hr
        )
        blocks.remove(at: i)
    }

    // MARK: Persist

    /// Gemini reconciles the typed description with the current GPS segments and
    /// returns a proposed structure, which we load into the editor for review.
    private func reconcileWithAI() async {
        errorMsg = nil
        aiLoading = true
        defer { aiLoading = false }
        struct BoutDTO: Encodable {
            let distance_meters: Double
            let duration_s: Int
            let is_rest: Bool
            let avg_pace_per_mile: String?
        }
        struct Req: Encodable {
            let mode: String
            let training_log_id: String
            let description: String
            let bouts: [BoutDTO]
        }
        struct BlockDTO: Decodable {
            let role: String
            let distance_miles: Double?
            let duration_s: Double?
            let avg_pace_per_mile: String?
            let avg_hr: Int?
        }
        struct Proposal: Decodable { let blocks: [BlockDTO]?; let intent_pattern: String? }
        struct Resp: Decodable { let success: Bool?; let error: String?; let proposal: Proposal? }

        let bouts = blocks.map { b in
            BoutDTO(
                distance_meters: b.distanceMeters,
                duration_s: Int(b.durationS.rounded()),
                is_rest: b.role == .recovery,
                avg_pace_per_mile: b.paceSecPerMile.map { paceString($0) }
            )
        }
        let req = Req(
            mode: "describe",
            training_log_id: workoutId.uuidString,
            description: aiDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            bouts: bouts
        )
        do {
            let resp: Resp = try await supabase.functions.invoke(
                "correct-workout-structure", options: .init(body: req))
            guard resp.success == true,
                  let proposalBlocks = resp.proposal?.blocks, !proposalBlocks.isEmpty else {
                errorMsg = resp.error ?? "AI couldn't rebuild that. Try rephrasing."
                return
            }
            let mapped: [EditableBlock] = proposalBlocks.map { pb in
                EditableBlock(
                    role: EditableBlock.Role(rawValue: pb.role.lowercased()) ?? .work_rep,
                    distanceMeters: (pb.distance_miles ?? 0) * 1609.344,
                    durationS: pb.duration_s ?? 0,
                    hr: pb.avg_hr
                )
            }
            withAnimation {
                blocks = mapped
                if let ip = resp.proposal?.intent_pattern, !ip.isEmpty { intent = ip }
            }
        } catch {
            errorMsg = "Couldn't reach the coach. Try again."
            Log.coach.error("reconcileWithAI failed: \(error)")
        }
    }

    private func save() async {
        errorMsg = nil
        saving = true
        defer { saving = false }
        struct BlockDTO: Encodable {
            let role: String
            let distance_miles: Double
            let duration_s: Int
            let avg_pace_per_mile: String?
            let avg_hr: Int?
        }
        struct Payload: Encodable { let blocks: [BlockDTO]; let intent_pattern: String? }
        struct Req: Encodable { let mode: String; let training_log_id: String; let override: Payload }
        struct Resp: Decodable { let success: Bool?; let error: String? }

        let dto = blocks.map { b in
            BlockDTO(
                role: b.role.rawValue,
                distance_miles: (b.distanceMeters / 1609.344 * 100).rounded() / 100,
                duration_s: Int(b.durationS.rounded()),
                avg_pace_per_mile: b.paceSecPerMile.map { paceString($0) },
                avg_hr: b.hr
            )
        }
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = Req(
            mode: "save",
            training_log_id: workoutId.uuidString,
            override: Payload(blocks: dto, intent_pattern: trimmed.isEmpty ? nil : trimmed)
        )
        do {
            let resp: Resp = try await supabase.functions.invoke(
                "correct-workout-structure", options: .init(body: req))
            if resp.success == true {
                onSaved()
                dismiss()
            } else {
                errorMsg = resp.error ?? "Couldn't save. Try again."
            }
        } catch {
            errorMsg = "Couldn't reach the server. Try again."
            Log.coach.error("correct-workout-structure save failed: \(error)")
        }
    }

    private func restore() async {
        errorMsg = nil
        restoring = true
        defer { restoring = false }
        struct Req: Encodable { let mode: String; let training_log_id: String }
        struct Resp: Decodable { let success: Bool?; let error: String? }
        let req = Req(mode: "restore", training_log_id: workoutId.uuidString)
        do {
            let resp: Resp = try await supabase.functions.invoke(
                "correct-workout-structure", options: .init(body: req))
            if resp.success == true {
                onSaved()
                dismiss()
            } else {
                errorMsg = resp.error ?? "Couldn't restore. Try again."
            }
        } catch {
            errorMsg = "Couldn't reach the server. Try again."
            Log.coach.error("correct-workout-structure restore failed: \(error)")
        }
    }

    // MARK: Formatting

    private func distanceLabel(_ m: Double) -> String {
        if m <= 0 { return "—" }
        let miles = m / 1609.344
        if miles >= 1, abs(miles - miles.rounded()) / miles < 0.06 {
            return "\(Int(miles.rounded())) mi"
        }
        for opt in Self.distanceOptions where abs(m - opt.1) / opt.1 < 0.06 { return opt.0 }
        return "\(Int((m / 50).rounded() * 50))m"
    }
    private func paceString(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
    private func durationString(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
}

// MARK: - Preview

#Preview {
    // The 5500m·1K·600m·1800m mis-parse from the report.
    let laps: [WorkoutLapRow] = [
        WorkoutLapRow(lap_index: 0, distance_meters: 5500, moving_time_seconds: 1299,
                      avg_pace_sec_per_mile: 380, avg_heart_rate: 158, is_rest: false),
        WorkoutLapRow(lap_index: 1, distance_meters: 80, moving_time_seconds: 183,
                      avg_pace_sec_per_mile: nil, avg_heart_rate: 150, is_rest: true),
        WorkoutLapRow(lap_index: 2, distance_meters: 1000, moving_time_seconds: 188,
                      avg_pace_sec_per_mile: 303, avg_heart_rate: 168, is_rest: false),
        WorkoutLapRow(lap_index: 3, distance_meters: 90, moving_time_seconds: 113,
                      avg_pace_sec_per_mile: nil, avg_heart_rate: 150, is_rest: true),
        WorkoutLapRow(lap_index: 4, distance_meters: 600, moving_time_seconds: 111,
                      avg_pace_sec_per_mile: 297, avg_heart_rate: 170, is_rest: false),
        WorkoutLapRow(lap_index: 5, distance_meters: 110, moving_time_seconds: 192,
                      avg_pace_sec_per_mile: nil, avg_heart_rate: 148, is_rest: true),
        WorkoutLapRow(lap_index: 6, distance_meters: 1800, moving_time_seconds: 396,
                      avg_pace_sec_per_mile: 354, avg_heart_rate: 169, is_rest: false),
    ]
    return EditWorkoutStructureSheet(
        workoutId: UUID(), initialLaps: laps,
        initialIntent: "3k tempo + 3 × (1k, 600m)", onSaved: {})
}
