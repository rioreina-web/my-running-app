import Combine
import CoreLocation
import os
import Supabase
import SwiftUI

// MARK: - PaceChartView

struct PaceChartView: View {
    @State private var viewModel = PaceChartViewModel()
    @Environment(\.dismiss) private var dismiss

    // Splits sheet state
    @State private var showSplitsSheet = false
    @State private var selectedSplitsPace: Double?
    @State private var selectedSplitsName: String = ""

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Goal Race Section
                    goalRaceSection

                    // Weather Adjustment Section
                    weatherAdjustmentSection

                    // Race Paces Section
                    racePacesSection

                    // Training Paces Section
                    trainingPacesSection

                    // Info Section
                    infoSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Pace Chart")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load engine zones (real training paces) and goal context
            // (hypothetical race paces) in parallel.
            async let zones: () = viewModel.loadEngineZones()
            async let goal: () = viewModel.loadFromGoal()
            _ = await (zones, goal)
        }
        .sheet(isPresented: $showSplitsSheet) {
            if let pace = selectedSplitsPace {
                PaceSplitsSheet(
                    paceName: selectedSplitsName,
                    paceSecondsPerMile: pace,
                    useKilometers: viewModel.useKilometers
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Goal Race Section

    private var goalRaceSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("GOAL RACE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            VStack(spacing: 16) {
                // Distance Picker (Dropdown)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Distance")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    Menu {
                        ForEach(PaceChartDistance.allCases) { distance in
                            Button {
                                viewModel.selectDistance(distance)
                            } label: {
                                HStack {
                                    Text(distance.displayName)
                                    if viewModel.selectedDistance == distance {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(viewModel.selectedDistance.displayName)
                                .font(.dripLabel(16))
                                .foregroundStyle(Color.drip.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.drip.coral)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Time Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal Time")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    HStack {
                        TextField(viewModel.selectedDistance.exampleTime, text: $viewModel.goalTimeString)
                            .font(.dripStat(32))
                            .foregroundStyle(Color.drip.textPrimary)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                viewModel.updateGoalTime(viewModel.goalTimeString)
                            }

                        Button {
                            viewModel.updateGoalTime(viewModel.goalTimeString)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Color.drip.coral)
                                .clipShape(Circle())
                        }
                    }
                    .padding(16)
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(viewModel.selectedDistance.timeFormatHint)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)

                    // Validation error/warning
                    if let error = viewModel.validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(error)
                                .font(.dripCaption(11))
                        }
                        .foregroundStyle(Color.drip.tired)
                        .padding(.top, 4)
                    }
                }

                // Calculated pace for goal
                if let goalPace = viewModel.racePaces[viewModel.selectedDistance.rawValue] {
                    HStack {
                        Text("Goal Pace:")
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)
                        Spacer()
                        Text(formatPaceWithUnit(goalPace))
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.coral)
                    }
                }

                // KM / Miles toggle
                HStack(spacing: 0) {
                    Button {
                        viewModel.useKilometers = false
                    } label: {
                        Text("Miles")
                            .font(.dripLabel(13))
                            .foregroundStyle(!viewModel.useKilometers ? .white : Color.drip.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(!viewModel.useKilometers ? Color.drip.coral : Color.clear)
                    }

                    Button {
                        viewModel.useKilometers = true
                    } label: {
                        Text("Kilometers")
                            .font(.dripLabel(13))
                            .foregroundStyle(viewModel.useKilometers ? .white : Color.drip.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(viewModel.useKilometers ? Color.drip.coral : Color.clear)
                    }
                }
                .background(Color.drip.cardBackgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Pace Formatting Helpers

    private func formatPaceWithUnit(_ secondsPerMile: Double) -> String {
        if viewModel.useKilometers {
            "\(PaceCalculator.formatPaceKm(secondsPerMile)) /km"
        } else {
            "\(PaceCalculator.formatPace(secondsPerMile)) /mi"
        }
    }

    private func formatPaceRangeWithUnit(low: Double?, high: Double?) -> String? {
        guard let low else { return nil }

        if let high {
            if viewModel.useKilometers {
                return "\(PaceCalculator.formatPaceKm(high)) - \(PaceCalculator.formatPaceKm(low))"
            } else {
                return "\(PaceCalculator.formatPace(high)) - \(PaceCalculator.formatPace(low))"
            }
        } else {
            if viewModel.useKilometers {
                return "\(PaceCalculator.formatPaceKm(low))+"
            } else {
                return "\(PaceCalculator.formatPace(low))+"
            }
        }
    }

    // MARK: - Weather Adjustment Section

    private var weatherAdjustmentSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coralLight)
                Text("WEATHER ADJUSTMENT")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.weatherEnabled },
                    set: { _ in viewModel.toggleWeather() }
                ))
                .labelsHidden()
                .tint(Color.drip.coral)
            }

            if viewModel.weatherEnabled {
                VStack(spacing: 16) {
                    // Current vs Forecast Toggle
                    HStack(spacing: 0) {
                        Button {
                            viewModel.useForecast = false
                            viewModel.calculateWeatherAdjustments()
                        } label: {
                            Text("Current")
                                .font(.dripLabel(13))
                                .foregroundStyle(!viewModel.useForecast ? .white : Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(!viewModel.useForecast ? Color.drip.coral : Color.clear)
                        }

                        Button {
                            viewModel.toggleForecast()
                        } label: {
                            Text("Forecast")
                                .font(.dripLabel(13))
                                .foregroundStyle(viewModel.useForecast ? .white : Color.drip.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(viewModel.useForecast ? Color.drip.coral : Color.clear)
                        }
                    }
                    .background(Color.drip.cardBackgroundElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Forecast Date/Time Picker
                    if viewModel.useForecast {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Run Time")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)

                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { viewModel.selectedForecastDate },
                                    set: { viewModel.updateForecastDate($0) }
                                ),
                                in: Date() ... (Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.drip.coral)
                        }
                    }

                    // Weather Display
                    if viewModel.isLoadingWeather {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Fetching weather...")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else if let weather = viewModel.useForecast ? viewModel.forecastWeather : viewModel.currentWeather {
                        weatherDisplayCard(weather: weather)
                    } else {
                        // No weather data
                        Button {
                            Task {
                                if viewModel.useForecast {
                                    await viewModel.fetchForecastWeather()
                                } else {
                                    await viewModel.fetchCurrentWeather()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                Text("Get Weather")
                            }
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.drip.coral.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Adjustment Summary or Error
                    if let adjustment = viewModel.currentAdjustment {
                        adjustmentSummaryCard(adjustment: adjustment)
                    } else if let error = viewModel.weatherError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.drip.energized)
                            Text(error)
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.drip.energized.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(Color.drip.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func weatherDisplayCard(weather: WorkoutWeather) -> some View {
        HStack(spacing: 16) {
            // Weather Icon & Condition
            VStack(spacing: 4) {
                Image(systemName: weather.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.drip.energized)
                Text(weather.description)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .frame(width: 70)

            // Temperature & Dew Point
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TEMP")
                            .font(.dripCaption(9))
                            .foregroundStyle(Color.drip.textTertiary)
                        Text(weather.formattedTemperature)
                            .font(.dripStat(22))
                            .foregroundStyle(Color.drip.textPrimary)
                    }

                    if let dewPoint = weather.formattedDewPoint {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DEW POINT")
                                .font(.dripCaption(9))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(dewPoint)
                                .font(.dripStat(22))
                                .foregroundStyle(Color.drip.textPrimary)
                        }
                    }
                }

                if let humidity = weather.humidity {
                    Text("Humidity: \(humidity)%")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textSecondary)
                }
            }

            Spacer()

            // Refresh button
            Button {
                Task {
                    if viewModel.useForecast {
                        await viewModel.fetchForecastWeather()
                    } else {
                        await viewModel.fetchCurrentWeather()
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .padding(12)
        .background(Color.drip.cardBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func adjustmentSummaryCard(adjustment: DewPointAdjustment) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: adjustment.heatCategory.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(adjustment.heatCategory.color)
                    Text(adjustment.heatCategory.rawValue)
                        .font(.dripLabel(14))
                        .foregroundStyle(adjustment.heatCategory.color)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(adjustment.formattedAdjustment)
                        .font(.dripStat(18))
                        .foregroundStyle(adjustment.heatCategory.color)
                    Text("(\(adjustment.formattedPercent) slower)")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            // Composite score indicator
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.drip.cardBackgroundElevated)
                            .frame(height: 6)

                        // Gradient scale
                        LinearGradient(
                            colors: [Color.drip.positive, Color.drip.energized, Color.drip.coralLight, Color.drip.coral, Color.drip.tired],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(height: 6)

                        // Indicator
                        let position = min(max((adjustment.compositeScore - 80) / 120, 0), 1) // Scale 80-200
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            .offset(x: geo.size.width * position - 6)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("Ideal")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                    Spacer()
                    Text("Score: \(Int(adjustment.compositeScore))")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer()
                    Text("Dangerous")
                        .font(.dripCaption(9))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
        .padding(12)
        .background(adjustment.heatCategory.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(adjustment.heatCategory.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Race Paces Section

    private var racePacesSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("RACE PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(PaceChartDistance.allCases) { distance in
                    if let pace = viewModel.racePaces[distance.rawValue] {
                        racePaceRow(
                            distance: distance,
                            pace: pace,
                            isGoal: distance == viewModel.selectedDistance
                        )

                        if distance != PaceChartDistance.allCases.last {
                            Divider()
                                .background(Color.drip.divider)
                        }
                    }
                }
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func racePaceRow(distance: PaceChartDistance, pace: Double, isGoal: Bool) -> some View {
        let adjustedPace = viewModel.weatherEnabled ? viewModel.adjustedRacePaces[distance.rawValue] : nil
        let displayPace = adjustedPace ?? pace

        return Button {
            selectedSplitsPace = displayPace
            selectedSplitsName = distance.displayName
            showSplitsSheet = true
        } label: {
            HStack {
                HStack(spacing: 8) {
                    if isGoal {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.drip.coral)
                    }
                    Text(distance.displayName)
                        .font(.dripLabel(14))
                        .foregroundStyle(isGoal ? Color.drip.coral : Color.drip.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let adjusted = adjustedPace, viewModel.weatherEnabled {
                        // Show adjusted pace
                        HStack(spacing: 6) {
                            Text(viewModel.useKilometers ? PaceCalculator.formatPaceKm(pace) : PaceCalculator.formatPace(pace))
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textTertiary)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text(formatPaceWithUnit(adjusted))
                                .font(.dripStat(18))
                                .foregroundStyle(viewModel.currentAdjustment?.heatCategory.color ?? Color.drip.coralLight)
                        }
                    } else {
                        Text(formatPaceWithUnit(pace))
                            .font(.dripStat(18))
                            .foregroundStyle(isGoal ? Color.drip.coral : Color.drip.textPrimary)
                    }

                    // Show estimated finish time (use adjusted if available)
                    let finishTime = Int(displayPace * distance.distanceMiles)
                    Text(PaceCalculator.formatTime(finishTime))
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isGoal ? Color.drip.coral.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Training Paces Section

    private var trainingPacesSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.positive)
                Text("TRAINING PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
                Spacer()

                Text(trainingPacesSourceLabel)
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            VStack(spacing: 0) {
                // Easy (not clickable)
                trainingPaceRow(
                    name: "Easy",
                    description: "70-80% MP",
                    paceRange: formatPaceRangeWithUnit(
                        low: viewModel.trainingPaces["Easy Fast"],
                        high: viewModel.trainingPaces["Easy Slow"]
                    ) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(
                        low: viewModel.adjustedTrainingPaces["Easy Fast"],
                        high: viewModel.adjustedTrainingPaces["Easy Slow"]
                    ),
                    color: Color.drip.positive,
                    icon: "leaf.fill",
                    isClickable: false,
                    pace: nil
                )

                // Observed easy diagnostic — only when ≥8 easy runs in last 90 days.
                if let obs = viewModel.engineZones?.observedEasy {
                    observedEasyDiagnosticRow(observed: obs)
                }

                Divider().background(Color.drip.divider)

                // Moderate (not clickable)
                trainingPaceRow(
                    name: "Moderate",
                    description: "80-90% MP",
                    paceRange: formatPaceRangeWithUnit(
                        low: viewModel.trainingPaces["Moderate Fast"],
                        high: viewModel.trainingPaces["Moderate Slow"]
                    ) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(
                        low: viewModel.adjustedTrainingPaces["Moderate Fast"],
                        high: viewModel.adjustedTrainingPaces["Moderate Slow"]
                    ),
                    color: Color.drip.energized,
                    icon: "figure.walk",
                    isClickable: false,
                    pace: nil
                )

                Divider().background(Color.drip.divider)

                // Steady (not clickable)
                trainingPaceRow(
                    name: "Steady",
                    description: "90-100% MP",
                    paceRange: formatPaceRangeWithUnit(
                        low: viewModel.trainingPaces["Steady Fast"],
                        high: viewModel.trainingPaces["Steady Slow"]
                    ) ?? "--",
                    adjustedPaceRange: formatPaceRangeWithUnit(
                        low: viewModel.adjustedTrainingPaces["Steady Fast"],
                        high: viewModel.adjustedTrainingPaces["Steady Slow"]
                    ),
                    color: Color.drip.coralLight,
                    icon: "flame",
                    isClickable: false,
                    pace: nil
                )

                Divider().background(Color.drip.divider)

                // MP — engine race anchor (your real marathon pace) or
                // goal-Riegel fallback when the engine has nothing yet.
                if let mpPace = viewModel.engineZones?.marathon?.pace ?? viewModel.racePaces["marathon"] {
                    trainingPaceRow(
                        name: "MP",
                        description: "Marathon Pace",
                        paceRange: viewModel.useKilometers ? PaceCalculator.formatPaceKm(mpPace) : PaceCalculator.formatPace(mpPace),
                        adjustedPaceRange: nil,
                        color: Color.drip.coral,
                        icon: "bolt.fill",
                        isClickable: true,
                        pace: mpPace
                    )
                }

                Divider().background(Color.drip.divider)

                // HMP — engine race anchor or goal-Riegel fallback.
                if let hmpPace = viewModel.engineZones?.halfMarathon?.pace ?? viewModel.racePaces["half"] {
                    trainingPaceRow(
                        name: "HMP",
                        description: "Half Marathon Pace",
                        paceRange: viewModel.useKilometers ? PaceCalculator.formatPaceKm(hmpPace) : PaceCalculator.formatPace(hmpPace),
                        adjustedPaceRange: nil,
                        color: Color.drip.tired,
                        icon: "bolt.horizontal.fill",
                        isClickable: true,
                        pace: hmpPace
                    )
                }

            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Header label that explains where the training paces are coming from.
    /// Engine = user's real fitness; goal-fallback = chart's goal-MP what-if.
    private var trainingPacesSourceLabel: String {
        switch viewModel.trainingPaceSource {
        case .engine:
            switch viewModel.engineZones?.primarySource {
            case "profile":      return "From your pace profile"
            case "race_derived": return "From your fitness predictions"
            case "goal_only":    return "From your training plan"
            default:             return "From your data"
            }
        case .goalFallback:
            return "From your goal (no run data yet)"
        case .empty:
            return "—"
        }
    }

    /// Diagnostic row beneath Easy showing where the athlete's actual easy
    /// runs land (p25–p75). Annotates "running too fast" / "too slow" when
    /// observed bounds escape the doctrine band.
    private func observedEasyDiagnosticRow(observed: ObservedEasySnapshot) -> some View {
        let easyDoctrineFast = viewModel.trainingPaces["Easy Fast"]
        let easyDoctrineSlow = viewModel.trainingPaces["Easy Slow"]

        let runningTooFast = easyDoctrineFast.map { observed.paceFast < $0 } ?? false
        let runningTooSlow = easyDoctrineSlow.map { observed.paceSlow > $0 } ?? false

        let label: String
        let color: Color
        if runningTooFast {
            let secsTooFast = Int((easyDoctrineFast ?? 0) - observed.paceFast)
            label = "averaging \(secsTooFast)s/mi too fast"
            color = Color.drip.coral
        } else if runningTooSlow {
            label = "running easy on the slow side"
            color = Color.drip.textTertiary
        } else {
            label = "in the band"
            color = Color.drip.positive
        }

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Observed easy")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                Text("\(observed.sessionCount) runs, last \(observed.lookbackDays) days")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(observedEasyRangeFormatted(observed))
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textPrimary)
                Text(label)
                    .font(.dripCaption(10))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.drip.cardBackgroundElevated.opacity(0.4))
    }

    private func observedEasyRangeFormatted(_ obs: ObservedEasySnapshot) -> String {
        let unit = viewModel.useKilometers ? "/km" : "/mi"
        let fast = viewModel.useKilometers ? PaceCalculator.formatPaceKm(obs.paceFast) : PaceCalculator.formatPace(obs.paceFast)
        let slow = viewModel.useKilometers ? PaceCalculator.formatPaceKm(obs.paceSlow) : PaceCalculator.formatPace(obs.paceSlow)
        return "\(fast) – \(slow) \(unit)"
    }

    @ViewBuilder
    private func trainingPaceRow(
        name: String,
        description: String,
        paceRange: String,
        adjustedPaceRange: String?,
        color: Color,
        icon: String,
        isClickable: Bool,
        pace: Double?
    ) -> some View {
        let unit = viewModel.useKilometers ? "/km" : "/mi"

        let content = HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.dripLabel(14))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(description)
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }

            Spacer()

            if let adjusted = adjustedPaceRange, viewModel.weatherEnabled {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(adjusted) \(unit)")
                        .font(.dripStat(16))
                        .foregroundStyle(viewModel.currentAdjustment?.heatCategory.color ?? color)
                    Text(paceRange)
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                        .strikethrough()
                }
            } else {
                Text("\(paceRange) \(unit)")
                    .font(.dripStat(16))
                    .foregroundStyle(color)
            }

            if isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if isClickable, let pace {
            Button {
                selectedSplitsPace = pace
                selectedSplitsName = name
                showSplitsSheet = true
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func formatTrainingPaceRange(low: Double?, high: Double?) -> String? {
        if let low, let high {
            return "\(PaceCalculator.formatPace(high)) - \(PaceCalculator.formatPace(low))"
        } else if let low {
            return "\(PaceCalculator.formatPace(low))+"
        }
        return nil
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.textTertiary)
                Text("ABOUT THESE PACES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            VStack(alignment: .leading, spacing: 8) {
                // swiftlint:disable:next line_length
                Text("Race paces are calculated using standard equivalency formulas. Training paces are based on percentage of marathon pace (MP) effort.")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("MP = Marathon Pace")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                Text("HMP = Half Marathon Pace")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)

                if viewModel.weatherEnabled {
                    Divider().background(Color.drip.divider)

                    // swiftlint:disable:next line_length
                    Text("Weather adjustments use the Dew Point Heat Index formula: higher temperature and humidity require slower paces to maintain the same effort level.")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
            .padding(16)
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - PaceSplitsSheet

struct PaceSplitsSheet: View {
    let paceName: String
    let paceSecondsPerMile: Double
    let useKilometers: Bool

    @Environment(\.dismiss) private var dismiss

    private var splits: (fourHundred: Double, oneK: Double, mile: Double) {
        PaceCalculator.calculateSplits(paceSecondsPerMile: paceSecondsPerMile)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Pace header
                    VStack(spacing: 8) {
                        Text(paceName)
                            .font(.dripLabel(14))
                            .foregroundStyle(Color.drip.textSecondary)
                            .tracking(1.2)

                        Text(useKilometers ? PaceCalculator.formatPaceKm(paceSecondsPerMile) : PaceCalculator.formatPace(paceSecondsPerMile))
                            .font(.dripStat(48))
                            .foregroundStyle(Color.drip.coral)

                        Text(useKilometers ? "per kilometer" : "per mile")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    .padding(.top, 16)

                    // Splits grid
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.drip.energized)
                            Text("SPLITS")
                                .font(.dripCaption(11))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.2)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        VStack(spacing: 0) {
                            splitRow(distance: "400m", time: splits.fourHundred, icon: "figure.run")

                            Divider().background(Color.drip.divider)

                            splitRow(distance: "1K", time: splits.oneK, icon: "flame")

                            Divider().background(Color.drip.divider)

                            splitRow(distance: "Mile", time: splits.mile, icon: "flag.fill")
                        }
                        .background(Color.drip.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Pace Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                }
            }
        }
    }

    private func splitRow(distance: String, time: Double, icon: String) -> some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.drip.coral)
                    .frame(width: 24)

                Text(distance)
                    .font(.dripLabel(16))
                    .foregroundStyle(Color.drip.textPrimary)
            }

            Spacer()

            Text(PaceCalculator.formatSplit(time))
                .font(.dripStat(24))
                .foregroundStyle(Color.drip.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

#Preview {
    NavigationStack {
        PaceChartView()
    }
}
