import SwiftUI
import UniformTypeIdentifiers
import RunSyncDomain
import RunSyncSimulation

/// Bibliothèque locale (E03, RS-020) : import de fichiers, BPM manuel, suppression,
/// affichage honnête de la disponibilité et des droits.
///
/// Aucun fichier n'est fourni avec l'application : tout morceau réel vient de
/// l'utilisateur, et n'est tempo-ajustable que s'il en atteste les droits.
struct MusicLibraryView: View {
    @Environment(DependencyContainer.self) private var container

    @State private var isFileImporterPresented = false
    @State private var pendingImportURL: URL?
    @State private var isRightsSheetPresented = false
    @State private var attestsAdaptationRights = false
    @State private var bpmEditingTrack: TrackDescriptor?
    @State private var bpmText = ""
    @State private var didRefreshAvailability = false

    private var library: LocalLibraryStore { container.library }

    var body: some View {
        NavigationStack {
            List {
                importedSection
                testToneSection
                demoSection
                providerSection
            }
            .navigationTitle("Musique")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Importer", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: library.importableContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    attestsAdaptationRights = false
                    isRightsSheetPresented = true
                case let .failure(error):
                    library.reportImportFailure("Sélection impossible : \(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $isRightsSheetPresented) { rightsSheet }
            .alert("BPM du morceau", isPresented: bpmAlertBinding) {
                TextField("BPM (ex. 168)", text: $bpmText)
                    .keyboardType(.decimalPad)
                Button("Enregistrer") { saveBPM() }
                Button("Annuler", role: .cancel) { bpmEditingTrack = nil }
            } message: {
                Text("Le BPM saisi est utilisé tel quel : aucune estimation n'est faite à ce stade (RS-026).")
            }
            .onAppear {
                guard !didRefreshAvailability else { return }
                didRefreshAvailability = true
                let missing = library.refreshAvailability()
                if !missing.isEmpty {
                    library.reportImportFailure(
                        "\(missing.count) fichier(s) importé(s) ont disparu du stockage et ne sont plus jouables."
                    )
                }
            }
        }
    }

    // MARK: - Sections

    private var importedSection: some View {
        Section {
            if library.tracks.isEmpty {
                Text("Aucun morceau importé pour l'instant.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.tracks) { track in
                    importedRow(track)
                }
            }
        } header: {
            Text("Mes morceaux importés")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                if let message = library.lastImportSummary {
                    Text(message).foregroundStyle(Theme.accentSecondary)
                }
                if let error = library.lastErrorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Text("Les fichiers importés sont copiés dans l'espace privé de l'application. "
                    + "La bibliothèque n'est pas encore conservée entre deux lancements (RS-033).")
            }
            .font(Theme.Typography.caption)
        }
    }

    private func importedRow(_ track: TrackDescriptor) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text(track.title)
            Text(track.artist ?? "Artiste inconnu")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.small) {
                Text(track.nominalBPM.map { "\(Int($0)) BPM" } ?? "BPM inconnu")
                    .font(Theme.Typography.caption)
                Text(track.bpmProvenance.displayName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                Text(track.isTempoAdjustable ? "Tempo ajustable" : "Tempo non ajustable")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(track.isTempoAdjustable ? Theme.accentSecondary : .secondary)
            }
            if !track.isFileAvailable {
                Text("Fichier introuvable : ce morceau ne peut plus être joué.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            bpmText = track.nominalBPM.map { String(Int($0)) } ?? ""
            bpmEditingTrack = track
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                library.remove(trackID: track.id)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Touchez pour saisir le BPM")
    }

    /// Morceau de test synthétisé par le projet : c'est ce qui rend la
    /// synchronisation vérifiable à l'oreille dès la première installation.
    private var testToneSection: some View {
        Section {
            PrimaryActionButton(
                title: "Ajouter le morceau de test intégré",
                systemImage: "metronome",
                isEnabled: library.isBundledTestToneAvailable
            ) {
                library.addBundledTestTrack()
            }
            if !library.isBundledTestToneAvailable {
                Text("Morceau de test absent du paquet de l'application.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Morceau de test")
        } footer: {
            Text("Clics à 168 BPM synthétisés par le projet lui-même (domaine public), copiés dans "
                + "l'espace privé de l'application comme n'importe quel import. Ils permettent de vérifier "
                + "à l'oreille que la musique accélère et ralentit avec ta cadence.")
        }
    }

    private var demoSection: some View {
        Section {
            ForEach(DemoLibrary.tracks) { track in
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text(track.title)
                    Text(track.nominalBPM.map { "\(Int($0)) BPM — \(track.bpmProvenance.displayName)" } ?? "BPM inconnu")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Morceaux de démonstration")
        } footer: {
            Text("Descripteurs seuls, sans fichier audio : ils permettent de démontrer la synchronisation "
                + "sans capteur ni musique. Aucun morceau protégé n'est inclus dans le dépôt.")
        }
    }

    private var providerSection: some View {
        Section {
            ForEach(container.providers) { provider in
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        Text(provider.compliance.status.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(provider.compliance.status == .confirmed
                                ? Theme.accentSecondary : .secondary)
                    }
                    Text(provider.compliance.notes)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Sources musicales")
        } footer: {
            Text("Aucune source tierce n'est active : leur conformité n'a pas été vérifiée. "
                + "Voir Docs/PROVIDER_COMPLIANCE.md.")
        }
    }

    // MARK: - Feuille d'attestation de droits

    @ViewBuilder
    private var rightsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ce morceau va être copié dans l'espace privé de l'application. "
                        + "RunSync n'adapte le tempo que des morceaux dont vous avez les droits.")
                        .font(Theme.Typography.body)
                    Toggle("J'atteste avoir le droit d'adapter ce morceau", isOn: $attestsAdaptationRights)
                } header: {
                    Text("Droits d'utilisation")
                } footer: {
                    Text("Sans attestation, le morceau est importé mais son tempo reste non ajustable : "
                        + "aucune option trompeuse ne sera affichée (§02).")
                }
                Section {
                    PrimaryActionButton(
                        title: "Importer et attester",
                        systemImage: "checkmark.seal",
                        isEnabled: attestsAdaptationRights
                    ) {
                        performImport(attested: true)
                    }
                    Button("Importer sans attester") {
                        performImport(attested: false)
                    }
                }
            }
            .navigationTitle("Importer un morceau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        pendingImportURL = nil
                        isRightsSheetPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var bpmAlertBinding: Binding<Bool> {
        Binding(
            get: { bpmEditingTrack != nil },
            set: { if !$0 { bpmEditingTrack = nil } }
        )
    }

    private func performImport(attested: Bool) {
        defer {
            pendingImportURL = nil
            isRightsSheetPresented = false
        }
        guard let url = pendingImportURL else { return }
        library.importFile(at: url, userAttestsAdaptationRights: attested)
    }

    private func saveBPM() {
        defer { bpmEditingTrack = nil }
        guard let track = bpmEditingTrack else { return }
        let normalized = bpmText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        library.setManualBPM(Double(normalized), for: track.id)
    }
}
