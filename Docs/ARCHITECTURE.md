# RunSync — Architecture

## Découpage

```
App            -> composition root, navigation, réglages observables
Features       -> vues SwiftUI + modèles d'écran (@Observable, MainActor)
Domain (pur)   -> modèles, contrats, algorithmes tempo, cas d'usage  ← aucun framework iOS
Simulation     -> scénarios déterministes, source factice, catalogue de démo
Infrastructure -> adaptateurs : moteur audio réel (AVAudioEngine), capteur Core Motion,
                  import iOS, plus tard CoreLocation
  Persistence  -> stockage disque des fichiers importés (Foundation pur, testé)
```

Règles tenues :

- les vues ne contiennent **aucun** algorithme BPM ni logique fournisseur ;
- le Domain n'importe ni CoreMotion, ni CoreLocation, ni AVFAudio, ni SwiftUI ;
- aucun singleton caché : tout passe par `DependencyContainer` ;
- les paramètres d'algorithme sont injectables (`TempoMatchingPolicy`,
  `CadenceFilterConfiguration`, `FollowTimingConfiguration`) ;
- les erreurs sont typées, avec code stable et message utilisateur, sans donnée sensible.

## Deux cibles de compilation, une seule source de vérité

| Cible | Contenu | Outil |
| --- | --- | --- |
| `RunSyncDomain` (SwiftPM) | `RunSync/Domain` | `swift build` / `swift test` — **sans Xcode** |
| `RunSyncSimulation` (SwiftPM) | `RunSync/Simulation` | idem |
| `RunSyncPersistence` (SwiftPM) | `RunSync/Infrastructure/Persistence` (Foundation pur) | idem |
| `RunSync` (app iOS) | `App`, `DesignSystem`, `Features`, `Infrastructure/{Audio,Motion,Importer}` | XcodeGen (`project.yml`) → `xcodebuild` |

`project.yml` liste **explicitement** les sous-dossiers de `Infrastructure` : les fichiers
compilés par le paquet (`Persistence`) ne doivent pas l'être une seconde fois par
l'application, et une liste explicite rend cette règle vérifiable à la lecture.

Conséquence voulue : toute la logique de synchronisation est testable sur n'importe quelle
machine disposant d'un compilateur Swift, y compris en intégration continue Linux, et
l'application ne fait que brancher des vues sur ce noyau.

`RunSync.xcodeproj` n'est pas versionné : `project.yml` est la source de vérité
(génération déterministe, pas de conflits de merge dans le pbxproj).

## Contrats du Domain

`RunMode`, `DataQuality`, `CadenceSample`, `PaceSample`, `TrackDescriptor`,
`TempoDecision`, `RunSessionState`, `MusicProviderCapabilities`, plus les protocoles
`CadenceSource`, `LocationTracking`, `AudioPlayback`, `TrackCatalog`.

## Écarts documentés par rapport à l'esquisse §07 du cahier des charges

L'esquisse était explicitement présentée comme des « contrats cibles » à corriger selon le
compilateur ; chaque correction est listée ici.

1. **`CadenceSample.stepsPerMinute` est optionnel.** L'esquisse le déclarait non optionnel.
   Or le cas D exige qu'une absence de cadence ne devienne jamais `0` : l'absence est donc
   représentée par `nil` plus `quality == .unavailable`.
2. **`TempoDecision.reason` est un enum typé** (`TempoDecisionReason`) au lieu d'une
   `String`, et `targetBPM` est renommé `targetTrackBPM` pour éviter la confusion avec le
   BPM nominal du morceau. Bénéfice : décision exhaustive et testable ; la traduction
   utilisateur est fournie par `displayMessage`.
3. **`TempoDecision.requiredRate` est optionnel** (l'esquisse le déclarait `Double`).
   Certaines décisions n'ont aucun ratio calculable (BPM inconnu, cadence absente).
4. **Champs ajoutés** : `trackID`, `isClamped` (l'utilisateur doit savoir que la valeur a
   été bornée), `RunSessionEvent`, `TrackEvaluation`, `TempoRejection`.
5. **Pas de contraintes `actor`** dans le Domain : les types sont `Sendable` et immuables ;
   seul l'état mutable *de session* est détenu par son propriétaire (`ActiveRunViewModel`
   sur le `MainActor`, et le futur `SessionCoordinator` de RS-013).
6. **`TrackDescriptor` porte la légitimité autant que la capacité** : `canAlterTempo`,
   `isFileAvailable`, `isAdaptationRightsAttested`, `bpmProvenance`, `bpmConfidence`.
   Un morceau dont les droits ne sont pas attestés est rejeté avec une raison affichable.
7. **Ajout du module `RunSyncSimulation`** (non prévu par l'arborescence cible §06) : le
   simulateur et le catalogue de démonstration sont du code produit (FR-004, mode démo E01),
   pas du code de test ; les regrouper dans un module permet de les réutiliser dans les tests
   sans exposer d'API de test dans le Domain.

8. **`LocalLibraryCatalog` n'est pas un `TrackCatalog`.** Le protocole expose un import non
   mutant et sans attestation de droits, alors que la bibliothèque exige une attestation
   explicite et enregistre ce qu'elle importe. Un `importLocalFile` qui réussirait sans rien
   enregistrer serait un piège : les deux responsabilités sont donc séparées, l'adaptateur
   `TrackCatalog` restant disponible pour une source distante future.
9. **`TempoMatcher.evaluate` prend un `provider` optionnel** pour nommer la bonne cause de
   refus : si la source autorise l'adaptation mais que le morceau ne l'autorise pas, la raison
   est « droits d'adaptation non attestés » et non « source non autorisée ». Sans ce
   paramètre, un fichier local non attesté aurait affiché un message trompeur.

10. **`AudioPlayback.prepare(trackID:)` devient `prepare(track:fileURL:)`.** Le lecteur a
    besoin du descripteur **et** du fichier : du descripteur pour appliquer la garde de
    conformité (attestation, BPM, existence), du fichier pour ouvrir le média. Une signature
    qui ne recevrait qu'un identifiant obligerait le moteur audio à interroger la bibliothèque
    de l'application — donc à dépendre d'un état d'interface, et à rendre la garde contournable.
11. **`AudioPlayback` gagne `seek(toElapsedSeconds:)` et `state()`**, et `preparedTrackID`
    disparaît : l'état de lecture passe par une valeur explicite (`AudioPlaybackState`) au lieu
    d'une propriété interrogée à distance. Nécessaire pour que le moteur réel soit un `actor`
    (une exigence synchrone ne peut pas être satisfaite par un membre isolé à un acteur).
12. **Nouveau protocole `AudioEventReporting`** (`AudioPlaybackEvent` : fin de morceau,
    interruption, perte de sortie, commandes système). Séparé de `AudioPlayback` pour qu'un
    lecteur inactif — la course sans audio — n'ait pas à fabriquer un flux d'événements.
    `events()` est `async` pour la même raison que le point 11.
13. **`AudioPlaybackError.notAvailableInCurrentPhase` remplacé** par
    `playbackUnavailable(reason:)`, plus `trackFileUnreadable` et
    `tempoAdjustmentRefused(TempoAdjustmentError)`. L'ancien cas décrivait une phase de
    développement, pas une situation produit. Le refus de la garde conserve son erreur
    d'origine : la cause exacte reste affichable.
14. **`CadenceSourceError`** (appareil sans capteur, autorisation refusée, échec Core Motion)
    ajouté au Domain : l'échec du capteur est un résultat du produit, pas une exception
    technique, et l'interface doit pouvoir le distinguer d'une absence de valeur.

## Adaptateurs iOS (jamais compilés ici)

| Adaptateur | Fichier | Contrat | Points de vigilance |
| --- | --- | --- | --- |
| Capteur de cadence | `Infrastructure/Motion/CoreMotionCadenceSource.swift` | `CadenceSource` | `CMPedometer.isCadenceAvailable()`, `startUpdates(from:withHandler:)`, `currentCadence` en pas/s converti en SPM, `nil` → échantillon `unavailable` |
| Moteur audio | `Infrastructure/Audio/AudioEnginePlayback.swift` | `AudioPlayback` + `AudioEventReporting` | `actor`, `AVAudioEngine` + `PlayerNode` + `TimePitch`, jeton de génération pour distinguer fin naturelle et arrêt |
| Lecteur inactif | `Infrastructure/Audio/NoAudioPlayback.swift` | `AudioPlayback` | course sans audio : **rien** n'est simulé, toute opération qui prétendrait jouer échoue |
| Import | `Infrastructure/Importer/LocalLibraryStore.swift` | — | accès security-scoped, délégation au noyau, ajout du morceau de test intégré |

Ces quatre fichiers ne sont compilés que par `xcodebuild`. Le raisonnement qui les sépare est
celui du §06 : aucun SDK Apple ne doit apparaître dans le Domain, et l'orchestration de session
(`ActiveRunViewModel`, bientôt `SessionCoordinator`) commande le moteur sans jamais lire
l'audio lui-même.

### Pourquoi la rampe est dans le Domain, pas dans le moteur

`PlaybackRateRamp` est du Swift pur et testé (16 cas). Si la limitation de dérivée et la borne
de fréquence vivaient dans l'adaptateur AVFAudio, elles ne seraient vérifiables que sur
appareil, à l'oreille — c'est-à-dire trop tard. Le moteur audio ne fait qu'appliquer la valeur
qu'on lui donne, à la fréquence qu'on lui impose.

## Import local (RS-020)

```
URL choisie par l'utilisateur
  └─ LocalLibraryStore (app)  ── ouvre l'accès security-scoped, API iOS/macOS
       └─ LocalTrackImporter (Domain) ── valide PUIS copie
            └─ TrackFileStorage (contrat) ── FileSystemTrackStorage en production,
                                              faux enregistreur dans les tests
```

- validation **avant** toute écriture : extension, taille, espace libre restant ;
- chemins **relatifs** dans tous les modèles : aucun emplacement privé persisté ou journalisé ;
- un nom de destination contenant `/`, `\`, `:` ou `..` est refusé (remontée de chemin) ;
- le BPM n'est jamais deviné à l'import (`bpmProvenance == .unknown`) ;
- l'attestation de droits conditionne `canAlterTempo` : sans elle, le morceau est visible
  mais jamais présenté comme synchronisable.

## Machine à états de session

```
idle → preparing → running ⇄ paused → finishing → finished
preparing | running | paused → failed
```

`finish` est idempotent depuis tout état actif (aucune deuxième instance de lecture) et
`start` depuis `running` est une non-action. Tests : `RunSessionStateMachineTests`.

Propriétaire unique : `ActiveRunViewModel` détient cette machine à états **et** commande le
moteur audio ; le moteur ne modifie jamais l'état de la session, il rapporte des événements
(`AudioPlaybackEvent`) que la session traduit en transitions. C'est cette règle qui empêche
l'état fantôme du §07 exemple G : une interruption, une perte de sortie ou une commande de
l'écran verrouillé passent toutes par le même chemin décisionnel.

## Algorithmes (résumé)

- **Matching** : pour n ∈ {1,2} pas par battement, `targetTrackBPM = cadence / n` puis
  `requiredRate = targetTrackBPM / nominalBPM` ; admissible si `|requiredRate − 1| ≤ max`.
  Le ratio retenu est celui dont `|log(requiredRate)|` est le plus petit.
- **Coût de sélection** (plus petit = meilleur) :
  `0,65 · |log(rate)| normalisé + 0,20 · pénalité de changement + 0,15 · préférence`.
  Le terme de préférence vaut 0 tant qu'aucune préférence licite n'existe : on n'invente
  aucune caractéristique musicale.
- **Filtre** : rejet des valeurs invalides (diagnostiqué, jamais masqué) → médiane des 5
  dernières mesures valides → EMA α = 0,25 → hystérésis (écart > 1,5 SPM **confirmé** 2 s).
- **Rampe** : le rate appliqué ne varie pas de plus de 0,01 par seconde.
- **Perte de cadence** : maintien du rate 5 s, puis retour linéaire vers 1.0 en 10 s.

### Conséquence mesurée à connaître : retard d'hystérésis

La bande d'hystérésis de 1,5 SPM introduit un écart résiduel borné : pour une cadence
soutenue à 176 SPM, la consigne se stabilise jusqu'à ~1,5 SPM en dessous et ne rejoint
jamais exactement 176. C'est le comportement voulu (pas de pompage), l'erreur maximale de
rate qui en résulte est de l'ordre de 0,9 % — à mesurer sur iPhone en écoute réelle
(RS-023/TEST_PLAN). Les tests unitaires n'affirment donc jamais une convergence exacte.

## Dépendances

Aucune dépendance de production tierce. XcodeGen est un outil de développement
(`brew install xcodegen`), pas une dépendance du binaire.

## Concurrence

`RunSyncCore` est compilé en mode langage Swift 5 (tools-version 5.9) sans activer
`-strict-concurrency=complete`, pour rester compatible avec la version de Xcode la plus
large possible (§15 : décision à reconsidérer, avec la montée en Swift 6 comme travail
dédié et non comme effet de bord de la phase 1).
