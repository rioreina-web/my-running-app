//
//  CoachingDocument.swift
//  RunningLog
//
//  Swift mirror of the `coaching_documents` table — the knowledge-base
//  surface the Coach Read cites via `§` chips. Only the user-facing
//  fields are decoded; the underlying table has embeddings + indexing
//  metadata the iOS layer doesn't need.
//
//  Created for Phase 2.2 (DailyReadService hydration cache).
//

import Foundation

/// A knowledge-base doc referenced by a `CoachRead.Segment.doc` citation
/// or surfaced in the Sources panel.
struct CoachingDocument: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    /// Free-form category label ("aerobic support", "race-day fueling",
    /// etc.). Optional — older docs predate categorization.
    let category: String?
    /// Full doc content, markdown-ish. The DocDetailSheet renders this
    /// verbatim; inline `§` chips just show the title.
    let content: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case content
    }
}
