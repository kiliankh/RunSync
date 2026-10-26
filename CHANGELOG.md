# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versionnement sémantique une fois l'application distribuée.

## [0.3.0] — 2026-10-26 — Capteur et musique réels (RS-010, RS-021)

### Ajouté

- `AudioEnginePlayback` (actor) : moteur audio local réel — `AVAudioEngine` +
  `AVAudioPlayerNode` + `AVAudioUnitTimePitch` (`rate` sans transposition, `pitch` à 0),
  lecture par segment avec jeton de génération pour distinguer une fin de morceau d'un arrêt.
- `PlaybackRateRamp` (Domain, **testé**) : rampe de vitesse au point frontière de l'audio —
  dérivée limitée à 1 point de %/s, écriture au moteur ≤ 4 Hz, aucune émission inutile, aucun
  rattrapage brutal après une longue inactivité.
- `AudioEventReporting` / `AudioPlaybackEvent` / `AudioPlaybackState` : le moteur **rapporte**
  (fin de morceau, interruption, perte de sortie, commandes système) et la session décide.
- `CoreMotionCadenceSource` : capteur de cadence réel (`CMPedometer.startUpdates`,
  `currentCadence` en pas/s → SPM), diagnostic d'état (`CadenceSensorAvailability`) et erreurs
  typées (appareil sans capteur, autorisation refusée, échec Core Motion).
- Gestion des interruptions, des changements de route (`oldDeviceUnavailable` : écouteurs
  débranchés → pause, jamais de bascule sur le haut-parleur), et de l'écran verrouillé
  (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- `NoAudioPlayback` : lecteur inactif de la course sans audio ; il ne simule rien.
- **Morceau de test intégré** (clics à 168 BPM, 30 s, domaine public) produit par
  `Tools/generate_test_tone.py`, embarqué dans l'application et ajoutable depuis l'onglet
  Musique : il rend la synchronisation vérifiable à l'oreille.
- Écran de session : état audio explicite (lecture, position, durée, morceau n/N), vitesse
  réellement appliquée distincte de la consigne, message dédié en cas de refus d'ajustement.
- Bouton « Démarrer » désormais piloté par la réalité : actif si un fichier est jouable, ou si
  la course sans audio est explicitement choisie.
- `Docs/RUN_ON_IPHONE.md` réécrit : procédure PC → Mac → iPhone, puis recette d'appareil
  (cadence réelle, clics qui accélèrent, écouteurs débranchés, appel entrant, écran verrouillé).
  Il s'ouvre désormais sur un **contrôle des prérequis** à lancer avant tout (`sw_vers`,
  `xcodebuild -version`, `xcode-select -p`, `brew`, `xcodegen`) et sur la route « clone Xcode »
  avec ses deux pièges ; le plancher de version macOS y est explicité. Il annonçait d'abord à
  tort que macOS 14 était exigé à cause du `.macOS(.v14)` de `Package.swift` : un essai réel
  (macOS 13.7.8 + Xcode 15.2) a montré que `swift build` et `swift test` passent.
- `Docs/AUDIO_ENGINE.md` réécrit : moteur tel qu'implémenté, chaîne de contrôle et mesures
  encore manquantes.
- Tests : **108 cas** au total (16 nouveaux sur la rampe de vitesse).

### Modifié

- `AudioPlayback.prepare(trackID:)` → `prepare(track:fileURL:)` : le lecteur reçoit le
  descripteur **et** le fichier, pour appliquer lui-même la garde de conformité.
- `AudioPlayback` gagne `seek(toElapsedSeconds:)` et `state()` ; `preparedTrackID` retiré.
- `AudioPlaybackError` : `notAvailableInCurrentPhase` remplacé par `playbackUnavailable`,
  `trackFileUnreadable` et `tempoAdjustmentRefused(TempoAdjustmentError)`.
- `project.yml` : dossier `Infrastructure/Motion` et morceau de test embarqué (`*.wav`).
- `.gitignore` : exception explicite pour le morceau de test généré par le projet.

### Supprimé

- `LocalAudioPlayback` (stub de phase 1), remplacé par le moteur réel et `NoAudioPlayback`.

### Vérifié / non vérifié

- `swift test` : 108 tests, 0 échec, code de sortie 0 ; `swift build` sans avertissement.
- Tempo du morceau de test **mesuré** sur le fichier produit : 84 attaques, 168,0000 BPM.
- `swiftc -parse` : syntaxe de la couche app et des adaptateurs valide.
- **Câblage app ↔ paquet contrôlé mécaniquement** : tous les chemins de `project.yml`
  existent, 62 fichiers `.swift` dont **0 orphelin** (aucun fichier hors de tout target),
  imports inter-modules complets, noyau portable sans framework Apple.
- **Archive de transfert vérifiée par son usage réel** : `git bundle create … --all`, puis
  **clone de l'archive** et `swift test` dans ce clone → 108 tests, 0 échec. C'est le trajet
  exact que suivra le Mac.
- Dépôt initialisé, commité puis **poussé** sur `https://github.com/kiliankh/RunSync.git` (privé,
  `main` synchronisé) ; `*.bundle` est ignoré : artefact de transfert jetable.
- **NON VÉRIFIÉ** : aucune compilation iOS, **aucun son produit**, **aucune cadence réelle
  lue**, aucun artefact audio écouté, aucune mesure de batterie ou de latence.

### Défauts trouvés et corrigés

1. La première évaluation de la rampe appliquait déjà un pas : l'état initial transmis au
   moteur audio valait 1,01 au lieu du tempo original (marche audible au démarrage).
2. `CadenceSourceError` n'était pas `public` — invisible depuis la cible application.
3. `AudioEventReporting.events()` était synchrone, donc incompatible avec un moteur `actor`.
4. Deux attentes de test inexactes (repli d'une consigne non finie ; comparaison de commandes
   consécutives) corrigées sans affaiblir aucune assertion.
5. `Theme.swift` utilisait `DataQuality` (déclaré dans le paquet `RunSyncDomain`) sans
   `import RunSyncDomain` : la cible applicative n'aurait pas compilé. Trouvé par le contrôle
   mécanique des imports de la couche app, corrigé.

## [0.2.1] — 2026-10-26 — Guide d'installation sur iPhone (documentation seule)

### Ajouté

- `Docs/RUN_ON_IPHONE.md` : procédure exacte pour installer et tester l'application sur un
  iPhone physique — prérequis, transfert du dépôt sur un Mac, `xcodegen generate`, signature
  avec un Apple ID gratuit (validité 7 jours), mode développeur iOS, recette de test écran par
  écran avec les valeurs attendues du scénario simulé, et diagnostic des erreurs de premier
  build.
- Comparaison des routes disponibles sans Mac (Mac loué, runner CI macOS) et des limites qui
  leur restent propres : l'iPhone n'est pas branché sur une machine distante, et un Mac virtuel
  ou « hackintosh » est interdit par la licence Apple.

### Modifié

- `README.md` : section « Tester sur votre iPhone » et référence au nouveau document.
- `.gitignore` : `RunSync/Resources/Info.plist` (généré par XcodeGen depuis `project.yml`,
  comme `RunSync.xcodeproj`) n'est plus suivi.

### Vérifié

- Aucun code produit modifié : le noyau reste à 92 tests, 0 échec (`swift test`).
- Contrôle mécanique des références croisées de la couche application (SwiftUI, adaptateur
  d'import) : **aucun symbole du noyau manquant**. Cette couche reste, elle, **non compilée**
  faute de macOS.

## [0.2.0] — 2026-10-26 — Phase 1, suite : import local (RS-020)

### Ajouté

- Contrat `TrackFileStorage` (stockage disque des morceaux importés, chemins relatifs
  uniquement : aucun emplacement privé dans les modèles ni dans les logs).
- `LocalTrackImporter` : validation **avant** toute copie (extension, taille, espace
  disponible), erreurs typées (`unsupportedFormat`, `sourceFileUnreadable`, `fileTooLarge`,
  `insufficientStorage`, `invalidFileName`, `accessDenied`, `storageUnavailable`).
- Règle de conformité à l'import : un morceau importé sans attestation explicite de droits
  est rangé dans la bibliothèque mais reste **non tempo-ajustable**.
- `LocalLibraryReconciler` : un fichier disparu ne reste jamais faussement jouable (§09, T014).
- `FileSystemTrackStorage` (Foundation pur, testé sur disque réel), chemins relatifs
  confinés au répertoire d'import, refus de toute remontée de chemin (`../`).
- `LocalLibraryCatalog` : import, réconciliation, suppression, BPM manuel.
- `TrackDescriptor.settingManualBPM(_:)` : BPM manuel prioritaire, valeur invalide refusée.
- Application : `LocalLibraryStore` (accès security-scoped + délégation au noyau),
  écran Musique avec import, attestation de droits, BPM manuel et suppression ;
  la préparation de course propose désormais les morceaux réellement importés.
- Diagnostic plus exact : `TempoMatcher` distingue « source non autorisée » de
  « droits d'adaptation non attestés » pour un fichier local (nouveau paramètre `provider`).
- Tests : 92 cas au total (25 nouveaux sur l'import, le stockage disque, la réconciliation,
  le BPM manuel et la sécurité des chemins).
- Outil de diagnostic `runsync-demo` (livrable §00-7) : rejoue le scénario déterministe et
  affiche par seconde la cadence mesurée, la cadence filtrée, la qualité, le rate requis et
  appliqué (avec rampe), l'écart en % et la raison de la décision ; modes Follow et Pace.
- `Docs/design/app-mockup.html` et ses captures : aperçu statique des 8 écrans, explicite-
  ment identifié comme maquette et non comme l'application compilée.

### Notes

- La bibliothèque **n'est pas encore persistée** entre deux lancements (RS-033).
- L'adaptateur iOS (sélecteur de fichiers, security-scoped URL) n'a pas pu être compilé ni
  exécuté : aucun macOS/Xcode disponible. La logique testable située en dessous l'est.

## [0.1.0] — 2026-10-26 — Phase 1 (M0 + noyau de M1)

### Ajouté

- Noyau Domain pur et portable : `RunMode`, `DataQuality`, `CadenceSample`, `PaceSample`,
  `TrackDescriptor`, `TempoDecision`, `RunSessionState`, `MusicProviderCapabilities`,
  erreurs typées, conversions d'unités.
- Contrats `CadenceSource`, `LocationTracking`, `AudioPlayback`, `TrackCatalog`.
- `TempoMatchingPolicy` (validation ±5 %/±3 %, ratios 1:1 et 2:1, bornage).
- `TempoMatcher` : évaluation, rejets explicites, classement par coût de sélection.
- `CadenceFilter` : rejet diagnostiqué des valeurs invalides, médiane glissante, EMA,
  hystérésis confirmée, état de qualité explicite.
- `FollowController` : cible filtrée, bornage, rampe de rate, suggestion de morceau
  seulement après écart soutenu, politique de perte de cadence (maintien puis retour doux).
- `PaceController` : cible musicale déclarée, écart réel affiché séparément.
- `TempoAdjustmentGate` : capacité technique **et** conformité de la source exigées,
  attestation de droits et BPM vérifiés avant tout ajustement.
- `RunSessionStateMachine` : transitions idempotentes, aucune session fantôme.
- Module `RunSyncSimulation` : scénarios horodatés, décodage JSON/CSV, source factice
  déterministe (script 170 → 176 → 160 → indisponible → 170), catalogue de démonstration.
- Application SwiftUI : 4 onglets, onboarding sans permission anticipée, préparation de
  course Follow/Pace, écran live de démonstration, résumé, réglages, état de conformité
  des sources musicales.
- `LocalAudioPlayback` : stub derrière protocole, erreurs typées explicites, garde de
  conformité déjà branchée.
- Tests : 67 cas couvrant les oracles A–F, T001–T013 et les fixtures.
- Documentation : PRD, ARCHITECTURE, AUDIO_ENGINE, PROVIDER_COMPLIANCE, PRIVACY, TEST_PLAN,
  APP_STORE_CHECKLIST, PROJECT_STATUS.
- Intégration continue GitHub Actions (noyau portable + application iOS).

### Notes

- **Aucune lecture audio, aucun capteur Core Motion, aucun GPS, aucune persistance,
  aucun import de fichier ne sont implémentés.** Ces étapes sont listées dans
  `PROJECT_STATUS.md` avec leurs identifiants RS-XXX.
- La compilation et les tests sur simulateur iPhone n'ont pas été exécutés : l'environnement
  de développement ne disposait ni de macOS ni de Xcode. Les commandes exactes à lancer
  sont fournies dans `Docs/TEST_PLAN.md`.
