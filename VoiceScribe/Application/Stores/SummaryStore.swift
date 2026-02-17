import Foundation
import SwiftUI

/// Focused observable for AI-generated summaries and response suggestions.
///
/// Manages:
/// - Post-session summaries (generated after stopRecording)
/// - Real-time response suggestions (generated during conversation)
/// - Analytics insights and semantic search
@MainActor
final class SummaryStore: ObservableObject {

    // MARK: - Published State

    @Published var currentSummary: SessionSummary?
    @Published var isGeneratingSummary: Bool = false
    @Published var summaryError: String?

    @Published var responseSuggestions: [ResponseSuggestion] = []
    @Published var isGeneratingSuggestions: Bool = false

    @Published var insights: [ConversationInsight] = []
    @Published var searchResults: [SemanticSearchResult] = []
    @Published var isSearching: Bool = false

    // MARK: - Settings

    @AppStorage("llmBackend") var llmBackendRaw: String = LLMBackend.local.rawValue
    @AppStorage("autoSummaryEnabled") var autoSummaryEnabled: Bool = true
    @AppStorage("suggestionsEnabled") var suggestionsEnabled: Bool = true

    /// API key stored in macOS Keychain (not UserDefaults).
    var apiKey: String {
        get { KeychainService.shared.get(forKey: "llmApiKey") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainService.shared.delete(forKey: "llmApiKey")
            } else {
                KeychainService.shared.set(newValue, forKey: "llmApiKey")
            }
            objectWillChange.send()
        }
    }

    var llmBackend: LLMBackend {
        LLMBackend(rawValue: llmBackendRaw) ?? .local
    }

    var llmConfig: LLMConfig {
        LLMConfig(backend: llmBackend, apiKey: apiKey)
    }

    // MARK: - Dependencies

    private var llmProvider: LLMProvider
    private var apiLLMProvider: LLMProvider
    private var analytics: AnalyticsProvider

    /// Throttle suggestion generation.
    private var lastSuggestionTime: TimeInterval = 0
    private let suggestionThrottle: TimeInterval = 5.0

    // MARK: - Init

    init(
        llmProvider: LLMProvider = LocalLLMProvider(),
        apiLLMProvider: LLMProvider = APILLMProvider(),
        analytics: AnalyticsProvider = AnalyticsEngine()
    ) {
        self.llmProvider = llmProvider
        self.apiLLMProvider = apiLLMProvider
        self.analytics = analytics

        // One-time migration: move API key from UserDefaults to Keychain
        KeychainService.shared.migrateFromUserDefaults(key: "llmApiKey")
    }

    // MARK: - Summary Generation

    /// Generate a post-session summary.
    func generateSummary(
        transcript: String,
        report: PostCallReport?,
        topics: [DetectedTopic]
    ) async {
        isGeneratingSummary = true
        summaryError = nil

        do {
            let provider = resolveProvider()
            let summary = try await provider.summarize(
                transcript: transcript,
                report: report,
                topics: topics,
                config: llmConfig
            )
            currentSummary = summary
        } catch {
            summaryError = error.localizedDescription
        }

        isGeneratingSummary = false
    }

    /// Generate response suggestions for the current conversation context.
    func generateSuggestions(
        recentText: String,
        movement: ConversationMovement,
        emotion: EmotionalState,
        topics: [DetectedTopic],
        elapsed: TimeInterval
    ) async {
        guard suggestionsEnabled else { return }
        guard elapsed - lastSuggestionTime >= suggestionThrottle else { return }
        guard !recentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        lastSuggestionTime = elapsed
        isGeneratingSuggestions = true

        do {
            let provider = resolveProvider()
            let newSuggestions = try await provider.suggestResponse(
                recentText: recentText,
                movement: movement,
                emotion: emotion,
                topics: topics,
                config: llmConfig
            )
            responseSuggestions = newSuggestions
        } catch {
            // Suggestions are non-critical — fail silently
            Log.coaching.warning("Suggestion generation failed: \(error.localizedDescription)")
        }

        isGeneratingSuggestions = false
    }

    // MARK: - Analytics

    func refreshInsights() {
        analytics.refresh()
        insights = analytics.generateInsights()
    }

    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchResults = analytics.semanticSearch(query: query)
        isSearching = false
    }

    // MARK: - State Management

    func clearSuggestions() {
        responseSuggestions.removeAll()
    }

    func clearSummary() {
        currentSummary = nil
        summaryError = nil
    }

    func reset() {
        clearSuggestions()
        clearSummary()
        lastSuggestionTime = 0
    }

    // MARK: - Provider Resolution

    private func resolveProvider() -> LLMProvider {
        switch llmBackend {
        case .local:
            return llmProvider
        case .claudeAPI, .openAIAPI:
            if apiKey.isEmpty { return llmProvider } // Fallback to local
            return apiLLMProvider
        }
    }
}
