//
//  HistoryDetailSections.swift
//  RunningLog
//
//  Supporting section views and extensions for history detail views.
//

import os
import SwiftUI

// MARK: - CoachInsightSection

struct CoachInsightSection: View {
    let entry: TrainingLog
    @Binding var coachInsight: String?
    @Binding var isLoading: Bool
    var onSave: ((String) -> Void)?
    @State private var hasError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("COACH INSIGHT")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            if let insight = coachInsight {
                // Check if it's an error message
                if insight.starts(with: "Error:") || insight.starts(with: "Couldn't get") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight)
                            .font(.dripBody(14))
                            .foregroundStyle(Color.drip.injured)
                            .lineSpacing(4)

                        Button {
                            coachInsight = nil
                            getCoachInsight()
                        } label: {
                            Text("Try Again")
                                .font(.dripLabel(13))
                                .foregroundStyle(Color.drip.coral)
                        }
                    }
                } else {
                    Text(insight)
                        .font(.dripBody(15))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineSpacing(4)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.drip.coral)
                        .scaleEffect(0.8)
                    Text("Getting coach feedback...")
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                Button {
                    getCoachInsight()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                        Text("Get Coach Feedback")
                            .font(.dripLabel(14))
                    }
                    .foregroundStyle(Color.drip.coral)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.drip.coral.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    coachInsight.map { !$0.starts(with: "Error:") && !$0.starts(with: "Couldn't get") } == true ? Color.drip.coral
                        .opacity(0.3) : Color.drip.divider,
                    lineWidth: 1
                )
        )
        .alert("Coach Error", isPresented: $hasError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func getCoachInsight() {
        Log.coach.debug("getCoachInsight() called")
        isLoading = true

        // Build structured workout context
        var workoutDetails = ""
        if entry.hasLinkedWorkout {
            var parts: [String] = []
            if let distance = entry.formattedWorkoutDistance {
                parts.append(distance)
            }
            if let duration = entry.formattedWorkoutDuration {
                parts.append(duration)
            }
            if let pace = entry.formattedWorkoutPace {
                parts.append("\(pace)/mi")
            }
            workoutDetails = "Workout: " + parts.joined(separator: " | ")
        }

        var notesContext = ""
        if let cleaned = entry.cleanedNotes, !cleaned.isEmpty {
            notesContext = "Notes: \(cleaned)"
        } else if let notes = entry.notes, !notes.isEmpty {
            notesContext = "Notes: \(notes)"
        }

        var moodContext = ""
        if let mood = entry.mood, !mood.isEmpty {
            moodContext = "Mood: \(mood)"
        }

        // Check if this is a harder effort (tempo, interval, long run, speed work)
        let allNotes = (entry.cleanedNotes ?? "") + (entry.notes ?? "")
        let isHarderEffort = isQualityWorkout(notes: allNotes, distanceMiles: entry.workoutDistanceMiles)

        // Detect specific focus areas from the notes
        let hasRecoveryConcern = allNotes.lowercased().containsAny(["sore", "tight", "pain", "ache", "hurt", "tired", "fatigue", "heavy"])
        let hasMoodData = entry.mood.map { !$0.isEmpty } ?? false

        // Build the focused prompt
        let contextParts = [workoutDetails, notesContext, moodContext].filter { !$0.isEmpty }
        let context = contextParts.joined(separator: "\n")

        // Build dynamic focus suggestions
        var focusHints: [String] = []
        if hasRecoveryConcern {
            focusHints.append("note any recovery/fatigue signals")
        }
        if hasMoodData {
            focusHints.append("connect effort to how they felt")
        }
        if isHarderEffort {
            focusHints.append("training stimulus and adaptation")
        }

        let goalsInstruction = isHarderEffort
            ? "[GOALS] Reflect on how this workout connects to their upcoming goal race. Vary phrasing naturally (e.g., 'This type of effort builds the strength you'll need for...', 'Sessions like this are what prepare you for race day...', 'This is the work that'll pay off when...')."
            : ""

        let message = """
        [COACH INSIGHT REQUEST]

        \(context.isEmpty ? "Training log from \(entry.displayDate.shortDateString)" : context)

        Give thoughtful coaching feedback (4-5 sentences). Be conversational and supportive.
        Observations to consider: \(focusHints.isEmpty ? "effort, execution, pacing" : focusHints.joined(separator: ", "))
        \(goalsInstruction)
        """

        Log.coach.debug("Coach insight request message: \(message)")

        Task {
            await callCoachingAgent(message: message)
        }
    }

    /// Detect if workout is a quality/harder effort based on notes and distance
    private func isQualityWorkout(notes: String, distanceMiles: Double?) -> Bool {
        let lowercased = notes.lowercased()

        // Check for quality workout keywords
        let qualityKeywords = [
            "tempo", "interval", "speed", "fast", "hard",
            "long run", "longrun", "race", "threshold",
            "fartlek", "repeat", "workout", "track",
            "progressive", "negative split", "pr", "pb"
        ]

        if qualityKeywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Long runs (8+ miles) are quality efforts
        if let miles = distanceMiles, miles >= 8.0 {
            return true
        }

        return false
    }

    private func callCoachingAgent(message: String) async {
        Log.coach.debug("callCoachingAgent() starting...")

        guard let url = URL(string: "\(supabaseURL)/functions/v1/coaching-agent") else {
            Log.coach.error("Invalid URL")
            await MainActor.run {
                isLoading = false
                coachInsight = "Error: Invalid URL configuration"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30 // 30 second timeout

        let payload: [String: Any] = ["message": message]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            Log.coach.debug("Making API request to coaching-agent...")

            let (data, response) = try await URLSession.shared.data(for: request)

            Log.coach.debug("Received response from API")

            if let httpResponse = response as? HTTPURLResponse {
                Log.coach.debug("HTTP status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "No body"
                    Log.coach.error("Response body: \(errorBody)")
                    throw NSError(
                        domain: "CoachError",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode)): \(errorBody)"]
                    )
                }
            }

            // Log raw response for debugging
            if let rawResponse = String(data: data, encoding: .utf8) {
                Log.coach.debug("Raw API response: \(rawResponse.prefix(500))...")
            }

            struct CoachResponse: Codable {
                let response: String?
                let conversationId: String?
                let sources: [DocumentSource]?
                let error: String?
                let details: String?
                let model: String?
                let provider: String?
                let cached: Bool?
                let remaining: Int?

                struct DocumentSource: Codable {
                    let title: String
                    let category: String
                }
            }

            let coachResponse = try JSONDecoder().decode(CoachResponse.self, from: data)
            Log.coach.info("Successfully decoded response, model: \(coachResponse.model ?? "unknown")")

            await MainActor.run {
                if let error = coachResponse.error {
                    coachInsight = "Error: \(error)"
                    if let details = coachResponse.details {
                        Log.coach.error("Error details: \(details)")
                    }
                } else if let response = coachResponse.response {
                    coachInsight = response
                    // Save to database for persistence
                    onSave?(response)
                } else {
                    coachInsight = "No response received from coach."
                }
                isLoading = false
            }

        } catch let urlError as URLError {
            Log.coach.error("URLError: \(urlError.localizedDescription), code: \(urlError.code.rawValue)")
            await MainActor.run {
                if urlError.code == .timedOut {
                    coachInsight = "Error: Request timed out. Please try again."
                } else if urlError.code == .notConnectedToInternet {
                    coachInsight = "Error: No internet connection."
                } else {
                    coachInsight = "Error: Network error - \(urlError.localizedDescription)"
                }
                isLoading = false
            }
        } catch {
            Log.coach.error("General error: \(error)")
            await MainActor.run {
                coachInsight = "Couldn't get coach feedback: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - WorkoutNotesSection

struct WorkoutNotesSection: View {
    @Binding var workoutNotes: String
    @Binding var isEditing: Bool
    @Binding var isSaving: Bool
    var onSave: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("WORKOUT NOTES")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)

                Spacer()

                if !workoutNotes.isEmpty, !isEditing {
                    Button {
                        isEditing = true
                        isTextFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                }
            }

            if isEditing || workoutNotes.isEmpty {
                // Editing mode
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Add splits, paces, intervals...", text: $workoutNotes, axis: .vertical)
                        .font(.dripBody(14))
                        .foregroundStyle(Color.drip.textPrimary)
                        .lineLimit(1 ... 8)
                        .focused($isTextFieldFocused)
                        .padding(12)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 12) {
                        if isEditing, !workoutNotes.isEmpty {
                            Button {
                                isEditing = false
                                isTextFieldFocused = false
                            } label: {
                                Text("Cancel")
                                    .font(.dripLabel(13))
                                    .foregroundStyle(Color.drip.textSecondary)
                            }
                        }

                        Spacer()

                        Button {
                            isTextFieldFocused = false
                            onSave()
                        } label: {
                            HStack(spacing: 6) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(isSaving ? "Saving..." : "Save Notes")
                                    .font(.dripLabel(13))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(workoutNotes.isEmpty ? Color.drip.textTertiary : Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(workoutNotes.isEmpty || isSaving)
                    }
                }
            } else {
                // Display mode
                Text(workoutNotes)
                    .font(.dripBody(14))
                    .foregroundStyle(Color.drip.textPrimary)
                    .lineSpacing(4)
            }

            // Helper text
            if workoutNotes.isEmpty, !isEditing {
                Text("Record splits, interval times, pace notes, or any workout details")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(!workoutNotes.isEmpty ? Color.drip.coral.opacity(0.3) : Color.drip.divider, lineWidth: 1)
        )
        .onTapGesture {
            if workoutNotes.isEmpty {
                isEditing = true
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - EditableMoodPicker

struct EditableMoodPicker: View {
    @Binding var selectedMood: String

    private let moods = ["energized", "positive", "neutral", "tired", "struggling", "injured"]

    private func moodColor(_ mood: String) -> Color {
        switch mood {
        case "energized": return Color.drip.energized
        case "positive": return Color.drip.positive
        case "neutral": return Color.drip.neutral
        case "tired": return Color.drip.tired
        case "struggling": return Color.drip.struggling
        case "injured": return Color.drip.injured
        default: return Color.drip.neutral
        }
    }

    private func moodIcon(_ mood: String) -> String {
        switch mood {
        case "energized": return "bolt.fill"
        case "positive": return "face.smiling.fill"
        case "neutral": return "minus.circle.fill"
        case "tired": return "moon.fill"
        case "struggling": return "exclamationmark.triangle.fill"
        case "injured": return "bandage.fill"
        default: return "circle.fill"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    Button {
                        selectedMood = selectedMood == mood ? "" : mood
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: moodIcon(mood))
                                .font(.system(size: 10, weight: .bold))
                            Text(mood.capitalized)
                                .font(.dripCaption(11))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(selectedMood == mood ? .white : moodColor(mood))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedMood == mood ? moodColor(mood) : moodColor(mood).opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - EditableWorkoutTypeSection

struct EditableWorkoutTypeSection: View {
    @Binding var selectedType: String

    private let workoutTypes = [
        ("easy", "Easy"),
        ("tempo", "Tempo"),
        ("interval", "Intervals"),
        ("long_run", "Long Run"),
        ("recovery", "Recovery"),
        ("race", "Race"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("WORKOUT TYPE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workoutTypes, id: \.0) { type, label in
                        Button {
                            selectedType = selectedType == type ? "" : type
                        } label: {
                            Text(label)
                                .font(.dripCaption(12))
                                .fontWeight(.medium)
                                .foregroundStyle(selectedType == type ? .white : Color.drip.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selectedType == type ? Color.drip.coral : Color.drip.coral.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - EditableWorkoutStatsSection

struct EditableWorkoutStatsSection: View {
    @Binding var distanceText: String
    @Binding var durationText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.drip.energized)
                Text("WORKOUT STATS")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distance (mi)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0.00", text: $distanceText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration (m:ss)")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                    TextField("0:00", text: $durationText)
                        .font(.dripStat(18))
                        .foregroundStyle(Color.drip.textPrimary)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(10)
                        .background(Color.drip.cardBackgroundElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity)
            }

            // Computed pace display
            if let distance = Double(distanceText),
               let duration = parseDurationToMinutes(durationText),
               distance > 0 {
                let totalSecs = Int(((duration / distance) * 60).rounded())
                let paceMinutes = totalSecs / 60
                let paceSeconds = totalSecs % 60
                Text("Pace: \(String(format: "%d:%02d", paceMinutes, paceSeconds)) /mi")
                    .font(.dripCaption(12))
                    .foregroundStyle(Color.drip.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.energized.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.energized.opacity(0.3), lineWidth: 1)
        )
    }

    private func parseDurationToMinutes(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 60 + parts[1] + parts[2] / 60.0
        case 2: return parts[0] + parts[1] / 60.0
        case 1: return parts[0]
        default: return nil
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var dayOfWeekString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var monthString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: self)
    }

    var dayNumberString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }

    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    func containsAny(_ substrings: [String]) -> Bool {
        substrings.contains { self.contains($0) }
    }
}
