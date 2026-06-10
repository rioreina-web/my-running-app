import Auth
import Foundation
import os
import PostgREST
import Storage
import Supabase

// MARK: - Supabase Configuration

/// Read secrets from Info.plist (populated by Secrets.xcconfig at build time).
/// If Secrets.xcconfig is missing or not wired into the Xcode configuration,
/// these will be empty and the app will fail to connect — by design.
private enum Secrets {
    static let infoDictionary = Bundle.main.infoDictionary ?? [:]

    static var supabaseURL: String {
        infoDictionary["SUPABASE_URL"] as? String ?? ""
    }

    static var supabaseAnonKey: String {
        infoDictionary["SUPABASE_ANON_KEY"] as? String ?? ""
    }
}

let supabaseURL = Secrets.supabaseURL
let supabaseAnonKey = Secrets.supabaseAnonKey

// MARK: - Keychain Auth Storage

/// Persists auth sessions in Keychain so users stay signed in across app launches.
final class KeychainAuthStorage: AuthLocalStorage, Sendable {
    private let service = "com.postrundrip.app.auth"
    private let queue = DispatchQueue(label: "com.postrundrip.app.auth.keychain")

    func store(key: String, value: Data) throws {
        try queue.sync {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw NSError(domain: "KeychainAuthStorage", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to store auth data"])
            }
        }
    }

    func retrieve(key: String) throws -> Data? {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess else { return nil }
            return result as? Data
        }
    }

    func remove(key: String) throws {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

private func resolvedSupabaseURL() -> URL {
    guard !supabaseURL.isEmpty, let url = URL(string: supabaseURL) else {
        fatalError("SUPABASE_URL missing or invalid — verify Secrets.xcconfig is wired to the build configuration (Project → Info → Configurations).")
    }
    return url
}

let supabase = SupabaseClient(
    supabaseURL: resolvedSupabaseURL(),
    supabaseKey: supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: KeychainAuthStorage(),
            autoRefreshToken: true,
            // Emit the local session immediately without waiting for refresh.
            // Fixes the "Initial session emitted after attempting to refresh"
            // warning. We handle expired sessions by triggering a manual
            // refresh when SDK calls fail with auth errors.
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Edge Function Error

enum EdgeFunctionError: LocalizedError {
    case httpError(statusCode: Int, function: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .httpError(statusCode, function, message):
            return "Edge function '\(function)' failed (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Edge Function Helper

private let edgeFunctionLogger = Logger(subsystem: "com.postrundrip.app", category: "EdgeFunction")

/// Extracts a human-readable message from an edge function error response.
private func parseErrorMessage(from data: Data) -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
    // Edge functions may return { "error": "..." } or { "message": "..." } or { "error": { "message": "..." } }
    if let error = json["error"] as? String {
        return error
    }
    if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
        return msg
    }
    if let message = json["message"] as? String {
        return message
    }
    return String(data: data, encoding: .utf8) ?? "Unknown error"
}

/// Makes an authenticated request to a Supabase Edge Function using the user's JWT.
/// Automatically retries once on transient network errors and 5xx server errors.
func callEdgeFunction(name: String, body: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
        throw URLError(.badURL)
    }

    // Use JWT if authenticated, fall back to anon key
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
    request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    var lastError: Error?
    for attempt in 0 ..< 2 {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return data
            }

            let statusCode = httpResponse.statusCode

            if statusCode >= 200, statusCode < 300 {
                return data
            }

            let message = parseErrorMessage(from: data)

            if statusCode >= 500 {
                edgeFunctionLogger.error("Edge function '\(name)' returned \(statusCode): \(message)")
                lastError = EdgeFunctionError.httpError(statusCode: statusCode, function: name, message: message)
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
            } else {
                // 4xx — client error, not retryable
                edgeFunctionLogger.warning("Edge function '\(name)' returned \(statusCode): \(message)")
                throw EdgeFunctionError.httpError(statusCode: statusCode, function: name, message: message)
            }
        } catch let error as EdgeFunctionError {
            throw error
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
