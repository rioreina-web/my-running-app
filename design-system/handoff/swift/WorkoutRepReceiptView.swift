//
//  WorkoutRepReceiptView.swift
//  RunningLog
//
//  Direction A · "Rep Receipt" — the dense, full-screen workout detail.
//  A drop-in for `WorkoutRepChart(workoutId:)` inside `WorkoutRepDetailSheet`.
//  Keeps everything the current screen does (type picker, prescribed-workout
//  notes, ANALYSIS + on-demand AI insight, heat-adjust) and adds the full
//  Strava-stream telemetry the redesign called for:
//
//    HERO rep chart (distance-width bars + HR line + target refs) →
//    stat strip → THE READ (weather woven in) → time-in-HR-zone →
//    HR-over-session → pace trace → cadence → elevation+grade →
//    per-rep HR recovery → SPLITS vs target (diverging bars + rest jogs) →
//    [comparison vs recent same-type — see port note] → route.
//
//  Two data sources, loaded in parallel:
//    • rep laps      — WorkoutLapsService (running_workout_laps / parsed reps)
//    • per-second    — ExternalStreamAdapter.load(forTrainingLogId:)
//                      (HR / velocity / cadence / altitude / latlng)
//  Every stream-derived section hides gracefully when a run has no streams
//  (e.g. a manual entry), so the lap-only path still renders.
//
//  Charts live in WorkoutReceiptCharts.swift (RR* views + rr_* helpers).
//

import SwiftUI
import CoreLocation
import Supabase
import os

struct WorkoutRepReceiptView: View {
    let workoutId: UUID?
    private let injectedLaps: [WorkoutLapRow]?
    private let injectedZones: RepChartZones?

    init(workoutId: UUID) {
        self.workoutId = workoutId; self.injectedLaps = nil; self.injectedZones = nil
    }
    /// Preview / test seam (lap-only; stream sections stay hidden).
    init(laps: [WorkoutLapRow], zones: RepChartZones) {
        self.workoutId = nil; self.injectedLaps = laps; self.injectedZones = zones
    }

    // lap data
    @State private var laps: [WorkoutLapRow] = []
    @State private var zones: RepChartZones = .none
    @State private var prescription: WorkoutPrescription?
    @State private var parsedIntent: String?
    @State private var insight: String?
    @State private var workoutType: String?
    @State private var loaded = false
    @State private var showTypePicker = false
    @State private var insightLoading = false
    @State private var insightError: String?
    // stream data
    @State private var stream: VitalWorkoutStream?
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var streamMaxHR: Int?
    // tweaks
    @State private var heatOn = false
    @State private var km = false
    @State private var colorByZone = false

    private let mpm = 1609.344
    static let typeOptions = ["intervals", "threshold", "tempo", "fartlek", "progression", "easy", "long_run", "recovery", "race"]

    // MARK: Derived — work reps

    private var orderedLaps: [WorkoutLapRow] { laps.sorted { ($0.lap_index ?? 0) < ($1.lap_index ?? 0) } }

    private var reps: [WorkoutLapRow] {
        orderedLaps.filter { lap in
            guard lap.is_rest != true,
                  let p = lap.avg_pace_sec_per_mile, p > 0,
                  let d = lap.distance_meters, d >= 150,
                  let s = lap.moving_time_seconds, s >= 20 else { return false }
            return p <= 370
        }
    }

    /// Work-rep windows in stream time (cumulative lap durations), plus the
    /// rest lap that follows each — used for shading, per-rep cadence, recovery.
    private struct RepSlot { let rep: Int; let lap: WorkoutLapRow; let start: Double; let end: Double; let restStart: Double?; let restEnd: Double? }
    private var slots: [RepSlot] {
        var out: [RepSlot] = []
        var t = 0.0
        var repNum = 0
        for (i, lap) in orderedLaps.enumerated() {
            let dur = Double(lap.moving_time_seconds ?? 0)
            let isWork = reps.contains { ($0.lap_index ?? -1) == (lap.lap_index ?? -2) }
            if isWork {
                repNum += 1
                // rest = next lap if it's a rest
                var rs: Double? = nil, re: Double? = nil
                if i + 1 < orderedLaps.count, orderedLaps[i + 1].is_rest == true {
                    rs = t + dur; re = rs! + Double(orderedLaps[i + 1].moving_time_seconds ?? 0)
                }
                out.append(RepSlot(rep: repNum, lap: lap, start: t, end: t + dur, restStart: rs, restEnd: re))
            }
            t += dur
        }
        return out
    }

    // MARK: Stream arrays (downsampled for drawing)

    private var sTimes: [Double] { (stream?.time ?? []).map(Double.init) }
    private var sHR: [Double] { (stream?.heartrate ?? []).map(Double.init) }
    private var sPace: [Double] {
        (stream?.velocitySmooth ?? []).map { v in v > 0.4 ? min(mpm / v, 900) : 900 }
    }
    private var sCad: [Double] {
        let c = stream?.cadence ?? []
        let avg = c.isEmpty ? 0 : c.reduce(0, +) / Double(c.count)
        return avg < 120 ? c.map { $0 * 2 } : c   // Strava run cadence is per-leg
    }
    private var sAltFt: [Double] { (stream?.altitude ?? []).map { $0 * 3.281 } }
    private var sGrade: [Double] {
        guard let alt = stream?.altitude, let dist = stream?.distance, alt.count == dist.count, alt.count > 1 else { return [] }
        return alt.indices.map { i in
            guard i > 0 else { return 0 }
            let dd = dist[i] - dist[i - 1]
            return dd > 0.5 ? min(max((alt[i] - alt[i - 1]) / dd * 100, -25), 25) : 0
        }
    }
    private var hasStream: Bool { sTimes.count > 5 && sHR.count > 5 }

    private var windows: [RRWindow] { slots.map { RRWindow(id: $0.rep, start: $0.start, end: $0.end) } }

    private var maxHR: Int {
        streamMaxHR ?? reps.compactMap { $0.avg_heart_rate }.max() ?? 188
    }
    private var hrZones: [RRZone] { rr_zones(maxHR: maxHR) }

    // RRRep models for the hero chart + splits
    private func perRepCadence(_ slot: RepSlot) -> Int? {
        guard hasStream, !sCad.isEmpty else { return nil }
        let vals = sTimes.indices.filter { sTimes[$0] >= slot.start && sTimes[$0] < slot.end && $0 < sCad.count }.map { sCad[$0] }
        guard !vals.isEmpty else { return nil }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }
    private var rrReps: [RRRep] {
        slots.map { s in
            RRRep(
                id: s.rep,
                label: rr_repLabel(s.lap.distance_meters ?? 0),
                distMi: (s.lap.distance_meters ?? 0) / mpm,
                paceSec: s.lap.avg_pace_sec_per_mile ?? 0,
                hr: s.lap.avg_heart_rate,
                cad: perRepCadence(s),
                restSec: (s.restStart != nil && s.restEnd != nil) ? Int(s.restEnd! - s.restStart!) : nil,
                adjPaceSec: s.lap.heat_adjusted_pace_sec_per_mile
            )
        }
    }
    private var targetSec: Double {
        let p = reps.compactMap { $0.avg_pace_sec_per_mile }
        return p.isEmpty ? 330 : p.reduce(0, +) / Double(p.count)
    }

    // time in zone
    private var zoneSeconds: [String: Double] {
        var acc: [String: Double] = [:]
        hrZones.forEach { acc[$0.id] = 0 }
        if hasStream {
            for i in sHR.indices {
                let dt = i + 1 < sTimes.count ? sTimes[i + 1] - sTimes[i] : 2
                let z = hrZones.first { Int(sHR[i]) >= $0.lo && Int(sHR[i]) < $0.hi } ?? hrZones.last!
                acc[z.id, default: 0] += dt
            }
        } else {
            for s in slots {
                guard let hr = s.lap.avg_heart_rate else { continue }
                let z = hrZones.first { hr >= $0.lo && hr < $0.hi } ?? hrZones.last!
                acc[z.id, default: 0] += (s.end - s.start)
            }
        }
        return acc
    }
    private var dominantZone: String { zoneSeconds.max { $0.value < $1.value }?.key ?? "Z4" }

    // recoveries
    private var recoveries: [RRRecovery] {
        guard hasStream else { return [] }
        return slots.compactMap { s in
            guard let rs = s.restStart else { return nil }
            let idxs = sTimes.indices.filter { sTimes[$0] >= rs && sTimes[$0] <= rs + 60 && $0 < sHR.count }
            guard idxs.count >= 2 else { return nil }
            let series = idxs.map { Int(sHR[$0]) }
            let peak = series.first ?? 0
            let endHR = series.min() ?? peak
            // sample ~12 points
            let step = max(series.count / 12, 1)
            let pts = stride(from: 0, to: series.count, by: step).map { series[$0] }
            return RRRecovery(id: s.rep, drop: max(peak - endHR, 0), endHR: endHR, pts: pts)
        }
    }

    // route hr parallel
    private var routeHR: [Int] {
        guard !route.isEmpty else { return [] }
        // map stream HR onto route points by index proportion
        guard !sHR.isEmpty else { return [] }
        return route.indices.map { i in
            let f = Double(i) / Double(max(route.count - 1, 1))
            let j = min(Int(f * Double(sHR.count - 1)), sHR.count - 1)
            return Int(sHR[j])
        }
    }
    private var repStartIdx: [(idx: Int, rep: Int)] {
        guard !route.isEmpty, !sTimes.isEmpty else { return [] }
        return slots.map { s in
            let f = s.start / max(sTimes.last ?? 1, 1)
            return (idx: min(Int(f * Double(route.count - 1)), route.count - 1), rep: s.rep)
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if loaded && reps.isEmpty {
                Text("No rep-level splits for this run — it reads as a steady effort.")
                    .font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary).padding(.vertical, 24)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                header
                heroChart
                statStrip
                theRead
                tweaksRow
                section("TIME IN HR ZONE", value: dominantZone, sub: "DOMINANT") {
                    RRZoneBar(seconds: zoneSeconds, zones: hrZones, mainZone: dominantZone)
                }
                if hasStream {
                    section("HEART RATE · FULL SESSION", value: "\(maxHR)", sub: "MAX") {
                        RRZoneTimeline(times: sTimes, hr: sHR, windows: windows, zones: hrZones)
                    }
                    section("PACE", value: rr_pace(targetSec, km: km), sub: km ? "/KM" : "/MI") {
                        RRPaceTrace(times: sTimes, paceSec: sPace, windows: windows, km: km)
                    }
                    if !sCad.isEmpty {
                        section("CADENCE", value: "\(Int(sCad.reduce(0,+)/Double(max(sCad.count,1))))", sub: "SPM") {
                            RRCadenceStrip(times: sTimes, cadence: sCad)
                        }
                    }
                    if !sAltFt.isEmpty {
                        section("ELEVATION · GRADE", value: "+\(rr_elevGain())", sub: km ? "M" : "FT") {
                            RRElevationGrade(times: sTimes, altFt: sAltFt, grade: sGrade)
                        }
                    }
                    if !recoveries.isEmpty {
                        section("HR RECOVERY · AFTER EACH REP") { RRRecoveryRow(recoveries: recoveries) }
                    }
                }
                splitsSection
                if !route.isEmpty {
                    section("ROUTE") {
                        RRRouteShape(coords: route, hr: routeHR, colorByZone: colorByZone, zones: hrZones, repStartIdx: repStartIdx)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: Sections

    private var header: some View {
        let avgPace = targetSec
        let workMi = reps.compactMap { $0.distance_meters }.reduce(0, +) / mpm
        return VStack(alignment: .leading, spacing: 10) {
            Button { showTypePicker = true } label: {
                HStack(spacing: 6) {
                    Text((workoutType.map(prettyType) ?? "QUALITY").uppercased()).font(.dripStat(10)).tracking(1.3)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.drip.coral).padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.drip.coralWash).clipShape(Capsule()).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .confirmationDialog("Change workout type", isPresented: $showTypePicker, titleVisibility: .visible) {
                ForEach(Self.typeOptions, id: \.self) { t in Button(prettyType(t)) { updateType(t) } }
                Button("Cancel", role: .cancel) {}
            }
            Text(repHeadline).font(.dripDisplay(26)).foregroundStyle(Color.drip.textPrimary)
            if let p = prescription, p.hasContent, let pat = p.pattern, !pat.isEmpty {
                Text("— \(pat) —").font(.dripBody(13)).italic().foregroundStyle(Color.drip.textTertiary)
            }
            _ = avgPace; _ = workMi
        }
    }

    private var heroChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHead("REP BY REP", value: "\(reps.count) REPS", sub: "WORK")
            RRRepBars(reps: rrReps, targetSec: targetSec, colorByZone: colorByZone, heatOn: heatOn, km: km, zones: hrZones)
        }
    }

    private var statStrip: some View {
        let paces = reps.compactMap { $0.avg_pace_sec_per_mile }
        let workMi = reps.compactMap { $0.distance_meters }.reduce(0, +) / mpm
        let hrs = reps.compactMap { $0.avg_heart_rate }
        let spread = (paces.max() ?? 0) - (paces.min() ?? 0)
        let cells: [(String, String, String, Bool)] = [
            ("AVG WORK", rr_pace(heatOn ? targetSec + 8 : targetSec, km: km), km ? "/km" : "/mi", true),
            ("WORK", String(format: "%.1f", km ? workMi * 1.60934 : workMi), km ? "km" : "mi", false),
            ("AVG HR", hrs.isEmpty ? "—" : "\(hrs.reduce(0,+)/hrs.count)", "bpm", false),
            ("SPREAD", "\(Int(spread))", "s", false),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                VStack(spacing: 4) {
                    Text(c.0).font(.dripStat(9)).tracking(1.0).foregroundStyle(Color.drip.textTertiary)
                    (Text(c.1).font(.dripStat(16)).foregroundStyle(c.3 ? Color.drip.coral : Color.drip.textPrimary)
                     + Text(" \(c.2)").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary))
                }
                .frame(maxWidth: .infinity)
                .overlay(i < cells.count - 1 ? AnyView(Rectangle().fill(Color.drip.divider).frame(width: 1).frame(maxHeight: .infinity)) : AnyView(EmptyView()), alignment: .trailing)
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
    }

    private var theRead: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead("THE READ")
            weatherSentence
            if insightLoading {
                HStack(spacing: 8) { ProgressView().tint(Color.drip.coral); Text("Analyzing your workout…").font(.dripBody(14)).foregroundStyle(Color.drip.textSecondary) }
            } else if let ins = insight, ins.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
                Text(ins).font(.dripBody(14)).lineSpacing(3).foregroundStyle(Color.drip.textPrimary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(computedRead).font(.dripBody(14)).lineSpacing(3).foregroundStyle(Color.drip.textPrimary).fixedSize(horizontal: false, vertical: true)
                if workoutId != nil {
                    Button { Task { await generateInsight() } } label: {
                        HStack(spacing: 6) { Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)); Text("Generate AI insight").font(.dripLabel(13)) }
                            .foregroundStyle(Color.drip.coral).padding(.horizontal, 14).padding(.vertical, 9).background(Color.drip.coralWash).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).padding(.top, 2)
                }
            }
            if let err = insightError { Text(err).font(.dripStat(10)).foregroundStyle(Color.drip.struggling) }
        }
    }

    @ViewBuilder private var weatherSentence: some View {
        if let (t, d) = heatConds {
            let cool = rr_pace(targetSec - 8, km: km)
            (Text("Run in ").font(.dripBody(14)).italic().foregroundStyle(Color.drip.textPrimary)
             + Text("\(Int(t))°F").font(.dripBody(14)).foregroundStyle(Color.drip.textPrimary)
             + Text(" with a ").font(.dripBody(14)).italic().foregroundStyle(Color.drip.textPrimary)
             + Text("\(Int(d))° dew point").font(.dripBody(14)).foregroundStyle(Color.drip.coral)
             + Text(heatOn
                    ? " — paces below are heat-adjusted for the air."
                    : " — sticky heat that quietly taxes a threshold effort. In cool air your \(rr_pace(targetSec, km: km)) average is worth about \(cool).")
                .font(.dripBody(14)).italic().foregroundStyle(Color.drip.textPrimary))
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tweaksRow: some View {
        HStack(spacing: 8) {
            chip(heatOn ? "HEAT-ADJ ON" : "HEAT-ADJ", on: heatOn, color: Color.drip.tired) { withAnimation(.easeOut(duration: 0.2)) { heatOn.toggle() } }
                .opacity(heatConds == nil ? 0.4 : 1).disabled(heatConds == nil)
            chip(colorByZone ? "ZONE COLOR" : "ZONE COLOR", on: colorByZone, color: Color.drip.coral) { withAnimation(.easeOut(duration: 0.2)) { colorByZone.toggle() } }
            chip(km ? "KM" : "MI", on: false, color: Color.drip.textSecondary) { withAnimation(.easeOut(duration: 0.2)) { km.toggle() } }
            Spacer()
        }
    }

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHead("SPLITS · VS TARGET", value: rr_pace(rrReps.map(\.paceSec).min() ?? targetSec, km: km), sub: "FASTEST")
            DivergingSplits(reps: rrReps, recoveries: recoveries, targetSec: targetSec, heatOn: heatOn, km: km, colorByZone: colorByZone, zones: hrZones)
        }
    }

    // MARK: Section chrome

    private func sectionHead(_ title: String, value: String? = nil, sub: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.dripStat(10)).tracking(1.1).foregroundStyle(Color.drip.textSecondary)
            Spacer()
            if let v = value {
                (Text(v).font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary)
                 + Text(sub.map { "  \($0)" } ?? "").font(.dripStat(10)).foregroundStyle(Color.drip.textTertiary))
            }
        }
    }
    private func section<Content: View>(_ title: String, value: String? = nil, sub: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { sectionHead(title, value: value, sub: sub); content() }
    }
    private func chip(_ label: String, on: Bool, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.dripStat(9)).tracking(0.8)
                .foregroundStyle(on ? Color.white : color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? color : color.opacity(0.12)).clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Copy helpers

    private var heatConds: (Double, Double)? {
        guard let t = reps.compactMap({ $0.temp_f }).max(),
              let d = reps.compactMap({ $0.dew_point_f }).max(), d >= 55 else { return nil }
        return (t, d)
    }
    private var computedRead: String {
        let n = reps.count
        let avg = rr_pace(targetSec, km: km)
        let spread = Int((reps.compactMap { $0.avg_pace_sec_per_mile }.max() ?? 0) - (reps.compactMap { $0.avg_pace_sec_per_mile }.min() ?? 0))
        return "\(n) reps inside a \(spread)-second spread at \(avg)\(km ? "/km" : "/mi"), HR pinned to \(dominantZone) from the second rep on. Controlled and even — exactly the session you drew up."
    }
    private func prettyType(_ t: String) -> String {
        switch t { case "long_run": return "Long run"; case "intervals", "interval": return "Intervals"; default: return t.prefix(1).uppercased() + t.dropFirst() }
    }
    private func rr_elevGain() -> Int {
        guard sAltFt.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<sAltFt.count { let d = sAltFt[i] - sAltFt[i - 1]; if d > 0 { gain += d } }
        return Int((km ? gain * 0.3048 : gain).rounded())
    }
    private var repHeadline: String {
        if reps.isEmpty { return "—" }
        let labels = reps.map { rr_repLabel($0.distance_meters ?? 0) }
        if Set(labels).count == 1 { return "\(reps.count)×\(labels[0])" }
        return labels.count <= 8 ? labels.joined(separator: "·") : "\(reps.count) reps"
    }

    // MARK: Loading

    private func updateType(_ t: String) {
        workoutType = t
        guard let workoutId else { return }
        Task { await WorkoutLapsService.setType(workoutId: workoutId, type: t) }
    }

    @MainActor private func generateInsight() async {
        guard let workoutId else { return }
        insightLoading = true; insightError = nil
        struct Req: Encodable { let training_log_id: String }
        struct Resp: Decodable { let insight: String?; let error: String? }
        do {
            let resp: Resp = try await supabase.functions.invoke("generate-workout-insight", options: .init(body: Req(training_log_id: workoutId.uuidString)))
            let text = resp.insight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { insight = text } else { insightError = resp.error ?? "Couldn't generate insight. Try again." }
        } catch { insightError = "Couldn't reach the coach. Try again."; Log.coach.error("generateInsight failed: \(error)") }
        insightLoading = false
    }

    private func load() async {
        if let injectedLaps {
            laps = injectedLaps; zones = injectedZones ?? .none; loaded = true; return
        }
        guard let workoutId else { loaded = true; return }
        async let l = WorkoutLapsService.fetchLaps(workoutId: workoutId)
        async let pr = WorkoutLapsService.fetchParsedReps(workoutId: workoutId)
        async let z = WorkoutLapsService.fetchZones()
        async let ins = WorkoutLapsService.fetchInsight(workoutId: workoutId)
        async let ty = WorkoutLapsService.fetchType(workoutId: workoutId)
        async let pre = WorkoutLapsService.fetchPrescription(workoutId: workoutId)
        async let bundle = ExternalStreamAdapter.load(forTrainingLogId: workoutId)

        let lapRows = await l
        let parsed = await pr
        let parsedWork = parsed.laps.filter { $0.is_rest != true }.count
        laps = parsedWork >= 2 ? parsed.laps : lapRows
        parsedIntent = parsed.intentPattern
        zones = await z; insight = await ins; workoutType = await ty
        var pre2 = await pre
        if let ip = parsed.intentPattern, !ip.isEmpty { pre2.pattern = ip }
        prescription = pre2

        if let b = await bundle {
            stream = b.stream
            route = b.route.map { $0.coordinate }
            streamMaxHR = b.meta.maxHr
            if heatConds != nil { heatOn = false }
        }
        loaded = true
    }
}

// MARK: - Diverging splits table (vs target pace)

struct DivergingSplits: View {
    let reps: [RRRep]
    let recoveries: [RRRecovery]
    let targetSec: Double
    let heatOn: Bool
    let km: Bool
    let colorByZone: Bool
    let zones: [RRZone]

    private let dev = 14.0   // ± sec mapped to half the bar

    var body: some View {
        let fastest = reps.map(\.paceSec).min() ?? targetSec
        VStack(spacing: 0) {
            // header
            HStack(spacing: 8) {
                Text("#").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(width: 16, alignment: .trailing)
                Text("REP").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(width: 30, alignment: .leading)
                Text("◂ SLOW · FAST ▸").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(maxWidth: .infinity)
                Text("PACE").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(width: 48, alignment: .trailing)
                Text("Δ").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(width: 34, alignment: .trailing)
                Text("HR").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(width: 30, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)

            ForEach(reps) { r in
                let pace = heatOn ? (r.adjPaceSec ?? r.paceSec) : r.paceSec
                let delta = Int((pace - targetSec).rounded())
                let faster = delta <= 0
                let mag = min(1.0, abs(Double(delta)) / dev)
                let isFast = r.paceSec == fastest
                let col = colorByZone ? rr_zoneColor(r.hr, zones) : (faster ? Color.drip.coral : Color.drip.textSecondary)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("\(r.id)").font(.dripStat(9)).foregroundStyle(isFast ? Color.drip.coral : Color.drip.textTertiary).frame(width: 16, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.label).font(.dripStat(11)).foregroundStyle(Color.drip.textPrimary)
                            Text(rr_dist(r.distMi, km: km)).font(.dripStat(7.5)).foregroundStyle(Color.drip.textTertiary)
                        }.frame(width: 30, alignment: .leading)
                        // diverging bar
                        GeometryReader { geo in
                            let half = geo.size.width / 2
                            ZStack(alignment: .center) {
                                Rectangle().fill(Color.drip.textTertiary.opacity(0.5)).frame(width: 1, height: 14)
                                Rectangle().fill(col).opacity(colorByZone ? 0.9 : (faster ? 1 : 0.6))
                                    .frame(width: CGFloat(mag) * half, height: 6)
                                    .offset(x: faster ? CGFloat(mag) * half / 2 : -CGFloat(mag) * half / 2)
                            }
                            .frame(width: geo.size.width, height: 14)
                        }.frame(height: 14).frame(maxWidth: .infinity)
                        Text(rr_pace(pace, km: km)).font(.dripStat(13)).foregroundStyle(isFast ? Color.drip.coral : Color.drip.textPrimary).frame(width: 48, alignment: .trailing)
                        Text(delta == 0 ? "—" : "\(faster ? "−" : "+")\(abs(delta))s").font(.dripStat(10)).foregroundStyle(faster ? Color.drip.energized : Color.drip.textTertiary).frame(width: 34, alignment: .trailing)
                        Text(r.hr.map(String.init) ?? "—").font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary).frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                    // rest interstitial
                    if let rest = r.restSec {
                        HStack(spacing: 7) {
                            Rectangle().fill(Color.drip.textTertiary.opacity(0.4)).frame(width: 18, height: 1)
                            Text("REST \(rest)s · JOG").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary)
                            if let rec = recoveries.first(where: { $0.id == r.id }) {
                                Text("· HR −\(rec.drop) → \(rec.endHR)").font(.dripStat(8)).foregroundStyle(Color.drip.energized)
                            }
                            Spacer()
                        }
                        .padding(.leading, 18).padding(.bottom, 6)
                        .overlay(Rectangle().fill(Color.drip.divider).frame(height: 1), alignment: .bottom)
                    }
                }
            }

            // totals footer
            let totDist = reps.reduce(0.0) { $0 + $1.distMi }
            let avgHr = reps.compactMap(\.hr).isEmpty ? 0 : reps.compactMap(\.hr).reduce(0,+) / reps.compactMap(\.hr).count
            HStack(spacing: 8) {
                Text("").frame(width: 16)
                Text("ALL").font(.dripStat(9)).foregroundStyle(Color.drip.textPrimary).frame(width: 30, alignment: .leading)
                Text("\(rr_dist(totDist, km: km)) WORK · \(reps.count) REPS").font(.dripStat(9)).foregroundStyle(Color.drip.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
                Text(rr_pace(targetSec, km: km)).font(.dripStat(13)).foregroundStyle(Color.drip.coral).frame(width: 48, alignment: .trailing)
                Text("AVG").font(.dripStat(8)).foregroundStyle(Color.drip.textTertiary).frame(width: 34, alignment: .trailing)
                Text("\(avgHr)").font(.dripStat(11)).foregroundStyle(Color.drip.textSecondary).frame(width: 30, alignment: .trailing)
            }
            .padding(.top, 9)
        }
    }
}

/// Compact distance label ("2K" / "1K" / "1mi" / "800m").
func rr_repLabel(_ meters: Double) -> String {
    let mpm = 1609.344
    let miles = meters / mpm
    if abs(miles - miles.rounded()) / max(miles, 1) < 0.08, miles >= 1 { return "\(Int(miles.rounded()))mi" }
    for r in [400.0, 600, 800, 1000, 1200, 1600, 2000, 3000] where abs(meters - r) / r < 0.08 {
        return r.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(r / 1000))K" : "\(Int(r))m"
    }
    return "\(Int((meters / 100).rounded() * 100))m"
}

// MARK: - Preview

#Preview {
    func lap(_ i: Int, _ m: Double, _ s: Int, _ p: Double, _ hr: Int, _ rest: Bool = false, _ t: Double = 74, _ dew: Double = 66, _ adj: Double? = nil) -> WorkoutLapRow {
        WorkoutLapRow(lap_index: i, distance_meters: m, moving_time_seconds: s, avg_pace_sec_per_mile: p, avg_heart_rate: hr, is_rest: rest, temp_f: t, dew_point_f: dew, heat_adjusted_pace_sec_per_mile: adj)
    }
    let laps: [WorkoutLapRow] = [
        lap(0, 1609, 480, 480, 132),
        lap(1, 2000, 395, 318, 168, false, 74, 66, 326),
        lap(2, 220, 80, 1900, 150, true),
        lap(3, 1000, 194, 312, 174, false, 74, 66, 320),
        lap(4, 210, 80, 1900, 148, true),
        lap(5, 1000, 194, 312, 175, false, 74, 66, 320),
        lap(6, 210, 80, 1900, 150, true),
        lap(7, 2000, 399, 321, 175, false, 74, 66, 329),
        lap(8, 210, 80, 1900, 150, true),
        lap(9, 1000, 193, 310, 175, false, 74, 66, 318),
        lap(10, 210, 80, 1900, 150, true),
        lap(11, 1000, 195, 314, 175, false, 74, 66, 322),
        lap(12, 1300, 560, 560, 120),
    ]
    let zones = RepChartZones(fiveK: 300, tenK: 312, threshold: 326)
    return ScrollView {
        WorkoutRepReceiptView(laps: laps, zones: zones).padding(20)
    }
    .background(Color.drip.background.ignoresSafeArea())
}
