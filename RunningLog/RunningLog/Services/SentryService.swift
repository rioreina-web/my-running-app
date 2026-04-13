//
//  SentryService.swift
//  RunningLog
//
//  Crash + error reporting via Sentry.
//
//  SETUP (one-time):
//  1. In Xcode: File → Add Package Dependencies → https://github.com/getsentry/sentry-cocoa
//     - Choose the latest stable version, add `Sentry` library to RunningLog target.
//  2. Add `SENTRY_DSN` to RunningLog/Secrets.xcconfig (gitignored):
//        SENTRY_DSN = https:/$()/exampleKey@o1234.ingest.sentry.io/123
//     (the `$()` workaround prevents xcconfig from interpreting `//` as a comment)
//  3. In Info.plist add a String entry: SentryDSN = $(SENTRY_DSN)
//  4. Uncomment the `import Sentry` and `SentrySDK.start { ... }` blocks below.
//  5. Wire SentryService.start() into RunningLogApp.init().
//

import Foundation
// import Sentry  // ← uncomment after SPM install

enum SentryService {
    /// Initialize Sentry once at app launch.
    /// No-op if SENTRY_DSN isn't configured (dev builds, debug runs).
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !dsn.isEmpty,
              dsn.hasPrefix("https://")
        else {
            #if DEBUG
            print("[Sentry] SENTRY_DSN not set — error reporting disabled")
            #endif
            return
        }

        // SentrySDK.start { options in
        //     options.dsn = dsn
        //     options.debug = false
        //     options.enableAutoSessionTracking = true
        //     options.tracesSampleRate = 0.1
        //     options.attachScreenshot = false  // privacy: don't capture screen on crash
        //     options.attachViewHierarchy = false
        //     options.environment = Self.environment
        //     options.releaseName = Self.releaseName
        //     // Strip PII — Supabase user IDs are fine but no emails/names
        //     options.beforeSend = { event in
        //         event.user?.email = nil
        //         event.user?.name = nil
        //         return event
        //     }
        // }
    }

    /// Manually capture a non-fatal error.
    static func capture(_ error: Error, context: [String: Any]? = nil) {
        // SentrySDK.capture(error: error) { scope in
        //     if let context { scope.setContext(value: context, key: "extra") }
        // }
    }

    /// Capture a string message at a given level.
    static func capture(_ message: String, level: String = "error") {
        // SentrySDK.capture(message: message) { scope in
        //     scope.setLevel(SentryLevel.from(rawValue: level))
        // }
    }

    private static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private static var releaseName: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "running-log@\(version)+\(build)"
    }
}
