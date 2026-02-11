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

// MARK: - EmptyAuthStorage

/// Custom storage that doesn't persist anything (no auth needed for this app)
final class EmptyAuthStorage: AuthLocalStorage, @unchecked Sendable {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? {
        nil
    }

    func remove(key: String) throws {}
}

let supabase = SupabaseClient(
    supabaseURL: URL(string: supabaseURL)!, // swiftlint:disable:this force_unwrapping
    supabaseKey: supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: EmptyAuthStorage(),
            autoRefreshToken: false,
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Edge Function Helper

/// Makes a request to a Supabase Edge Function using the anon key
/// Edge functions have their own service_role access via environment variables
func callEdgeFunction(
    name: String,
    body: [String: Any],
    completion: @escaping (Result<Data, Error>) -> Void
) {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
        completion(.failure(URLError(.badURL)))
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { data, _, error in
        if let error {
            completion(.failure(error))
            return
        }
        guard let data else {
            completion(.failure(URLError(.zeroByteResource)))
            return
        }
        completion(.success(data))
    }.resume()
}

/// Async version of callEdgeFunction
func callEdgeFunction(name: String, body: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await URLSession.shared.data(for: request)
    return data
}
