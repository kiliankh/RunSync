import Foundation
import Observation
import RunSyncDomain

/// Métriques agrégées d'une session (§09). Aucune position GPS n'est conservée :
/// les champs correspondants restent `nil` plutôt que d'inventer une distance ou
/// une allure (FR-005).
struct RunMetricsSnapshot: Sendable, Equatable {
    var activeSeconds: Double = 0
    var cadenceSampleCount: Int = 0
    var averageCadenceSPM: Double?
    var synchronizedSeconds: Double = 0
    var distanceMeters: Double?
    var averagePaceSecondsPerKilometer: Double?
    var playedTrackTitles: [String] = []
    var cadenceRejectionCount: Int = 0
    var unavailabilitySeconds: Double = 0

    /// Part du temps de course pendant laquelle le tempo a réellement été piloté.
    var synchronizedFraction: Double? {
        guard activeSeconds > 0 else { return nil }
        return min(1, synchronizedSeconds / activeSeconds)
    }
}

/// Modèle de l'écran de session active (§03 E05).
///
/// Il est le **seul propriétaire** de la machine à états (§06) : le moteur audio
/// exécute ses ordres et lui rapporte ses événements, il ne décide jamais à sa
/// place. C'est ce qui évite l'état fantôme redouté au §07 exemple G.
///
/// La consigne de tempo vient du contrôleur (Follow ou Pace) ; la vitesse
/// réellement écrite dans le graphe audio passe par `PlaybackRateRamp`, qui borne
/// la dérivée et la fréquence de mise à jour (§05).
@MainActor
@Observable
final class ActiveRunViewModel {

    let configuration: RunConfiguration
    let audioItems: [RunAudioItem]
    /// D'où vient la cadence affichée. Toujours annoncé à l'utilisateur.
    let cadenceSourceDescription: String

    private(set) var state: RunSessionState = .idle
    private(set) var cadence: CadenceAssessment = .initial
    private(set) var decision: TempoDecision?
    private(set) var cadenceDeltaSPM: Double?
    private(set) var recommendedTrackID: UUID?
    private(set) var metrics = RunMetricsSnapshot()
    /// Récit de la session côté audio (lecture, interruption, fin de morceau).
    private(set) var audioStatusMessage: String
    /// Dernier refus d'ajustement de tempo (attestation, source, BPM). Séparé du
    /// récit pour ne pas l'effacer à chaque mise à jour d'état.
    private(set) var lastRateError: String?
    private(set) var audioIsPlaying = false
    private(set) var audioElapsedSeconds: Double?
    private(set) var audioDurationSeconds: Double?
    /// Vitesse réellement appliquée au moteur, après rampe. Distincte de la consigne
    /// du contrôleur : l'écart entre les deux, c'est la transition en cours.
    private(set) var appliedAudioRate: Double = 1.0
    private(set) var audioTrackIndex = 0
    private(set) var lastError: String?

    private let cadenceSource: any CadenceSource
    private let audioPlayback: AudioPlayback
    private let audioEventSource: (any AudioEventReporting)?
    private let policy: TempoMatchingPolicy

    private var machine = RunSessionStateMachine()
    private var filter = CadenceFilter()
    private var followController: FollowController
    private var paceController: PaceController
    private var ramp: PlaybackRateRamp
    private var runTask: Task<Void, Never>?
    private var rateControlTask: Task<Void, Never>?
    private var audioEventTask: Task<Void, Never>?
    private var lastSampleTimestamp: Date?
    private var cadenceSum: Double = 0
    /// Morceau réellement préparé dans le moteur audio.
    private var preparedTrackID: UUID?
    private var wasRunningBeforeInterruption = false

    init(
        configuration: RunConfiguration,
        audioItems: [RunAudioItem],
        cadenceSource: any CadenceSource,
        cadenceSourceDescription: String,
        audioPlayback: AudioPlayback,
        audioEventSource: (any AudioEventReporting)? = nil,
        settings: AppSettings
    ) {
        self.configuration = configuration
        self.audioItems = audioItems
        self.cadenceSourceDescription = cadenceSourceDescription
        self.cadenceSource = cadenceSource
        self.audioPlayback = audioPlayback
        self.audioEventSource = audioEventSource
        self.policy = settings.matchingPolicy
        self.ramp = PlaybackRateRamp(policy: settings.matchingPolicy)
        self.followController = FollowController(policy: settings.matchingPolicy)
        self.paceController = PaceController(
            policy: settings.matchingPolicy,
            configuration: PaceControllerConfiguration(
                targetCadenceSPM: configuration.targetCadenceSPM,
                targetPaceSecondsPerKilometer: configuration.targetPaceSecondsPerKilometer,
                audibleGuidanceEnabled: settings.audibleGuidanceEnabled
            )
        )
        if configuration.allowRunWithoutAudio {
            self.audioStatusMessage = "Course sans audio choisie : aucune lecture n'est demandée."
        } else if audioItems.contains(where: { $0.url != nil }) {
            self.audioStatusMessage = "Fichier audio prêt. Appuyez sur « Démarrer »."
        } else {
            self.audioStatusMessage = "Aucun fichier audio disponible pour cette sélection."
        }
    }

    // MARK: - État dérivé pour l'interface

    var mode: RunMode { configuration.mode }
    var targetCadenceSPM: Double { configuration.targetCadenceSPM }
    var isRunning: Bool { state == .running }
    var isPaused: Bool { state == .paused }
    var isFinished: Bool { state == .finished }

    /// La session lit-elle réellement un fichier ? Faux en mode sans audio et faux
    /// pour un descripteur sans fichier.
    var hasPlayableAudio: Bool {
        !configuration.allowRunWithoutAudio && audioItems.contains { $0.url != nil }
    }

    var currentItem: RunAudioItem? {
        guard !audioItems.isEmpty else { return nil }
        return audioItems.indices.contains(audioTrackIndex) ? audioItems[audioTrackIndex] : audioItems.first
    }

    var currentTrack: TrackDescriptor? { currentItem?.track }

    var playlistPositionText: String {
        guard audioItems.count > 1 else { return "" }
        return "morceau \(min(audioTrackIndex + 1, audioItems.count))/\(audioItems.count)"
    }

    var recommendedTrack: TrackDescriptor? {
        guard let recommendedTrackID else { return nil }
        return audioItems.first { $0.id == recommendedTrackID }?.track
    }

    var appliedAdjustmentPercent: Double? {
        decision.map { $0.appliedAdjustmentPercent }
    }

    var reasonMessage: String {
        decision?.reason.displayMessage ?? "Session non démarrée."
    }

    /// Position de lecture, au format m:ss. Jamais « 0:00 » inventé : `—` tant que
    /// rien n'est préparé.
    var audioPositionText: String {
        guard let audioElapsedSeconds else { return "—" }
        let total = Int(audioElapsedSeconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var audioDurationText: String {
        guard let audioDurationSeconds else { return "—" }
        let total = Int(audioDurationSeconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var isTempoAdjustable: Bool {
        guard let track = currentTrack else { return false }
        let provider = ProviderCatalog.provider(id: track.providerID)
        return TempoAdjustmentGate(policy: policy).isPermitted(
            track: track,
            provider: provider ?? ProviderCatalog.localImportedFiles
        )
    }

    /// Transition de tempo en cours (la consigne n'est pas encore atteinte).
    var isRamping: Bool { !ramp.isSettled }

    // MARK: - Commandes

    func start() {
        do {
            _ = try machine.apply(.start)
        } catch let error as RunSessionTransitionError {
            lastError = error.displayMessage
            return
        } catch {
            lastError = String(describing: error)
            return
        }
        state = machine.state
        audioTrackIndex = 0
        resetAccumulators(at: Date())
        metrics.playedTrackTitles = currentTrack.map { [$0.title] } ?? []
        lastError = nil
        lastRateError = nil
        observeAudioEvents()
        startRateControlLoop()
        startStreaming()
        Task { await self.beginAudioPlayback() }
    }

    func pause() {
        guard state == .running else { return }
        stopStreaming()
        _ = try? machine.apply(.pause)
        state = machine.state
        Task {
            await self.audioPlayback.pause()
            self.audioIsPlaying = false
        }
        if hasPlayableAudio {
            audioStatusMessage = "Session en pause : la musique est en pause."
        }
    }

    func resume() {
        guard state == .paused else { return }
        _ = try? machine.apply(.resume)
        state = machine.state
        let now = Date()
        filter.reset()
        followController.start(at: now)
        paceController.start(at: now)
        lastSampleTimestamp = nil
        // Note : le scénario simulé reprend au début (il est déterministe) ; le
        // capteur réel, lui, reprend simplement là où il en est.
        startStreaming()
        Task { await self.resumeAudioIfNeeded() }
    }

    func finish() {
        stopStreaming()
        stopRateControlLoop()
        _ = try? machine.apply(.finish)
        state = machine.state
        Task {
            await self.audioPlayback.stop()
            self.audioIsPlaying = false
            self.audioElapsedSeconds = nil
            self.appliedAudioRate = 1.0
        }
        preparedTrackID = nil
        audioStatusMessage = "Session terminée : lecture arrêtée."
    }

    func restart() {
        stopStreaming()
        stopRateControlLoop()
        stopAudioEvents()
        _ = try? machine.apply(.reset)
        state = machine.state
        decision = nil
        cadenceDeltaSPM = nil
        recommendedTrackID = nil
        lastError = nil
        lastRateError = nil
        audioIsPlaying = false
        audioElapsedSeconds = nil
        audioDurationSeconds = nil
        appliedAudioRate = 1.0
        audioTrackIndex = 0
        preparedTrackID = nil
        ramp.reset()
        resetAccumulators(at: nil)
    }

    /// Morceau suivant de la playlist (bouton de l'écran et commande système).
    func nextTrack() {
        guard audioItems.count > 1 else {
            audioStatusMessage = "Un seul morceau dans la playlist."
            return
        }
        audioTrackIndex = (audioTrackIndex + 1) % audioItems.count
        preparedTrackID = nil
        guard state == .running, hasPlayableAudio else { return }
        if let title = currentTrack?.title {
            metrics.playedTrackTitles.append(title)
        }
        Task { await self.playCurrentItem() }
    }

    // MARK: - Audio

    private func beginAudioPlayback() async {
        guard hasPlayableAudio else { return }
        await playCurrentItem()
    }

    private func playCurrentItem() async {
        guard let item = currentItem, let url = item.url else {
            audioIsPlaying = false
            audioStatusMessage = "Ce morceau n'a pas de fichier audio : rien n'est joué."
            return
        }
        do {
            try await audioPlayback.prepare(track: item.track, fileURL: url)
            preparedTrackID = item.track.id
            // Nouveau morceau : la rampe repart du tempo original, sans hériter de la
            // transition du morceau précédent.
            ramp.reset()
            appliedAudioRate = 1.0
            try await audioPlayback.play()
            audioIsPlaying = true
            audioStatusMessage = "Lecture : « \(item.track.title) »"
        } catch let error as AudioPlaybackError {
            audioIsPlaying = false
            audioStatusMessage = error.displayMessage
        } catch {
            audioIsPlaying = false
            audioStatusMessage = "Lecture impossible."
        }
        await refreshAudioState()
    }

    private func resumeAudioIfNeeded() async {
        guard hasPlayableAudio else { return }
        guard preparedTrackID == currentItem?.track.id else {
            await playCurrentItem()
            return
        }
        do {
            try await audioPlayback.play()
            audioIsPlaying = true
            audioStatusMessage = "Lecture reprise."
        } catch let error as AudioPlaybackError {
            audioStatusMessage = error.displayMessage
        } catch {
            audioStatusMessage = "Reprise de lecture impossible."
        }
        await refreshAudioState()
    }

    /// Boucle de contrôle du tempo : 4 Hz au maximum (§05). Chaque itération
    /// rafraîchit aussi la position de lecture, ce qui évite une seconde boucle.
    private func startRateControlLoop() {
        stopRateControlLoop()
        rateControlTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickRateControl()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func stopRateControlLoop() {
        rateControlTask?.cancel()
        rateControlTask = nil
    }

    private func tickRateControl() async {
        if state == .running {
            // Consigne seulement : `nil` (session pas encore décidée) signifie
            // « maintenir », jamais « remettre à 1.0 ».
            ramp.acceptTarget(decision?.appliedRate)
            if hasPlayableAudio, let command = ramp.command(at: Date()) {
                do {
                    try await audioPlayback.setRate(Float(command.rate))
                    appliedAudioRate = command.rate
                    if lastRateError != nil { lastRateError = nil }
                } catch let error as AudioPlaybackError {
                    if lastRateError != error.displayMessage {
                        lastRateError = error.displayMessage
                    }
                } catch {
                    lastRateError = "Vitesse de lecture non appliquée."
                }
            }
        }
        await refreshAudioState()
    }

    private func refreshAudioState() async {
        let audioState = await audioPlayback.state()
        audioIsPlaying = audioState.isPlaying
        audioElapsedSeconds = audioState.elapsedSeconds
        audioDurationSeconds = audioState.durationSeconds
    }

    /// Événements du moteur : la session décide, le moteur exécute.
    private func observeAudioEvents() {
        guard audioEventTask == nil, let audioEventSource else { return }
        audioEventTask = Task { [weak self] in
            let stream = await audioEventSource.events()
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(audioEvent: event)
            }
        }
    }

    private func stopAudioEvents() {
        audioEventTask?.cancel()
        audioEventTask = nil
    }

    private func handle(audioEvent event: AudioPlaybackEvent) {
        switch event {
        case let .trackFinished(trackID):
            audioIsPlaying = false
            guard state == .running, audioItems.count > 1,
                  let finishedIndex = audioItems.firstIndex(where: { $0.id == trackID })
            else {
                audioStatusMessage = "Morceau terminé : lecture arrêtée."
                return
            }
            audioTrackIndex = (finishedIndex + 1) % audioItems.count
            preparedTrackID = nil
            if let title = currentTrack?.title {
                metrics.playedTrackTitles.append(title)
            }
            Task { await self.playCurrentItem() }

        case .interruptionBegan:
            audioIsPlaying = false
            guard state == .running else {
                audioStatusMessage = "Interruption audio."
                return
            }
            wasRunningBeforeInterruption = true
            pause()
            audioStatusMessage = "Interruption audio : session mise en pause."

        case let .interruptionEnded(shouldResume):
            let shouldRestart = shouldResume && wasRunningBeforeInterruption && state == .paused
            wasRunningBeforeInterruption = false
            if shouldRestart {
                resume()
                audioStatusMessage = "Interruption terminée : session reprise."
            } else {
                audioStatusMessage = shouldResume
                    ? "Interruption terminée : appuyez sur « Reprendre »."
                    : "Interruption terminée."
            }

        case .outputRouteLost:
            audioIsPlaying = false
            guard state == .running else {
                audioStatusMessage = "Sortie audio perdue."
                return
            }
            pause()
            audioStatusMessage = "Sortie audio perdue (écouteurs débranchés) : session mise en pause."

        case .playRequested:
            if state == .paused { resume() } else { audioStatusMessage = "Commande de lecture reçue." }

        case .pauseRequested:
            if state == .running { pause() }

        case .nextTrackRequested:
            nextTrack()

        case let .failed(message):
            lastError = message
            audioIsPlaying = false
        }
    }

    // MARK: - Boucle de session

    private func startStreaming() {
        stopStreaming()
        let source = cadenceSource
        runTask = Task { [weak self] in
            do {
                for try await sample in source.samples() {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(sample)
                }
            } catch {
                guard let self else { return }
                self.reportCadenceFailure(error)
            }
        }
    }

    private func stopStreaming() {
        runTask?.cancel()
        runTask = nil
    }

    /// Le capteur a échoué (autorisation refusée, appareil sans capteur). On
    /// l'annonce sans transformer l'échec en cadence inventée.
    private func reportCadenceFailure(_ error: Error) {
        if let cadenceError = error as? CadenceSourceError {
            lastError = cadenceError.displayMessage
        } else {
            lastError = "Source de cadence interrompue."
        }
        // Une source qui s'arrête ne doit pas laisser la session croire qu'elle
        // tourne : l'adaptation retombe en état indisponible (pas de 0 inventé).
        decision = nil
        cadence = .initial
    }

    private func handle(_ sample: CadenceSample) {
        guard state == .running else { return }

        let elapsed = lastSampleTimestamp.map { max(0, sample.timestamp.timeIntervalSince($0)) } ?? 0
        lastSampleTimestamp = sample.timestamp
        metrics.activeSeconds += elapsed

        let assessment = filter.ingest(sample)
        cadence = assessment
        metrics.cadenceRejectionCount = filter.rejectionCount

        if let raw = assessment.rawSPM {
            cadenceSum += raw
            metrics.cadenceSampleCount += 1
            metrics.averageCadenceSPM = cadenceSum / Double(metrics.cadenceSampleCount)
        }

        let candidates = audioItems.map(\.track)
        switch configuration.mode {
        case .follow:
            let followDecision = followController.update(
                cadence: assessment,
                track: currentTrack,
                candidates: candidates,
                now: sample.timestamp
            )
            decision = followDecision.tempo
            recommendedTrackID = followDecision.recommendedTrackID
            cadenceDeltaSPM = nil
        case .pace:
            let paceDecision = paceController.update(
                observedCadence: assessment,
                track: currentTrack,
                candidates: candidates,
                now: sample.timestamp
            )
            decision = paceDecision.tempo
            recommendedTrackID = paceDecision.recommendedTrackID
            cadenceDeltaSPM = paceDecision.cadenceDeltaSPM
        }

        if decision?.reason.isActivelySynchronized == true {
            metrics.synchronizedSeconds += elapsed
        } else {
            metrics.unavailabilitySeconds += elapsed
        }
    }

    private func resetAccumulators(at date: Date?) {
        metrics = RunMetricsSnapshot()
        cadenceSum = 0
        lastSampleTimestamp = date
        filter.reset()
        if let date {
            followController.start(at: date)
            paceController.start(at: date)
        } else {
            followController.reset()
            paceController.reset()
        }
    }
}
