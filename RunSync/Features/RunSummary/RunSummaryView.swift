import SwiftUI
import RunSyncDomain

/// Résumé de course (E06). En phase 1 le résumé est en mémoire : la sauvegarde
/// et l'export sont l'étape RS-033/RS-035, et l'absence d'allure/distance vient
/// de l'absence de GPS (RS-012). Aucune valeur n'est inventée pour remplir le tableau.
struct RunSummaryView: View {
    let metrics: RunMetricsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Résumé de la session")
                .font(Theme.Typography.sectionTitle)

            InfoRow(
                label: "Durée active",
                value: String(format: "%.0f s", metrics.activeSeconds)
            )
            InfoRow(
                label: "Cadence moyenne",
                value: PaceUnits.formattedSPM(metrics.averageCadenceSPM),
                detail: "\(metrics.cadenceSampleCount) mesures valides retenues"
            )
            InfoRow(
                label: "Temps de synchronisation",
                value: metrics.synchronizedFraction.map { String(format: "%.0f %% du temps", $0 * 100) } ?? "—",
                detail: String(format: "%.0f s sans tempo piloté", metrics.unavailabilitySeconds)
            )
            InfoRow(
                label: "Allure moyenne",
                value: PaceUnits.formattedPace(secondsPerKilometer: metrics.averagePaceSecondsPerKilometer),
                detail: "GPS non actif : étape RS-012"
            )
            InfoRow(
                label: "Distance",
                value: metrics.distanceMeters.map { String(format: "%.0f m", $0) } ?? "—",
                detail: "Aucune distance estimée sans GPS"
            )
            InfoRow(
                label: "Morceaux lus",
                value: metrics.playedTrackTitles.isEmpty ? "—" : metrics.playedTrackTitles.joined(separator: ", "),
                detail: metrics.playedTrackTitles.isEmpty
                    ? "Aucun morceau joué pendant cette session"
                    : "Fichiers locaux lus, tempo ajusté dans la limite choisie"
            )
            InfoRow(
                label: "Mesures de cadence rejetées",
                value: "\(metrics.cadenceRejectionCount)",
                detail: "Diagnostic conservé, aucune valeur inventée"
            )

            StatusBanner(
                systemImage: "externaldrive.badge.questionmark",
                message: "Session non enregistrée : la persistance SwiftData arrive avec RS-033."
            )
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
