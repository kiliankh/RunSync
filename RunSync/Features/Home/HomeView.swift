import SwiftUI
import RunSyncDomain

/// Accueil (E02) : lancer une course en un geste, rappeler le dernier mode et
/// afficher le dernier résumé s'il existe.
struct HomeView: View {
    @Environment(DependencyContainer.self) private var container
    @Binding var selectedTab: AppTab

    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    Text("La musique suit tes pas.")
                        .font(Theme.Typography.sectionTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    PrimaryActionButton(title: "Commencer à courir", systemImage: "figure.run") {
                        selectedTab = .run
                    }

                    if let configuration = container.lastRunConfiguration {
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text("Dernière configuration")
                                .font(Theme.Typography.sectionTitle)
                            InfoRow(
                                label: "Mode",
                                value: configuration.mode.displayName,
                                detail: configuration.mode == .pace
                                    ? "Cadence cible \(Int(configuration.targetCadenceSPM)) SPM"
                                    : "Cadence mesurée"
                            )
                            if let metrics = container.lastRunMetrics {
                                RunSummaryView(metrics: metrics)
                            }
                        }
                    } else {
                        StatusBanner(
                            systemImage: "info.circle",
                            message: "Aucune session enregistrée. Le résumé apparaîtra ici après une course "
                                + "(persistance : RS-033).",
                            tint: Theme.accentSecondary
                        )
                    }

                    StatusBanner(
                        systemImage: "checkmark.shield",
                        message: "Phase 1 : noyau de synchronisation, simulateur déterministe et démonstration "
                            + "sans fournisseur tiers. Aucun compte ni réseau requis."
                    )
                }
                .padding(Theme.Spacing.medium)
            }
            .navigationTitle("RunSync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                NavigationStack { SettingsView() }
            }
        }
    }
}
