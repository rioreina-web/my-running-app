import Foundation
import os
import Supabase

@Observable
final class InjuryService {
    var injuries: [Injury] = []
    var isLoading = false
    var isAnalyzing = false
    var errorMessage: String?

    // Voice niggles — merged into the Living Log alongside formal injuries.
    private var niggleMentions: [NiggleMentionRow] = []
    private var niggleResolutions: [NiggleResolutionRow] = []

    // Daily run mileage keyed by UTC start-of-day, loaded from training_logs.
    // Powers the Plate 28 stat strip (AVG VOL / AVG LOAD) without needing a
    // dedicated injury_mentions table. Populated by fetchTrainingDays().
    private var milesByDay: [Date: Double] = [:]

    // DATE columns (mentioned_at / resolved_at) are decoded as String, not
    // Date: the Supabase Swift `.value` decoder only parses ISO-8601 and
    // throws on a bare DATE, which would drop the whole fetch.
    private struct NiggleMentionRow: Decodable {
        let id: UUID
        let training_log_id: UUID?
        let body_area: String
        let side: String?
        let verbatim_quote: String?
        let severity_hint: String?
        let mentioned_at: String
    }
    private struct NiggleResolutionRow: Decodable {
        let body_area: String
        let side: String?
        let resolved_at: String
        let verbatim_quote: String?
    }
    // workout_date is TIMESTAMPTZ; decoded as String and bucketed to a UTC day
    // so it lines up with body_mentions' bare-DATE mentioned_at.
    private struct TrainingDayRow: Decodable {
        let workout_date: String?
        let workout_distance_miles: Double?
    }

    // MARK: - Fetch everything (formal injuries + voice niggles)

    @MainActor
    func fetchAll() async {
        await fetchInjuries()
        await fetchNiggles()
        await fetchTrainingDays()
    }

    @MainActor
    private func fetchNiggles() async {
        let userId = (AuthManager.shared.currentUserId ?? "").lowercased()
        guard !userId.isEmpty else { return }
        do {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let since = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
            let mentions: [NiggleMentionRow] = try await supabase
                .from("body_mentions")
                .select("id, training_log_id, body_area, side, verbatim_quote, severity_hint, mentioned_at")
                .eq("user_id", value: userId)
                .gte("mentioned_at", value: df.string(from: since))
                .order("mentioned_at", ascending: false)
                .limit(1000)
                .execute().value
            let resolutions: [NiggleResolutionRow] = try await supabase
                .from("niggle_resolutions")
                .select("body_area, side, resolved_at, verbatim_quote")
                .eq("user_id", value: userId)
                .limit(1000)
                .execute().value
            niggleMentions = mentions
            niggleResolutions = resolutions
        } catch {
            // Non-fatal: formal injuries still render if niggles fail to load.
            Log.database.error("Failed to fetch niggles: \(error)")
        }
    }

    /// Loads the athlete's per-day run mileage for the last ~12 months so the
    /// Plate 28 stat strip can correlate aches with training. Bucketed by UTC
    /// day to line up with body_mentions' bare-DATE mentioned_at.
    @MainActor
    private func fetchTrainingDays() async {
        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return }
        do {
            let since = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
            let rows: [TrainingDayRow] = try await supabase
                .from("training_logs")
                .select("workout_date, workout_distance_miles")
                .eq("user_id", value: userId)
                .gte("workout_date", value: ISO8601DateFormatter().string(from: since))
                .limit(3000)
                .execute().value
            var map: [Date: Double] = [:]
            for r in rows {
                guard let miles = r.workout_distance_miles, miles > 0,
                      let iso = r.workout_date, let day = Self.utcDay(fromISO: iso) else { continue }
                map[day, default: 0] += miles
            }
            milesByDay = map
        } catch {
            // Non-fatal: cards still render; affected stat cells fall back to "—".
            Log.database.error("Failed to fetch training days for injury stats: \(error)")
        }
    }

    // MARK: - Plate 28 stat computation

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }()

    /// Parses an ISO-8601 timestamp (with or without fractional seconds) to its
    /// UTC start-of-day. nil if unparseable.
    private static func utcDay(fromISO s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let d = withFrac.date(from: s) ?? plain.date(from: s) else { return nil }
        return utcCalendar.startOfDay(for: d)
    }

    /// Computes (avg volume, avg load, trend) for an ache from its mention days.
    /// Pure function of the mention dates + the milesByDay map.
    ///
    ///  • AVG VOL  — mean distance of the runs on the mention days.
    ///  • AVG LOAD — mean 7-day rolling mileage ending on each mention day
    ///               (an "acute load" proxy; no fabricated intensity metric).
    ///  • TREND    — recent-7 vs prior-7 mention counts inside the trailing
    ///               14 days. nil unless >= 2 mentions land in that window.
    private func stats(forMentionDays days: [Date], now: Date)
        -> (vol: Double?, load: Int?, trend: AcheTrend?) {
        let cal = Self.utcCalendar
        let mentionDays = days.map { cal.startOfDay(for: $0) }

        // AVG VOL — runs on mention days
        let vols = mentionDays.compactMap { milesByDay[$0] }.filter { $0 > 0 }
        let vol = vols.isEmpty ? nil : (vols.reduce(0, +) / Double(vols.count))

        // AVG LOAD — 7-day rolling mileage ending on each mention day
        var loads: [Double] = []
        for d in mentionDays {
            var sum = 0.0
            for k in 0..<7 {
                if let day = cal.date(byAdding: .day, value: -k, to: d) {
                    sum += milesByDay[day] ?? 0
                }
            }
            if sum > 0 { loads.append(sum) }
        }
        let load = loads.isEmpty ? nil : Int((loads.reduce(0, +) / Double(loads.count)).rounded())

        // TREND — mention cadence in the trailing 14 days
        let today = cal.startOfDay(for: now)
        var recent = 0, prior = 0
        for d in mentionDays {
            let daysAgo = cal.dateComponents([.day], from: d, to: today).day ?? 99
            if (0...6).contains(daysAgo) { recent += 1 }
            else if (7...13).contains(daysAgo) { prior += 1 }
        }
        let trend: AcheTrend?
        if recent + prior < 2 { trend = nil }
        else if recent > prior { trend = .worsening }
        else if recent < prior { trend = .easing }
        else { trend = .steady }

        return (vol.map { ($0 * 10).rounded() / 10 }, load, trend)
    }

    /// Fallback stats for a manually-added injury that has no voice mentions:
    /// averages over the injury's active window (capped to the last 84 days),
    /// so the strip still shows real training context. No trend (needs mentions).
    private func windowStats(from firstReported: Date, now: Date)
        -> (vol: Double?, load: Int?) {
        let cal = Self.utcCalendar
        let end = cal.startOfDay(for: now)
        let cap = cal.date(byAdding: .day, value: -83, to: end) ?? firstReported
        let start = max(cal.startOfDay(for: firstReported), cap)
        guard end >= start else { return (nil, nil) }
        var runDays: [Double] = []
        var totalMiles = 0.0
        var dayCount = 0
        var day = start
        while day <= end {
            if let m = milesByDay[day], m > 0 { runDays.append(m); totalMiles += m }
            dayCount += 1
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let vol = runDays.isEmpty ? nil : runDays.reduce(0, +) / Double(runDays.count)
        let weeks = max(1.0, Double(dayCount) / 7.0)
        let load = totalMiles > 0 ? Int((totalMiles / weeks).rounded()) : nil
        return (vol.map { ($0 * 10).rounded() / 10 }, load)
    }

    // MARK: - Promote a voice niggle to a formal (editable) injury

    /// Turns a voice-detected ache into a real `injuries` row so it can be
    /// viewed and edited in the detail sheet. Idempotent: if an active injury
    /// for the same body-area + side already exists, that one is returned
    /// instead of creating a duplicate. Returns nil on failure.
    @MainActor
    func promoteToInjury(_ entry: LivingLogEntry) async -> Injury? {
        if !entry.isNiggle { return entry.injury }

        let k = Self.key(area: entry.bodyArea, side: entry.side)
        if let existing = activeInjuries.first(where: { Self.key(area: $0.bodyArea, side: $0.side) == k }) {
            return existing
        }

        let userId = AuthManager.shared.userId
        guard !userId.isEmpty else { return nil }

        var row: [String: AnyJSON] = [
            "user_id": .string(userId),
            "body_area": .string(entry.bodyArea),
            "side": .string(entry.side),
            "severity": .integer(NiggleSeverity.score(entry.severityWord)),
            "status": .string("active"),
            "source": .string("voice_memo"),
        ]
        if let quote = entry.lastQuote, !quote.isEmpty {
            row["description"] = .string(quote)
        }

        do {
            let created: Injury = try await supabase
                .from("injuries")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            await fetchInjuries()
            return created
        } catch {
            Log.database.error("Failed to promote niggle to injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.promoteToInjury")
            errorMessage = "Could not open this ache for editing."
            return nil
        }
    }

    /// Mark a voice-niggle ache resolved by writing an all-clear watermark to
    /// `niggle_resolutions` (via the resolve-niggle edge function). Niggles
    /// have no `injuries` row, so they can't use the injury status path.
    @MainActor
    func resolveNiggle(bodyArea: String, side: String) async -> Bool {
        do {
            _ = try await callEdgeFunction(
                name: "resolve-niggle",
                body: ["body_area": bodyArea, "side": side == "unknown" ? "" : side]
            )
            await fetchNiggles()
            return true
        } catch {
            Log.database.error("Failed to resolve niggle: \(error)")
            errorMessage = "Could not mark resolved."
            return false
        }
    }

    // MARK: - Fetch All Injuries

    @MainActor
    func fetchInjuries() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: [Injury] = try await supabase
                .from("injuries")
                .select()
                .order("status", ascending: true)
                .order("severity", ascending: false)
                .order("first_reported_at", ascending: false)
                .limit(100)
                .execute()
                .value

            injuries = response
        } catch {
            Log.database.error("Failed to fetch injuries: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.fetchInjuries: Failed to fetch injuries")
            errorMessage = "Could not load injuries."
        }

        isLoading = false
    }

    // MARK: - Create Injury (Manual)

    @MainActor
    func createInjury(
        bodyArea: String,
        side: String,
        severity: Int,
        description: String?
    ) async -> Bool {
        do {
            let userId = AuthManager.shared.currentUserId ?? ""
            var newInjury: [String: AnyJSON] = [
                "user_id": .string(userId),
                "body_area": .string(bodyArea),
                "side": .string(side),
                "severity": .integer(severity),
                "status": .string("active"),
                "source": .string("manual"),
            ]

            if let description, !description.isEmpty {
                newInjury["description"] = .string(description)
            }

            try await supabase
                .from("injuries")
                .insert(newInjury)
                .execute()

            await fetchInjuries()
            return true
        } catch {
            Log.database.error("Failed to create injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.createInjury: Failed to create injury")
            errorMessage = "Could not save injury."
            return false
        }
    }

    // MARK: - Update Injury

    @MainActor
    func updateInjury(
        id: UUID,
        severity: Int? = nil,
        status: InjuryStatus? = nil,
        description: String? = nil
    ) async -> Bool {
        var updateData: [String: AnyJSON] = [:]

        if let severity { updateData["severity"] = .integer(severity) }
        if let description { updateData["description"] = .string(description) }
        if let status {
            updateData["status"] = .string(status.rawValue)
            if status == .resolved {
                updateData["resolved_at"] = .string(ISO8601DateFormatter().string(from: Date()))
            }
        }

        guard !updateData.isEmpty else { return true }

        do {
            try await supabase
                .from("injuries")
                .update(updateData)
                .eq("id", value: id.uuidString)
                .execute()

            await fetchInjuries()
            return true
        } catch {
            Log.database.error("Failed to update injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.updateInjury: Failed to update injury \(id)")
            errorMessage = "Could not update injury."
            return false
        }
    }

    // MARK: - Delete Injury

    @MainActor
    func deleteInjury(id: UUID) async -> Bool {
        do {
            try await supabase
                .from("injuries")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()

            injuries.removeAll { $0.id == id }
            return true
        } catch {
            Log.database.error("Failed to delete injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.deleteInjury: Failed to delete injury \(id)")
            errorMessage = "Could not delete injury."
            return false
        }
    }

    // MARK: - AI Analysis

    @MainActor
    func analyzeInjury(injuryId: UUID) async -> InjuryAnalysis? {
        isAnalyzing = true
        errorMessage = nil

        do {
            let data = try await callEdgeFunction(
                name: "injury-analysis",
                body: ["injuryId": injuryId.uuidString]
            )

            struct AnalysisResponse: Codable {
                let analysis: InjuryAnalysis?
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(AnalysisResponse.self, from: data)

            // Update local state
            if let analysis = response.analysis,
               let index = injuries.firstIndex(where: { $0.id == injuryId }) {
                injuries[index].aiAnalysis = analysis
                injuries[index].aiAnalysisAt = Date()
            }

            isAnalyzing = false
            return response.analysis
        } catch {
            Log.database.error("Failed to analyze injury: \(error)")
            ErrorReporter.shared.report(error, context: "InjuryService.analyzeInjury: AI analysis request failed for injury \(injuryId)")
            errorMessage = "Could not analyze injury. Please try again."
            isAnalyzing = false
            return nil
        }
    }

    // MARK: - Computed Properties (formal injuries)

    var activeInjuries: [Injury] {
        injuries.filter { $0.status == .active || $0.status == .monitoring }
    }

    var resolvedInjuries: [Injury] {
        injuries.filter { $0.status == .resolved }
    }

    var hasActiveInjuries: Bool { !activeEntries.isEmpty }

    // MARK: - Unified Living Log (formal injuries + voice niggles)

    /// area+side → canonical key. Side normalized so null / "unknown" collapse.
    private static func key(area: String, side: String?) -> String {
        let s = (side ?? "").lowercased()
        let norm = (s.isEmpty || s == "unknown") ? "unspecified" : s
        return "\(area.lowercased())|\(norm)"
    }

    private static var dateFmt: DateFormatter {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC"); df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }

    private static func synthesizedInjury(area: String, side: String?, severityHint: String?,
                                          firstSeen: Date, resolvedAt: Date?, status: InjuryStatus,
                                          quote: String?, id: UUID) -> Injury {
        Injury(
            id: id, userId: "", bodyArea: area,
            side: (side.map { $0.isEmpty ? "unknown" : $0 }) ?? "unknown",
            description: quote, severity: NiggleSeverity.score(severityHint), status: status,
            firstReportedAt: firstSeen, resolvedAt: resolvedAt, source: .voiceMemo,
            sourceReferenceId: nil, aiAnalysis: nil, aiAnalysisAt: nil,
            createdAt: firstSeen, updatedAt: firstSeen
        )
    }

    /// Active vs resolved niggles via the watermark rule: a mention is active
    /// only if its date is strictly AFTER the latest resolution for that
    /// area+side. Mirrors athlete-state.ts (the Coach Read's active-niggle rule).
    private func niggleEntries() -> (active: [LivingLogEntry], resolved: [LivingLogEntry]) {
        let df = Self.dateFmt

        var latestResolved: [String: (date: Date, area: String, side: String?, quote: String?)] = [:]
        for r in niggleResolutions {
            guard let d = df.date(from: r.resolved_at) else { continue }
            let k = Self.key(area: r.body_area, side: r.side)
            if let cur = latestResolved[k], cur.date >= d { continue }
            latestResolved[k] = (d, r.body_area, r.side, r.verbatim_quote)
        }

        var groups: [String: (area: String, side: String?, rows: [NiggleMentionRow], dates: [Date])] = [:]
        for m in niggleMentions {
            guard let d = df.date(from: m.mentioned_at) else { continue }
            let k = Self.key(area: m.body_area, side: m.side)
            if let wm = latestResolved[k], d <= wm.date { continue }  // cleared → not active
            groups[k, default: (m.body_area, m.side, [], [])].rows.append(m)
            groups[k]!.dates.append(d)
        }

        let now = Date(); let cal = Calendar.current
        var active: [LivingLogEntry] = []
        for (_, g) in groups {
            guard let latest = g.rows.max(by: { $0.mentioned_at < $1.mentioned_at }) else { continue }
            var dots: Set<Int> = []
            for d in g.dates {
                let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 99
                if (0...13).contains(daysAgo) { dots.insert(13 - daysAgo) }
            }
            let injury = Self.synthesizedInjury(area: g.area, side: g.side, severityHint: latest.severity_hint,
                                                firstSeen: g.dates.min() ?? now, resolvedAt: nil, status: .active,
                                                quote: latest.verbatim_quote, id: latest.id)
            let s = stats(forMentionDays: g.dates, now: now)
            active.append(LivingLogEntry(id: latest.id, injury: injury, isNiggle: true,
                                         severityWord: latest.severity_hint, mentionsCount: g.rows.count,
                                         mentionDotIndices: dots, lastQuote: latest.verbatim_quote,
                                         avgVolumeMiles: s.vol, avgLoad: s.load, trend: s.trend))
        }

        var resolved: [LivingLogEntry] = []
        for (k, wm) in latestResolved where groups[k] == nil {
            let injury = Self.synthesizedInjury(area: wm.area, side: wm.side, severityHint: nil,
                                                firstSeen: wm.date, resolvedAt: wm.date, status: .resolved,
                                                quote: wm.quote, id: UUID())
            resolved.append(LivingLogEntry(id: injury.id, injury: injury, isNiggle: true,
                                           severityWord: nil, mentionsCount: nil, mentionDotIndices: [],
                                           lastQuote: wm.quote))
        }
        return (active, resolved)
    }

    /// Active aches: formal injuries + niggle aches, merged by body-part so a
    /// "sore knee" memo and a manual knee injury don't double up.
    var activeEntries: [LivingLogEntry] {
        var byKey: [String: LivingLogEntry] = [:]
        for e in niggleEntries().active { byKey[Self.key(area: e.bodyArea, side: e.side)] = e }
        var result: [LivingLogEntry] = []
        let now = Date()
        for inj in activeInjuries {
            let n = byKey.removeValue(forKey: Self.key(area: inj.bodyArea, side: inj.side))
            var entry = LivingLogEntry(id: inj.id, injury: inj, isNiggle: false, severityWord: nil,
                                       mentionsCount: n?.mentionsCount, mentionDotIndices: n?.mentionDotIndices ?? [],
                                       lastQuote: n?.lastQuote ?? inj.description)
            if let n {
                // Merged with a voice ache — reuse its mention-based stats.
                entry.avgVolumeMiles = n.avgVolumeMiles
                entry.avgLoad = n.avgLoad
                entry.trend = n.trend
            } else {
                // Pure manual injury — average training over its active window.
                let fb = windowStats(from: inj.firstReportedAt, now: now)
                entry.avgVolumeMiles = fb.vol
                entry.avgLoad = fb.load
            }
            result.append(entry)
        }
        result.append(contentsOf: byKey.values)
        return result.sorted { $0.injury.severity > $1.injury.severity }
    }

    var resolvedEntries: [LivingLogEntry] {
        var result = resolvedInjuries.map {
            LivingLogEntry(id: $0.id, injury: $0, isNiggle: false, severityWord: nil,
                           mentionsCount: nil, mentionDotIndices: [], lastQuote: $0.description)
        }
        let formalKeys = Set(resolvedInjuries.map { Self.key(area: $0.bodyArea, side: $0.side) })
        for e in niggleEntries().resolved where !formalKeys.contains(Self.key(area: e.bodyArea, side: e.side)) {
            result.append(e)
        }
        return result
    }

    var isEmpty: Bool {
        injuries.isEmpty && niggleMentions.isEmpty && niggleResolutions.isEmpty
    }

    // MARK: - Mention timeline

    /// The niggle mention-timeline, derived from rows this service already
    /// holds — no extra fetch. Built fresh on read; `@Observable` invalidates
    /// it whenever `fetchNiggles`/`fetchTrainingDays` land.
    ///
    /// DATE columns arrive as Strings (see `NiggleMentionRow`), so they are
    /// parsed here with the bare-DATE formatter rather than `utcDay(fromISO:)`,
    /// which expects a full ISO-8601 timestamp and would drop every row.
    var niggleTimeline: NiggleTimeline {
        let df = Self.dateFmt

        let mentions: [NiggleMention] = niggleMentions.compactMap { row in
            guard let date = df.date(from: row.mentioned_at) else { return nil }
            return NiggleMention(
                id: row.id,
                bodyArea: row.body_area,
                side: NiggleSide(raw: row.side),
                quote: row.verbatim_quote,
                severityHint: row.severity_hint,
                mentionedAt: date
            )
        }

        let resolutions = niggleResolutions.compactMap {
            row -> (bodyArea: String, side: NiggleSide, resolvedAt: Date, quote: String?)? in
            guard let date = df.date(from: row.resolved_at) else { return nil }
            return (row.body_area, NiggleSide(raw: row.side), date, row.verbatim_quote)
        }

        return NiggleTimelineBuilder.build(
            mentions: mentions,
            resolutions: resolutions,
            milesByDay: milesByDay,
            today: Date()
        )
    }
}
