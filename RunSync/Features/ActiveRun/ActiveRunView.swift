import SwiftUI
import RunSyncDomain

/// Écran de session active (E05). Objectif : lisible en courant, un seul écran,
/// gros boutons, état du tempo et de l'audio toujours explicite.
struct ActiveRunView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let configuration: RunConfiguration
    @State private var viewModel: ActiveRunViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    content(for: viewModel)
                } else {
                    ProgressView("Préparation de la session…")
                        .padding(Theme.Spacing.xLarge)
                }
            }
            .background(Theme.screenBackground)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = container.makeActiveRunViewModel(configuration: configuration)
            }
        }
    }

    @ViewBuilder
    private func content(for viewModel: ActiveRunViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            captureStatus(for: viewModel)
            metrics(for: viewModel)
            tempoState(for: viewModel)
            if let recommended = viewModel.recommendedTrack {
                StatusBanner(
                    systemImage: "arrow.triangle.swap",
                    message: "Morceau mieux adapté : « \(recommended.title) ». Le morceau courant n'est pas coupé.",
                    tint: Theme.accentSecondary
                )
            }
            if let rateError = viewModel.lastRateError {
                StatusBanner(
                    systemImage: "speaker.slash",
                    message: "Tempo non appliqué : \(rateError)",
                    tint: .orange
                )
            }
            if let error = viewModel.lastError {
                StatusBanner(systemImage: "exclamationmark.triangle", message: error, tint: .red)
            }
            controls(for: viewModel)
            if viewModel.isFinished {
                RunSummaryView(metrics: viewModel.metrics)
            }
        }
        .padding(Theme.Spacing.medium)
    }

    /// Ce qui mesure et ce qui joue, annoncé sans ambiguïté : c'est ici que
    /// l'utilisateur découvre qu'il est en démonstration ou qu'il utilise vraiment
    /// son capteur et son fichier.
    private func captureStatus(for viewModel: ActiveRunViewModel) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            StatusBanner(
                systemImage: viewModel.hasPlayableAudio ? "music.note" : "speaker.slash",
                message: viewModel.audioStatusMessage,
                tint: viewModel.hasPlayableAudio ? Theme.accent : .orange
            )
            StatusBanner(
                systemImage: "figure.walk.motion",
                message: viewModel.cadenceSourceDescription,
                tint: Theme.accentSecondary
            )
            StatusBanner(
                systemImage: "location.slash",
                message: "Allure et distance indisponibles : le suivi GPS est l'étape RS-012."
            )
        }
    }

    private func metrics(for viewModel: ActiveRunViewModel) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                MetricTile(
                    title: "Cadence",
                    value: CadenceUnits.paceFreeCadenceText(viewModel.cadence.setpointSPM),
                    unit: "SPM",
                    detail: viewModel.cadence.setpointSPM == nil
                        ? "Aucune cadence exploitable"
                        : "Filtrée (médiane + lissage)",
                    tint: Theme.accent,
                    isEmphasized: true
                )
                MetricTile(
                    title: "Mode",
                    value: viewModel.mode.displayName,
                    unit: viewModel.mode == .pace
                        ? "cible \(Int(viewModel.targetCadenceSPM)) SPM"
                        : (viewModel.hasPlayableAudio ? "course" : "démo"),
                    detail: viewModel.mode.shortExplanation
                )
            }
            HStack(spacing: Theme.Spacing.small) {
                MetricTile(
                    title: "BPM morceau",
                    value: viewModel.currentTrack?.nominalBPM.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "BPM",
                    detail: viewModel.currentTrack?.title ?? "Aucun morceau sélectionné"
                )
                MetricTile(
                    title: "Taux d'ajustement",
                    value: PaceUnits.formattedRatePercent(viewModel.appliedAudioRate),
                    unit: "",
                    detail: viewModel.isRamping ? "Transition en cours" : "Vitesse audio appliquée"
                )
            }
            if viewModel.hasPlayableAudio {
                HStack(spacing: Theme.Spacing.small) {
                    MetricTile(
                        title: "Lecture",
                        value: viewModel.audioPositionText,
                        unit: "/ \(viewModel.audioDurationText)",
                        detail: viewModel.audioIsPlaying ? "En cours" : "En pause"
                    )
                    MetricTile(
                        title: "Durée active",
                        value: String(format: "%.0f", viewModel.metrics.activeSeconds),
                        unit: "s",
                        detail: "Session non persistée (RS-033)"
                    )
                }
            } else {
                MetricTile(
                    title: "Durée active",
                    value: String(format: "%.0f", viewModel.metrics.activeSeconds),
                    unit: "s",
                    detail: "Session non persistée (RS-033)"
                )
            }
            if viewModel.mode == .pace {
                MetricTile(
                    title: "Écart à la cadence cible",
                    value: viewModel.cadenceDeltaSPM.map { String(format: "%+.0f", $0) } ?? "—",
                    unit: "SPM",
                    detail: "Cible \(Int(viewModel.targetCadenceSPM)) SPM — indépendant du tempo appliqué"
                )
            }
        }
    }

    private func tempoState(for viewModel: ActiveRunViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                QualityBadge(quality: viewModel.decision?.quality ?? viewModel.cadence.quality)
                Spacer()
                Text(viewModel.isTempoAdjustable ? "Tempo ajustable" : "Tempo non ajustable")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(viewModel.isTempoAdjustable ? Theme.accentSecondary : .secondary)
            }
            Text(viewModel.reasonMessage)
                .font(Theme.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            if let decision = viewModel.decision {
                InfoRow(
                    label: "Ratio requis / appliqué",
                    value: "\(decision.requiredRate.map { String(format: "%.4f", $0) } ?? "—") / \(String(format: "%.4f", viewModel.appliedAudioRate))",
                    detail: decision.stepsPerBeat.map { "Ratio musical \($0):1" } ?? "Aucun ratio retenu"
                )
                InfoRow(
                    label: "Cadence cible retenue",
                    value: CadenceUnits.paceFreeCadenceText(viewModel.cadence.setpointSPM),
                    detail: "BPM cible du morceau : \(decision.targetTrackBPM.map { String(format: "%.1f", $0) } ?? "—")"
                )
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func controls(for viewModel: ActiveRunViewModel) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            if viewModel.state == .idle {
                PrimaryActionButton(title: "Démarrer la session", systemImage: "play.fill") {
                    viewModel.start()
                }
            }
            if viewModel.isRunning {
                PrimaryActionButton(
                    title: "Pause",
                    systemImage: "pause.fill",
                    tint: Theme.accentSecondary
                ) {
                    viewModel.pause()
                }
            }
            if viewModel.isPaused {
                PrimaryActionButton(title: "Reprendre", systemImage: "play.fill") {
                    viewModel.resume()
                }
            }
            if viewModel.hasPlayableAudio, viewModel.isRunning || viewModel.isPaused {
                PrimaryActionButton(
                    title: "Chanson suivante",
                    systemImage: "forward.fill",
                    tint: Theme.accentSecondary
                ) {
                    viewModel.nextTrack()
                }
                if !viewModel.playlistPositionText.isEmpty {
                    Text(viewModel.playlistPositionText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.isRunning || viewModel.isPaused {
                PrimaryActionButton(title: "Terminer", systemImage: "stop.fill", tint: .red) {
                    viewModel.finish()
                    container.recordFinishedRun(
                        configuration: configuration,
                        metrics: viewModel.metrics
                    )
                }
            }
            if viewModel.isFinished {
                PrimaryActionButton(
                    title: "Nouvelle session",
                    systemImage: "arrow.clockwise",
                    tint: Theme.accentSecondary
                ) {
                    viewModel.restart()
                }
            }
        }
    }
}

private extension CadenceUnits {
    /// Affichage d'une cadence sans jamais transformer une absence en 0.
    static func paceFreeCadenceText(_ spm: Double?) -> String {
        guard let spm else { return "—" }
        return String(format: "%.0f", spm)
    }
}
