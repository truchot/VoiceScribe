import SwiftUI

// MARK: - Real-Time LLM Suggestion Panel

/// Displays AI-generated response suggestions during a live conversation.
/// Shown below the coaching panel when suggestions are available.
struct SuggestionPanelView: View {
    @EnvironmentObject var summary: SummaryStore

    var body: some View {
        if !summary.responseSuggestions.isEmpty || summary.isGeneratingSuggestions {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)

                    Text("Suggestions IA")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(.purple)

                    if summary.isGeneratingSuggestions {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    }

                    Spacer()

                    Text(summary.llmBackend.displayLabel)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.quaternary)

                    Button(action: { summary.clearSuggestions() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)

                // Suggestions list
                ForEach(Array(summary.responseSuggestions.enumerated()), id: \.offset) { idx, suggestion in
                    if idx > 0 {
                        Divider().padding(.horizontal, 10)
                    }

                    SuggestionRow(suggestion: suggestion)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }

                Spacer().frame(height: 4)
            }
            .background(Color.purple.opacity(0.03))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.purple.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: ResponseSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: contextIcon)
                .font(.system(size: 9))
                .foregroundStyle(contextColor)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.text)
                    .font(.system(.caption, weight: .medium))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Text(contextLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(contextColor.opacity(0.7))
            }

            Spacer()

            if suggestion.confidence > 0 {
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private var contextIcon: String {
        switch suggestion.context {
        case .objectionHandling: return "shield.fill"
        case .questionToAsk: return "questionmark.bubble"
        case .closingOpportunity: return "checkmark.seal.fill"
        case .reengagement: return "arrow.counterclockwise"
        case .valueProposition: return "star.fill"
        case .followUp: return "envelope.fill"
        case .general: return "lightbulb.fill"
        }
    }

    private var contextColor: Color {
        switch suggestion.context {
        case .objectionHandling: return .red
        case .questionToAsk: return .blue
        case .closingOpportunity: return .green
        case .reengagement: return .orange
        case .valueProposition: return .purple
        case .followUp: return .mint
        case .general: return .secondary
        }
    }

    private var contextLabel: String {
        switch suggestion.context {
        case .objectionHandling: return "Réponse à objection"
        case .questionToAsk: return "Question à poser"
        case .closingOpportunity: return "Opportunité de closing"
        case .reengagement: return "Réengagement"
        case .valueProposition: return "Proposition de valeur"
        case .followUp: return "Suivi"
        case .general: return "Suggestion"
        }
    }
}

// MARK: - LLMBackend Display Helper

extension LLMBackend {
    var displayLabel: String {
        switch self {
        case .local: return "local"
        case .claudeAPI: return "Claude"
        case .openAIAPI: return "GPT-4"
        }
    }
}
