import SwiftUI
import RunSyncDomain

/// Tuile de métrique lisible en courant : valeur très grande, unité explicite,
/// libellé secondaire. Accessibilité : un seul élément VoiceOver cohérent.
struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    var detail: String?
    var tint: Color = Theme.accent
    var isEmphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text(title)
                .font(Theme.Typography.metricCaption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xSmall) {
                Text(value)
                    .font(isEmphasized ? Theme.Typography.heroMetric : Theme.Typography.metric)
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(Theme.Typography.metricCaption)
                    .foregroundStyle(.secondary)
            }
            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(value) \(unit)")
        .accessibilityValue(detail ?? "")
    }
}

/// Badge d'état de qualité de donnée. Jamais décoratif : il porte l'information
/// « le tempo est ajusté, borné, maintenu ou indisponible » (NFR-007).
struct QualityBadge: View {
    let quality: DataQuality
    var overrideText: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Circle()
                .fill(Theme.color(for: quality))
                .frame(width: 10, height: 10)
            Text(overrideText ?? quality.displayName)
                .font(Theme.Typography.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.xSmall)
        .background(Theme.color(for: quality).opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Qualité des données : \(overrideText ?? quality.displayName)")
    }
}

/// Bannière d'état non intrusive (§03 E05) : capteurs indisponibles, GPS imprécis,
/// audio indisponible, tempo bloqué, écouteurs déconnectés.
struct StatusBanner: View {
    let systemImage: String
    let message: String
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(Theme.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Gros bouton d'action, utilisable en mouvement.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Theme.accent
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.small) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(Theme.Typography.sectionTitle)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

/// Ligne clé/valeur pour les écrans de réglages et de résumé.
struct InfoRow: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(Theme.Typography.body)
                Spacer(minLength: Theme.Spacing.small)
                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// État vide explicite : dit ce qui n'est pas encore disponible et pourquoi.
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "hourglass"

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
