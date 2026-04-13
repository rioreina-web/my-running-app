import Auth
import Foundation
import PostgREST
import Storage
import Supabase

// MARK: - Supabase Configuration

/// Read secrets from Info.plist (populated by Secrets.xcconfig at build time)
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
final class KeychainAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let service = "com.postrundrip.app.auth"

    func store(key: String, value: Data) throws {
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

    func retrieve(key: String) throws -> Data? {
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

    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

let supabase = SupabaseClient(
    supabaseURL: URL(string: supabaseURL)!, // swiftlint:disable:this force_unwrapping
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

// MARK: - Edge Function Helper

/// Makes an authenticated request to a Supabase Edge Function using the user's JWT.
/// Automatically retries once on transient network errors (timeout, connection lost, etc.).
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
