import SwiftUI
// DataQuality est déclaré dans le paquet RunSyncDomain : sans cet import, la cible
// applicative ne compile pas (Color.color(for:) prend ce type en paramètre).
import RunSyncDomain

/// Design system minimal (RS-003) : couleurs, typographies et espacements
/// centralisés, contrastes lisibles en plein soleil et Dynamic Type respecté.
/// Aucune couleur ni taille n'est écrite « en dur » dans les écrans.
enum Theme {

    // MARK: - Couleurs

    /// Couleur d'accent (contraste vérifié sur fond sombre et clair).
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.13)
    static let accentSecondary = Color(red: 0.13, green: 0.62, blue: 0.60)
    static let cardBackground = Color(.secondarySystemBackground)
    static let screenBackground = Color(.systemBackground)

    /// Couleur associée à une qualité de donnée (NFR-007 : état toujours visible).
    static func color(for quality: DataQuality) -> Color {
        switch quality {
        case .good: return accentSecondary
        case .degraded: return .orange
        case .unavailable: return .red
        }
    }

    // MARK: - Espacements

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: - Typographies (relatives : Dynamic Type respecté)

    enum Typography {
        static let heroMetric = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let metric = Font.system(.title2, design: .rounded).weight(.semibold)
        static let metricCaption = Font.caption
        static let sectionTitle = Font.headline
        static let body = Font.body
        static let caption = Font.caption
    }

    /// Zone tactile minimale recommandée pour une utilisation en course (§03 E05).
    static let minimumTouchTarget: CGFloat = 60
}
