//
//  SentryService.swift
//  RunningLog
//
//  Crash + error reporting via Sentry.
//  DSN is read from Secrets.xcconfig via Info.plist at build time.
//

import Foundation
import Sentry

enum SentryService {
    /// Initialize Sentry once at app launch.
    /// DSN is read from Info.plist (populated by Secrets.xcconfig).
    static func start() {
        let dsn = Bundle.main.infoDictionary?["SENTRY_DSN"] as? String ?? ""
        guard !dsn.isEmpty, dsn.hasPrefix("https://") else {
            #if DEBUG
            print("[Sentry] SENTRY_DSN not set in Secrets.xcconfig — error reporting disabled")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.1
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.environment = Self.environment
            options.releaseName = Self.releaseName
            options.beforeSend = { event in
                event.user?.email = nil
                event.user?.name = nil
                return event
            }
        }
    }

    /// Manually capture a non-fatal error.
    static func capture(_ error: Error, context: [String: Any]? = nil) {
        SentrySDK.capture(error: error) { scope in
            if let context { scope.setContext(value: context, key: "extra") }
        }
    }

    /// Capture a string message at a given level.
    static func capture(_ message: String, level: String = "error") {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(Self.sentryLevel(from: level))
        }
    }

    private static func sentryLevel(from raw: String) -> SentryLevel {
        switch raw.lowercased() {
        case "debug": return .debug
        case "info": return .info
        case "warning": return .warning
        case "fatal": return .fatal
        default: return .error
        }
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
