//
//  VideoDownloadManager.swift
//  RunningLog
//
//  Service for downloading and managing offline video content.
//

import Foundation
import os
import SwiftUI

// MARK: - VideoDownloadManager

@Observable
class VideoDownloadManager: NSObject {
    static let shared = VideoDownloadManager()

    /// Track active downloads: videoId -> progress (0.0 to 1.0)
    var activeDownloads: [UUID: Double] = [:]

    /// Track downloaded videos
    private(set) var downloadedVideos: Set<UUID> = []

    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private var progressHandlers: [UUID: (Double) -> Void] = [:]
    private var completionHandlers: [UUID: (Result<URL, Error>) -> Void] = [:]
    private var videoExtensions: [UUID: String] = [:] // Store original file extension

    private var urlSession: URLSession!

    private let fileManager = FileManager.default
    private let downloadedVideosKey = "downloadedVideos"
    private let videoMetadataKey = "downloadedVideoMetadata"

    /// Store video metadata for offline access
    private(set) var cachedVideoMetadata: [UUID: ContentLibraryItem] = [:]

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300 // 5 minutes for large files
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        loadDownloadedVideos()
        loadCachedMetadata()
    }

    // MARK: - Public Methods

    /// Check if a video is downloaded
    func isDownloaded(_ videoId: UUID) -> Bool {
        downloadedVideos.contains(videoId) && fileExists(for: videoId)
    }

    /// Check if a video is currently downloading
    func isDownloading(_ videoId: UUID) -> Bool {
        activeDownloads[videoId] != nil
    }

    /// Get download progress for a video (0.0 to 1.0)
    func progress(for videoId: UUID) -> Double {
        activeDownloads[videoId] ?? 0.0
    }

    /// Get local file URL for a downloaded video
    func localURL(for videoId: UUID) -> URL? {
        // Check for common video extensions
        let extensions = ["mov", "mp4", "m4v"]
        for ext in extensions {
            let url = videosDirectory.appendingPathComponent("\(videoId.uuidString).\(ext)")
            if fileManager.fileExists(atPath: url.path) {
                Log.video.debug("Found local video at: \(url.path)")
                return url
            }
        }
        Log.video.debug("No local video found for: \(videoId)")
        return nil
    }

    /// Start downloading a video
    func download(
        video: ContentLibraryItem,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !isDownloaded(video.id) else {
            if let url = localURL(for: video.id) {
                completion(.success(url))
            } else {
                completion(.failure(DownloadError.fileNotFound))
            }
            return
        }

        guard !isDownloading(video.id) else {
            completion(.failure(DownloadError.alreadyDownloading))
            return
        }

        guard let videoURL = URL(string: video.videoUrl) else {
            completion(.failure(DownloadError.invalidURL))
            return
        }

        // Extract file extension from URL
        let pathExtension = videoURL.pathExtension.lowercased()
        let fileExtension = ["mov", "mp4", "m4v"].contains(pathExtension) ? pathExtension : "mov"

        // Store handlers and extension
        progressHandlers[video.id] = progress
        completionHandlers[video.id] = completion
        videoExtensions[video.id] = fileExtension

        // Cache video metadata for offline access
        cacheVideoMetadata(video)

        Log.video.info("Starting download for \(video.title) with extension: \(fileExtension)")
        Log.video.debug("Video URL: \(videoURL)")

        // Start download
        let task = urlSession.downloadTask(with: videoURL)
        task.taskDescription = video.id.uuidString
        downloadTasks[video.id] = task
        activeDownloads[video.id] = 0.0

        task.resume()
    }

    /// Cancel an active download
    func cancelDownload(for videoId: UUID) {
        downloadTasks[videoId]?.cancel()
        cleanupDownload(for: videoId)
    }

    /// Delete a downloaded video
    func deleteDownload(for videoId: UUID) {
        // Try to delete with any common extension
        let extensions = ["mov", "mp4", "m4v"]
        for ext in extensions {
            let url = videosDirectory.appendingPathComponent("\(videoId.uuidString).\(ext)")
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
                Log.video.info("Deleted: \(url.path)")
            }
        }
        downloadedVideos.remove(videoId)
        cachedVideoMetadata.removeValue(forKey: videoId)
        saveDownloadedVideos()
        saveCachedMetadata()
    }

    /// Get total size of all downloaded videos
    func totalDownloadedSize() -> Int64 {
        var totalSize: Int64 = 0
        for videoId in downloadedVideos {
            if let url = localURL(for: videoId),
               let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    /// Delete all downloaded videos
    func deleteAllDownloads() {
        for videoId in downloadedVideos {
            deleteDownload(for: videoId)
        }
    }

    // MARK: - Private Methods

    private var videosDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosPath = documentsPath.appendingPathComponent("DownloadedVideos", isDirectory: true)

        if !fileManager.fileExists(atPath: videosPath.path) {
            try? fileManager.createDirectory(at: videosPath, withIntermediateDirectories: true)
        }

        return videosPath
    }

    private func fileExists(for videoId: UUID) -> Bool {
        // Check for common video extensions
        let extensions = ["mov", "mp4", "m4v"]
        for ext in extensions {
            let url = videosDirectory.appendingPathComponent("\(videoId.uuidString).\(ext)")
            if fileManager.fileExists(atPath: url.path) {
                return true
            }
        }
        return false
    }

    private func loadDownloadedVideos() {
        if let data = UserDefaults.standard.data(forKey: downloadedVideosKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            // Verify files still exist
            downloadedVideos = Set(ids.filter { fileExists(for: $0) })
            // Save cleaned list if any were removed
            if downloadedVideos.count != ids.count {
                saveDownloadedVideos()
            }
        }
    }

    private func saveDownloadedVideos() {
        if let data = try? JSONEncoder().encode(Array(downloadedVideos)) {
            UserDefaults.standard.set(data, forKey: downloadedVideosKey)
        }
    }

    private func loadCachedMetadata() {
        if let data = UserDefaults.standard.data(forKey: videoMetadataKey),
           let metadata = try? JSONDecoder().decode([UUID: ContentLibraryItem].self, from: data) {
            // Only keep metadata for videos that are still downloaded
            cachedVideoMetadata = metadata.filter { downloadedVideos.contains($0.key) }
        }
    }

    private func saveCachedMetadata() {
        if let data = try? JSONEncoder().encode(cachedVideoMetadata) {
            UserDefaults.standard.set(data, forKey: videoMetadataKey)
        }
    }

    /// Cache video metadata for offline access
    func cacheVideoMetadata(_ video: ContentLibraryItem) {
        cachedVideoMetadata[video.id] = video
        saveCachedMetadata()
    }

    /// Get cached video metadata
    func getCachedVideo(for id: UUID) -> ContentLibraryItem? {
        cachedVideoMetadata[id]
    }

    /// Get all cached videos that are downloaded
    func getAllDownloadedVideos() -> [ContentLibraryItem] {
        downloadedVideos.compactMap { cachedVideoMetadata[$0] }
    }

    private func cleanupDownload(for videoId: UUID) {
        activeDownloads.removeValue(forKey: videoId)
        downloadTasks.removeValue(forKey: videoId)
        progressHandlers.removeValue(forKey: videoId)
        completionHandlers.removeValue(forKey: videoId)
        videoExtensions.removeValue(forKey: videoId)
    }
}

// MARK: URLSessionDownloadDelegate

extension VideoDownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let videoIdString = downloadTask.taskDescription,
              let videoId = UUID(uuidString: videoIdString) else { return }

        // Use stored extension or default to mov
        let fileExtension = videoExtensions[videoId] ?? "mov"
        let destinationURL = videosDirectory.appendingPathComponent("\(videoId.uuidString).\(fileExtension)")

        Log.video.debug("Download finished, saving to: \(destinationURL.path)")

        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Move downloaded file to permanent location
            try fileManager.moveItem(at: location, to: destinationURL)

            // Verify file was saved
            if fileManager.fileExists(atPath: destinationURL.path) {
                Log.video.info("File saved successfully at: \(destinationURL.path)")

                // Get file size for confirmation
                if let attrs = try? fileManager.attributesOfItem(atPath: destinationURL.path),
                   let size = attrs[.size] as? Int64 {
                    Log.video.debug("File size: \(VideoDownloadManager.formatBytes(size))")
                }
            } else {
                Log.video.error("File NOT found after move!")
            }

            // Update state
            downloadedVideos.insert(videoId)
            saveDownloadedVideos()

            // Notify completion
            completionHandlers[videoId]?(.success(destinationURL))
        } catch {
            Log.video.error("Error saving file: \(error)")
            completionHandlers[videoId]?(.failure(error))
        }

        cleanupDownload(for: videoId)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let videoIdString = downloadTask.taskDescription,
              let videoId = UUID(uuidString: videoIdString) else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        activeDownloads[videoId] = progress
        progressHandlers[videoId]?(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let videoIdString = downloadTask.taskDescription,
              let videoId = UUID(uuidString: videoIdString),
              let error else { return }

        // Only report error if not cancelled
        if (error as NSError).code != NSURLErrorCancelled {
            completionHandlers[videoId]?(.failure(error))
        }

        cleanupDownload(for: videoId)
    }
}

// MARK: - DownloadError

enum DownloadError: LocalizedError {
    case invalidURL
    case alreadyDownloading
    case fileNotFound
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid video URL"
        case .alreadyDownloading:
            "Video is already downloading"
        case .fileNotFound:
            "Downloaded file not found"
        case .saveFailed:
            "Failed to save video"
        }
    }
}

// MARK: - Size Formatting Helper

extension VideoDownloadManager {
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
