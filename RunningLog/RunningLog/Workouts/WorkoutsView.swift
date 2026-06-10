import CoreLocation
import HealthKit
import Supabase
import SwiftUI

// MARK: - WorkoutsView

struct WorkoutsView: View {
    @Environment(VitalManager.self) private var vitalManager
    @State private var isLoading = false
    @State private var selectedWorkout: RunningWorkout?
    @State private var showManualEntry = false
    @State private var syncService = WorkoutSyncService()

    var body: some View {
        ZStack {
            DripBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Header Stats
                    if !vitalManager.recentWorkouts.isEmpty {
                        WeeklyStatsHeader(workouts: vitalManager.recentWorkouts)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    // Workouts list
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader("Recent Runs", action: refreshWorkouts, actionIcon: "arrow.clockwise")
                            .padding(.horizontal, 20)

                        if isLoading {
                            VStack(spacing: 16) {
                                ForEach(0 ..< 3, id: \.self) { _ in
                                    WorkoutCardSkeleton()
                                }
                            }
                            .padding(.horizontal, 20)
                        } else if vitalManager.recentWorkouts.isEmpty {
                            EmptyWorkoutsView()
                                .padding(.horizontal, 20)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(vitalManager.recentWorkouts) { workout in
                                    WorkoutCard(workout: workout)
                                        .onTapGesture {
                                            selectedWorkout = workout
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Manual entry button
                    ManualEntryButton {
                        showManualEntry = true
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 40)
                }
            }
            .refreshable {
                await loadWorkouts()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SidebarMenuButton()
            }
            ToolbarItem(placement: .principal) {
                Text("WORKOUTS")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManualEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .toolbarBackground(Color.drip.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            Task { await loadWorkouts() }
        }
        .sheet(item: $selectedWorkout) { workout in
            if let vitalId = workout.vitalWorkoutId {
                VitalWorkoutDetailView(workout: workout, vitalWorkoutId: vitalId)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            } else {
                WorkoutDetailSheet(workout: workout)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualWorkoutView()
        }
    }

    private func refreshWorkouts() {
        Task { await loadWorkouts() }
    }

    private func loadWorkouts() async {
        await MainActor.run { isLoading = true }
        let workouts = await vitalManager.fetchRecentRunningWorkouts(limit: 30)
        await MainActor.run {
            vitalManager.recentWorkouts = workouts
            isLoading = false
        }
        // Auto-sync unlogged workouts to training_logs for analysis
        await syncService.syncUnloggedWorkouts(workouts: workouts)
    }
}

// MARK: - WeeklyStatsHeader

struct WeeklyStatsHeader: View {
    let workouts: [RunningWorkout]

    var thisWeekWorkouts: [RunningWorkout] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let startOfWeek = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date ?? Date()
        return workouts.filter { $0.startDate >= startOfWeek }
    }

    var totalMiles: Double {
        thisWeekWorkouts.reduce(0) { $0 + $1.distanceMiles }
    }

    var totalRuns: Int {
        thisWeekWorkouts.count
    }

    var avgPace: Double {
        let totalTime = thisWeekWorkouts.reduce(0) { $0 + $1.durationMinutes }
        let totalDist = thisWeekWorkouts.reduce(0) { $0 + $1.distanceMiles }
        return totalDist > 0 ? totalTime / totalDist : 0
    }

    // Negative Splits redesign: drop the peachy gradient card; replace
    // with a hairline-divided three-stat strip (display serif numerals,
    // mono caps labels). Same data, less chrome.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NSEyebrow("THIS WEEK")
            NSHairline()
            NSStatStrip(items: [
                .init(label: "DISTANCE",
                      value: String(format: "%.1f", totalMiles),
                      unit: "MILES"),
                .init(label: "RUNS",
                      value: "\(totalRuns)",
                      unit: totalRuns == 1 ? "RUN" : "RUNS"),
                .init(label: "AVG PACE",
                      value: avgPace > 0 ? formatPace(avgPace) : "—",
                      unit: avgPace > 0 ? "/ MI" : "TBD"),
            ])
            NSHairline()
        }
        .padding(.vertical, 8)
    }

    private func formatPace(_ pace: Double) -> String {
        guard pace > 0 else { return "--:--" }
        return PaceCalculator.formatPaceFromMinutes(pace)
    }
}

// MARK: - WeeklyStatCard

struct WeeklyStatCard: View {
    let value: String
    let unit: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.drip.coral)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.dripStat(22))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(unit)
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            Text(label)
                .font(.dripCaption(10))
                .foregroundStyle(Color.drip.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pace Zone

enum PaceZone: Int, CaseIterable, Comparable {
    case easy = 0
    case moderate = 1
    case steady = 2
    case mp = 3
    case hmp = 4
    case tenK = 5
    case fiveK = 6
    case threeK = 7
    case mile = 8

    static func < (lhs: PaceZone, rhs: PaceZone) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Mod"
        case .steady: return "Steady"
        case .mp: return "MP"
        case .hmp: return "HMP"
        case .tenK: return "10K"
        case .fiveK: return "5K"
        case .threeK: return "3K"
        case .mile: return "Mile"
        }
    }

    var color: Color {
        switch self {
        case .easy: return Color.drip.positive
        case .moderate: return Color.drip.positive.opacity(0.7)
        case .steady: return Color.drip.coral.opacity(0.5)
        case .mp: return Color.drip.coral.opacity(0.65)
        case .hmp: return Color.drip.coral.opacity(0.8)
        case .tenK: return Color.drip.coral
        case .fiveK: return Color.drip.tired.opacity(0.8)
        case .threeK: return Color.drip.tired
        case .mile: return Color.drip.injured
        }
    }

    /// Classify a velocity (m/s) into a pace zone using EquivalentPaces.
    /// Zones are ranges on a spectrum — each named pace marks where the NEXT zone begins.
    /// Anything between two named paces belongs to the slower zone.
    /// e.g., anything slower than moderatePace is easy, anything between
    /// moderatePace and steadyPace is moderate, etc.
    static func from(velocity: Double, paces: EquivalentPaces? = nil) -> PaceZone {
        let mileInMeters = 1609.34
        guard velocity > 0.5 else { return .easy }
        let paceSecPerMile = mileInMeters / velocity // seconds per mile

        guard let p = paces else {
            return .easy
        }

        // Each named pace is the boundary where the next faster zone starts.
        // Pace is in sec/mi (higher = slower), so we check descending.
        // slower than moderatePace → easy
        // moderatePace to steadyPace → moderate
        // steadyPace to mpPace → steady
        // mpPace to hmPace → mp
        // etc.
        if paceSecPerMile > p.moderatePace { return .easy }
        if paceSecPerMile > p.steadyPace { return .moderate }
        if paceSecPerMile > p.mpPace { return .steady }
        if paceSecPerMile > p.hmPace { return .mp }
        if paceSecPerMile > p.tenKPace { return .hmp }
        if paceSecPerMile > p.fiveKPace { return .tenK }
        if paceSecPerMile > p.threeKPace { return .fiveK }
        if paceSecPerMile > p.milePace { return .threeK }
        return .mile
    }
}

// MARK: - Marathon Pace Zone (%MP breakdown)

enum MPZone: Int, CaseIterable {
    case seventy = 0     // ≤70% MP
    case eighty = 1      // ~80% MP
    case ninety = 2      // 90-95% MP
    case mp = 3          // 95-105% MP
    case fast = 4        // 105-110% MP
    case veryFast = 5    // >110% MP

    var label: String {
        switch self {
        case .seventy: return "<75%"
        case .eighty: return "75-85%"
        case .ninety: return "85-95%"
        case .mp: return "95-105%"
        case .fast: return "105%+"
        case .veryFast: return "110%+"
        }
    }

    var color: Color {
        switch self {
        case .seventy: return Color.drip.positive.opacity(0.5)
        case .eighty: return Color.drip.positive
        case .ninety: return Color.drip.coral.opacity(0.6)
        case .mp: return Color.drip.coral
        case .fast: return Color.drip.tired
        case .veryFast: return Color.drip.injured
        }
    }

    /// Classify velocity (m/s) into %MP zone given marathon pace in sec/mi
    static func from(velocity: Double, mpPaceSecPerMile: Double) -> MPZone {
        let mileInMeters = 1609.34
        guard velocity > 0.5 else { return .seventy }
        let paceSecPerMile = mileInMeters / velocity
        // %MP = mpPace / actualPace (faster pace = higher %)
        let pctMP = mpPaceSecPerMile / paceSecPerMile
        switch pctMP {
        case ..<0.75: return .seventy
        case ..<0.85: return .eighty     // 75-85%
        case ..<0.95: return .ninety     // 85-95%
        case ..<1.05: return .mp         // 95-105% → MP
        case ..<1.10: return .fast       // 105-110%
        default: return .veryFast        // >110%
        }
    }
}

// MARK: - Training Effort Chart (Zone Volume Distribution)

enum EffortTimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case custom = "Custom"
}

enum ChartMode: String, CaseIterable {
    case zones = "Zones"
    case marathon = "% MP"
}

struct TrainingEffortChart: View {
    @Environment(VitalManager.self) private var vitalManager
    let workouts: [RunningWorkout]
    var equivalentPaces: EquivalentPaces?

    @State private var zoneVolumes: [PaceZone: Double] = [:]
    @State private var mpVolumes: [MPZone: Double] = [:]
    @State private var isLoading = true
    @State private var selectedRange: EffortTimeRange = .week
    @State private var chartMode: ChartMode = .zones
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var showDatePicker = false
    @State private var resolvedPaces: EquivalentPaces?

    private var filteredWorkouts: [RunningWorkout] {
        let now = Date()
        let start: Date
        let end: Date

        switch selectedRange {
        case .week:
            var calendar = Calendar.current
            calendar.firstWeekday = 2
            start = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now).date ?? now
            end = now
        case .month:
            start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            end = now
        case .custom:
            start = Calendar.current.startOfDay(for: customStart)
            end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd)) ?? now
        }
        return workouts.filter { $0.startDate >= start && $0.startDate <= end }
    }

    private var maxZoneMiles: Double {
        switch chartMode {
        case .zones: return max(zoneVolumes.values.max() ?? 1, 0.1)
        case .marathon: return max(mpVolumes.values.max() ?? 1, 0.1)
        }
    }

    private var totalMiles: Double {
        switch chartMode {
        case .zones: return zoneVolumes.values.reduce(0, +)
        case .marathon: return mpVolumes.values.reduce(0, +)
        }
    }

    private var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        switch selectedRange {
        case .week:
            var calendar = Calendar.current
            calendar.firstWeekday = 2
            let start = calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: Date()).date ?? Date()
            return "\(fmt.string(from: start)) – \(fmt.string(from: Date()))"
        case .month:
            let start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return "\(fmt.string(from: start)) – \(fmt.string(from: Date()))"
        case .custom:
            return "\(fmt.string(from: customStart)) – \(fmt.string(from: customEnd))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartHeader
            dateSubtitle
            if selectedRange == .custom && showDatePicker {
                customDatePickers
            }
            if isLoading {
                loadingIndicator
            } else {
                switch chartMode {
                case .zones: zoneBarChart
                case .marathon: mpBarChart
                }
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .task { await loadEffortData() }
        .onChange(of: selectedRange) { Task { await loadEffortData() } }
        .onChange(of: customStart) { Task { await loadEffortData() } }
        .onChange(of: customEnd) { Task { await loadEffortData() } }
        .onChange(of: equivalentPaces?.mpPace) { Task { await loadEffortData() } }
    }

    private var chartHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("TRAINING VOLUME")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()
                rangePicker
            }
            HStack(spacing: 0) {
                ForEach(ChartMode.allCases, id: \.rawValue) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { chartMode = mode }
                    } label: {
                        chartModeLabel(mode)
                    }
                }
                Spacer()
            }
        }
    }

    private func chartModeLabel(_ mode: ChartMode) -> some View {
        let isSelected = chartMode == mode
        return Text(mode.rawValue)
            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Color.drip.textPrimary : Color.drip.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.drip.divider.opacity(0.5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(EffortTimeRange.allCases, id: \.rawValue) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRange = range
                        if range == .custom { showDatePicker = true }
                    }
                } label: {
                    rangeButtonLabel(range)
                }
            }
        }
        .fixedSize()
    }

    private func rangeButtonLabel(_ range: EffortTimeRange) -> some View {
        let isSelected = selectedRange == range
        return Text(range.rawValue)
            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Color.drip.coral : Color.drip.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.drip.coral.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var dateSubtitle: some View {
        HStack {
            Text(dateRangeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.drip.textTertiary)
            Spacer()
            Text(String(format: "%.1f mi total", totalMiles))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.drip.textSecondary)
        }
    }

    private var customDatePickers: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FROM")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(0.8)
                DatePicker("", selection: $customStart, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Color.drip.coral)
                    .scaleEffect(0.85, anchor: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TO")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                    .tracking(0.8)
                DatePicker("", selection: $customEnd, displayedComponents: .date)
                    .labelsHidden()
                    .tint(Color.drip.coral)
                    .scaleEffect(0.85, anchor: .leading)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var loadingIndicator: some View {
        HStack {
            Spacer()
            ProgressView().tint(Color.drip.coral)
            Spacer()
        }
        .frame(height: 140)
    }

    @State private var expandedZone: PaceZone?
    @State private var expandedMpZone: MPZone?

    private var zoneBarChart: some View {
        let activeZones = PaceZone.allCases.filter { (zoneVolumes[$0] ?? 0) > 0.01 }
        return VStack(spacing: 6) {
            ForEach(activeZones, id: \.rawValue) { zone in
                let miles = zoneVolumes[zone] ?? 0
                let pct = totalMiles > 0 ? miles / totalMiles * 100 : 0
                let isExpanded = expandedZone == zone
                zoneRow(
                    label: zone.label,
                    miles: miles,
                    pct: pct,
                    color: zone.color,
                    isExpanded: isExpanded,
                    paceRange: zonePaceRange(zone)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedZone = expandedZone == zone ? nil : zone
                    }
                }
            }
            if activeZones.isEmpty {
                Text("No data for this period")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private var mpBarChart: some View {
        let activeZones = MPZone.allCases.filter { (mpVolumes[$0] ?? 0) > 0.01 }
        let mpTotal = mpVolumes.values.reduce(0, +)
        return VStack(spacing: 6) {
            ForEach(activeZones, id: \.rawValue) { zone in
                let miles = mpVolumes[zone] ?? 0
                let pct = mpTotal > 0 ? miles / mpTotal * 100 : 0
                zoneRow(
                    label: zone.label,
                    miles: miles,
                    pct: pct,
                    color: zone.color,
                    isExpanded: expandedMpZone == zone,
                    paceRange: mpZonePaceRange(zone)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedMpZone = expandedMpZone == zone ? nil : zone
                    }
                }
            }
        }
    }

    private func zoneRow(label: String, miles: Double, pct: Double, color: Color, isExpanded: Bool, paceRange: String?, action: @escaping () -> Void) -> some View {
        let barFraction = totalMiles > 0 ? CGFloat(miles / maxZoneMiles) : 0

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 50, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: max(barFraction * geo.size.width, 4))
                    }
                    .frame(height: isExpanded ? 28 : 20)

                    Text(String(format: "%.1fmi", miles))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.drip.textPrimary)
                        .frame(width: 52, alignment: .trailing)
                        .lineLimit(1)

                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.drip.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                        .lineLimit(1)
                }

                if isExpanded {
                    expandedDetail(miles: miles, pct: pct, color: color, paceRange: paceRange)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func expandedDetail(miles: Double, pct: Double, color: Color, paceRange: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(color.opacity(0.3))
                .padding(.vertical, 4)

            // Pace range
            if let range = paceRange {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                    Text(range)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            // Duration estimate (rough: miles * avg pace)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(String(format: "%.1f miles  ·  %.0f%% of volume", miles, pct))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textSecondary)
            }

            // Visual proportion bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.drip.divider.opacity(0.3))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.4))
                        .frame(width: totalMiles > 0 ? CGFloat(pct / 100) * geo.size.width : 0)
                }
            }
            .frame(height: 6)
        }
        .padding(.leading, 58)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func zonePaceRange(_ zone: PaceZone) -> String? {
        guard let p = equivalentPaces ?? resolvedPaces else { return nil }
        let fmt = { (s: Double) -> String in
            let m = Int(s) / 60; let sec = Int(s) % 60
            return String(format: "%d:%02d", m, sec)
        }
        switch zone {
        case .easy: return "Slower than \(fmt(p.moderatePace))/mi"
        case .moderate: return "\(fmt(p.steadyPace)) – \(fmt(p.moderatePace))/mi"
        case .steady: return "\(fmt(p.mpPace)) – \(fmt(p.steadyPace))/mi"
        case .mp: return "\(fmt(p.hmPace)) – \(fmt(p.mpPace))/mi"
        case .hmp: return "\(fmt(p.tenKPace)) – \(fmt(p.hmPace))/mi"
        case .tenK: return "\(fmt(p.fiveKPace)) – \(fmt(p.tenKPace))/mi"
        case .fiveK: return "\(fmt(p.threeKPace)) – \(fmt(p.fiveKPace))/mi"
        case .threeK: return "\(fmt(p.milePace)) – \(fmt(p.threeKPace))/mi"
        case .mile: return "Faster than \(fmt(p.milePace))/mi"
        }
    }

    private func mpZonePaceRange(_ zone: MPZone) -> String? {
        guard let p = equivalentPaces ?? resolvedPaces else { return nil }
        let mp = p.mpPace // seconds per mile
        let fmt = { (s: Double) -> String in
            let m = Int(s) / 60; let sec = Int(s) % 60
            return String(format: "%d:%02d", m, sec)
        }
        // %MP = mpPace / actualPace → actualPace = mpPace / %MP
        // Higher %MP = faster pace = lower sec/mi
        switch zone {
        case .seventy: return "Slower than \(fmt(mp / 0.75))/mi"
        case .eighty: return "\(fmt(mp / 0.85)) – \(fmt(mp / 0.75))/mi"
        case .ninety: return "\(fmt(mp / 0.95)) – \(fmt(mp / 0.85))/mi"
        case .mp: return "\(fmt(mp / 1.05)) – \(fmt(mp / 0.95))/mi  (MP \(fmt(mp)))"
        case .fast: return "\(fmt(mp / 1.10)) – \(fmt(mp / 1.05))/mi"
        case .veryFast: return "Faster than \(fmt(mp / 1.10))/mi"
        }
    }

    private func loadEffortData() async {
        await MainActor.run { isLoading = true }

        var volumes: [PaceZone: Double] = [:]
        var mpVols: [MPZone: Double] = [:]

        // Step 1: Determine pace zones — priority: passed-in paces > fitness snapshot > derived
        let effectivePaces: EquivalentPaces? = await resolvePaces()
        let effectiveMpPace = effectivePaces?.mpPace ?? 360

        // Fetch training_logs with pace_segments for the date range
        let segmentLookup = await fetchPaceSegments()

        // Debug
        let fmt = { (s: Double) -> String in String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
        if let ep = effectivePaces {
            print("[EffortChart] easy: \(fmt(ep.easyPace)), mod: \(fmt(ep.moderatePace)), steady: \(fmt(ep.steadyPace)), MP: \(fmt(ep.mpPace))")
        } else {
            print("[EffortChart] NO paces — all easy")
        }

        for workout in filteredWorkouts {
            let expectedMiles = workout.distanceMiles
            let avgVelocity = workoutVelocity(workout)
            let avgZone = PaceZone.from(velocity: avgVelocity, paces: effectivePaces)
            let avgMpZone = MPZone.from(velocity: avgVelocity, mpPaceSecPerMile: effectiveMpPace)

            // Check if we have stored pace_segments for this workout
            if let segments = matchSegments(for: workout, in: segmentLookup), !segments.isEmpty {
                var segZoneVols: [PaceZone: Double] = [:]
                var segMpVols: [MPZone: Double] = [:]
                var segTotal = 0.0
                print("[EffortChart] \(String(format: "%.1f", expectedMiles))mi workout — \(segments.count) segments:")
                for seg in segments {
                    let velocity = velocityFromPaceString(seg.pacePerMile)
                    let zone = PaceZone.from(velocity: velocity, paces: effectivePaces)
                    print("  \(seg.effort) \(String(format: "%.2f", seg.distanceMiles))mi @ \(seg.pacePerMile) → \(zone.label)")
                    segZoneVols[zone, default: 0] += seg.distanceMiles
                    let mpZone = MPZone.from(velocity: velocity, mpPaceSecPerMile: effectiveMpPace)
                    segMpVols[mpZone, default: 0] += seg.distanceMiles
                    segTotal += seg.distanceMiles
                }
                // Scale proportionally so total matches expectedMiles
                let scale = segTotal > 0.01 ? expectedMiles / segTotal : 1.0
                for (zone, vol) in segZoneVols { volumes[zone, default: 0] += vol * scale }
                for (zone, vol) in segMpVols { mpVols[zone, default: 0] += vol * scale }
                continue
            }

            // No stored segments — fetch Vital stream, extract segments, classify, and save
            let avgPaceFmt = avgVelocity > 0 ? String(format: "%d:%02d", Int(1609.34 / avgVelocity) / 60, Int(1609.34 / avgVelocity) % 60) : "?"
            guard let vitalId = workout.vitalWorkoutId else {
                print("[EffortChart] \(String(format: "%.1f", expectedMiles))mi workout — no segments, no vitalId, avg \(avgPaceFmt) → \(avgZone.label)")
                volumes[avgZone, default: 0] += expectedMiles
                mpVols[avgMpZone, default: 0] += expectedMiles
                continue
            }

            if let stream = await vitalManager.fetchWorkoutStream(workoutId: vitalId),
               let velocities = stream.velocitySmooth,
               let distances = stream.distance,
               velocities.count == distances.count, velocities.count > 10 {

                // Use per-second velocity for granular zone classification
                var streamZoneVols: [PaceZone: Double] = [:]
                var streamMpVols: [MPZone: Double] = [:]
                var streamTotal = 0.0
                let mileInMeters = 1609.34
                for i in 1..<distances.count {
                    let segDist = (distances[i] - distances[i - 1]) / mileInMeters
                    guard segDist > 0 && segDist < 0.1 else { continue }
                    let v = velocities[i]
                    streamZoneVols[PaceZone.from(velocity: v, paces: effectivePaces), default: 0] += segDist
                    streamMpVols[MPZone.from(velocity: v, mpPaceSecPerMile: effectiveMpPace), default: 0] += segDist
                    streamTotal += segDist
                }
                let scale = streamTotal > 0.01 ? expectedMiles / streamTotal : 1.0
                for (zone, vol) in streamZoneVols { volumes[zone, default: 0] += vol * scale }
                for (zone, vol) in streamMpVols { mpVols[zone, default: 0] += vol * scale }

                // Extract pace segments from stream and save to DB for future use
                Task.detached {
                    await self.extractAndSavePaceSegments(
                        stream: stream, workout: workout,
                        paces: effectivePaces, vitalManager: vitalManager
                    )
                }
            } else {
                volumes[avgZone, default: 0] += expectedMiles
                mpVols[avgMpZone, default: 0] += expectedMiles
            }
        }

        await MainActor.run {
            zoneVolumes = volumes
            mpVolumes = mpVols
            resolvedPaces = effectivePaces
            isLoading = false
        }
    }

    /// Resolve pace zones: passed-in paces > fitness snapshot > pace chart goal > fitness predictor > derived
    private func resolvePaces() async -> EquivalentPaces? {
        // 1. Use passed-in paces (from training plan or parent view)
        if let paces = equivalentPaces { return paces }

        // 2. Query fitness snapshot directly
        if let snapshotPaces = await loadFitnessSnapshotPaces() { return snapshotPaces }

        // 3. Use the Pace Chart's saved goal (user has explicitly set this)
        if let paceChartPaces = loadPaceChartGoal() {
            // Trigger fitness predictor in background so a snapshot exists next time
            Task.detached { await self.triggerFitnessSnapshot() }
            return paceChartPaces
        }

        // 4. Run fitness predictor to generate a snapshot
        if let predictorPaces = await runFitnessPredictorForPaces() { return predictorPaces }

        // 5. Fall back to deriving from workout history
        return derivePacesFromWorkouts(workouts)
    }

    /// Load pace zones from the athlete's pace profile — the single source of
    /// truth for goal race distance + target time (superseded the old
    /// paceChart_* UserDefaults keys in adaptive-plan-1.9).
    private func loadPaceChartGoal() -> EquivalentPaces? {
        guard let profile = AthletePaceProfileService.shared.profile,
              let distRaw = profile.goalRaceDistance,
              let seconds = profile.goalTimeSeconds,
              seconds > 0 else { return nil }

        let distMap: [String: RaceDistance] = [
            "marathon": .marathon, "half": .halfMarathon,
            "10K": .tenK, "5K": .fiveK, "mile": .mile1500,
        ]
        guard let distance = distMap[distRaw] else { return nil }
        return EquivalentPaces(raceDistance: distance, goalTimeSeconds: seconds)
    }

    /// Trigger the fitness predictor to generate and save a snapshot for future use.
    private func triggerFitnessSnapshot() async {
        let predictor = FitnessPredictorService()
        await predictor.predictFitness(plan: nil)
    }

    /// Run the fitness predictor inline and convert its predictions to EquivalentPaces.
    private func runFitnessPredictorForPaces() async -> EquivalentPaces? {
        let predictor = FitnessPredictorService()
        await predictor.predictFitness(plan: nil)

        guard let prediction = predictor.predictions else { return nil }
        let pace10k = prediction.estimated10kPaceSeconds
        guard pace10k > 0 else { return nil }

        let tenKSeconds = Int(pace10k * 6.21371)
        guard tenKSeconds > 0 else { return nil }
        print("[EffortChart] Using fitness predictor: 10K = \(tenKSeconds)s")
        return EquivalentPaces(raceDistance: .tenK, goalTimeSeconds: tenKSeconds)
    }

    /// Load pace zones directly from the most recent fitness snapshot race predictions.
    /// Uses the best available prediction (half > 10K > marathon > 5K > mile).
    private func loadFitnessSnapshotPaces() async -> EquivalentPaces? {
        do {
            struct SnapRow: Codable {
                let predictedMileSeconds: Int?
                let predicted5kSeconds: Int?
                let predicted10kSeconds: Int?
                let predictedHalfSeconds: Int?
                let predictedMarathonSeconds: Int?
                enum CodingKeys: String, CodingKey {
                    case predictedMileSeconds = "predicted_mile_seconds"
                    case predicted5kSeconds = "predicted_5k_seconds"
                    case predicted10kSeconds = "predicted_10k_seconds"
                    case predictedHalfSeconds = "predicted_half_seconds"
                    case predictedMarathonSeconds = "predicted_marathon_seconds"
                }
            }
            let rows: [SnapRow] = try await supabase
                .from("fitness_snapshots")
                .select("predicted_mile_seconds, predicted_5k_seconds, predicted_10k_seconds, predicted_half_seconds, predicted_marathon_seconds")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let snap = rows.first else { return nil }

            // Use the best available prediction — prefer half/10K as most reliable
            let candidates: [(RaceDistance, Int?)] = [
                (.halfMarathon, snap.predictedHalfSeconds),
                (.tenK, snap.predicted10kSeconds),
                (.marathon, snap.predictedMarathonSeconds),
                (.fiveK, snap.predicted5kSeconds),
                (.mile1500, snap.predictedMileSeconds),
            ]

            for (distance, seconds) in candidates {
                if let s = seconds, s > 0 {
                    let fmt = { (t: Int) -> String in
                        let m = t / 60; let sec = t % 60
                        return String(format: "%d:%02d", m, sec)
                    }
                    print("[EffortChart] Using fitness snapshot: \(distance) = \(fmt(s))")
                    return EquivalentPaces(raceDistance: distance, goalTimeSeconds: s)
                }
            }
        } catch {
            print("[EffortChart] Fitness snapshot query failed: \(error.localizedDescription)")
        }
        return nil
    }

    /// Fetch training_logs with pace_segments for matching against workouts
    private func fetchPaceSegments() async -> [TrainingLog] {
        do {
            let cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            let logs: [TrainingLog] = try await supabase
                .from("training_logs")
                .select()
                .gte("workout_date", value: ISO8601DateFormatter().string(from: cutoff))
                .not("pace_segments", operator: .is, value: "null")
                .execute()
                .value
            return logs
        } catch {
            print("[EffortChart] Failed to fetch pace segments: \(error.localizedDescription)")
            return []
        }
    }

    /// Match a workout to its training_log pace_segments by date and distance
    private func matchSegments(for workout: RunningWorkout, in logs: [TrainingLog]) -> [PaceSegment]? {
        for log in logs {
            guard let logDate = log.workoutDate else { continue }
            guard abs(logDate.timeIntervalSince(workout.startDate)) < 300 else { continue }
            guard abs((log.workoutDistanceMiles ?? 0) - workout.distanceMiles) < 0.3 else { continue }
            if let segments = log.paceSegments, !segments.isEmpty {
                return segments
            }
        }
        return nil
    }

    /// Extract pace segments from a Vital workout stream, classify by zone, and save to the DB.
    /// This backfills pace_segments for workouts that were synced without stream data.
    private func extractAndSavePaceSegments(
        stream: VitalWorkoutStream, workout: RunningWorkout,
        paces: EquivalentPaces?, vitalManager: VitalManager
    ) async {
        let mileInMeters = 1609.34

        // Use VitalManager's pace split algorithm (same one that powers the workout detail view)
        let rawSplits = vitalManager.calculatePaceSplits(from: stream)

        // Build PaceSegments — classify each split's velocity into a zone using EquivalentPaces
        var segments: [PaceSegment] = []

        if rawSplits.isEmpty {
            // Steady run — no meaningful pace variation. Build per-mile segments from stream.
            let mileSplits = vitalManager.calculateSplits(from: stream)
            for split in mileSplits {
                let paceSecPerMile = split.paceMinutes * 60
                guard paceSecPerMile > 0 else { continue }
                let velocity = mileInMeters / paceSecPerMile
                let zone = PaceZone.from(velocity: velocity, paces: paces)
                let totalSec = Int(paceSecPerMile.rounded())
                let paceStr = String(format: "%d:%02d", totalSec / 60, totalSec % 60)
                let dist = split.isPartial ? split.partialDistance : 1.0
                segments.append(PaceSegment(
                    effort: zone.label.lowercased(),
                    distanceMiles: dist,
                    durationSeconds: split.paceMinutes * 60 * dist,
                    pacePerMile: paceStr,
                    avgHeartRate: nil
                ))
            }
        } else {
            // Interval/varied run — use the detected pace splits
            for split in rawSplits {
                let paceSecPerMile = split.paceMinutes * 60
                guard paceSecPerMile > 0 else { continue }
                let velocity = mileInMeters / paceSecPerMile
                let zone = PaceZone.from(velocity: velocity, paces: paces)
                let totalSec = Int(paceSecPerMile.rounded())
                let paceStr = String(format: "%d:%02d", totalSec / 60, totalSec % 60)
                segments.append(PaceSegment(
                    effort: zone.label.lowercased(),
                    distanceMiles: split.distanceMiles,
                    durationSeconds: split.durationSeconds,
                    pacePerMile: paceStr,
                    avgHeartRate: split.avgHeartRate
                ))
            }
        }

        guard !segments.isEmpty else { return }

        // Save to DB: update the matching training_log row
        do {
            let fmt = ISO8601DateFormatter()
            let windowStart = workout.startDate.addingTimeInterval(-300)
            let windowEnd = workout.startDate.addingTimeInterval(300)

            struct SegmentUpdate: Codable {
                let paceSegments: [PaceSegment]
                enum CodingKeys: String, CodingKey {
                    case paceSegments = "pace_segments"
                }
            }

            try await supabase
                .from("training_logs")
                .update(SegmentUpdate(paceSegments: segments))
                .gte("workout_date", value: fmt.string(from: windowStart))
                .lte("workout_date", value: fmt.string(from: windowEnd))
                .execute()

            print("[EffortChart] Saved \(segments.count) pace segments for \(String(format: "%.1f", workout.distanceMiles))mi workout")
        } catch {
            print("[EffortChart] Failed to save pace segments: \(error.localizedDescription)")
        }
    }

    /// Convert pace string "M:SS" to velocity in m/s
    private func velocityFromPaceString(_ pace: String) -> Double {
        let parts = pace.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 else { return 0 }
        let secPerMile = parts[0] * 60 + parts[1]
        guard secPerMile > 0 else { return 0 }
        return 1609.34 / secPerMile
    }

    /// Average velocity for a workout in m/s
    private func workoutVelocity(_ workout: RunningWorkout) -> Double {
        workout.distanceMiles > 0
            ? (workout.distanceMiles * 1609.34) / (workout.durationMinutes * 60)
            : 0
    }

    /// Derive pace zones from the runner's own data when no plan/fitness snapshot exists.
    /// Estimates a marathon equivalent from the fastest sustained effort, then uses the
    /// proper EquivalentPaces constructor so zone boundaries match the pace chart system.
    private func derivePacesFromWorkouts(_ workouts: [RunningWorkout]) -> EquivalentPaces? {
        // Collect (paceSecPerMile, distanceMiles) for qualifying runs
        let runs = workouts
            .filter { $0.distanceMiles >= 2.0 && $0.durationMinutes > 0 }
            .map { (pace: ($0.durationMinutes * 60) / $0.distanceMiles, dist: $0.distanceMiles) }
            .filter { $0.pace >= 300 && $0.pace <= 900 }

        guard runs.count >= 3 else { return nil }

        // Find the fastest sustained effort: best pace from runs >= 5 mi, else >= 3 mi
        let longRuns = runs.filter { $0.dist >= 5.0 }
        let bestEffort = (longRuns.isEmpty ? runs.filter { $0.dist >= 3.0 } : longRuns)
            .min(by: { $0.pace < $1.pace })

        guard let best = bestEffort else { return nil }

        // The fastest sustained effort approximates ~HM effort for most runners.
        // Convert to an equivalent marathon time using PaceCalculator.
        let estimatedHMSeconds = Int(best.pace * 13.1094)  // half marathon distance in miles
        let estimatedMarathonSeconds = PaceCalculator.getEquivalentTime(
            fromDistance: "half", fromSeconds: estimatedHMSeconds, toDistance: "marathon"
        )

        guard estimatedMarathonSeconds > 0 else { return nil }

        return EquivalentPaces(
            raceDistance: .marathon,
            goalTimeSeconds: estimatedMarathonSeconds
        )
    }
}

// MARK: - ConnectHealthCard

struct ConnectHealthCard: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.drip.coral.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.drip.coral)
                }

                VStack(spacing: 8) {
                    Text("Connect Apple Health")
                        .font(.dripLabel(17))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text("Import your runs from Garmin, Apple Watch, and other devices")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text("Get Started")
                        .font(.dripLabel(14))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.drip.coral)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - WorkoutCard

struct WorkoutCard: View {
    let workout: RunningWorkout

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.dayOfWeek)
                        .font(.dripLabel(15))
                        .foregroundStyle(Color.drip.textPrimary)

                    Text(workout.shortDate)
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                }

                Spacer()

                SourceBadge(source: workout.sourceApp)
            }

            // Stats row
            HStack(spacing: 0) {
                WorkoutStat(value: workout.formattedDistance, label: "DISTANCE")
                Divider()
                    .frame(height: 32)
                    .background(Color.drip.divider)
                WorkoutStat(value: workout.formattedDuration, label: "TIME")
                Divider()
                    .frame(height: 32)
                    .background(Color.drip.divider)
                WorkoutStat(value: workout.formattedPace, label: "PACE")
            }
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - WorkoutStat

struct WorkoutStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.dripStat(18))
                .foregroundStyle(Color.drip.textPrimary)

            Text(label)
                .font(.dripCaption(9))
                .foregroundStyle(Color.drip.textTertiary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SourceBadge

struct SourceBadge: View {
    let source: String

    var icon: String {
        let lowered = source.lowercased()
        if lowered.contains("garmin") { return "g.circle.fill" }
        if lowered.contains("apple") || lowered.contains("watch") { return "applewatch" }
        if lowered.contains("strava") { return "figure.run.circle.fill" }
        return "app.badge.fill"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(source)
                .font(.dripCaption(10))
        }
        .foregroundStyle(Color.drip.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(Capsule())
    }
}

// MARK: - WorkoutCardSkeleton

struct WorkoutCardSkeleton: View {
    var body: some View {
        SkeletonPulse {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBar(width: 80, height: 14)
                        SkeletonBar(width: 60, height: 10)
                    }
                    Spacer()
                    SkeletonBar(width: 60, height: 20)
                }

                HStack {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        VStack(spacing: 6) {
                            SkeletonBar(width: 50, height: 18)
                            SkeletonBar(width: 40, height: 8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - EmptyWorkoutsView

struct EmptyWorkoutsView: View {
    var body: some View {
        EmptyStateView(
            icon: "figure.run",
            title: "No runs yet",
            subtitle: "Your running workouts will appear here"
        )
    }
}

// MARK: - ManualEntryButton

struct ManualEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.drip.coral)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Log workout manually")
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text("Enter distance, duration, and more")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.drip.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        WorkoutsView()
    }
}
