import Foundation

/// API-based LLM provider for Claude or OpenAI.
///
/// Sends conversation data to a remote API for high-quality summaries
/// and suggestions. Requires an API key configured in settings.
///
/// Supports:
/// - Claude API (Anthropic)
/// - OpenAI API (GPT-4)
final class APILLMProvider: LLMProvider {

    // MARK: - Generate

    func generate(prompt: String, config: LLMConfig) async throws -> LLMResponse {
        let start = Date()

        let requestBody = buildRequestBody(prompt: prompt, config: config)
        let (data, _) = try await sendRequest(body: requestBody, config: config)
        let text = extractText(from: data, config: config)

        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return LLMResponse(text: text, tokensUsed: text.count / 4, latencyMs: latency, backend: config.backend)
    }

    // MARK: - Summarize

    func summarize(
        transcript: String,
        report: PostCallReport?,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> SessionSummary {
        let prompt = buildSummaryPrompt(transcript: transcript, report: report, topics: topics)
        let response = try await generate(prompt: prompt, config: config)
        return parseSummary(from: response.text, config: config)
    }

    // MARK: - Suggest Response

    func suggestResponse(
        recentText: String,
        movement: ConversationMovement,
        emotion: EmotionalState,
        topics: [DetectedTopic],
        config: LLMConfig
    ) async throws -> [ResponseSuggestion] {
        let prompt = buildSuggestionPrompt(
            recentText: recentText,
            movement: movement,
            emotion: emotion,
            topics: topics
        )
        let response = try await generate(prompt: prompt, config: config)
        return parseSuggestions(from: response.text)
    }

    // MARK: - Prompt Builders

    private func buildSummaryPrompt(transcript: String, report: PostCallReport?, topics: [DetectedTopic]) -> String {
        var prompt = """
        Tu es un assistant commercial expert. Analyse cette transcription d'appel commercial et génère un résumé structuré.

        ## Transcription
        \(transcript.prefix(4000))

        """

        if let report = report {
            prompt += """

            ## Données coaching
            - Durée: \(Int(report.totalDuration / 60))min
            - Fluidité: \(Int(report.averageFluidityScore * 100))%
            - Qualification BANT: \(Int(report.memoryReport.qualificationScore * 100))%
            - Mouvements couverts: \(report.movementCount)

            """
        }

        if !topics.isEmpty {
            prompt += "\n## Topics détectés\n"
            for topic in topics {
                prompt += "- \(topic.category.rawValue): \(topic.name) (\(topic.mentionCount) mentions)\n"
            }
        }

        prompt += """

        Réponds en JSON avec cette structure:
        {
            "executiveSummary": "...",
            "keyPoints": ["...", "..."],
            "actionItems": [{"title": "...", "owner": "...", "priority": "Haute|Moyenne|Basse"}],
            "sentimentArc": "...",
            "nextSteps": "...",
            "coachingFeedback": "..."
        }
        """

        return prompt
    }

    private func buildSuggestionPrompt(
        recentText: String,
        movement: ConversationMovement,
        emotion: EmotionalState,
        topics: [DetectedTopic]
    ) -> String {
        """
        Tu es un coach commercial en temps réel. Le prospect vient de dire:
        "\(recentText)"

        Contexte:
        - Mouvement actuel: \(movement.name)
        - Émotion détectée: \(emotion.label.rawValue) (valence: \(emotion.valence), arousal: \(emotion.arousal))
        - Topics abordés: \(topics.map(\.name).joined(separator: ", "))

        Suggère 2-3 réponses courtes et percutantes que le vendeur pourrait utiliser.
        Format JSON: [{"text": "...", "context": "objectionHandling|questionToAsk|closingOpportunity|reengagement|valueProposition"}]
        """
    }

    // MARK: - Network

    private func buildRequestBody(prompt: String, config: LLMConfig) -> [String: Any] {
        switch config.backend {
        case .claudeAPI:
            return [
                "model": config.model,
                "max_tokens": config.maxTokens,
                "messages": [["role": "user", "content": prompt]]
            ]
        case .openAIAPI:
            return [
                "model": config.model.isEmpty ? "gpt-4" : config.model,
                "max_tokens": config.maxTokens,
                "temperature": config.temperature,
                "messages": [
                    ["role": "system", "content": "Tu es un assistant commercial expert en analyse de conversations de vente."],
                    ["role": "user", "content": prompt]
                ]
            ]
        default:
            return [:]
        }
    }

    private func sendRequest(body: [String: Any], config: LLMConfig) async throws -> (Data, URLResponse) {
        let url: URL
        var request: URLRequest

        switch config.backend {
        case .claudeAPI:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            request = URLRequest(url: url)
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAIAPI:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            request = URLRequest(url: url)
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        default:
            throw LLMError.unsupportedBackend
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        return try await URLSession.shared.data(for: request)
    }

    private func extractText(from data: Data, config: LLMConfig) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        switch config.backend {
        case .claudeAPI:
            if let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
        case .openAIAPI:
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let text = message["content"] as? String {
                return text
            }
        default: break
        }

        return ""
    }

    // MARK: - Parsers

    private func parseSummary(from text: String, config: LLMConfig) -> SessionSummary {
        // Try JSON parsing first
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return SessionSummary(
                sessionId: UUID(),
                backend: config.backend,
                executiveSummary: json["executiveSummary"] as? String ?? text,
                keyPoints: json["keyPoints"] as? [String] ?? [],
                actionItems: parseActionItems(json["actionItems"]),
                sentimentArc: json["sentimentArc"] as? String ?? "",
                nextSteps: json["nextSteps"] as? String ?? "",
                coachingFeedback: json["coachingFeedback"] as? String ?? ""
            )
        }

        // Fallback: use raw text
        return SessionSummary(
            sessionId: UUID(),
            backend: config.backend,
            executiveSummary: text,
            keyPoints: [],
            actionItems: [],
            sentimentArc: "",
            nextSteps: "",
            coachingFeedback: ""
        )
    }

    private func parseActionItems(_ raw: Any?) -> [ActionItem] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let title = item["title"] as? String else { return nil }
            let owner = item["owner"] as? String ?? "Moi"
            let priorityStr = item["priority"] as? String ?? "Moyenne"
            let priority = ActionItem.Priority(rawValue: priorityStr) ?? .medium
            return ActionItem(title: title, owner: owner, priority: priority)
        }
    }

    private func parseSuggestions(from text: String) -> [ResponseSuggestion] {
        guard let data = text.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [ResponseSuggestion(text: text, context: .general, timestamp: 0)]
        }

        return items.compactMap { item in
            guard let text = item["text"] as? String else { return nil }
            let contextStr = item["context"] as? String ?? "general"
            let context = SuggestionContext(rawValue: contextStr) ?? .general
            return ResponseSuggestion(text: text, context: context, timestamp: 0)
        }
    }

    // MARK: - Error

    enum LLMError: LocalizedError {
        case unsupportedBackend
        case apiError(String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .unsupportedBackend: return "Backend LLM non supporté"
            case .apiError(let msg): return "Erreur API: \(msg)"
            case .parseError: return "Erreur de parsing de la réponse"
            }
        }
    }
}
