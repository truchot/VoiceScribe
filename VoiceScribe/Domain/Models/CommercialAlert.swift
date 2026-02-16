import Foundation

/// Domain value object for commercial alerts detected during conversation.
/// Produced by the hybrid sentiment infrastructure, consumed by domain events and persistence.
struct CommercialAlert {
    let type: AlertType
    let category: String      // Signal category name (e.g., "objection", "achat")
    let message: String
    let strength: Float       // 0.0 - 1.0

    enum AlertType: String {
        case objection
        case buyingSignal
        case authority
        case competitor
    }
}
