import Foundation
import os
import Supabase
import SwiftUI

/// Manages chat state and API interactions for the AI coach conversation.
@Observable
final class CoachChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var conversationId: String?
    var rateLimit = RateLimitState()
    var showRateLimitAlert = false

    // MARK: - Send Message

    @MainActor
    func sendMessage(workoutSummary: String, planContext: String, fitnessPredictions: String) {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)

        let messageToSend = inputText
        inputText = ""
        isLoading = true

        Task {
            await callCoachingAgent(
                message: messageToSend,
                workoutSummary: workoutSummary,
                planContext: planContext,
                fitnessPredictions: fitnessPredictions
            )
        }
    }

    // MARK: - Proactive Check-In

    @MainActor
    func initiateProactiveCheckIn(
        _ context: CheckInContext,
        workoutSummary: String,
        planContext: String,
        fitnessPredictions: String
    ) async {
        startNewConversation()
        isLoading = true

        var payload: [String: Any] = [
            "message": "[PROACTIVE CHECK-IN]\nMood: \(context.mood)\nWhat they said: \(context.cleanedNotes ?? "")\nInitial insight: \(context.coachInsight ?? "")",
            "proactive": true,
            "checkInContext": [
                "logId": context.logId.uuidString,
                "mood": context.mood,
                "cleanedNotes": context.cleanedNotes ?? "",
                "coachInsight": context.coachInsight ?? "",
            ],
        ]

        payload["userId"] = AuthManager.shared.currentUserId ?? supabase.auth.currentUser?.id.uuidString ?? "dev-user"
        if !workoutSummary.isEmpty { payload["workoutSummary"] = workoutSummary }
        if !planContext.isEmpty { payload["trainingPlanContext"] = planContext }
        if !fitnessPredictions.isEmpty { payload["fitnessPredictions"] = fitnessPredictions }

        do {
            let data = try await callEdgeFunction(name: "coaching-agent", body: payload)
            let coachResponse = try JSONDecoder().decode(CoachResponse.self, from: data)

            if let convId = coachResponse.conversationId {
                conversationId = convId
            }
            if let responseText = coachResponse.response {
                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: responseText,
                    sources: coachResponse.sources
                )
                messages.append(assistantMessage)
            }
            isLoading = false
        } catch {
            isLoading = false
            appendErrorMessage("Couldn't start check-in. You can always type a message.")
            ErrorReporter.shared.report(error, context: "proactive check-in")
        }
    }

    // MARK: - New Conversation

    @MainActor
    func startNewConversation() {
        messages = []
        conversationId = nil
        inputText = ""
        isLoading = false
    }

    // MARK: - Rate Limit

    var rateLimitMessage: String {
        if let resetAt = rateLimit.resetAt {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "You've used all \(rateLimit.limit) questions for today. Questions reset at \(formatter.string(from: resetAt))."
        }
        return "You've used all \(rateLimit.limit) questions for today. Questions reset at midnight UTC."
    }

    // MARK: - Private

    private func callCoachingAgent(
        message: String,
        workoutSummary: String,
        planContext: String,
        fitnessPredictions: String
    ) async {
        var payload: [String: Any] = ["message": message]
        // Send user ID — fall back to "dev-user" when auth gate is disabled
        payload["userId"] = AuthManager.shared.currentUserId ?? supabase.auth.currentUser?.id.uuidString ?? "dev-user"
        if let convId = conversationId {
            payload["conversationId"] = convId
        }
        if UserDefaults.standard.bool(forKey: "smartInsightsEnabled") {
            payload["smartInsights"] = true
        }
        if !workoutSummary.isEmpty {
            payload["workoutSummary"] = workoutSummary
        }
        if !planContext.isEmpty {
            payload["trainingPlanContext"] = planContext
        }
        if !fitnessPredictions.isEmpty {
            payload["fitnessPredictions"] = fitnessPredictions
        }

        do {
            Log.coach.debug("Sending coach request via callEdgeFunction")

            let data = try await callEdgeFunction(name: "coaching-agent", body: payload)
            let rawBody = String(data: data, encoding: .utf8) ?? ""

            // Check for error responses (callEdgeFunction returns data for 4xx too)
            if let coachResponse = try? JSONDecoder().decode(CoachResponse.self, from: data) {
                // Rate limit
                if coachResponse.error?.contains("limit") == true || coachResponse.remaining == 0 {
                    await MainActor.run {
                        isLoading = false
                        rateLimit.remaining = 0
                        if let resetAtString = coachResponse.resetAt {
                            let formatter = ISO8601DateFormatter()
                            rateLimit.resetAt = formatter.date(from: resetAtString)
                        }
                        if let limit = coachResponse.limit {
                            rateLimit.limit = limit
                        }
                        showRateLimitAlert = true
                        appendErrorMessage("You've reached your daily limit. Your questions reset at midnight UTC.")
                    }
                    return
                }

                // Auth error
                if coachResponse.error == "Authentication required" {
                    Log.coach.error("Coach auth failed despite callEdgeFunction")
                    await MainActor.run {
                        isLoading = false
                        appendErrorMessage("Not signed in. Please sign in and try again.")
                    }
                    return
                }

                // Other error from function
                if let error = coachResponse.error {
                    Log.coach.error("Coach error: \(error)")
                    await MainActor.run {
                        isLoading = false
                        appendErrorMessage(error)
                    }
                    return
                }

                // Success
                Log.coach.debug("Coach response received (model: \(coachResponse.model ?? "unknown"))")
                await MainActor.run {
                    if let remaining = coachResponse.remaining {
                        rateLimit.remaining = remaining
                    }
                    if let convId = coachResponse.conversationId {
                        conversationId = convId
                    }
                    // Failsafe: if the typed decoder produced an empty shape (all
                    // nil), don't drop the response — fall back to the raw body.
                    // Prevents the "coach says nothing" case when server shape
                    // drifts or a field changes unexpectedly.
                    let text = coachResponse.response
                        ?? (coachResponse.error ?? (rawBody.isEmpty ? nil : rawBody))
                    if let text, !text.isEmpty {
                        let assistantMessage = ChatMessage(
                            role: .assistant,
                            content: text,
                            sources: coachResponse.sources
                        )
                        messages.append(assistantMessage)
                    } else {
                        appendErrorMessage("Coach returned an empty response. Please try again.")
                    }
                    isLoading = false
                }
            } else {
                // Response didn't decode as CoachResponse
                Log.coach.error("Coach response decode failed: \(rawBody.prefix(300))")
                await MainActor.run {
                    isLoading = false
                    appendErrorMessage("Coach returned an unexpected response. Please try again.")
                }
            }

        } catch let error as URLError where error.code == .timedOut {
            Log.coach.error("Coach request timed out")
            await MainActor.run {
                isLoading = false
                appendErrorMessage("Coach took too long to respond. Please try again.")
            }
        } catch {
            Log.coach.error("Coach call failed: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                appendErrorMessage("Couldn't reach the coach. Check your connection and try again.")
            }
            ErrorReporter.shared.report(error, context: "coaching agent call")
        }
    }

    @MainActor
    private func appendErrorMessage(_ text: String) {
        let errorMessage = ChatMessage(role: .assistant, content: text)
        messages.append(errorMessage)
    }
}
