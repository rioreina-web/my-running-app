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
                .execute()
                .value

            await MainActor.run {
                isLoading = false
                errorMessage = nil
            }

            return response
        } catch {
            Log.content.error("Failed to fetch content library: \(error)")
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
            return []
        }
    }

    /// Get count of videos per category
    func fetchCategoryCounts() async -> [ContentCategory: Int] {
        var counts: [ContentCategory: Int] = [:]

        for category in ContentCategory.allCases {
            do {
                let response: [ContentLibraryItem] = try await supabase
                    .from("content_library")
                    .select("id")
                    .eq("category", value: category.rawValue)
                    .eq("is_active", value: true)
                    .execute()
                    .value

                counts[category] = response.count
            } catch {
                counts[category] = 0
            }
        }

        return counts
    }
}
