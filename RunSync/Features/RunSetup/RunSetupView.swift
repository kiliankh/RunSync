import SwiftUI
import RunSyncDomain
import RunSyncSimulation

/// Préparation de la course (E04) : Follow ou Pace, cadence cible déclarée,
/// limite d'ajustement, playlist. Le bouton Démarrer n'est activé que si
/// l'audio est réellement jouable **ou** si l'utilisateur choisit explicitement
/// une course sans audio (§03 E04).
struct RunSetupView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var configuration = RunConfiguration()
    @State private var isRunPresented = false

    /// Le bouton n'est actif que si la session peut réellement faire quelque chose :
    /// jouer un fichier local, **ou** exécuter une course sans audio explicitement
    /// choisie. Aucun état « prêt à jouer » simulé.
    private var canStart: Bool {
        configuration.allowRunWithoutAudio || container.hasPlayableAudio(for: configuration)
    }

    var body: some View {
        @Bindable var settings = container.settings

        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $configuration.mode) {
                        ForEach(RunMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(configuration.mode.shortExplanation)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if configuration.mode == .pace {
                    Section {
                        Picker("Préréglage", selection: presetBinding) {
                            Text("160").tag(160.0)
                            Text("170").tag(170.0)
                            Text("180").tag(180.0)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Cadence cible")
                            Slider(value: $configuration.targetCadenceSPM, in: 120...200, step: 1)
                            Text("\(Int(configuration.targetCadenceSPM)) SPM")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Allure cible")
                            Slider(value: paceBinding, in: 240...420, step: 5)
                            Text(PaceUnits.formattedPace(secondsPerKilometer: configuration.targetPaceSecondsPerKilometer))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Cadence cible")
                    } footer: {
                        Text("L'allure seule ne détermine pas la cadence (elle dépend de la longueur de foulée). "
                            + "La cadence cible est donc déclarée explicitement ; une calibration personnelle "
                            + "viendra plus tard.")
                    }
                } else {
                    Section {
                        InfoRow(
                            label: "Cible du mode Follow",
                            value: "cadence mesurée",
                            detail: "La musique suit ta cadence filtrée, dans les limites d'ajustement choisies."
                        )
                    } header: {
                        Text("Cadence cible")
                    }
                }

                Section("Limite d'ajustement du tempo") {
                    Picker("Limite", selection: $settings.maxAdjustment) {
                        Text("±5 % (par défaut)").tag(0.05)
                        Text("±3 % (prudent)").tag(0.03)
                    }
                }

                Section {
                    Picker("Morceau", selection: playlistBinding) {
                        ForEach(container.availableTracks) { track in
                            Text(trackLabel(track)).tag(track.id)
                        }
                    }
                } header: {
                    Text("Playlist")
                } footer: {
                    Text(availableTracksFooter)
                }

                Section {
                    InfoRow(
                        label: "Lecture",
                        value: hasPlayableSelection ? "Fichier local" : "Aucun fichier",
                        detail: hasPlayableSelection
                            ? "Le morceau sera lu depuis l'espace privé de l'application, avec ajustement du tempo dans la limite choisie."
                            : "Le morceau sélectionné est un descripteur de démonstration : il n'a pas de fichier audio à jouer."
                    )
                    Toggle("Course sans audio (démonstration)", isOn: $configuration.allowRunWithoutAudio)
                } header: {
                    Text("Audio")
                } footer: {
                    Text(audioFooter)
                }

                Section {
                    PrimaryActionButton(
                        title: "Démarrer",
                        systemImage: "figure.run",
                        isEnabled: canStart
                    ) {
                        isRunPresented = true
                    }
                }
            }
            .navigationTitle("Courir")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .fullScreenCover(isPresented: $isRunPresented) {
                ActiveRunView(configuration: configuration)
            }
            .onAppear(perform: ensureSelectionIsValid)
        }
    }

    // MARK: - Liaisons

    /// Préréglage de cadence : sélectionne la valeur la plus proche parmi 160/170/180.
    private var presetBinding: Binding<Double> {
        Binding(
            get: {
                [160.0, 170.0, 180.0].min { abs($0 - configuration.targetCadenceSPM) < abs($1 - configuration.targetCadenceSPM) } ?? 170
            },
            set: { configuration.targetCadenceSPM = $0 }
        )
    }

    private var paceBinding: Binding<Double> {
        Binding(
            get: { configuration.targetPaceSecondsPerKilometer ?? 300 },
            set: { configuration.targetPaceSecondsPerKilometer = $0 }
        )
    }

    private var playlistBinding: Binding<UUID> {
        Binding(
            get: {
                let tracks = container.availableTracks
                if let selected = configuration.playlistTrackIDs.first,
                   tracks.contains(where: { $0.id == selected }) {
                    return selected
                }
                return tracks.first?.id ?? DemoLibrary.testTrackID
            },
            set: { configuration.playlistTrackIDs = [$0] }
        )
    }

    /// La sélection doit toujours pointer sur un morceau réellement présent : après
    /// un import, une suppression ou la disparition d'un fichier, on retombe sur le
    /// premier morceau disponible au lieu d'afficher une sélection vide.
    private func ensureSelectionIsValid() {
        let tracks = container.availableTracks
        guard !tracks.isEmpty else { return }
        if !tracks.contains(where: { configuration.playlistTrackIDs.contains($0.id) }) {
            configuration.playlistTrackIDs = [tracks[0].id]
        }
    }

    /// Vrai si le morceau sélectionné possède un fichier réellement lisible.
    private var hasPlayableSelection: Bool {
        container.hasPlayableAudio(for: configuration)
    }

    private var audioFooter: String {
        if configuration.allowRunWithoutAudio {
            return "Course sans audio : le scénario de cadence tourne, mais aucune musique n'est jouée. "
                + "Désactivez cette option pour une vraie lecture."
        }
        if hasPlayableSelection {
            let limit = Int((container.settings.maxAdjustment * 100).rounded())
            return "« Démarrer » est disponible : le morceau sera réellement joué et son tempo ajusté de ±\(limit) % au maximum."
        }
        return "Ajoutez le morceau de test depuis l'onglet Musique, ou importez vos propres fichiers, "
            + "pour obtenir une vraie lecture. Sinon, activez la course sans audio."
    }

    private var availableTracksFooter: String {
        let importedCount = container.library.tracks.count
        guard importedCount > 0 else {
            return "Aucun morceau importé : les morceaux de démonstration sont proposés. "
                + "Ajoutez le morceau de test intégré, ou importez vos fichiers, depuis l'onglet Musique."
        }
        return "\(importedCount) morceau(x) importé(s) — bibliothèque locale uniquement. "
            + "Les playlists intelligentes par plage de BPM arrivent avec RS-025."
    }

    private func trackLabel(_ track: TrackDescriptor) -> String {
        let bpm = track.nominalBPM.map { "\(Int($0)) BPM (\(track.bpmProvenance.displayName))" } ?? "BPM inconnu"
        return "\(track.title) — \(bpm)"
    }
}
