import Auth
import Foundation
import PostgREST
import Storage
import Supabase

// MARK: - Supabase Configuration

/// Supabase project URL
let supabaseURL = "https://aqdijapxmjqaetursrde.supabase.co"

// Supabase anonymous key - safe to include in client apps when RLS is properly configured
// This key only grants access allowed by Row Level Security policies
// swiftlint:disable:next line_length
let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxZGlqYXB4bWpxYWV0dXJzcmRlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0MzEyNzEsImV4cCI6MjA4NTAwNzI3MX0.bMqAvXDjtqyZXYDhPnyhJOm35l_2y3tIp82sLlALtBE"

let supabase = SupabaseClient(
    supabaseURL: URL(string: supabaseURL)!, // swiftlint:disable:this force_unwrapping
    supabaseKey: supabaseAnonKey
)

// MARK: - Edge Function Helper

/// Makes an authenticated request to a Supabase Edge Function using the user's JWT.
/// Automatically retries once on transient network errors (timeout, connection lost, etc.).
func callEdgeFunction(name: String, body: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
        throw URLError(.badURL)
    }

    // Use JWT if authenticated, fall back to anon key for development
    let bearerToken: String
    if let session = try? await supabase.auth.session {
        bearerToken = session.accessToken
    } else {
        bearerToken = supabaseAnonKey
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    var lastError: Error?
    for attempt in 0 ..< 2 {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Client errors (400-499): don't retry, return data for caller to handle
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400, httpResponse.statusCode < 500
            {
                return data
            }

            return data
        } catch let error as URLError where isRetryableError(error) {
            lastError = error
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    throw lastError ?? URLError(.unknown)
}

private func isRetryableError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut,
         .cannotConnectToHost,
         .networkConnectionLost,
         .notConnectedToInternet,
         .dnsLookupFailed:
        return true
    default:
        return false
    }
}
