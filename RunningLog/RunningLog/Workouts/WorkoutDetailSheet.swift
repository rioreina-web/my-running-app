//
//  WorkoutDetailSheet.swift
//  RunningLog
//
//  Detail sheet for viewing workout stats, heart rate, weather, and notes.
//

import CoreLocation
import HealthKit
import SwiftUI

// MARK: - WorkoutDetailSheet

struct WorkoutDetailSheet: View {
    let workout: RunningWorkout
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var heartRateData: (average: Double, max: Double)?
    @State private var heartRateSamples: [HeartRateSample] = []
    @State private var isLoadingHR = true
    @State private var workoutNotes: String = ""
    @State private var weather: WorkoutWeather?
    @State private var isLoadingWeather = true
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        ZStack {
            Color.drip.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(workout.dayOfWeek)
                            .font(.dripDisplay(28))
                            .foregroundStyle(Color.drip.textPrimary)

                        Text(workout.formattedDate)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.textSecondary)

                        SourceBadge(source: workout.sourceApp)
                            .padding(.top, 4)
                    }
                    .padding(.top, 20)

                    // Main stats
                    HStack(spacing: 16) {
                        StatCard(value: workout.formattedDistance, label: "Distance", icon: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        StatCard(value: workout.formattedDuration, label: "Duration", icon: "clock.fill")
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 16) {
                        StatCard(value: workout.formattedPace, label: "Avg Pace", icon: "speedometer")
                        StatCard(value: "\(Int(workout.calories))", label: "Calories", icon: "flame.fill", accentColor: Color.drip.tired)
                    }
                    .padding(.horizontal, 20)

                    // Heart Rate Section
                    if isLoadingHR {
                        HeartRateLoadingCard()
                            .padding(.horizontal, 20)
                    } else if let hrData = heartRateData {
                        HeartRateCard(average: hrData.average, max: hrData.max)
                            .padding(.horizontal, 20)
                    }

                    // Heart Rate Graph
                    if !heartRateSamples.isEmpty {
                        HeartRateGraphCard(samples: heartRateSamples, duration: workout.durationMinutes)
                            .padding(.horizontal, 20)
                    }

                    // Weather Section
                    if isLoadingWeather {
                        WeatherLoadingCard()
                            .padding(.horizontal, 20)
                    } else if let weather {
                        WeatherCard(weather: weather)
                            .padding(.horizontal, 20)
                    }

                    // Notes Section
                    NotesCard(notes: $workoutNotes, isFocused: $isNotesFocused)
                        .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            loadHeartRateData()
        }
    }

    private func loadHeartRateData() {
        Task {
            // Fetch the HKWorkout object
            if let hkWorkout = await healthKitManager.fetchWorkoutWithUUID(workout.id) {
                // Fetch heart rate stats
                let hrStats = await healthKitManager.fetchWorkoutHeartRate(for: hkWorkout)

                // Fetch heart rate samples for graph
                let samples = await healthKitManager.fetchHeartRateSamples(for: hkWorkout)

                await MainActor.run {
                    heartRateData = hrStats
                    heartRateSamples = samples
                    isLoadingHR = false
                }

                // Fetch weather data
                await loadWeatherData(for: hkWorkout)
            } else {
                await MainActor.run {
                    isLoadingHR = false
                    isLoadingWeather = false
                }
            }
        }
    }

    private func loadWeatherData(for hkWorkout: HKWorkout) async {
        // Try to get GPS location from workout route
        let routeLocations = await healthKitManager.fetchWorkoutRoute(for: hkWorkout)
        let location: CLLocation

        if let firstLocation = routeLocations.first {
            // Use GPS location from workout route (Apple Watch workouts)
            location = firstLocation
        } else {
            // Fallback: Use device's current location or a default
            // For now, try to get current location
            if let currentLocation = await getCurrentLocation() {
                location = currentLocation
            } else {
                // Ultimate fallback - no weather available
                await MainActor.run {
                    isLoadingWeather = false
                }
                return
            }
        }

        // Fetch weather for workout date and location
        let fetchedWeather = await WeatherService.shared.fetchWeather(
            for: workout.startDate,
            location: location
        )

        await MainActor.run {
            weather = fetchedWeather
            isLoadingWeather = false
        }
    }

    private func getCurrentLocation() async -> CLLocation? {
        // Simple one-shot location fetch
        let locationManager = CLLocationManager()

        // Check authorization
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }

        // Use last known location if available
        return locationManager.location
    }
}

// MARK: - WeatherCard

struct WeatherCard: View {
    let weather: WorkoutWeather

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("WEATHER")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            HStack(spacing: 20) {
                // Temperature
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(weather.temperatureFahrenheit))")
                            .font(.dripStat(32))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("°F")
                            .font(.dripCaption(14))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text("Temperature")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(width: 1, height: 40)

                // Condition
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: weather.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(iconColor)

                        Text(weather.description)
                            .font(.dripLabel(16))
                            .foregroundStyle(Color.drip.textPrimary)
                    }
                    Text("Condition")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()
            }

            // Additional details
            if weather.humidity != nil || weather.windSpeedMph != nil {
                HStack(spacing: 16) {
                    if let humidity = weather.humidity {
                        HStack(spacing: 6) {
                            Image(systemName: "humidity.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text("\(humidity)%")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }

                    if let wind = weather.windSpeedMph {
                        HStack(spacing: 6) {
                            Image(systemName: "wind")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.drip.textTertiary)
                            Text("\(Int(wind)) mph")
                                .font(.dripCaption(12))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                    }
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
    }

    var iconColor: Color {
        switch weather.condition {
        case .clear: Color.drip.energized
        case .partlyCloudy: Color.drip.coral
        case .cloudy,
             .fog: Color.drip.textSecondary
        case .drizzle,
             .rain: Color.drip.neutral
        case .snow: Color.drip.textSecondary
        case .thunderstorm: Color.drip.injured
        case .unknown: Color.drip.textTertiary
        }
    }
}

// MARK: - WeatherLoadingCard

struct WeatherLoadingCard: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.energized)
                .opacity(isAnimating ? 0.5 : 1)

            Text("Loading weather data...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - HeartRateCard

struct HeartRateCard: View {
    let average: Double
    let max: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.injured)
                Text("HEART RATE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(average))")
                            .font(.dripStat(32))
                            .foregroundStyle(Color.drip.textPrimary)
                        Text("bpm")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text("Average")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(width: 1, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(max))")
                            .font(.dripStat(32))
                            .foregroundStyle(Color.drip.injured)
                        Text("bpm")
                            .font(.dripCaption(12))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text("Maximum")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Spacer()
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - HeartRateLoadingCard

struct HeartRateLoadingCard: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.drip.injured)
                .opacity(isAnimating ? 0.5 : 1)

            Text("Loading heart rate data...")
                .font(.dripBody(14))
                .foregroundStyle(Color.drip.textSecondary)

            Spacer()
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - HeartRateGraphCard

struct HeartRateGraphCard: View {
    let samples: [HeartRateSample]
    let duration: Double // in minutes

    var minHR: Double {
        samples.map(\.bpm).min() ?? 100
    }

    var maxHR: Double {
        samples.map(\.bpm).max() ?? 180
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HEART RATE OVER TIME")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textSecondary)
                .tracking(1.2)

            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 120
                let hrRange = max(maxHR - minHR, 20)

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0 ..< 3) { _ in
                            Spacer()
                            Rectangle()
                                .fill(Color.drip.divider.opacity(0.5))
                                .frame(height: 1)
                        }
                        Spacer()
                    }
                    .frame(height: height)

                    // HR Line
                    Path { path in
                        let points = samples.compactMap { sample -> CGPoint? in
                            let x = CGFloat(sample.timestamp / (duration * 60)) * width
                            let y = height - CGFloat((sample.bpm - minHR) / hrRange) * height
                            return CGPoint(x: x, y: y)
                        }

                        guard let firstPoint = points.first else { return }
                        path.move(to: firstPoint)

                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.drip.injured.opacity(0.8), Color.drip.coral],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Fill gradient under line
                    Path { path in
                        let points = samples.compactMap { sample -> CGPoint? in
                            let x = CGFloat(sample.timestamp / (duration * 60)) * width
                            let y = height - CGFloat((sample.bpm - minHR) / hrRange) * height
                            return CGPoint(x: x, y: y)
                        }

                        guard let firstPoint = points.first else { return }
                        path.move(to: CGPoint(x: firstPoint.x, y: height))
                        path.addLine(to: firstPoint)

                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }

                        if let lastPoint = points.last {
                            path.addLine(to: CGPoint(x: lastPoint.x, y: height))
                        }
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.drip.injured.opacity(0.2), Color.drip.injured.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: height)
            }
            .frame(height: 120)

            // Time labels
            HStack {
                Text("0:00")
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
                Spacer()
                Text(formatTime(duration * 60))
                    .font(.dripCaption(10))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - NotesCard

struct NotesCard: View {
    @Binding var notes: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("NOTES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add notes about this workout...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $notes)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused(isFocused)
            }
            .frame(minHeight: 80)
        }
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused.wrappedValue ? Color.drip.coral.opacity(0.5) : Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Extensions

extension RunningWorkout {
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: startDate)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: startDate)
    }
}
