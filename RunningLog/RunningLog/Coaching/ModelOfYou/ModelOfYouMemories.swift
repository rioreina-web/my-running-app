//
//  ModelOfYouMemories.swift
//  RunningLog
//
//  Long-term memory visibility + control (roadmap 4.1, "it knows you").
//  Reads `user_memories` directly — the table's RLS scopes the auth'd client
//  to the signed-in user (SELECT), and the "Users delete own memories" DELETE
//  policy (migration 20260702190000) lets the athlete forget any item.
//
//  Trust rule (plan Step 7): memory ships ONLY with athlete control. This
//  surface is the control. Read + delete only for now — editing can wait.
//

import SwiftUI
import Supabase
import os

// MARK: - Model

struct UserMemoryItem: Decodable, Identifiable {
    let id: String
    let category: String
    let content: String
    let their_words: String?
    let memory_date: String?
    let importance: Int?
    let mention_count: Int?
}

enum MemoryStore {
    /// Active (non-archived) memories, highest-importance first. RLS-scoped.
    static func fetchActive() async -> [UserMemoryItem] {
        do {
            let rows: [UserMemoryItem] = try await supabase
                .from("user_memories")
                .select("id, category, content, their_words, memory_date, importance, mention_count")
                .eq("status", value: "active")
                .order("importance", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            Log.coach.error("UserMemory fetch failed: \(error)")
            return []
        }
    }

    /// Forget one memory. DELETE (not archive) — the athlete's own revocation.
    static func forget(id: String) async -> Bool {
        do {
            try await supabase
                .from("user_memories")
                .delete()
                .eq("id", value: id)
                .execute()
            return true
        } catch {
            Log.coach.error("UserMemory delete failed: \(error)")
            return false
        }
    }
}

// MARK: - Category display

private struct MemoryCategoryMeta {
    let key: String
    let title: String
}

/// Render order + friendly titles. Categories not listed fall to the bottom
/// under their raw name (forward-compatible if the extractor adds one).
private let MEMORY_CATEGORY_ORDER: [MemoryCategoryMeta] = [
    .init(key: "constraint", title: "Constraints"),
    .init(key: "preference", title: "Preferences"),
    .init(key: "life", title: "Life"),
    .init(key: "pr", title: "Records"),
    .init(key: "race", title: "Races"),
    .init(key: "gear", title: "Gear"),
    .init(key: "episode", title: "Moments"),
]

// MARK: - Summary card (main Model of You screen)

/// A trapdoor-style summary that opens the full, editable list in a sheet.
struct MemoriesCard: View {
    @State private var items: [UserMemoryItem] = []
    @State private var loaded = false
    @State private var showingList = false

    var body: some View {
        Button {
            showingList = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT YOU'VE TOLD ME")
                    .font(.dripStat(9)).tracking(1.1)
                    .foregroundStyle(Color.drip.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(loaded ? "\(items.count)" : "—")
                        .font(.dripDisplay(21))
                        .foregroundStyle(Color.drip.textPrimary)
                    Text(items.count == 1 ? "thing I remember" : "things I remember")
                        .font(.dripBody(12))
                        .foregroundStyle(Color.drip.textSecondary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.drip.textTertiary)
                }
                Text(observation)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
        .task {
            if loaded { return }
            items = await MemoryStore.fetchActive()
            loaded = true
        }
        .sheet(isPresented: $showingList) {
            MemoriesListView(items: $items)
        }
    }

    private var observation: String {
        if loaded && items.isEmpty {
            return "Nothing yet — tell me about your life and training in your memos, and I'll remember."
        }
        return "Everything I remember about you, in your own words. Tap to review or forget anything."
    }
}

// MARK: - Full list (read + swipe-to-forget)

struct MemoriesListView: View {
    @Binding var items: [UserMemoryItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(orderedCategories, id: \.self) { cat in
                            Section(title(for: cat)) {
                                ForEach(items.filter { $0.category == cat }) { item in
                                    MemoryRow(item: item)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                Task { await forget(item) }
                                            } label: {
                                                Label("Forget", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("What I remember")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("I don't know much about you yet")
                .font(.dripBody(16))
                .foregroundStyle(Color.drip.textPrimary)
            Text("Tell me about your life and training in your memos — night shifts, race goals, the runs that stick with you — and I'll remember them here.")
                .font(.dripBody(13))
                .foregroundStyle(Color.drip.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    /// Categories present, in the canonical order, unknowns appended.
    private var orderedCategories: [String] {
        let present = Set(items.map { $0.category })
        var out = MEMORY_CATEGORY_ORDER.map { $0.key }.filter { present.contains($0) }
        out.append(contentsOf: present.subtracting(out).sorted())
        return out
    }

    private func title(for cat: String) -> String {
        MEMORY_CATEGORY_ORDER.first { $0.key == cat }?.title ?? cat.capitalized
    }

    private func forget(_ item: UserMemoryItem) async {
        let ok = await MemoryStore.forget(id: item.id)
        if ok {
            await MainActor.run { items.removeAll { $0.id == item.id } }
        }
    }
}

private struct MemoryRow: View {
    let item: UserMemoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.content)
                .font(.dripBody(15))
                .foregroundStyle(Color.drip.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // Episodes carry the athlete's verbatim phrase + when it happened.
            if let words = item.their_words, !words.isEmpty {
                Text("“\(words)”")
                    .font(.dripBody(13))
                    .italic()
                    .foregroundStyle(Color.drip.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = item.memory_date, !date.isEmpty {
                Text(date)
                    .font(.dripStat(10)).tracking(0.6)
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
