import SwiftUI
import RunSyncDomain

/// Réglages et profil (E07). Chaque option affiche son état réel : ce qui n'est
/// pas encore implémenté est annoncé comme tel, jamais simulé.
struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings

        Form {
            Section {
                Picker("Limite", selection: $settings.maxAdjustment) {
                    Text("±5 % (par défaut)").tag(0.05)
                    Text("±3 % (prudent)").tag(0.03)
                }
            } header: {
                Text("Limite d'adaptation audio")
            } footer: {
                Text("Le tempo appliqué ne dépasse jamais cette limite (FR-009). "
                    + "Le réglage s'applique aux nouvelles sessions.")
            }

            Section {
                Picker("Source de cadence", selection: $settings.cadenceSource) {
                    ForEach(CadenceSourceChoice.allCases) { choice in
                        Text(choice.displayName)
                            .tag(choice)
                    }
                }
                Text(settings.cadenceSource.availabilityMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(settings.cadenceSource.isAvailable ? .secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Cadence")
            } footer: {
                Text("Le capteur de l'iPhone mesure une cadence réelle ; le scénario simulé ne dépend "
                    + "d'aucun capteur (utile dans le simulateur). Si le capteur est indisponible ou refusé, "
                    + "la session l'annonce au lieu d'inventer une cadence.")
            }

            Section {
                Toggle("Signaux sonores de guidage", isOn: $settings.audibleGuidanceEnabled)
            } header: {
                Text("Guidage")
            } footer: {
                Text("Désactivés par défaut (§05). Les signaux sonores ne sont pas encore restitués : "
                    + "seul l'écart à la cible est affiché.")
            }

            Section {
                InfoRow(
                    label: "Unités",
                    value: "km / min:sec",
                    detail: "Le système d'unités impériales n'est pas encore proposé."
                )
            } header: {
                Text("Unités")
            }

            Section {
                InfoRow(
                    label: "Export CSV de l'historique",
                    value: "Indisponible",
                    detail: "Étape RS-035 : l'historique n'est pas encore enregistré."
                )
                InfoRow(
                    label: "Effacement des données locales",
                    value: "Partiel",
                    detail: "Les morceaux importés se suppriment depuis l'onglet Musique (fichier inclus). "
                        + "L'effacement global arrive avec RS-035."
                )
                InfoRow(
                    label: "Permissions demandées",
                    value: "Mouvement et forme",
                    detail: "Demandée au démarrage d'une course avec le capteur, jamais au lancement. "
                        + "Aucun accès micro, aucune donnée de santé, aucun analytics tiers."
                )
            } header: {
                Text("Confidentialité")
            } footer: {
                Text("Voir Docs/PRIVACY.md. Les permissions mouvement et localisation seront "
                    + "demandées au moment utile, jamais au démarrage.")
            }

            Section {
                ForEach(container.providers) { provider in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            Text(provider.compliance.status.displayName)
                                .foregroundStyle(provider.compliance.status == .confirmed
                                    ? Theme.accentSecondary : .secondary)
                        }
                        Text(provider.isTempoAdjustmentPermitted
                            ? "Tempo ajustable"
                            : "Tempo non ajustable")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Sources musicales et conformité")
            } footer: {
                Text("Les sources tierces ne sont pas vérifiées à ce jour : elles restent désactivées. "
                    + "Voir Docs/PROVIDER_COMPLIANCE.md.")
            }

            Section {
                InfoRow(label: "Version", value: "0.3.0 (capteur et audio réels)")
                Button("Revoir l'introduction") {
                    settings.onboardingCompleted = false
                }
            } header: {
                Text("À propos")
            }
        }
        .navigationTitle("Réglages")
    }
}
