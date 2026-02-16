import SwiftUI

// MARK: - Domain → Color Mappings (Presentation Layer Only)
//
// These extensions bridge domain types to SwiftUI colors.
// Domain types (EmotionLabel, ConversationAct, etc.) stay framework-free.
// All color decisions live here — one place to update themes.

extension EmotionLabel {
    var color: Color {
        switch self {
        case .enthusiastic: .green
        case .satisfied:    .mint
        case .confident:    .blue
        case .animated:     .cyan
        case .neutral:      .gray
        case .hesitant:     .orange
        case .frustrated:   .red
        case .disengaged:   .purple
        }
    }
}

extension ConversationAct {
    var uiColor: Color {
        switch self {
        case .connexion:   .cyan
        case .exploration: .blue
        case .solution:    .purple
        case .suivi:       .mint
        }
    }
}
