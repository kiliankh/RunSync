import SwiftUI

/// Statistiques (E06/historique). Les sessions ne sont pas encore persistées :
/// l'écran le dit explicitement plutôt que d'afficher des chiffres inventés.
struct StatisticsView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                title: "Aucune session enregistrée",
                message: "L'enregistrement des sessions et l'export CSV arrivent avec RS-033 et RS-035. "
                    + "Le résumé d'une session en cours est visible à la fin de la course.",
                systemImage: "chart.bar.doc.horizontal"
            )
            .navigationTitle("Statistiques")
        }
    }
}
