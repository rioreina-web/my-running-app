//
//  WorkoutRepChart.swift
//  RunningLog
//
//  The per-workout rep visualization (Training Analysis headline feature).
//  Reads rep-level `running_workout_laps` for one workout and draws it
//  split-by-split: rep bars (faster = taller), HR overlay, rest markers,
//  pace-zone reference lines, a stat row, and a heat-adjustment toggle.
//
//  Design: outputs/workout-detail-viz.html + weather-adjustment-viz.html.
//  Post Run Drip. Hand-drawn (GeometryReader/Path) — no chart dependency.
//
//  Use: `WorkoutRepChart(workoutId: log.id)` from any workout tap-through.
//  Preview-able offline via the #Preview at the bottom.
//

import SwiftUI
import Supabase
import os

// MARK: - Data

struct WorkoutLapRow: Decodable, Identifiable {
    var id: Int { lap_index ?? 0 }
    var lap_index: Int?
    var distance_meters: Double?
    var moving_time_seconds: Int?
    var avg_pace_sec_per_mile: Double?
    var avg_heart_rate: Int?
    var is_rest: Bool?
    var temp_f: Double?
    var dew_point_f: Double?
    var heat_adjusted_pace_sec_per_mile: Double?
}

/// Pace zones (sec/mi) used for the dashed reference lines.
struct RepChartZones {
    var fiveK: Double?
    var tenK: Double?
    var threshold: Double?   // HMP / LT
    static let none = RepChartZones(fiveK: nil, tenK: nil, threshold: nil)
}

enum WorkoutLapsService {
    static func fetchLaps(workoutId: UUID) async -> [WorkoutLapRow] {
        do {
            return try await supabase
                .from("running_workout_laps")
                .select("lap_index,distance_meters,moving_time_seconds,avg_pace_sec_per_mile,avg_heart_rate,is_rest,temp_f,dew_point_f,heat_adjusted_pace_sec_per_mile")
                .eq("workout_id", value: workoutId.uuidString)
                .order("lap_index", ascending: true)
                .execute().value
        } catch {
            Log.coach.error("WorkoutLapsService.fetchLaps failed: \(error)")
            return []
        }
    }

    static func fetchInsight(workoutId: UUID) async -> String? {
        struct Row: Decodable { var coach_insight: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("coach_insight")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            return rows.first?.coach_insight
        } catch { return nil }
    }

    static func fetchType(workoutId: UUID) async -> String? {
        struct Row: Decodable { var workout_type: String? }
        do {
            let rows: [Row] = try await supabase
                .from("training_logs").select("workout_type")
                .eq("id", value: workoutId.uuidString).limit(1).execute().value
            return rows.first?.workout_type
        } catch { return nil }
    }

    /// Manual override of the detected workout type. compute-workout-features
    /// only fills workout_type when it's null, so a manual value persists.
    static func setType(workoutId: UUID, type: String) async {
        do {
            try await supabase
                .from("training_logs")
                .update(["workout_type": type])
                .eq("id", value: workoutId.uuidString)
                .execute()
        } catch {
            Log.coach.error("WorkoutLapsService.setType failed: \(error)")
        }
    }

    static func fetchZones() async -> RepChartZones {
        struct Row: Decodable { var pace_zones: [String: Double]? }
        do {
            let rows: [Row] = try await supabase
                .from("athlete_state").select("pace_zones").limit(1).execute().value
            let z = rows.first?.pace_zones
            return RepChartZones(fiveK: z?["fiveK"], tenK: z?["tenK"], threshold: z?["hm"])
        } catch {
            return .none
        }
    }
}

// MARK: - View

struct WorkoutRepChart: View {
    let workoutId: UUID?
    private let injectedLaps: [WorkoutLapRow]?
    private let injectedZones: RepChartZones?

    init(workoutId: UUID) {
        self.workoutId = workoutId
        self.injectedLaps = nil
        self.injectedZones = nil
    }
    /// Preview / test seam.
    init(laps: [WorkoutLapRow], zones: RepChartZones) {
        self.workoutId = nil
        self.injectedLaps = laps
        self.injectedZones = zones
    }

    @State private var laps: [WorkoutLapRow] = []
    @State private var zones: RepChartZones = .none
    @State private var loaded = false
    @State private var heatOn = false
    @State private var insight: String?
    @State private var workoutType: String?
    @State private var showTypePicker = false

    private let metersPerMile = 1609.344
    static let typeOptions = ["intervals", "threshold", "tempo", "fartlek", "progression", "easy", "long_run", "recovery", "race"]

    // Work reps = non-rest laps faster than ~steady and long enough to be a rep.
    private var reps: [WorkoutLapRow] {
        laps.filter { lap in
            guard lap.is_rest != true,
                  let p = lap.avg_pace_sec_per_mile, p > 0,
                  let d = lap.distance_meters, d >= 150,
                  let s = lap.moving_time_seconds, s >= 20 else { return false }
            // faster than ~6:10/mi (steady-ish) counts as work
            return p <= 370
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loaded && reps.isEmpty {
                emptyState
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                headerStats
                analysisCard
                chartPanel
                splitsCard
                heatChip
            }
        }
        .task {
            if let injectedLaps {
                laps = injectedLaps; zones = injectedZones ?? .none; loaded = true; return
            }
            guard let workoutId else { loaded = true; return }
            async let l = WorkoutLapsService.fetchLaps(workoutId: workoutId)
            async let z = WorkoutLapsService.fetchZones()
            async let ins = WorkoutLapsService.fetchInsight(workoutId: workoutId)
            async let ty = WorkoutLapsService.fetchType(workoutId: workoutId)
            laps = await l; zones = await z; insight = await ins; workoutType = await ty; loaded = true
        }
    }

    // MARK: Header + stats

    private var headerStats: some View {
        let paces = reps.compactMap { $0.avg_pace_sec_per_mile }
        let hrs = reps.compactMap { $0.avg_heart_rate }
        let avgPace = paces.isEmpty ? 0 : paces.reduce(0, +) / Double(paces.count)
        let workMi = reps.compactMap { $0.distance_meters }.reduce(0, +) / metersPerMile
        let spread = (paces.max() ?? 0) - (paces.min() ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Button { showTypePicker = true } label: {
                HStack(spacing: 6) {
                    Text((workoutType.map(prettyType) ?? zoneTag(avgPace)).uppercased())
                        .font(.dripStat(10)).tracking(1.3)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.drip.coral)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.drip.coralWash)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .confirmationDialog("Change workout type", isPresented: $showTypePicker, titleVisibility: .visible) {
                ForEach(Self.typeOptions, id: \.self) { t in
                    Button(prettyType(t)) { updateType(t) }
                }
                Button("Cancel", role: .cancel) {}
            }
            Text("\(reps.count)×\(repDistanceLabel())")
                .font(.dripDisplay(24))
                .foregroundStyle(Color.drip.textPrimary)
            HStack(spacing: 18) {
                stat("AVG WORK", fmt(avgPace) + "/mi")
                stat("WORK", String(format: "%.1f mi", workMi))
                if let hi = hrs.max() { stat("HR", "\(avg(hrs)) · \(hi) max") }
                stat("SPREAD", "\(Int(spread))s")
            }
        }
    }

    /// Manual workout-type override — updates immediately on screen and persists.
    private func updateType(_ t: String) {
        workoutType = t
        guard let workoutId else { return }
        Task { await WorkoutLapsService.setType(workoutId: workoutId, type: t) }
    }

    private func prettyType(_ t: String) -> String {
        switch t {
        case "long_run": return "Long run"
        case "intervals", "interval": return "Intervals"
        default: return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.dripStat(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
            Text(v).font(.dripStat(13)).foregroundStyle(Color.drip.textPrimary)
        }
    }

    // MARK: Chart

    // AI analysis of the session — the stored coach_insight when it's
    // substantial, else a deterministic computed read so the card is never empty.
    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANALYSIS")
                .font(.dripStat(10)).tracking(1.1)
                .foregroundStyle(Color.drip.coral)
            Text(analysisText)
                .font(.dripBody(15)).lineSpacing(3)
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var analysisText: String {
        if let s = insight?.trimmingCharacters(in: .whitespacesAndNewlines), s.count >= 40 {
            return s
        }
        return computedRead
    }

    private var computedRead: String {
        let n = reps.count
        let dist = repDistanceLabel()
        let avg = repPacesArr.isEmpty ? "—" : fmt(repPacesArr.reduce(0, +) / Double(repPacesArr.count))
        let zone = workoutType.map { prettyType($0).lowercased() }
            ?? (repPacesArr.isEmpty ? "quality" : zoneTag(repPacesArr.reduce(0, +) / Double(repPacesArr.count)))
        let shapeRead: String
        switch shapeString {
        case "negative": shapeRead = "and you got stronger through the set"
        case "faded":    shapeRead = "but drifted slower over the reps"
        default:         shapeRead = "and held it even"
        }
        var drift = ""
        if let f = repHRArr.first, let l = repHRArr.last, f > 0 {
            let pct = Double(l - f) / Double(f) * 100
            if pct >= 6 { drift = " HR climbed \(Int(pct))% across the reps — normal fatigue for the effort." }
            else if pct >= 0 { drift = " HR held steady, a sign you stayed in control." }
        }
        return "\(n)×\(dist) at \(avg)/mi (\(zone)) \(shapeRead).\(drift)"
    }

    // Per-rep splits + durability — the deeper analysis under the chart.
    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SPLITS")
                .font(.dripStat(10)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
                .padding(.bottom, 12)
            HStack(spacing: 18) {
                stat("FADE", fadeString)
                stat("HR DRIFT", driftString)
                stat("SHAPE", shapeString)
            }
            .padding(.bottom, 10)
            ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                HStack {
                    Text("REP \(i + 1)")
                        .font(.dripStat(11)).foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    if let p = rep.avg_pace_sec_per_mile {
                        Text(fmt(p) + "/mi")
                            .font(.dripBody(14)).foregroundStyle(Color.drip.textPrimary)
                    }
                    if let hr = rep.avg_heart_rate {
                        Text("\(hr) bpm")
                            .font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                .padding(.vertical, 9)
                .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var repPacesArr: [Double] { reps.compactMap { $0.avg_pace_sec_per_mile } }
    private var repHRArr: [Int] { reps.compactMap { $0.avg_heart_rate } }
    private var fadeString: String {
        guard let f = repPacesArr.first, let l = repPacesArr.last, f > 0 else { return "—" }
        return String(format: "%+.0f%%", (l - f) / f * 100)
    }
    private var driftString: String {
        guard let f = repHRArr.first, let l = repHRArr.last, f > 0 else { return "—" }
        return String(format: "%+.0f%%", Double(l - f) / Double(f) * 100)
    }
    private var shapeString: String {
        guard let f = repPacesArr.first, let l = repPacesArr.last, f > 0 else { return "even" }
        let pct = (l - f) / f * 100
        if pct < -1.5 { return "negative" }
        if pct > 1.5 { return "faded" }
        return "even"
    }

    // Chart wrapped in a panel card to match workout-detail-viz.html.
    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REP-BY-REP")
                .font(.dripStat(10)).tracking(1.1)
                .foregroundStyle(Color.drip.textSecondary)
            Text("Each bar is a rep — taller = faster. Line = HR. Dashed lines are your pace zones.")
                .font(.dripBody(12.5))
                .foregroundStyle(Color.drip.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chart
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.drip.divider, lineWidth: 1))
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padTop: CGFloat = 16, padBottom: CGFloat = 20
            let plotH = h - padTop - padBottom
            let n = max(reps.count, 1)
            let slot = w / CGFloat(n)
            let barW = slot * 0.5

            // pace scale (faster = top). Pad the rep range a touch.
            let paces = reps.compactMap { $0.avg_pace_sec_per_mile }
            let pMin = (paces.min() ?? 300) - 6
            let pMax = (paces.max() ?? 320) + 6
            let yPace: (Double) -> CGFloat = { p in
                padTop + CGFloat((p - pMin) / max(pMax - pMin, 1)) * plotH
            }
            // HR scale on upper band
            let hrs = reps.compactMap { $0.avg_heart_rate }.map(Double.init)
            let hMin = (hrs.min() ?? 140) - 4
            let hMax = (hrs.max() ?? 175) + 4
            let yHR: (Double) -> CGFloat = { v in
                padTop + (1 - CGFloat((v - hMin) / max(hMax - hMin, 1))) * plotH
            }
            let xC: (Int) -> CGFloat = { i in slot * CGFloat(i) + slot / 2 }

            ZStack(alignment: .topLeading) {
                // zone reference lines
                ForEach(Array(zoneLines().enumerated()), id: \.offset) { _, line in
                    let name = line.0, pace = line.1, color = line.2
                    let y = yPace(pace)
                    if y >= padTop && y <= padTop + plotH {
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w - 30, y: y)) }
                            .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        Text(name).font(.dripStat(8)).foregroundStyle(color)
                            .position(x: w - 16, y: y)
                    }
                }
                // bars + labels
                ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                    if let p = rep.avg_pace_sec_per_mile {
                        let y = yPace(p)
                        let barH = padTop + plotH - y
                        Rectangle().fill(Color.drip.coral)
                            .frame(width: barW, height: max(barH, 1))
                            .position(x: xC(i), y: y + barH / 2)
                        Text(fmt(p)).font(.dripStat(8)).foregroundStyle(Color.drip.textPrimary)
                            .position(x: xC(i), y: y - 8)
                        // cool-air equivalent marker when heat toggle on
                        if heatOn, let adj = adjustedPace(rep) {
                            let ya = yPace(adj)
                            Path { pa in pa.move(to: CGPoint(x: xC(i) - barW/2, y: ya)); pa.addLine(to: CGPoint(x: xC(i) + barW/2, y: ya)) }
                                .stroke(Color.drip.coralLight, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        }
                        Text("\(i + 1)").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                            .position(x: xC(i), y: padTop + plotH + 10)
                    }
                }
                // HR polyline + dots
                if hrs.count >= 2 {
                    Path { path in
                        for (i, rep) in reps.enumerated() {
                            guard let hr = rep.avg_heart_rate else { continue }
                            let pt = CGPoint(x: xC(i), y: yHR(Double(hr)))
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.drip.textSecondary, lineWidth: 1.5)
                    ForEach(Array(reps.enumerated()), id: \.offset) { i, rep in
                        if let hr = rep.avg_heart_rate {
                            Circle().fill(Color.drip.textSecondary).frame(width: 5, height: 5)
                                .position(x: xC(i), y: yHR(Double(hr)))
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Color.drip.coral, "rep pace")
            legendItem(Color.drip.textSecondary, "avg HR")
            Text("dashed = your 5K / 10K / threshold")
                .font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary)
        }
    }
    private func legendItem(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(t).font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary)
        }
    }

    private var heatChip: some View {
        let conds = heatConditions()
        return Group {
            if let c = conds {
                Button { withAnimation(.easeOut(duration: 0.2)) { heatOn.toggle() } } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Color.drip.tired).frame(width: 7, height: 7)
                        Text(heatOn
                             ? "Heat-adjusted — cool-air equivalent shown ‹"
                             : "Hot & humid — \(c). Tap for cool-air splits ›")
                            .font(.dripBody(12.5))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(heatOn ? Color.drip.coral : Color.drip.tired)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background((heatOn ? Color.drip.coral : Color.drip.tired).opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        Text("No rep-level splits for this run — it reads as a steady effort.")
            .font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary)
            .padding(.vertical, 24)
    }

    // MARK: Helpers

    private func zoneLines() -> [(String, Double, Color)] {
        var out: [(String, Double, Color)] = []
        if let v = zones.fiveK { out.append(("5K \(fmt(v))", v, Color.drip.coral)) }
        if let v = zones.tenK { out.append(("10K \(fmt(v))", v, Color.drip.textTertiary)) }
        if let v = zones.threshold { out.append(("Thr \(fmt(v))", v, Color.drip.tired)) }
        return out
    }
    private func adjustedPace(_ lap: WorkoutLapRow) -> Double? {
        if let a = lap.heat_adjusted_pace_sec_per_mile, a > 0 { return a }
        return nil
    }
    private func heatConditions() -> String? {
        guard let t = reps.compactMap({ $0.temp_f }).max(),
              let d = reps.compactMap({ $0.dew_point_f }).max(), d >= 60 else { return nil }
        return "\(Int(t))°F, \(Int(d))° dew"
    }
    private func repDistanceLabel() -> String {
        guard let m = reps.compactMap({ $0.distance_meters }).first else { return "rep" }
        let miles = m / metersPerMile
        if abs(miles - miles.rounded()) / max(miles, 1) < 0.08 && miles >= 1 { return "\(Int(miles.rounded()))mi" }
        for r in [400.0, 600, 800, 1000, 1200, 1600] where abs(m - r) / r < 0.08 {
            return r.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(r/1000))K" : "\(Int(r))m"
        }
        return "\(Int((m/100).rounded()*100))m"
    }
    private func zoneTag(_ p: Double) -> String {
        if let v = zones.fiveK, p <= v + 6 { return "5K pace" }
        if let v = zones.tenK, p <= v + 6 { return "10K pace" }
        if let v = zones.threshold, p <= v + 8 { return "threshold" }
        return "quality"
    }
    private func fmt(_ sec: Double) -> String {
        let t = Int(sec.rounded()); return "\(t/60):\(String(format: "%02d", t%60))"
    }
    private func avg(_ xs: [Int]) -> Int { xs.isEmpty ? 0 : xs.reduce(0,+)/xs.count }
}

// MARK: - Preview (renders in Xcode canvas, no app run)

#Preview {
    // Real-shaped May 20 9×1K @ ~5:07 with rests, plus warmup/cooldown.
    func lap(_ i: Int, _ m: Double, _ s: Int, _ p: Double, _ hr: Int, _ rest: Bool = false, _ t: Double = 67, _ dew: Double = 67, _ adj: Double? = nil) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s,
                   avg_pace_sec_per_mile: p, avg_heart_rate: hr, is_rest: rest,
                   temp_f: t, dew_point_f: dew, heat_adjusted_pace_sec_per_mile: adj)
    }
    let laps: [WorkoutLapRow] = [
        lap(0, 1609, 480, 480, 132),                 // warmup
        lap(1, 1000, 307, 307, 162, false, 67, 67, 301),
        lap(2, 64, 63, 1579, 167, true),
        lap(3, 1000, 309, 309, 168, false, 67, 67, 303),
        lap(4, 60, 63, 1900, 158, true),
        lap(5, 1000, 306, 306, 166, false, 67, 67, 300),
        lap(6, 60, 63, 1900, 169, true),
        lap(7, 1000, 307, 307, 168, false, 67, 67, 301),
        lap(8, 60, 63, 1900, 170, true),
        lap(9, 1000, 309, 309, 169, false, 67, 67, 303),
        lap(10, 60, 63, 1900, 169, true),
        lap(11, 1000, 307, 307, 170, false, 67, 67, 301),
        lap(12, 60, 63, 1900, 169, true),
        lap(13, 1000, 309, 309, 169, false, 67, 67, 303),
        lap(14, 60, 63, 1900, 169, true),
        lap(15, 1000, 307, 307, 169, false, 67, 67, 301),
        lap(16, 60, 63, 1900, 168, true),
        lap(17, 1000, 306, 306, 166, false, 67, 67, 300),
        lap(18, 1200, 540, 540, 140),                // cooldown
    ]
    let zones = RepChartZones(fiveK: 302, tenK: 314, threshold: 328)
    return ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("INTERVALS · MAY 20")
                .font(.dripStat(10)).tracking(1.4).foregroundStyle(Color.drip.coral)
            WorkoutRepChart(laps: laps, zones: zones)
        }
        .padding(20)
    }
    .background(Color.drip.background.ignoresSafeArea())
}
