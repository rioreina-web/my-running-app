//
//  ContentLibraryService.swift
//  RunningLog
//
//  Service for fetching content library videos from Supabase.
//

import Foundation
import os
import Supabase

@Observable
class ContentLibraryService {
    static let shared = ContentLibraryService()

    var isLoading = false
    var errorMessage: String?

    private init() {}

    /// Fetch all videos for a specific category
    func fetchVideos(for category: ContentCategory) async -> [ContentLibraryItem] {
        await MainActor.run { isLoading = true }

        do {
            let response: [ContentLibraryItem] = try await supabase
                .from("content_library")
                .select()
                .eq("category", value: category.rawValue)
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            await MainActor.run {
                isLoading = false
                errorMessage = nil
            }

            return response
        } catch {
            Log.content.error("Failed to fetch content library: \(error)")
            ErrorReporter.shared.report(error, context: "ContentLibraryService.fetchVideos: Failed to fetch content library for category \(category.rawValue)")
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to load videos"
            }
            return []
        }
    }

    /// Fetch featured videos across all categories
    func fetchFeaturedVideos() async -> [ContentLibraryItem] {
        do {
            return try await supabase
                .from("content_library")
                .select()
                .eq("is_featured", value: true)
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .limit(5)
                .execute()
                .value
        } catch {
            Log.content.error("Failed to fetch featured videos: \(error)")
            ErrorReporter.shared.report(error, context: "ContentLibraryService.fetchFeaturedVideos: Failed to fetch featured videos")
            return []
        }
    }

    /// Get count of videos per category (single query instead of N+1)
    func fetchCategoryCounts() async -> [ContentCategory: Int] {
        struct CategoryRow: Decodable { let category: String }
        do {
            let response: [CategoryRow] = try await supabase
                .from("content_library")
                .select("category")
                .eq("is_active", value: true)
                .limit(500)
                .execute()
                .value

            var counts: [ContentCategory: Int] = [:]
            for row in response {
                if let cat = ContentCategory(rawValue: row.category) {
                    counts[cat, default: 0] += 1
                }
            }
            return counts
        } catch {
            Log.content.error("Failed to fetch category counts: \(error)")
            ErrorReporter.shared.report(error, context: "ContentLibraryService.fetchCategoryCounts: Failed to fetch category counts")
            return [:]
        }
    }
}
