import Foundation

/// Shared hallucination filter for transcription engines.
/// Detects common phantom outputs produced during silence or noise.
enum HallucinationFilter {

    private static let patterns: Set<String> = [
        "sous-titrage société radio-canada",
        "sous-titres réalisés para la communauté d'amara.org",
        "sous-titres par la communauté d'amara.org",
        "sous-titrage st 501",
        "merci d'avoir regardé",
        "merci de votre attention",
        "s'abonner",
        "je vous remercie",
    ]

    private static let shortPatterns: Set<String> = [
        "merci.", "...", "…", "you", "thank you.", "thanks.",
        "bye.", "the end.", "fin.", "merci",
    ]

    static func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased()
        if shortPatterns.contains(lower) { return true }
        for pattern in patterns {
            if lower.contains(pattern) { return true }
        }
        // Repeated single words/phrases (e.g. "Merci. Merci. Merci.")
        let words = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let unique = Set(words)
            if unique.count == 1 { return true }
        }
        return false
    }
}
