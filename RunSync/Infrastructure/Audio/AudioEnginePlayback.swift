import AVFoundation
import Foundation
import MediaPlayer
import RunSyncDomain

/// Moteur audio local réel (RS-021, FR-008, FR-009).
///
/// Chaîne audio :
///
///     AVAudioFile → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixerNode
///
/// `AVAudioUnitTimePitch.rate` modifie la vitesse **sans transposer la hauteur**
/// (au contraire d'`AVAudioUnitVarispeed`, qui changerait la tonalité) : c'est la
/// seule façon de tenir la promesse « la musique suit tes pas » sans déformer la
/// voix. `pitch` reste à 0.
///
/// Choix d'implémentation :
/// - le moteur est un `actor` : c'est le seul propriétaire de l'état audio, donc
///   aucune écriture concurrente dans le graphe, et aucun risque d'état fantôme ;
/// - **toute** demande de vitesse passe par `TempoAdjustmentGate` : le fait que le
///   contrôleur ait déjà borné la consigne ne dispense jamais de vérifier la source,
///   l'attestation de droits et le BPM (T013, RS-040) ;
/// - la vitesse appliquée ne vient pas directement du contrôleur : elle vient de
///   `PlaybackRateRamp`, qui limite la dérivée et la fréquence d'écriture ;
/// - les notifications systèmes (interruption, perte de sortie) **mettent la
///   lecture en pause** et sont ensuite rapportées à la session, qui reste seule
///   propriétaire de la machine à états. Le moteur ne reprend jamais tout seul ;
/// - l'application ne lit que des fichiers de la sandbox, importés légalement par
///   l'utilisateur : aucune extraction, aucun flux tiers (§02).
actor AudioEnginePlayback: AudioPlayback, AudioEventReporting {

    private let policy: TempoMatchingPolicy
    private let provider: MusicProviderCapabilities
    private let gate: TempoAdjustmentGate

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    private var currentTrack: TrackDescriptor?
    private var durationSeconds: Double?
    private var appliedRate: Double = 1.0
    private var isPlaying = false
    private var hasScheduledAudio = false
    private var scheduledStartFrame: AVAudioFramePosition = 0
    /// Jeton de planification : permet d'ignorer la fin des segments abandonnés
    /// (arrêt volontaire, déplacement) et de n'annoncer qu'une **vraie** fin de
    /// morceau.
    private var scheduleGeneration: Int = 0

    private var continuations: [UUID: AsyncStream<AudioPlaybackEvent>.Continuation] = [:]
    private var observersInstalled = false
    private var remoteCommandsInstalled = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init(
        policy: TempoMatchingPolicy = .standard,
        provider: MusicProviderCapabilities = ProviderCatalog.localImportedFiles
    ) {
        self.policy = policy
        self.provider = provider
        self.gate = TempoAdjustmentGate(policy: policy)
    }

    // MARK: - Capacité déclarée

    /// Capacité de la source pour cette session. Immutable, donc lisible sans
    /// traverser l'isolat de l'acteur.
    nonisolated var supportsTempoAdjustment: Bool {
        provider.isTempoAdjustmentPermitted
    }

    // MARK: - AudioPlayback

    func prepare(track: TrackDescriptor, fileURL: URL) async throws {
        activateIfNeeded()

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AudioPlaybackError.trackFileUnreadable(trackID: track.id)
        }

        // Reconnexion à l'arrêt : changer le format d'un graphe en marche produit
        // des artefacts audibles.
        player.stop()
        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(player, to: timePitch, format: audioFile.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: audioFile.processingFormat)

        self.file = audioFile
        self.currentTrack = track
        let sampleRate = audioFile.processingFormat.sampleRate
        self.durationSeconds = sampleRate > 0
            ? Double(audioFile.length) / sampleRate
            : nil
        self.appliedRate = 1.0
        self.isPlaying = false
        self.scheduledStartFrame = 0
        timePitch.rate = 1.0
        timePitch.pitch = 0
        scheduleFrom(frame: 0)
        updateNowPlaying()
    }

    func play() async throws {
        guard let track = currentTrack, file != nil else {
            throw AudioPlaybackError.trackNotPrepared(trackID: currentTrack?.id ?? UUID())
        }
        _ = track.id
        try activateSession()
        engine.prepare()
        if !engine.isRunning {
            try engine.start()
        }
        if !hasScheduledAudio {
            scheduleFrom(frame: scheduledStartFrame)
        }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() async {
        guard isPlaying else { return }
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    /// Fin de session : tout est arrêté, la session audio est relâchée pour que les
    /// autres applications reprennent la main.
    func stop() async {
        player.stop()
        engine.stop()
        isPlaying = false
        hasScheduledAudio = false
        scheduledStartFrame = 0
        appliedRate = 1.0
        timePitch.rate = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func setRate(_ rate: Float) async throws {
        guard let track = currentTrack, file != nil else {
            throw AudioPlaybackError.trackNotPrepared(trackID: currentTrack?.id ?? UUID())
        }
        guard rate.isFinite else {
            throw AudioPlaybackError.underlying(code: "nonFiniteRate")
        }
        let validated: Double
        do {
            validated = try gate.validatedRate(
                requestedRate: Double(rate),
                track: track,
                provider: provider
            )
        } catch let error as TempoAdjustmentError {
            throw AudioPlaybackError.tempoAdjustmentRefused(error)
        }
        appliedRate = validated
        timePitch.rate = Float(validated)
        updateNowPlaying()
    }

    func seek(toElapsedSeconds seconds: Double) async throws {
        guard let file else {
            throw AudioPlaybackError.trackNotPrepared(trackID: currentTrack?.id ?? UUID())
        }
        guard seconds.isFinite, seconds >= 0 else {
            throw AudioPlaybackError.underlying(code: "invalidSeekPosition")
        }
        let sampleRate = file.processingFormat.sampleRate
        let position = min(seconds, durationSeconds ?? seconds)
        let frame = AVAudioFramePosition((position * sampleRate).rounded())
        let wasPlaying = isPlaying
        player.stop()
        scheduleFrom(frame: frame)
        if wasPlaying {
            player.play()
        }
        updateNowPlaying()
    }

    func state() async -> AudioPlaybackState {
        AudioPlaybackState(
            preparedTrackID: currentTrack?.id,
            isPlaying: isPlaying,
            elapsedSeconds: currentElapsedSeconds,
            durationSeconds: durationSeconds,
            rate: appliedRate
        )
    }

    // MARK: - AudioEventReporting

    func events() async -> AsyncStream<AudioPlaybackEvent> {
        let (stream, continuation) = AsyncStream<AudioPlaybackEvent>.makeStream()
        let identifier = UUID()
        continuations[identifier] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(identifier: identifier) }
        }
        return stream
    }

    /// Arrête le moteur et retire les observateurs (fin de session).
    func deactivate() async {
        await stop()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        interruptionObserver = nil
        routeChangeObserver = nil
        observersInstalled = false
        continuations.removeAll()
    }

    // MARK: - Position

    private var currentElapsedSeconds: Double? {
        guard let file else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return durationSeconds }
        var playedFrames: Double = 0
        if let nodeTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: nodeTime) {
            playedFrames = Double(playerTime.sampleTime)
        }
        let position = Double(scheduledStartFrame) + max(0, playedFrames)
        let elapsed = position / sampleRate
        return min(max(0, elapsed), durationSeconds ?? elapsed)
    }

    // MARK: - Planification

    private func scheduleFrom(frame: AVAudioFramePosition) {
        guard let file else {
            hasScheduledAudio = false
            return
        }
        let total = file.length
        let start = min(max(0, frame), max(0, total))
        let remaining = max(0, total - start)
        scheduleGeneration += 1
        let generation = scheduleGeneration
        let trackID = currentTrack?.id
        scheduledStartFrame = start
        guard remaining > 0, let trackID else {
            hasScheduledAudio = false
            return
        }
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { await self?.handleSegmentFinished(generation: generation, trackID: trackID) }
        }
        hasScheduledAudio = true
    }

    /// Fin de segment. `.dataPlayedBack` se déclenche aussi quand le lecteur est
    /// arrêté : le jeton de planification et l'état de lecture distinguent une vraie
    /// fin de morceau de la conséquence d'un arrêt, d'une pause ou d'un déplacement.
    private func handleSegmentFinished(generation: Int, trackID: UUID) {
        guard generation == scheduleGeneration else { return }
        guard isPlaying else { return }
        isPlaying = false
        hasScheduledAudio = false
        updateNowPlaying()
        broadcast(.trackFinished(trackID: trackID))
    }

    // MARK: - Session audio et notifications

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            // Lecture musicale : catégorie `.playback`, pas d'enregistrement, aucune
            // permission micro demandée (FR-019).
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setActive(true)
    }

    private func activateIfNeeded() {
        installObserversIfNeeded()
        installRemoteCommandsIfNeeded()
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default

        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue
            Task { await self?.handleInterruption(rawType: type, rawOptions: options) }
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            Task { await self?.handleRouteChange(rawReason: reason) }
        }
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            // Le système exige que l'application se taise immédiatement.
            if isPlaying {
                player.pause()
                isPlaying = false
                updateNowPlaying()
            }
            broadcast(.interruptionBegan)
        case .ended:
            // Note : `shouldResume` peut être signalé comme obsolète selon la version
            // du SDK ; la reprise reste de toute façon décidée par la session, jamais
            // par le moteur.
            let options = rawOptions.map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            broadcast(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
              reason == .oldDeviceUnavailable
        else { return }
        // Écouteurs débranchés ou casque Bluetooth perdu : on met en pause plutôt
        // que de basculer sur le haut-parleur devant tout le monde.
        if isPlaying {
            player.pause()
            isPlaying = false
            updateNowPlaying()
        }
        broadcast(.outputRouteLost)
    }

    // MARK: - Événements

    private func removeContinuation(identifier: UUID) {
        continuations.removeValue(forKey: identifier)
    }

    private func broadcast(_ event: AudioPlaybackEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    // MARK: - Écran verrouillé

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artist ?? "RunSync"
        }
        if let durationSeconds {
            info[MPMediaItemPropertyPlaybackDuration] = durationSeconds
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentElapsedSeconds ?? 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? appliedRate : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info.isEmpty ? nil : info
    }

    /// Commandes système (écran verrouillé, écouteurs). Le moteur ne change jamais
    /// l'état de la session lui-même : il **rapporte** la commande, et la session
    /// décide. C'est ce qui empêche l'écran d'afficher « en cours » alors que
    /// l'audio s'est arrêté (état fantôme, §07).
    private func installRemoteCommandsIfNeeded() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.broadcastRemote(.playRequested) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.broadcastRemote(.pauseRequested) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.togglePlaybackFromRemote() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { await self.broadcastRemote(.nextTrackRequested) }
            return .success
        }
    }

    private func broadcastRemote(_ event: AudioPlaybackEvent) {
        broadcast(event)
    }

    private func togglePlaybackFromRemote() {
        broadcast(isPlaying ? .pauseRequested : .playRequested)
    }
}
