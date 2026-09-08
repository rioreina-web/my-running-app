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
                // ThisDeviceOnly: the refresh token must not ride along in iCloud
                // Keychain / encrypted backups onto another device.
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
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

/// `nonisolated` because `AuthAvailability` below is an actor, and under the
/// module's main-actor-by-default isolation a bare file-scope `let` belongs to
/// the main actor — which an actor's methods may not touch. Matches `Log`,
/// which is `nonisolated` for the same reason. `Logger` is `Sendable`, so
/// there is nothing to make unsafe.
private nonisolated let authLogger = Logger(subsystem: "com.postrundrip.app", category: "AuthAvailability")

/// Circuit breaker around a stalled auth service.
///
/// The SDK funnels every caller through one in-flight refresh task
/// (`SessionManager.inFlightRefreshTask`), and PostgREST reads fetch their
/// access token down that same path. So when `/auth/v1/token` hangs — as it
/// did on 2026-08-07, 504-ing once the database stalled — every request in the
/// app queues behind a single doomed refresh and dies at URLSession's 60 s
/// timeout. That produced twelve independent-looking `-1001`s from one cause,
/// and left the app unusable for minutes after the backend had recovered.
///
/// This does not make auth work. It makes the failure cheap: the first caller
/// pays the timeout, the rest fail immediately for a short cooldown instead of
/// joining the queue behind it.
actor AuthAvailability {
    static let shared = AuthAvailability()

    private var openedAt: Date?
    private let cooldown: TimeInterval = 30

    /// True while auth is known-bad and callers should not wait on it.
    func isTripped() -> Bool {
        guard let opened = openedAt else { return false }
        guard Date().timeIntervalSince(opened) < cooldown else {
            openedAt = nil
            return false
        }
        return true
    }

    func recordFailure() {
        guard openedAt == nil else { return }
        openedAt = Date()
        authLogger.warning("Auth unavailable — failing fast for \(Int(self.cooldown), privacy: .public)s")
    }

    func recordSuccess() {
        if openedAt != nil {
            authLogger.info("Auth recovered")
        }
        openedAt = nil
    }
}

/// Bearer token for an authenticated edge-function call.
///
/// Returns `nil` when the user has a session that we cannot currently refresh
/// — deliberately WITHOUT falling back to the anon key. Every caller of
/// `callEdgeFunction` is an authenticated user action, so an anon-key request
/// is a guaranteed 401 that costs a full round-trip and then triggers a
/// *second* refresh against the same stalled service. That doubling is what
/// turned a backend blip into a multi-minute client outage.
///
/// A genuinely signed-out user (no stored session at all) still gets the anon
/// key, preserving the previous behaviour for that case.
private func edgeFunctionBearerToken() async -> String? {
    guard supabase.auth.currentSession != nil else {
        return supabaseAnonKey
    }
    if await AuthAvailability.shared.isTripped() {
        return nil
    }
    do {
        let session = try await supabase.auth.session
        await AuthAvailability.shared.recordSuccess()
        return session.accessToken
    } catch {
        await AuthAvailability.shared.recordFailure()
        return nil
    }
}

/// Bounds an async operation in WALL-CLOCK time, cancelling it if it overruns.
///
/// `URLRequest.timeoutInterval` does not cover this on its own: it governs the
/// gap between packets rather than the whole call, it is re-armed by
/// `callEdgeFunction`'s retry (so a 25s bound becomes a 50s wait), and it does
/// not cover the auth round-trip that happens BEFORE the request is built. A
/// caller that says twenty seconds means twenty seconds, and on 2026-08-11 the
/// gateway answered `trends-timeline` with a 401 after thirty-eight of them
/// while the Train tab sat on "Loading" for the duration.
///
/// The losing side of the race is cancelled. Two private copies of this shape
/// already exist (`AuthManager`, `VoiceLogViewModel`); new callers should take
/// this one, and those two should fold into it when they are next touched.
func withNetworkTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        guard let result = try await group.next() else { throw URLError(.timedOut) }
        group.cancelAll()
        return result
    }
}

/// Makes an authenticated request to a Supabase Edge Function using the user's JWT.
/// Automatically retries once on transient network errors and 5xx server errors.
func callEdgeFunction(name: String, body: [String: Any]) async throws -> Data {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
        throw URLError(.badURL)
    }

    guard let bearerToken = await edgeFunctionBearerToken() else {
        edgeFunctionLogger.warning("Edge function '\(name)' skipped — auth unavailable")
        throw EdgeFunctionError.httpError(
            statusCode: 401,
            function: name,
            message: "Session could not be refreshed"
        )
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
            } else if statusCode == 401, attempt == 0 {
                // A mid-session 401 almost always means the access token
                // expired (and the anon-key fallback above kicked in, which
                // the server rightly refuses). Force a session refresh and
                // retry once with a fresh token instead of failing the
                // feature — this is what left Ask spinning on "Reading…"
                // while the server logged a 401.
                edgeFunctionLogger.warning("Edge function '\(name)' returned 401 — refreshing session and retrying")
                lastError = EdgeFunctionError.httpError(statusCode: statusCode, function: name, message: message)
                if let refreshed = try? await supabase.auth.refreshSession() {
                    await AuthAvailability.shared.recordSuccess()
                    request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
                    continue
                }
                // Refresh failed against a stalled auth service. Trip the
                // breaker so the other surfaces loading concurrently fail
                // immediately instead of each queueing behind their own
                // doomed refresh.
                await AuthAvailability.shared.recordFailure()
                throw EdgeFunctionError.httpError(statusCode: statusCode, function: name, message: message)
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

/// Upload voice-memo audio via the service-role `upload-voice-memo` edge
/// function and return its public URL.
///
/// Direct uploads to the `training-memos` storage bucket have been rejected by
/// the storage service since 2026-06-02 (storage RLS returns "Unauthorized" on
/// a valid user JWT, even though the bucket policy is PUBLIC and the same JWT
/// clears PostgREST). The edge function writes with the service role, bypassing
/// that broken layer. Callers still insert the `training_logs` row themselves
/// over PostgREST (which works).
/// Raw-bytes upload (2026-08-04, latency Phase 5.2): the m4a bytes go up as
/// the request body with an audio/* Content-Type — ~25% fewer bytes on the
/// wire than the old base64-in-JSON shape (which also cost the function a
/// per-byte decode loop). The edge function still accepts the JSON shape, so
/// older builds and queued offline retries keep working.
func uploadVoiceMemoAudio(_ audioData: Data, contentType: String = "audio/m4a") async throws -> String {
    guard let url = URL(string: "\(supabaseURL)/functions/v1/upload-voice-memo") else {
        throw URLError(.badURL)
    }

    let bearerToken: String
    if let session = try? await supabase.auth.session {
        bearerToken = session.accessToken
    } else {
        bearerToken = supabaseAnonKey
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

    struct Resp: Decodable { let audio_url: String }

    var lastError: Error?
    for attempt in 0 ..< 2 {
        do {
            // upload(for:from:) streams the body — no extra in-memory copy.
            let (data, response) = try await URLSession.shared.upload(for: request, from: audioData)
            guard let httpResponse = response as? HTTPURLResponse else {
                return try JSONDecoder().decode(Resp.self, from: data).audio_url
            }
            if (200 ..< 300).contains(httpResponse.statusCode) {
                return try JSONDecoder().decode(Resp.self, from: data).audio_url
            }
            let message = parseErrorMessage(from: data)
            if httpResponse.statusCode >= 500 {
                edgeFunctionLogger.error("upload-voice-memo returned \(httpResponse.statusCode): \(message)")
                lastError = EdgeFunctionError.httpError(
                    statusCode: httpResponse.statusCode, function: "upload-voice-memo", message: message
                )
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
            } else {
                // 4xx — client error, not retryable.
                throw EdgeFunctionError.httpError(
                    statusCode: httpResponse.statusCode, function: "upload-voice-memo", message: message
                )
            }
        } catch let error as EdgeFunctionError {
            throw error
        } catch let error as URLError where isRetryableError(error) {
            lastError = error
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
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

// MARK: - Athlete Settings (account-scoped preferences)

/// Account-scoped athlete settings persisted in `athlete_settings` (one row per
/// user_id), so preferences like max HR sync across devices instead of living
/// only in this device's UserDefaults. The local `@AppStorage("userMaxHR")`
/// cache stays the fast read path; this keeps it in sync with the account.
enum AthleteSettingsService {
    static let maxHRDefaultsKey = "userMaxHR"

    /// Pull the account max HR into the local cache so zone scaling on THIS
    /// device reflects what was set on any device. No-op when unset on the
    /// server (keeps the local value). Call at launch.
    static func syncMaxHRFromServer() async {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return }
        struct Row: Decodable { let max_heart_rate: Int? }
        do {
            let rows: [Row] = try await supabase
                .from("athlete_settings")
                .select("max_heart_rate")
                .eq("user_id", value: userId.lowercased())
                .limit(1)
                .execute().value
            if let hr = rows.first?.max_heart_rate, (100...240).contains(hr) {
                await MainActor.run { UserDefaults.standard.set(hr, forKey: maxHRDefaultsKey) }
            }
        } catch {
            Log.app.error("AthleteSettingsService.syncMaxHRFromServer failed: \(error.localizedDescription)")
        }
    }

    /// Beta-audit item #10 (2026-07-16): nothing ever wrote
    /// `athlete_settings.timezone`, so every athlete defaulted to UTC — the
    /// Daily Read cron fired at 06:00 UTC for everyone (10pm–2am local in
    /// the US) and the whole roster dispatched in one simultaneous burst.
    /// Upserts the device timezone identifier (e.g. "America/Chicago");
    /// a per-user cache skips the write when it hasn't changed. Only the
    /// timezone column is sent, so max_heart_rate etc. survive on conflict.
    /// (2026-08-11) Now yields to an explicit choice. The athlete can set their
    /// timezone in Settings, and this runs at every launch — without the guard,
    /// a picked zone was reverted to the device's on the next cold start, which
    /// looks exactly like the setting not saving. `AthleteTimeZone.set` writes
    /// the account value in that case, so the server still gets told.
    static func syncDeviceTimezone() async {
        guard !AthleteTimeZone.isOverridden else { return }
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return }
        let tz = TimeZone.current.identifier
        let cacheKey = "athleteSettings.lastSyncedTimezone.\(userId.lowercased())"
        guard UserDefaults.standard.string(forKey: cacheKey) != tz else { return }
        await saveTimezone(tz)
    }

    /// Upsert a timezone to the account. Only the timezone column is sent, so
    /// max_heart_rate etc. survive on conflict. Shared by the launch sync and
    /// by the Settings picker so there is one writer, not two.
    static func saveTimezone(_ identifier: String) async {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty, TimeZone(identifier: identifier) != nil else { return }
        let cacheKey = "athleteSettings.lastSyncedTimezone.\(userId.lowercased())"
        struct Upsert: Encodable { let user_id: String; let timezone: String }
        do {
            try await supabase
                .from("athlete_settings")
                .upsert(Upsert(user_id: userId.lowercased(), timezone: identifier),
                        onConflict: "user_id")
                .execute()
            await MainActor.run { UserDefaults.standard.set(identifier, forKey: cacheKey) }
        } catch {
            // Non-fatal: the table doesn't exist until the 20260615
            // migrations are pushed. Cache stays unset, so we retry on the
            // next launch instead of silently giving up forever.
            Log.app.error("AthleteSettingsService.saveTimezone failed: \(error.localizedDescription)")
        }
    }

    /// Upsert the athlete's max HR to the account. Only the max-HR column is
    /// sent, so existing settings (e.g. timezone) are preserved on conflict.
    static func saveMaxHR(_ bpm: Int) async {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty, (100...240).contains(bpm) else { return }
        struct Upsert: Encodable { let user_id: String; let max_heart_rate: Int }
        do {
            try await supabase
                .from("athlete_settings")
                .upsert(Upsert(user_id: userId.lowercased(), max_heart_rate: bpm), onConflict: "user_id")
                .execute()
        } catch {
            Log.app.error("AthleteSettingsService.saveMaxHR failed: \(error.localizedDescription)")
        }
    }

    /// The athlete's own display name + short bio, loaded into the Settings
    /// screen so they can edit their profile. Both empty for a fresh athlete.
    /// The same `athlete_settings` row the coach portal reads, so a name set
    /// here shows up on the coach's roster and athlete page too.
    static func fetchProfile() async -> (displayName: String, bio: String, avatarPath: String?) {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return ("", "", nil) }
        struct Row: Decodable { let display_name: String?; let bio: String?; let avatar_path: String? }
        do {
            let rows: [Row] = try await supabase
                .from("athlete_settings")
                .select("display_name, bio, avatar_path")
                .eq("user_id", value: userId.lowercased())
                .limit(1)
                .execute().value
            let r = rows.first
            return (r?.display_name ?? "", r?.bio ?? "", r?.avatar_path)
        } catch {
            Log.app.error("AthleteSettingsService.fetchProfile failed: \(error.localizedDescription)")
            return ("", "", nil)
        }
    }

    /// Upload a new profile photo (JPEG) to the private `avatars` bucket at
    /// `{userId}/avatar.jpg` (upsert), persist the path on athlete_settings,
    /// and return the stored path. The coach portal reads this path and signs
    /// its own URL. Returns nil on failure.
    static func uploadAvatar(_ jpeg: Data) async -> String? {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return nil }
        let path = "\(userId)/avatar.jpg"
        do {
            try await supabase.storage
                .from("avatars")
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
            struct Upsert: Encodable { let user_id: String; let avatar_path: String }
            try await supabase
                .from("athlete_settings")
                .upsert(Upsert(user_id: userId.lowercased(), avatar_path: path), onConflict: "user_id")
                .execute()
            return path
        } catch {
            Log.app.error("AthleteSettingsService.uploadAvatar failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// A short-lived signed URL for displaying an avatar (the bucket is
    /// private, so `getPublicURL` won't serve it). Cache-bust with a query
    /// item so a freshly replaced photo doesn't show the stale one.
    static func signedAvatarURL(_ path: String) async -> URL? {
        guard !path.isEmpty else { return nil }
        do {
            return try await supabase.storage
                .from("avatars")
                .createSignedURL(path: path, expiresIn: 3600)
        } catch {
            Log.app.error("AthleteSettingsService.signedAvatarURL failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Upsert the athlete's display name + short bio. Only these two profile
    /// columns are sent, so timezone / max_heart_rate survive on conflict.
    /// Values are trimmed and clamped to the DB CHECK limits (name ≤ 80,
    /// bio ≤ 600). Empty text clears the field — every reader treats an empty
    /// string as "no value" and falls back to the placeholder.
    static func saveProfile(displayName: String, bio: String) async {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return }
        struct Upsert: Encodable {
            let user_id: String
            let display_name: String
            let bio: String
        }
        let cleanName = String(
            displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
        )
        let cleanBio = String(
            bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600)
        )
        do {
            try await supabase
                .from("athlete_settings")
                .upsert(
                    Upsert(user_id: userId.lowercased(), display_name: cleanName, bio: cleanBio),
                    onConflict: "user_id"
                )
                .execute()
        } catch {
            Log.app.error("AthleteSettingsService.saveProfile failed: \(error.localizedDescription)")
        }
    }
}
