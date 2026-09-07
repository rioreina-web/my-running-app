//
//  SessionStoryService.swift
//  RunningLog
//
//  Loads one session's story (plus its comparison ghost) from the
//  `session-story` edge function. This is the lazy per-session path —
//  `trends-timeline` deliberately keeps per-second streams out of the list
//  load, so the split-grade hills adjustment happens here, when the athlete
//  actually opens a session.
//
//  Mirrors the `TrendsService` shape: @Observable, cached results, a
//  `load()` the view calls on appear. Cached per (log, compare) pair so
//  re-opening a session is instant.
//

import Foundation
import os

@Observable
final class SessionStoryService {
    static let shared = SessionStoryService()

    private(set) var isLoading = false
    private(set) var lastError: Error?
    private var cache: [String: SessionStoryPayload] = [:]

    private init() {}

    /// Test / preview seam.
    init(preview: SessionStoryPayload, forLogId logId: String, compareId: String?) {
        cache[Self.key(logId, compareId)] = preview
    }

    func cached(logId: String, compareLogId: String?) -> SessionStoryPayload? {
        cache[Self.key(logId, compareLogId)]
    }

    /// Fetch the story for a session (and its ghost). Returns the cached
    /// payload when present; a network failure records `lastError` and
    /// returns nil — the view shows the error empty-state, never a spinner
    /// forever.
    @MainActor
    func load(logId: String, compareLogId: String?) async -> SessionStoryPayload? {
        let key = Self.key(logId, compareLogId)
        if let hit = cache[key] { return hit }
        isLoading = true
        defer { isLoading = false }
        do {
            var body: [String: Any] = ["log_id": logId]
            if let compareLogId { body["compare_log_id"] = compareLogId }
            let data = try await callEdgeFunction(name: "session-story", body: body)
            let payload = try JSONDecoder().decode(SessionStoryPayloadDTO.self, from: data).toModel()
            cache[key] = payload
            lastError = nil
            return payload
        } catch {
            lastError = error
            Log.coach.error("Session story load failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func key(_ logId: String, _ compareId: String?) -> String {
        "\(logId)|\(compareId ?? "-")"
    }
}
