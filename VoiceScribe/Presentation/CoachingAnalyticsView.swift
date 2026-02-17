import SwiftUI

// MARK: - Analytics Dashboard

/// Displays cross-session coaching analytics from SQLite persistence.
/// Shows movement distribution, objection patterns, qualification trends,
/// and per-session report browsing.
struct CoachingAnalyticsView: View {
    @State private var movementStats: [SessionPersistence.MovementStat] = []
    @State private var objectionStats: [SessionPersistence.ObjectionStat] = []
    @State private var qualTrend: [(sessionId: UUID, date: Date, score: Float)] = []
    @State private var coachingStats: SessionPersistence.CoachingStatsSummary?
    @State private var selectedSessionReport: (id: UUID, title: String, report: String)?

    // Phase 3: AI insights + semantic search
    @State private var insights: [ConversationInsight] = []
    @State private var searchQuery = ""
    @State private var searchResults: [SemanticSearchResult] = []
    private let analyticsEngine = AnalyticsEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection

                // Semantic search bar
                searchSection

                // AI-generated insights
                if !insights.isEmpty {
                    insightsSection
                }

                if let stats = coachingStats, stats.totalRows > 0 {
                    HStack(spacing: 12) {
                        movementSection
                        objectionSection
                    }

                    qualificationSection
                    reportBrowserSection
                } else if insights.isEmpty && searchResults.isEmpty {
                    emptyState
                }

                // Search results
                if !searchResults.isEmpty {
                    searchResultsSection
                }
            }
            .padding(16)
        }
        .onAppear { loadData() }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coaching Analytics").font(.title2).fontWeight(.semibold)
                if let stats = coachingStats {
                    Text("\(stats.reports) appels analysés · \(stats.snapshots) snapshots · \(stats.alerts) alertes")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise").font(.body)
            }.buttonStyle(.plain)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Pas encore de données").font(.headline).foregroundStyle(.secondary)
            Text("Les analytics apparaîtront après votre premier appel avec le coaching activé.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Movement Distribution
    
    private var movementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Temps par mouvement", systemImage: "chart.bar.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            
            if movementStats.isEmpty {
                Text("—").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .center)
            } else {
                let maxCount = movementStats.map(\.snapshotCount).max() ?? 1
                
                ForEach(movementStats, id: \.movement) { stat in
                    HStack(spacing: 6) {
                        Text(stat.movement.emoji).font(.system(size: 10))
                        Text(stat.movement.shortLabel).font(.system(size: 9)).frame(width: 40, alignment: .leading)
                        
                        GeometryReader { geo in
                            let w = geo.size.width * CGFloat(stat.snapshotCount) / CGFloat(maxCount)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(barColor(for: stat.avgFluidity))
                                .frame(width: max(4, w), height: 12)
                        }
                        .frame(height: 12)
                        
                        Text("\(stat.snapshotCount)×")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                
                HStack(spacing: 12) {
                    legendDot(color: .green, label: "Fluide >0.7")
                    legendDot(color: .orange, label: "Moyen")
                    legendDot(color: .red, label: "Tendu <0.4")
                }
                .font(.system(size: 8)).foregroundStyle(.tertiary).padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Objection Patterns
    
    private var objectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Objections fréquentes", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            
            if objectionStats.isEmpty {
                Text("Aucune objection détectée").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(objectionStats, id: \.category) { stat in
                    HStack(spacing: 6) {
                        objectionIcon(stat.category)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(objectionLabel(stat.category))
                                .font(.system(size: 10)).fontWeight(.medium)
                            HStack(spacing: 4) {
                                Text("\(stat.count)×").font(.system(size: 9, design: .monospaced))
                                strengthBar(stat.avgStrength)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Qualification Trend
    
    private var qualificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Évolution qualification BANT", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            
            if qualTrend.isEmpty {
                Text("Pas encore de données de qualification")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(qualTrend.reversed().enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: 2) {
                            Text("\(Int(entry.score * 100))%")
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(qualColor(entry.score))
                                .frame(width: 20, height: max(4, CGFloat(entry.score) * 60))
                            
                            Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 7))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                
                // Trend summary
                if let first = qualTrend.first, let last = qualTrend.last, qualTrend.count >= 2 {
                    let diff = first.score - last.score
                    HStack(spacing: 4) {
                        Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9))
                            .foregroundStyle(diff >= 0 ? .green : .red)
                        Text(diff >= 0 ? "+\(Int(diff * 100))% sur \(qualTrend.count) sessions" : "\(Int(diff * 100))% sur \(qualTrend.count) sessions")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Report Browser
    
    private var reportBrowserSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rapports post-appel", systemImage: "doc.text.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            
            if qualTrend.isEmpty {
                Text("Aucun rapport sauvegardé")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(Array(qualTrend.enumerated()), id: \.offset) { _, entry in
                    Button(action: { loadReport(entry.sessionId, date: entry.date) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10)).fontWeight(.medium)
                                Text("Qualification: \(Int(entry.score * 100))%")
                                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            
                            let snapshots = SessionPersistence.shared.loadSnapshots(sessionId: entry.sessionId)
                            let alerts = SessionPersistence.shared.loadAlerts(sessionId: entry.sessionId)
                            
                            HStack(spacing: 6) {
                                if !snapshots.isEmpty {
                                    let movements = Set(snapshots.map(\.movement)).count
                                    Text("\(movements) mvt").font(.system(size: 8, design: .monospaced)).foregroundStyle(.blue)
                                }
                                if !alerts.isEmpty {
                                    Text("\(alerts.count) ⚠️").font(.system(size: 8, design: .monospaced)).foregroundStyle(.orange)
                                }
                            }
                            
                            Image(systemName: selectedSessionReport?.id == entry.sessionId ? "chevron.up" : "chevron.right")
                                .font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .padding(6)
                        .background(selectedSessionReport?.id == entry.sessionId ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    if selectedSessionReport?.id == entry.sessionId, let report = selectedSessionReport?.report {
                        reportDetailView(report: report, sessionId: entry.sessionId)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
    
    // MARK: - Report Detail
    
    private func reportDetailView(report: String, sessionId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Report markdown (truncated preview)
            Text(report.prefix(800) + (report.count > 800 ? "\n\n[...]" : ""))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            
            // Memory slots captured
            let slots = SessionPersistence.shared.loadMemorySlots(sessionId: sessionId)
            if !slots.isEmpty {
                Text("Mémoire capturée").font(.system(size: 9)).fontWeight(.semibold).foregroundStyle(.secondary)
                FlowLayout(spacing: 4) {
                    ForEach(slots, id: \.key) { slot in
                        HStack(spacing: 2) {
                            Text(slot.key).font(.system(size: 8)).fontWeight(.medium)
                            Text("=").font(.system(size: 7)).foregroundStyle(.tertiary)
                            Text(slot.value).font(.system(size: 8)).lineLimit(1)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1)).cornerRadius(3)
                    }
                }
            }
            
            // Movement timeline
            let timeline = SessionPersistence.shared.reconstructTimeline(sessionId: sessionId)
            if !timeline.isEmpty {
                Text("Timeline").font(.system(size: 9)).fontWeight(.semibold).foregroundStyle(.secondary)
                HStack(spacing: 1) {
                    ForEach(Array(timeline.enumerated()), id: \.offset) { _, entry in
                        let totalDur = timeline.map { $0.end - $0.start }.reduce(0, +)
                        let ratio = totalDur > 0 ? CGFloat((entry.end - entry.start) / totalDur) : 0
                        
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(entry.movement.act.uiColor)
                                .frame(height: 6)
                            Text(entry.movement.emoji).font(.system(size: 7))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: ratio * 200)
                    }
                }
            }
        }
        .padding(.leading, 12)
        .transition(.opacity)
    }
    
    // MARK: - Search Section

    private var searchSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Rechercher dans les sessions...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit { performSearch() }
                .onChange(of: searchQuery) { _, newValue in
                    if newValue.isEmpty { searchResults = [] }
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Insights IA", systemImage: "lightbulb.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                InsightRow(insight: insight)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Résultats (\(searchResults.count))", systemImage: "doc.text.magnifyingglass")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            ForEach(Array(searchResults.prefix(10).enumerated()), id: \.offset) { _, result in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.sessionTitle)
                            .font(.system(size: 10, weight: .medium))

                        Spacer()

                        Text("\(Int(result.relevanceScore * 100))%")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(result.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }

                    Text(result.context)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(6)
                .background(Color.accentColor.opacity(0.03))
                .cornerRadius(4)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Data Loading

    private func loadData() {
        let p = SessionPersistence.shared
        movementStats = p.movementStats()
        objectionStats = p.objectionStats()
        qualTrend = p.qualificationTrend()
        coachingStats = p.coachingStats()

        // Load AI insights
        analyticsEngine.refresh()
        insights = analyticsEngine.generateInsights()
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }
        analyticsEngine.refresh()
        searchResults = analyticsEngine.semanticSearch(query: searchQuery)
    }
    
    private func loadReport(_ sessionId: UUID, date: Date) {
        if selectedSessionReport?.id == sessionId {
            selectedSessionReport = nil
        } else if let report = SessionPersistence.shared.loadReport(sessionId: sessionId) {
            selectedSessionReport = (sessionId, date.formatted(), report)
        }
    }
    
    // MARK: - Helpers
    
    private func barColor(for fluidity: Float) -> Color {
        if fluidity > 0.7 { return .green }
        if fluidity > 0.4 { return .orange }
        return .red
    }
    
    private func qualColor(_ score: Float) -> Color {
        if score > 0.7 { return .green }
        if score > 0.4 { return .blue }
        return .orange
    }
    
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
        }
    }
    
    private func strengthBar(_ strength: Float) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Float(i) / 5.0 < strength ? Color.orange : Color.gray.opacity(0.2))
                    .frame(width: 6, height: 4)
            }
        }
    }
    
    private func objectionIcon(_ category: String) -> some View {
        let icon: String = {
            switch category {
            case "price": return "dollarsign.circle"
            case "timing": return "clock"
            case "competitor": return "flag.2.crossed"
            case "authority": return "person.badge.key"
            case "need_denial": return "hand.raised"
            case "trust": return "shield.slash"
            default: return "questionmark.circle"
            }
        }()
        return Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.orange).frame(width: 16)
    }
    
    private func objectionLabel(_ category: String) -> String {
        switch category {
        case "price": return "Prix / Budget"
        case "timing": return "Timing"
        case "competitor": return "Concurrent"
        case "authority": return "Autorité / Décideur"
        case "need_denial": return "Pas de besoin"
        case "trust": return "Confiance"
        default: return category.capitalized
        }
    }
}

// MARK: - Insight Row

struct InsightRow: View {
    let insight: ConversationInsight

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: categoryIcon)
                .font(.system(size: 10))
                .foregroundStyle(categoryColor)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(insight.title)
                        .font(.system(size: 10, weight: .medium))

                    Spacer()

                    impactBadge
                }

                Text(insight.description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(insight.dataPoints) données")
                    .font(.system(size: 7))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(6)
        .background(categoryColor.opacity(0.04))
        .cornerRadius(4)
    }

    private var categoryIcon: String {
        switch insight.category {
        case .strength: return "star.fill"
        case .improvement: return "arrow.up.right"
        case .risk: return "exclamationmark.triangle.fill"
        case .pattern: return "repeat"
        }
    }

    private var categoryColor: Color {
        switch insight.category {
        case .strength: return .green
        case .improvement: return .blue
        case .risk: return .red
        case .pattern: return .purple
        }
    }

    private var impactBadge: some View {
        let (label, color): (String, Color) = {
            switch insight.impact {
            case .high: return ("Fort", .red)
            case .medium: return ("Moyen", .orange)
            case .low: return ("Faible", .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 7, weight: .bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Flow Layout (for memory tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(in width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        
        return (positions, y + lineHeight)
    }
}
