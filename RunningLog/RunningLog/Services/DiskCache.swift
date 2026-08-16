//
//  DiskCache.swift
//  RunningLog
//
//  A tiny JSON file cache for last-known-good fetch results, powering the
//  stale-while-revalidate pattern (PERF-AUDIT-2026-08-10.md, finding #5):
//  screens render instantly from the last snapshot on disk while the
//  network refresh runs, so a second launch never stares at "Loading…".
//
//  Design rules:
//  - Failure is always silent. A cache read or write that fails returns
//    nil / does nothing — the cache is an accelerant, never load-bearing.
//    The network path must work exactly as it did before this existed.
//  - Every payload embeds the userId it was saved for (see the stores that
//    use this). Readers validate it so one account's data can never render
//    for another. `clearAll()` is called on sign-out as a second belt.
//  - Files live in Application Support/RunCache, excluded from iCloud
//    backup (they're re-derivable from the server).
//

import Foundation

enum DiskCache {
    private static let directoryName = "RunCache"

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(_ name: String) -> URL? {
        directory?.appendingPathComponent("\(name).json")
    }

    /// Write `value` as JSON under `name`. Silent on failure.
    static func save<T: Encodable>(_ value: T, name: String) {
        guard let url = fileURL(name) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        // Cache is re-derivable from the server — keep it out of backups.
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resource)
    }

    /// Read the JSON stored under `name`, or nil if absent/corrupt/stale-schema.
    /// A failed decode (e.g. after a model change) deletes the file so it
    /// doesn't fail again on every launch.
    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = fileURL(name),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(type, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return value
    }

    /// Delete every cached file. Called on sign-out so no training data
    /// survives an account switch.
    static func clearAll() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
