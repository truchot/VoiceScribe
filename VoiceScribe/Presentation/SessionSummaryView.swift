import SwiftUI

// MARK: - Post-Session AI Summary

/// Displays the AI-generated summary after a recording session ends.
/// Shows executive summary, key points, action items, and coaching feedback.
struct SessionSummaryView: View {
    @EnvironmentObject var summary: SummaryStore
    @State private var showFullSummary = true

    var body: some View {
        if summary.isGeneratingSummary {
            generatingView
        } else if let sessionSummary = summary.currentSummary {
            summaryContent(sessionSummary)
        } else if let error = summary.summaryError {
            errorView(error)
        }
    }

    // MARK: - Generating State

    private var generatingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Génération du résumé IA...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Summary Content

    private func summaryContent(_ s: SessionSummary) -> some View {
        VStack(spacing: 0) {
            // Header with toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showFullSummary.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.accentColor)

                    Text("Résumé IA")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(.accentColor)

                    Text("(\(s.backend.displayLabel))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.quaternary)

                    Spacer()

                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(s.toMarkdown(), forType: .string)
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copier en Markdown")

                    Image(systemName: showFullSummary ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if showFullSummary {
                Divider().padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 10) {
                    // Executive summary
                    Text(s.executiveSummary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)

                    // Key points
                    if !s.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Points clés").font(.system(.caption2, weight: .bold)).foregroundStyle(.secondary)
                            ForEach(Array(s.keyPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•").foregroundStyle(.accentColor)
                                    Text(point).font(.caption)
                                }
                            }
                        }
                    }

                    // Action items
                    if !s.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Actions à faire").font(.system(.caption2, weight: .bold)).foregroundStyle(.secondary)
                            ForEach(Array(s.actionItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 6) {
                                    priorityBadge(item.priority)
                                    Text(item.title)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if !item.owner.isEmpty {
                                        Text(item.owner)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }

                    // Coaching feedback
                    if !s.coachingFeedback.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feedback coaching").font(.system(.caption2, weight: .bold)).foregroundStyle(.secondary)
                            Text(s.coachingFeedback)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Next steps
                    if !s.nextSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prochaines étapes").font(.system(.caption2, weight: .bold)).foregroundStyle(.secondary)
                            Text(s.nextSteps)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.accentColor.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Résumé: \(error)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Réessayer") {
                summary.clearSummary()
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private func priorityBadge(_ priority: ActionItem.Priority) -> some View {
        let (label, color): (String, Color) = {
            switch priority {
            case .high: return ("!", .red)
            case .medium: return ("•", .orange)
            case .low: return ("◦", .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 12)
    }
}
