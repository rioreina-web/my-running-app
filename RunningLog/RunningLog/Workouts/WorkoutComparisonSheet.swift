//
//  WorkoutComparisonSheet.swift
//  RunningLog
//
//  "The Effort, compared" — the workout comparison tool
//  (spec: workoutcomparisonspec.md; design: the-effort-compare-mock.html).
//
//  Two strictly separated layers, both computed server-side by the
//  `compare-workouts` edge function:
//    • Layer 1 — a deterministic feature-diff (segmented via the canonical
//      workoutSegmentation module). Every number here is measured or
//      explicitly absent; nothing is modeled except heat-adjusted pace,
//      which is labeled as a model.
//    • Layer 2 — the coach's read (one sentence + at most one caveat),
//      generated only from those facts and validated server-side so it can
//      never cite a number the diff doesn't contain. When the verdict is
//      unavailable (rate limit, model failure), the diff still renders —
//      the numbers never depend on the AI.
//
//  Front doors (decision 2026-07-20, Rio): opens on the AUTO-suggested
//  fairest prior session with a "CHANGE ↗" affordance; the manual picker
//  never refuses a pair — the comparability score just says how loosely
//  to read the result.
//

import SwiftUI
import Supabase
import Charts
import os

// MARK: - Wire format (mirrors compare-workouts response, camelCase)

/// Top-level response from `compare-workouts`.
private struct CompareResponse: Decodable {
    let success: Bool
    let mode: String                  // "auto" | "manual"
    let annotated: Bool
    let comparison: ComparisonDTO?
    let verdict: VerdictDTO?
    let noCandidate: Bool?

    enum CodingKeys: String, CodingKey {
        case success, mode, annotated, comparison, verdict
        case noCandidate = "no_candidate"
    }
}

private struct VerdictDTO: Decodable {
    let verdict: String
    let caveat: String?
}

private struct ComparisonDTO: Decodable {
    let ok: Bool
    let reason: String?               // "unreadable_a" | "unreadable_b"
    let a: WorkProfileDTO
    let b: WorkProfileDTO
    let comparability: ComparabilityDTO?
    let diff: DiffDTO?
}

private struct SeriesPointDTO: Decodable {
    let mi: Double
    let paceSec: Double
    let hr: Double?
    let gradePct: Double?
}

private struct WorkProfileDTO: Decodable {
    let id: String
    let date: String                  // "YYYY-MM-DD"
    let readable: Bool
    let workoutKind: String?
    let structure: String?
    let dominantWorkZone: String?
    let repCount: Int
    let repDistanceLabel: String?
    let tempF: Double?
    let avgPaceSec: Double?
    let avgRunHr: Double?
    let conditionsAdjustedPaceSec: Double?
    let fastSegPaceSec: Double?
    let series: [SeriesPointDTO]
}

private struct ComparabilityDTO: Decodable {
    let score: Double
    let confidence: String            // "high" | "moderate" | "low"
    let zoneMatch: Bool
    let familyMatch: String
    let volumeBandOk: Bool
    let notes: [String]
}

private struct NumPairDTO: Decodable {
    let a: Double
    let b: Double
    let delta: Double
}

private struct VolumePairDTO: Decodable {
    let a: Double
    let b: Double
    let pctChange: Double?
}

private struct ZonePairDTO: Decodable {
    let a: String?
    let b: String?
    let same: Bool
}

/// A pair where either side may be absent (fade / decoupling).
private struct NullablePairDTO: Decodable {
    let a: Double?
    let b: Double?
}

private struct DiffDTO: Decodable {
    let mode: String                  // "quality" | "aerobic" | "mixed"
    let zone: ZonePairDTO
    // Whole-run rows (every readable pair)
    let totalDistanceMeters: VolumePairDTO?
    let totalDurationSec: NumPairDTO?
    let avgPaceSec: NumPairDTO?
    let conditionsAdjustedPaceSec: NumPairDTO?
    let avgRunHr: NumPairDTO?
    let elevationGainM: NumPairDTO?
    let fastSegPaceSec: NumPairDTO?
    let decouplingPct: NullablePairDTO
    // Quality-work rows (quality pairs only)
    let reps: NumPairDTO?
    let avgRepPaceRawSec: NumPairDTO?
    let avgRepPaceAdjSec: NumPairDTO?
    let avgRecoverySec: NumPairDTO?
    let recoveryHrDropBpm: NumPairDTO?
    let avgWorkHr: NumPairDTO?
    let qualityVolumeMeters: VolumePairDTO?
    let tempF: NumPairDTO?
    let unavailable: [String]
}

// MARK: - Manual-picker candidate (athlete's own rows via PostgREST/RLS)

private struct CandidateRow: Decodable, Identifiable {
    let trainingLogId: String
    let workoutDate: String
    let workoutStructure: String?
    let totalDistanceMiles: Double?
    let avgPaceSeconds: Double?

    var id: String { trainingLogId }

    /// "6.2 mi · 8:12/mi" summary for the picker, or nil when features are thin.
    var summary: String? {
        var parts: [String] = []
        if let mi = totalDistanceMiles, mi > 0 {
            parts.append(String(format: "%.1f mi", mi))
        }
        if let p = avgPaceSeconds, p > 0 {
            parts.append(paceString(p) + "/mi")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case trainingLogId = "training_log_id"
        case workoutDate = "workout_date"
        case workoutStructure = "workout_structure"
        case totalDistanceMiles = "total_distance_miles"
        case avgPaceSeconds = "avg_pace_seconds"
    }
}

// MARK: - Formatting helpers

private let comparisonMonthAbbr = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

/// "2026-06-15" (or an ISO timestamp) → "Jun 15". Raw string on parse failure.
private func shortDate(_ iso: String) -> String {
    let day = String(iso.prefix(10))
    let parts = day.split(separator: "-")
    guard parts.count == 3,
          let m = Int(parts[1]), (1...12).contains(m),
          let d = Int(parts[2]) else { return day }
    return "\(comparisonMonthAbbr[m - 1]) \(d)"
}

/// 329 sec/mile → "5:29".
private func paceString(_ sec: Double) -> String {
    let t = Int(sec.rounded())
    return "\(t / 60):" + String(format: "%02d", t % 60)
}

/// 2700s → "45:00"; 5400s → "1:30:00".
private func durationString(_ sec: Double) -> String {
    let t = Int(sec.rounded())
    let h = t / 3600, m = (t % 3600) / 60, s = t % 60
    if h > 0 { return "\(h):" + String(format: "%02d:%02d", m, s) }
    return "\(m):" + String(format: "%02d", s)
}

/// +2 → "+2", −15 → "−15" (typographic minus, per the design system).
private func signed(_ value: Double, decimals: Int = 0) -> String {
    let rounded = decimals == 0 ? String(Int(value.rounded()))
        : String(format: "%.\(decimals)f", value)
    if value > 0 { return "+" + rounded }
    return rounded.replacingOccurrences(of: "-", with: "\u{2212}")
}

/// Zone key → display label (mirrors keySessions ZONE_LABEL).
private func zoneLabel(_ zone: String?) -> String {
    switch zone?.lowercased() {
    case "mile": return "MILE"
    case "3k": return "3K"
    case "5k": return "5K"
    case "10k": return "10K"
    case "hmp": return "HMP"
    case "mp": return "MP"
    case .some(let z): return z.uppercased()
    case nil: return "?"
    }
}

private func repsLabel(_ p: WorkProfileDTO) -> String {
    guard p.repCount > 0 else { return "no reps" }
    if let label = p.repDistanceLabel { return "\(p.repCount)×\(label)" }
    return "\(p.repCount) reps"
}

// MARK: - Service

private enum WorkoutComparisonService {
    /// Run a comparison. `compareToId == nil` → auto mode (the server picks
    /// the fairest prior session).
    static func compare(workoutId: String, compareToId: String?) async throws -> CompareResponse {
        var body: [String: Any] = ["workout_id": workoutId]
        if let compareToId { body["compare_to_id"] = compareToId }
        let data = try await callEdgeFunction(name: "compare-workouts", body: body)
        return try JSONDecoder().decode(CompareResponse.self, from: data)
    }

    /// Prior sessions for the manual picker — the athlete's own
    /// `workout_features` rows (RLS-scoped), ALL workout types (2026-07-20: the
    /// tool compares easy/long runs too, not just quality efforts). The server
    /// auto-suggests the fairest match; this list is the "change it yourself"
    /// override, newest first, with a distance/pace summary so the athlete can
    /// pick a likewise session.
    static func candidates(excluding workoutId: String) async -> [CandidateRow] {
        do {
            let rows: [CandidateRow] = try await supabase
                .from("workout_features")
                .select("training_log_id, workout_date, workout_structure, total_distance_miles, avg_pace_seconds")
                .order("workout_date", ascending: false)
                .limit(80)
                .execute().value
            return rows.filter { $0.trainingLogId != workoutId }
        } catch {
            Log.coach.error("Comparison candidates load failed: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - WorkoutComparisonSheet

/// The comparison screen. Present as a sheet with the training_logs row id
/// of the session to compare (the laps-bearing row — for a Strava-linked
/// entry that's `workoutDetailId`, same as WorkoutRepDetailSheet).
struct WorkoutComparisonSheet: View {
    let workoutId: String

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded(CompareResponse)
        case noCandidate
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var showPicker = false
    @State private var candidates: [CandidateRow] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DripPlateStrip(
                            leadingBottom: "THE EFFORT · COMPARED",
                            trailingBottom: "TRENDS"
                        )
                        content
                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
            .task { await load(compareToId: nil) }
            .sheet(isPresented: $showPicker) {
                comparisonPicker
            }
        }
    }

    // ── Load ────────────────────────────────────────────────────────────

    private func load(compareToId: String?) async {
        phase = .loading
        do {
            let response = try await WorkoutComparisonService.compare(
                workoutId: workoutId, compareToId: compareToId
            )
            if response.noCandidate == true {
                phase = .noCandidate
            } else {
                phase = .loaded(response)
            }
        } catch {
            Log.coach.error("compare-workouts failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    // ── Content states ──────────────────────────────────────────────────

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack {
                Spacer()
                ProgressView().tint(Color.drip.coral)
                Spacer()
            }
            .padding(.top, 80)

        case .noCandidate:
            // Empty-state pattern: state the absence, then what fills it.
            VStack(alignment: .leading, spacing: 12) {
                DripEyebrow(text: "NO FAIR MATCH YET")
                Text("No similar past session to compare against. Once another run of this kind is on the log, the fairest one lands here — or pick any session yourself.")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(3)
                pickButton(label: "PICK A SESSION ↗")
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                DripEyebrow(text: "COMPARISON UNAVAILABLE")
                Text("Couldn't run the comparison. \(message)")
                    .font(.dripBody(13).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(3)
                DripButton("Try again", style: .secondary) {
                    Task { await load(compareToId: nil) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

        case .loaded(let response):
            if let comparison = response.comparison, comparison.ok {
                comparisonBody(response: response, comparison: comparison)
            } else {
                // Honest degradation — never compare garbage.
                VStack(alignment: .leading, spacing: 12) {
                    DripEyebrow(text: "COULDN'T READ THIS SESSION")
                    Text("Couldn't read this session's structure — no clean laps to segment. Sessions recorded with rep-level laps compare here.")
                        .font(.dripBody(13).italic())
                        .foregroundStyle(Color.drip.textTertiary)
                        .lineSpacing(3)
                    pickButton(label: "PICK A DIFFERENT SESSION ↗")
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
    }

    // ── The comparison itself ───────────────────────────────────────────

    @ViewBuilder
    private func comparisonBody(response: CompareResponse, comparison: ComparisonDTO) -> some View {
        let a = comparison.a
        let b = comparison.b

        // Compared-with strip (auto vs manual) + change affordance.
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                DripEyebrow(text: "COMPARED WITH")
                Text(response.mode == "auto" ? "Your last similar session" : "A session you picked")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
            }
            Spacer()
            pickButton(label: "CHANGE ↗")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { DripHairline().padding(.horizontal, 24) }

        // A / B header.
        HStack(alignment: .top, spacing: 16) {
            sessionColumn(eyebrow: "A · EARLIER", profile: a)
            Rectangle().fill(Color.drip.divider).frame(width: 1)
            sessionColumn(eyebrow: "B · THIS SESSION", profile: b)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)

        // Comparability pill.
        if let comp = comparison.comparability {
            comparabilityRow(comp)
                .padding(.horizontal, 24)
                .padding(.top, 12)
        }

        // The read — verdict above the numbers it came from.
        if let verdict = response.verdict {
            VStack(alignment: .leading, spacing: 8) {
                DripEyebrow(
                    text: comparison.comparability?.confidence == "low"
                        ? "THE READ · HEDGED" : "THE READ",
                    coral: true
                )
                Text(verdict.verdict)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat = verdict.caveat, !caveat.isEmpty {
                    Text(caveat)
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.drip.coral.opacity(0.5))
                    .frame(width: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
        }

        // Visual layer — the deltas as paired bars, and the pace/effort drift
        // across each run. Between the words and the audit table.
        if let diff = comparison.diff {
            let bars = metricBars(diff: diff)
            if !bars.isEmpty {
                EditorialRule()
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                VStack(alignment: .leading, spacing: 12) {
                    DripEyebrow(text: "THE MOVE · A → B")
                    MetricBarsView(metrics: bars)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            // The whole run, overlaid — pace, HR and elevation drawn over
            // distance, A as the pale ghost, B in coral. Replaces the single
            // decoupling trace; the drift math still feeds the DECOUPLING row.
            if a.series.count >= 2, b.series.count >= 2 {
                WorkoutGraphsPanel(a: a, b: b)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }
        }

        EditorialRule()
            .padding(.horizontal, 24)
            .padding(.top, 18)

        // The numbers — Layer 1, auditable.
        if let diff = comparison.diff {
            diffTable(diff: diff, a: a, b: b)
                .padding(.horizontal, 24)
                .padding(.top, 14)
        }

        Text(comparison.diff?.avgRepPaceAdjSec != nil
             ? "Every number above is measured, except heat-adjusted pace — a model, and marked as one."
             : "Every number above is measured.")
            .font(.dripBody(12).italic())
            .foregroundStyle(Color.drip.textTertiary)
            .lineSpacing(3)
            .padding(.horizontal, 24)
            .padding(.top, 16)
    }

    private func sessionColumn(eyebrow: String, profile: WorkProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DripEyebrow(text: eyebrow)
            Text(profile.structure ?? repsLabel(profile))
                .font(.dripDisplay(18))
                .foregroundStyle(Color.drip.textPrimary)
                .lineLimit(2)
            Text(shortDate(profile.date)
                 + (profile.tempF != nil ? " · \(Int(profile.tempF!.rounded()))°F" : ""))
                .font(.dripCaption(10))
                .tracking(1.0)
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparabilityRow(_ comp: ComparabilityDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(comp.confidence == "low" ? Color.drip.tired : Color.drip.positive)
                    .frame(width: 5, height: 5)
                Text(String(format: "%.2f COMPARABILITY · %@", comp.score, comp.confidence.uppercased()))
                    .font(.dripEyebrow(10))
                    .tracking(1.0)
            }
            .foregroundStyle(comp.confidence == "low" ? Color.drip.tired : Color.drip.positive)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((comp.confidence == "low" ? Color.drip.tired : Color.drip.positive).opacity(0.12))
            .clipShape(Capsule())

            if let note = comp.notes.first {
                Text(note)
                    .font(.dripBody(12).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── Diff table ──────────────────────────────────────────────────────

    @ViewBuilder
    private func diffTable(diff: DiffDTO, a: WorkProfileDTO, b: WorkProfileDTO) -> some View {
        VStack(spacing: 0) {
            HStack {
                DripEyebrow(text: "THE NUMBERS")
                Spacer()
                Text("A → B · Δ")
                    .font(.dripCaption(9))
                    .tracking(1.2)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.bottom, 8)

            let isQuality = diff.mode == "quality"

            diffRow("ZONE", zoneLabel(diff.zone.a), zoneLabel(diff.zone.b),
                    diff.zone.same ? "same" : "differs")

            // ── Whole-run rows (every workout type) ──
            if let v = diff.totalDistanceMeters {
                diffRow("DISTANCE",
                        String(format: "%.1f mi", v.a / 1609.344),
                        String(format: "%.1f mi", v.b / 1609.344),
                        v.pctChange.map { signed($0) + "%" })
            }
            if let d = diff.totalDurationSec {
                diffRow("DURATION", durationString(d.a), durationString(d.b),
                        signed(d.delta / 60) + "m")
            }
            if let p = diff.avgPaceSec {
                diffRow("AVG PACE", paceString(p.a), paceString(p.b),
                        signed(p.delta) + "s")
            }
            if let p = diff.conditionsAdjustedPaceSec {
                diffRow("PACE · HEAT+HILL ADJ", paceString(p.a), paceString(p.b),
                        signed(p.delta) + "s", modelTag: true)
            }
            if let p = diff.fastSegPaceSec {
                diffRow("FAST SEGMENT", paceString(p.a), paceString(p.b),
                        signed(p.delta) + "s")
            }
            if let h = diff.avgRunHr {
                diffRow("AVG HR", "\(Int(h.a.rounded()))", "\(Int(h.b.rounded()))",
                        signed(h.delta))
            }
            if let e = diff.elevationGainM, e.a > 0 || e.b > 0 {
                let ft = { (m: Double) in "\(Int((m * 3.28084).rounded())) ft" }
                diffRow("ELEVATION", ft(e.a), ft(e.b),
                        signed(e.delta * 3.28084) + "ft")
            }
            // Aerobic decoupling — the headline signal for a steady run (its
            // coral hit); shown whenever both sides have HR. Lower = held form.
            if !isQuality, let da = diff.decouplingPct.a, let db = diff.decouplingPct.b {
                diffRow("DECOUPLING", signed(da, decimals: 1) + "%", signed(db, decimals: 1) + "%",
                        signed(db - da, decimals: 1) + "%", coral: true)
            }

            // ── Quality-work rows (rep sessions only) ──
            if isQuality {
                diffRow("REPS", repsLabel(a), repsLabel(b),
                        diff.reps.map { signed($0.delta) })

                if let p = diff.avgRepPaceRawSec {
                    diffRow("REP PACE · RAW", paceString(p.a), paceString(p.b),
                            signed(p.delta) + "s")
                }
                if let p = diff.avgRepPaceAdjSec {
                    diffRow("REP PACE · HEAT-ADJ", paceString(p.a), paceString(p.b),
                            signed(p.delta) + "s", modelTag: true)
                }
                if let r = diff.avgRecoverySec {
                    diffRow("RECOVERY", "\(Int(r.a.rounded()))s", "\(Int(r.b.rounded()))s",
                            signed(r.delta) + "s")
                }
                if let h = diff.recoveryHrDropBpm {
                    // The headline signal for a quality session — its coral hit.
                    diffRow("HR DROP IN FLOATS", "\(Int(h.a.rounded()))", "\(Int(h.b.rounded()))",
                            signed(h.delta), coral: true)
                }
                if let h = diff.avgWorkHr {
                    diffRow("AVG WORK HR", "\(Int(h.a.rounded()))", "\(Int(h.b.rounded()))",
                            signed(h.delta))
                }
                if let v = diff.qualityVolumeMeters {
                    diffRow("QUALITY VOLUME",
                            String(format: "%.1f mi", v.a / 1609.344),
                            String(format: "%.1f mi", v.b / 1609.344),
                            v.pctChange.map { signed($0) + "%" })
                }
            }

            if let t = diff.tempF {
                diffRow("TEMP", "\(Int(t.a.rounded()))°F", "\(Int(t.b.rounded()))°F",
                        signed(t.delta) + "°")
            }

            // Honest gaps — stated, never faked as zeros.
            if !diff.unavailable.isEmpty {
                Text(diff.unavailable.joined(separator: " · "))
                    .font(.dripBody(12).italic())
                    .foregroundStyle(Color.drip.textTertiary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func diffRow(
        _ label: String,
        _ a: String,
        _ b: String,
        _ delta: String?,
        coral: Bool = false,
        modelTag: Bool = false
    ) -> some View {
        let color = coral ? Color.drip.coral : Color.drip.textPrimary
        return VStack(spacing: 0) {
            DripHairline()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.dripCaption(9))
                        .tracking(1.0)
                        .foregroundStyle(coral ? Color.drip.coral : Color.drip.textSecondary)
                    if modelTag {
                        Text("MODEL")
                            .font(.dripCaption(7))
                            .tracking(0.8)
                            .foregroundStyle(Color.drip.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.drip.divider, lineWidth: 1)
                            )
                    }
                }
                Spacer(minLength: 8)
                Text(a)
                    .font(.dripStat(13))
                    .foregroundStyle(color)
                Text("→")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                Text(b)
                    .font(.dripStat(13))
                    .foregroundStyle(color)
                Text(delta ?? "·")
                    .font(.dripStat(12))
                    .foregroundStyle(coral ? Color.drip.coral : Color.drip.textSecondary)
                    .frame(minWidth: 46, alignment: .trailing)
            }
            .padding(.vertical, 8)
        }
    }

    // ── Manual picker ───────────────────────────────────────────────────

    private func pickButton(label: String) -> some View {
        Button {
            showPicker = true
            if candidates.isEmpty {
                Task { candidates = await WorkoutComparisonService.candidates(excluding: workoutId) }
            }
        } label: {
            Text(label)
                .font(.dripCaption(10))
                .tracking(1.4)
                .foregroundStyle(Color.drip.coral)
        }
        .buttonStyle(.plain)
    }

    private var comparisonPicker: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        DripPlateStrip(
                            leadingBottom: "PICK THE MIRROR SESSION",
                            trailingBottom: "COMPARE"
                        )

                        if candidates.isEmpty {
                            Text("No past runs to compare yet. Your logged runs show up here once they're processed.")
                                .font(.dripBody(13).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                                .lineSpacing(3)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(candidates) { candidate in
                                    Button {
                                        showPicker = false
                                        Task { await load(compareToId: candidate.trainingLogId) }
                                    } label: {
                                        VStack(spacing: 0) {
                                            DripHairline()
                                            HStack {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(candidate.workoutStructure ?? "Run")
                                                        .font(.dripBody(14))
                                                        .fontWeight(.bold)
                                                        .foregroundStyle(Color.drip.textPrimary)
                                                        .lineLimit(1)
                                                    Text(shortDate(candidate.workoutDate)
                                                         + (candidate.summary.map { " · \($0)" } ?? ""))
                                                        .font(.dripCaption(10))
                                                        .tracking(1.0)
                                                        .foregroundStyle(Color.drip.textSecondary)
                                                }
                                                Spacer()
                                                Text("COMPARE ↗")
                                                    .font(.dripCaption(10))
                                                    .tracking(1.4)
                                                    .foregroundStyle(Color.drip.coral)
                                            }
                                            .padding(.vertical, 12)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                DripHairline()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)

                            Text("Any two sessions will compare. The score only says how tightly to read the result.")
                                .font(.dripBody(12).italic())
                                .foregroundStyle(Color.drip.textTertiary)
                                .lineSpacing(3)
                                .padding(.horizontal, 24)
                                .padding(.top, 14)
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showPicker = false }
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }
        }
    }
}

// MARK: - Paired-metric bars ("the move")

private struct MetricBar: Identifiable {
    let id = UUID()
    let label: String
    let aText: String
    let bText: String
    let aFrac: Double       // 0…1 relative to the pair's larger value
    let bFrac: Double
    let deltaText: String
}

/// Build the paired-bar rows from the diff. Each bar's length encodes the two
/// raw values relative to each other; the delta label carries the direction
/// (so "lower is better" metrics like pace read correctly from the delta).
private func metricBars(diff: DiffDTO) -> [MetricBar] {
    var bars: [MetricBar] = []
    func frac(_ a: Double, _ b: Double) -> (Double, Double) {
        let m = max(abs(a), abs(b), 0.0001)
        return (max(0.06, abs(a) / m), max(0.06, abs(b) / m))
    }
    if let v = diff.totalDistanceMeters {
        let (af, bf) = frac(v.a, v.b)
        bars.append(MetricBar(
            label: "DISTANCE",
            aText: String(format: "%.1f", v.a / 1609.344),
            bText: String(format: "%.1f mi", v.b / 1609.344),
            aFrac: af, bFrac: bf,
            deltaText: v.pctChange.map { signed($0) + "%" } ?? "·"))
    }
    if let p = diff.avgPaceSec {
        let (af, bf) = frac(p.a, p.b)
        bars.append(MetricBar(label: "PACE", aText: paceString(p.a), bText: paceString(p.b),
                              aFrac: af, bFrac: bf, deltaText: signed(p.delta) + "s"))
    }
    if let h = diff.avgRunHr {
        let (af, bf) = frac(h.a, h.b)
        bars.append(MetricBar(label: "AVG HR", aText: "\(Int(h.a.rounded()))",
                              bText: "\(Int(h.b.rounded()))", aFrac: af, bFrac: bf,
                              deltaText: signed(h.delta)))
    }
    if let p = diff.fastSegPaceSec {
        let (af, bf) = frac(p.a, p.b)
        bars.append(MetricBar(label: "FAST SEG", aText: paceString(p.a), bText: paceString(p.b),
                              aFrac: af, bFrac: bf, deltaText: signed(p.delta) + "s"))
    }
    if let da = diff.decouplingPct.a, let db = diff.decouplingPct.b {
        let (af, bf) = frac(da, db)
        bars.append(MetricBar(label: "DECOUPLING", aText: signed(da, decimals: 1) + "%",
                              bText: signed(db, decimals: 1) + "%", aFrac: af, bFrac: bf,
                              deltaText: signed(db - da, decimals: 1) + "%"))
    }
    return bars
}

private struct MetricBarsView: View {
    let metrics: [MetricBar]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(metrics) { m in
                VStack(spacing: 5) {
                    HStack {
                        Text(m.label)
                            .font(.dripCaption(9)).tracking(1.0)
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text(m.deltaText)
                            .font(.dripStat(11))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    bar(frac: m.aFrac, fill: Color.drip.textTertiary, tag: "A", value: m.aText)
                    bar(frac: m.bFrac, fill: Color.drip.coral, tag: "B", value: m.bText)
                }
            }
        }
    }

    private func bar(frac: Double, fill: Color, tag: String, value: String) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(fill.opacity(0.14)).frame(height: 16)
                Capsule().fill(fill)
                    .frame(width: max(10, geo.size.width * frac), height: 16)
                HStack(spacing: 6) {
                    Text(tag)
                        .font(.dripCaption(8)).tracking(0.8)
                        .foregroundStyle(Color.drip.background)
                        .padding(.leading, 8)
                    Spacer()
                    Text(value)
                        .font(.dripStat(11))
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.trailing, 2)
                }
                .frame(height: 16)
            }
        }
        .frame(height: 16)
    }
}

// MARK: - Overlaid workout graphs (pace · HR · elevation, A vs B)

/// The redesigned "whole run" figure: three synced lanes over one distance
/// axis — Pace, Heart rate, Elevation — each drawing both runs. B (this
/// session) leads in coral; A (the earlier session) trails as a pale ghost.
/// All three read from the per-point `series` the edge function already ships,
/// so no new data is required. Lanes that lack data (no HR, no grade) drop out.
private struct WorkoutGraphsPanel: View {
    let a: WorkProfileDTO
    let b: WorkProfileDTO

    private struct LanePoint: Identifiable {
        let id = UUID()
        let run: String     // "A" or "B"
        let mi: Double
        let value: Double
    }

    private var ghost: Color { Color.drip.textTertiary }

    // ── Per-lane point builders ─────────────────────────────────────────
    private func pacePoints(_ s: [SeriesPointDTO], run: String) -> [LanePoint] {
        s.compactMap { p in
            guard p.paceSec > 0, p.paceSec < 1200 else { return nil }
            return LanePoint(run: run, mi: p.mi, value: p.paceSec)
        }
    }

    private func hrPoints(_ s: [SeriesPointDTO], run: String) -> [LanePoint] {
        s.compactMap { p in
            guard let hr = p.hr, hr > 0 else { return nil }
            return LanePoint(run: run, mi: p.mi, value: hr)
        }
    }

    /// Elevation profile integrated from grade %, indexed to 0 ft at the start.
    /// Relative shape only — enough to compare terrain, not absolute altitude.
    private func elevationPoints(_ s: [SeriesPointDTO], run: String) -> [LanePoint] {
        guard s.contains(where: { $0.gradePct != nil }) else { return [] }
        var cumMeters = 0.0
        var prevMi = s.first?.mi ?? 0
        var out: [LanePoint] = []
        for p in s {
            let dMi = max(0, p.mi - prevMi)
            prevMi = p.mi
            if let g = p.gradePct { cumMeters += (g / 100.0) * (dMi * 1609.344) }
            out.append(LanePoint(run: run, mi: p.mi, value: cumMeters * 3.28084))
        }
        return out
    }

    var body: some View {
        let pace = pacePoints(a.series, run: "A") + pacePoints(b.series, run: "B")
        let hr = hrPoints(a.series, run: "A") + hrPoints(b.series, run: "B")
        let elev = elevationPoints(a.series, run: "A") + elevationPoints(b.series, run: "B")
        let hasHR = hr.count >= 2
        let hasElev = elev.count >= 2

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("The whole run.")
                    .font(.dripDisplay(18))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                HStack(spacing: 12) {
                    legendSwatch(color: ghost, label: "A · THEN")
                    legendSwatch(color: Color.drip.coral, label: "B · NOW")
                }
            }
            .padding(.bottom, 10)

            lane(title: "Pace.", hint: "FASTER ↑", points: pace,
                 reversed: true, area: false, showX: !hasHR && !hasElev,
                 format: { paceString($0) })

            if hasHR {
                DripHairline().padding(.vertical, 8)
                lane(title: "Heart rate.", hint: "BPM", points: hr,
                     reversed: false, area: false, showX: !hasElev,
                     format: { "\(Int($0.rounded()))" })
            }

            if hasElev {
                DripHairline().padding(.vertical, 8)
                lane(title: "Elevation.", hint: "ROUTE · CONTEXT", points: elev,
                     reversed: false, area: true, showX: true,
                     format: { "\(Int($0.rounded()))ft" })
            }
        }
        .padding(16)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 14, height: 2.5)
            Text(label)
                .font(.dripEyebrow(8))
                .tracking(0.6)
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    @ViewBuilder
    private func lane(
        title: String,
        hint: String,
        points: [LanePoint],
        reversed: Bool,
        area: Bool,
        showX: Bool,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.dripDisplay(15))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
                Text(hint)
                    .font(.dripEyebrow(8))
                    .tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Chart {
                if area {
                    ForEach(points.filter { $0.run == "B" }) { p in
                        AreaMark(
                            x: .value("Mile", p.mi),
                            y: .value("Value", p.value),
                            series: .value("Run", "Bfill")
                        )
                        .foregroundStyle(Color.drip.coralWash)
                        .interpolationMethod(.catmullRom)
                    }
                }
                ForEach(points) { p in
                    LineMark(
                        x: .value("Mile", p.mi),
                        y: .value("Value", p.value),
                        series: .value("Run", p.run)
                    )
                    .foregroundStyle(p.run == "B" ? Color.drip.coral : ghost)
                    .lineStyle(StrokeStyle(
                        lineWidth: p.run == "B" ? 2.2 : 1.4,
                        lineJoin: .round
                    ))
                    .interpolationMethod(reversed ? .linear : .catmullRom)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: reversed))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(format(v))
                                .font(.dripEyebrow(8))
                                .foregroundStyle(Color.drip.textTertiary)
                        }
                    }
                    AxisGridLine().foregroundStyle(Color.drip.divider.opacity(0.5))
                }
            }
            .chartXAxis {
                if showX {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))mi")
                                    .font(.dripEyebrow(8))
                                    .foregroundStyle(Color.drip.textTertiary)
                            }
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: area ? 72 : 92)
        }
    }
}

// MARK: - Effort-drift curve (decoupling across the run)

private struct DriftPoint: Identifiable {
    let id = UUID()
    let run: String     // "A" or "B"
    let mi: Double
    let index: Double   // efficiency vs. the run's own start, % (100 = baseline)
}

private struct DriftCurveChart: View {
    let seriesA: [SeriesPointDTO]
    let seriesB: [SeriesPointDTO]

    /// Efficiency (speed ÷ HR, or speed alone without HR) indexed to the first
    /// lap. Rising above 100 = the run got less efficient — decoupling.
    private func indexed(_ s: [SeriesPointDTO], run: String) -> [DriftPoint] {
        func eff(_ p: SeriesPointDTO) -> Double? {
            guard p.paceSec > 0 else { return nil }
            let speed = 1.0 / p.paceSec
            if let hr = p.hr, hr > 0 { return speed / hr }
            return speed
        }
        guard let base = s.first.flatMap(eff), base > 0 else { return [] }
        return s.compactMap { p in
            guard let e = eff(p), e > 0 else { return nil }
            return DriftPoint(run: run, mi: p.mi, index: (base / e) * 100)
        }
    }

    var body: some View {
        let points = indexed(seriesA, run: "A") + indexed(seriesB, run: "B")
        Chart {
            RuleMark(y: .value("Baseline", 100))
                .foregroundStyle(Color.drip.divider)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(points) { p in
                LineMark(
                    x: .value("Mile", p.mi),
                    y: .value("Efficiency", p.index)
                )
                .foregroundStyle(by: .value("Run", p.run))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartForegroundStyleScale([
            "A": Color.drip.textTertiary,
            "B": Color.drip.coral,
        ])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%")
                            .font(.dripCaption(8))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
                AxisGridLine().foregroundStyle(Color.drip.divider.opacity(0.5))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))mi")
                            .font(.dripCaption(8))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            }
        }
        .frame(height: 150)
    }
}
