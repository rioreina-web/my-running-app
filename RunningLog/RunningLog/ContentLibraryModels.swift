//
//  ContentLibraryModels.swift
//  RunningLog
//
//  Data models for the Content Library feature.
//

import SwiftUI

// MARK: - ContentCategory

enum ContentCategory: String, CaseIterable, Codable, Identifiable {
    case mobility
    case drills
    case strength
    case recovery
    case coachesCorner = "coaches_corner"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .mobility: "Mobility"
        case .drills: "Drills"
        case .strength: "Strength"
        case .recovery: "Recovery"
        case .coachesCorner: "Coach's Corner"
        }
    }

    var icon: String {
        switch self {
        case .mobility: "figure.flexibility"
        case .drills: "figure.run"
        case .strength: "dumbbell.fill"
        case .recovery: "heart.circle.fill"
        case .coachesCorner: "person.fill.questionmark"
        }
    }

    var description: String {
        switch self {
        case .mobility: "Stretching and flexibility routines"
        case .drills: "Running form and technique drills"
        case .strength: "Strength training for runners"
        case .recovery: "Post-run recovery routines"
        case .coachesCorner: "Coaching tips and advice"
        }
    }

    var accentColor: Color {
        switch self {
        case .mobility: Color.drip.energized
        case .drills: Color.drip.coral
        case .strength: Color.drip.tired
        case .recovery: Color.drip.positive
        case .coachesCorner: Color.drip.coralLight
        }
    }
}

// MARK: - ContentLibraryItem

struct ContentLibraryItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String?
    let category: String
    let videoUrl: String
    let thumbnailUrl: String?
    let durationSeconds: Int?
    let sortOrder: Int
    let isFeatured: Bool
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case category
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case sortOrder = "sort_order"
        case isFeatured = "is_featured"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var contentCategory: ContentCategory? {
        ContentCategory(rawValue: category)
    }

    var formattedDuration: String {
        guard let seconds = durationSeconds else { return "" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", remainingSeconds))"
        }
        return "\(remainingSeconds)s"
    }
}

// MARK: - ContentLibraryState

@Observable
class ContentLibraryState {
    var showSidebar = false
    var selectedCategory: ContentCategory?
    var showContentLibrary = false
    var selectedVideo: ContentLibraryItem?
    var showVideoPlayer = false
}
