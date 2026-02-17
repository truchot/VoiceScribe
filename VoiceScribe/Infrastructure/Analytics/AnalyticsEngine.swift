import Foundation

/// Cross-session analytics and semantic search engine.
///
/// Generates actionable insights from accumulated coaching data
/// and provides semantic search across all sessions using
/// TF-IDF-like relevance scoring on text segments.
final class AnalyticsEngine: AnalyticsProvider {

    // MARK: - Internal Types

    struct MovementStatEntry {
        let movement: ConversationMovement
        let avgDuration: TimeInterval
        let avgFluidity: Float
        let count: Int
    }

    struct SearchableSession {
        let id: UUID
        let title: String
        let segments: [String]
        let date: Date
    }

    // MARK: - State

    private var movementStats: [MovementStatEntry] = []
    private var sessions: [SearchableSession] = []
    private let persistence = SessionPersistence.shared

    // MARK: - AnalyticsProvider

    func generateInsights() -> [ConversationInsight] {
        var insights: [ConversationInsight] = []

        // Movement-based insights
        insights.append(contentsOf: movementInsights())

        // Session trend insights
        insights.append(contentsOf: sessionTrendInsights())

        // Objection pattern insights
        insights.append(contentsOf: objectionInsights())

        return insights
    }

    func semanticSearch(query: String) -> [SemanticSearchResult] {
        guard !query.isEmpty else { return [] }

        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty else { return [] }

        var results: [SemanticSearchResult] = []

        for session in sessions {
            for segment in session.segments {
                let score = relevanceScore(query: queryTerms, document: segment)
                if score > 0.2 {
                    results.append(SemanticSearchResult(
                        sessionId: session.id,
                        sessionTitle: session.title,
                        matchingText: segment,
                        relevanceScore: score,
                        timestamp: session.date,
                        context: extractContext(segment, query: query)
                    ))
                }
            }
        }

        // Sort by relevance
        results.sort { $0.relevanceScore > $1.relevanceScore }
        return Array(results.prefix(20))
    }

    func refresh() {
        loadMovementStats()
        loadSessions()
    }

    // MARK: - Data Injection (for testing)

    func injectMovementStats(_ stats: [MovementStatEntry]) {
        self.movementStats = stats
    }

    func addSearchableSession(id: UUID, title: String, segments: [String], date: Date) {
        sessions.append(SearchableSession(id: id, title: title, segments: segments, date: date))
    }

    // MARK: - Data Loading

    private func loadMovementStats() {
        let stats = persistence.movementStats()
        movementStats = stats.map { stat in
            MovementStatEntry(
                movement: ConversationMovement(rawValue: stat.movement) ?? .accueil,
                avgDuration: stat.avgDuration,
                avgFluidity: Float(stat.avgFluidity),
                count: stat.count
            )
        }
    }

    private func loadSessions() {
        sessions.removeAll()
        let savedSessions = persistence.loadSessionList()
        for session in savedSessions {
            let segments = session.segments.map(\.text)
            sessions.append(SearchableSession(
                id: session.id,
                title: session.title,
                segments: segments,
                date: session.startDate
            ))
        }
    }

    // MARK: - Insight Generators

    private func movementInsights() -> [ConversationInsight] {
        guard !movementStats.isEmpty else { return [] }

        var insights: [ConversationInsight] = []

        // Find movements with low fluidity
        let lowFluidity = movementStats.filter { $0.avgFluidity < 0.4 && $0.count >= 3 }
        for stat in lowFluidity {
            insights.append(ConversationInsight(
                title: "Fluidité faible en \(stat.movement.name)",
                description: "Score moyen de \(Int(stat.avgFluidity * 100))% sur \(stat.count) sessions. Travaillez les transitions vers ce mouvement.",
                category: .improvement,
                impact: .high,
                dataPoints: stat.count
            ))
        }

        // Find movements with high fluidity (strengths)
        let highFluidity = movementStats.filter { $0.avgFluidity > 0.7 && $0.count >= 3 }
        for stat in highFluidity {
            insights.append(ConversationInsight(
                title: "Force en \(stat.movement.name)",
                description: "Score moyen de \(Int(stat.avgFluidity * 100))% — c'est votre point fort.",
                category: .strength,
                impact: .medium,
                dataPoints: stat.count
            ))
        }

        // Find skipped movements
        let covered = Set(movementStats.map(\.movement))
        let skipped = ConversationMovement.allCases.filter { !covered.contains($0) }
        if !skipped.isEmpty && movementStats.count >= 3 {
            insights.append(ConversationInsight(
                title: "Mouvements systématiquement sautés",
                description: "\(skipped.map(\.name).joined(separator: ", ")) — explorez ces phases pour enrichir vos conversations.",
                category: .improvement,
                impact: .medium,
                dataPoints: movementStats.reduce(0) { $0 + $1.count }
            ))
        }

        // Duration outliers
        let longMovements = movementStats.filter { stat in
            let (_, expectedMax) = stat.movement.expectedDuration
            return stat.avgDuration > expectedMax * 1.5 && stat.count >= 3
        }
        for stat in longMovements {
            insights.append(ConversationInsight(
                title: "Temps excessif en \(stat.movement.name)",
                description: "Moyenne de \(Int(stat.avgDuration / 60))min contre \(Int(stat.movement.expectedDuration.1 / 60))min recommandé.",
                category: .risk,
                impact: .medium,
                dataPoints: stat.count
            ))
        }

        return insights
    }

    private func sessionTrendInsights() -> [ConversationInsight] {
        guard sessions.count >= 5 else { return [] }

        var insights: [ConversationInsight] = []

        // Session frequency
        let recentMonth = sessions.filter { $0.date > Date().addingTimeInterval(-30 * 24 * 3600) }
        if recentMonth.count > 0 {
            insights.append(ConversationInsight(
                title: "Activité du mois",
                description: "\(recentMonth.count) sessions ce mois, \(sessions.count) au total.",
                category: .pattern,
                impact: .low,
                dataPoints: sessions.count
            ))
        }

        return insights
    }

    private func objectionInsights() -> [ConversationInsight] {
        let stats = persistence.objectionStats()
        guard !stats.isEmpty else { return [] }

        var insights: [ConversationInsight] = []

        // Most frequent objection
        if let top = stats.first {
            insights.append(ConversationInsight(
                title: "Objection la plus fréquente: \(top.category)",
                description: "\(top.count) occurrences avec une intensité moyenne de \(Int(top.avgStrength * 100))%. Préparez des réponses types pour cette objection.",
                category: .pattern,
                impact: top.count > 5 ? .high : .medium,
                dataPoints: top.count
            ))
        }

        return insights
    }

    // MARK: - Semantic Search Internals

    private func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 } // Skip very short words
            .filter { !Self.stopWords.contains($0) }
        return Set(words)
    }

    private func relevanceScore(query: Set<String>, document: String) -> Float {
        let docTerms = tokenize(document)
        guard !docTerms.isEmpty else { return 0 }

        // Term overlap
        let overlap = query.intersection(docTerms)
        let overlapScore = Float(overlap.count) / Float(query.count)

        // Substring match bonus (for partial matches)
        let docLower = document.lowercased()
        var substringBonus: Float = 0
        for term in query {
            if docLower.contains(term) {
                substringBonus += 0.15
            }
        }

        // Length penalty (very short documents get a slight penalty)
        let lengthFactor = min(1.0, Float(docTerms.count) / 5.0)

        return min(1.0, (overlapScore * 0.6 + substringBonus) * lengthFactor)
    }

    private func extractContext(_ segment: String, query: String) -> String {
        // Return surrounding context around the match
        if segment.count <= 100 { return segment }
        let lower = segment.lowercased()
        let queryLower = query.lowercased()
        if let range = lower.range(of: queryLower) {
            let start = segment.index(range.lowerBound, offsetBy: -30, limitedBy: segment.startIndex) ?? segment.startIndex
            let end = segment.index(range.upperBound, offsetBy: 30, limitedBy: segment.endIndex) ?? segment.endIndex
            return "..." + String(segment[start..<end]) + "..."
        }
        return String(segment.prefix(100)) + "..."
    }

    // MARK: - Stop Words (FR)

    private static let stopWords: Set<String> = [
        "les", "des", "une", "que", "qui", "est", "dans", "pour", "pas",
        "sur", "par", "avec", "son", "mais", "ses", "aux", "comme",
        "plus", "leur", "cette", "tout", "aussi", "bien", "très",
        "the", "and", "for", "are", "but", "not", "you", "all",
        "can", "had", "her", "was", "one", "our", "out"
    ]
}
