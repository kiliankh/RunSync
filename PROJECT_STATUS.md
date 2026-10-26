# RunSync — État du projet

**Version :** 0.3.0 · **Date :** 2026-10-26 · **Périmètre livré :** phase 1 (M0 + noyau de M1),
RS-020 (import local), puis **RS-021 (moteur audio réel)** et **RS-010 (capteur de cadence
Core Motion)**, avec leur branchement dans l'application et un morceau de test embarqué.

**Statut global : `Partial`** — le noyau de synchronisation est **réellement testé** (108 cas)
et l'application sait maintenant lire un fichier local en ajustant son tempo et mesurer la
cadence réelle. Mais **aucune ligne de la couche application ni des deux adaptateurs iOS n'a
jamais été compilée**, et rien n'a été exécuté sur un iPhone : l'application n'est donc **pas
encore une application de course utilisable**, seulement une application prête à être compilée
et testée sur appareil.

## Environnement d'exécution (important)

| Élément | Valeur |
| --- | --- |
| Système de développement | Windows (aucun macOS, aucun Xcode, aucun SDK Apple) |
| Mac de l'utilisateur | macOS **13.7.8** (x86_64), **Xcode 15.2**, Swift 5.9.2 |
| Noyau portable (Domain, Simulation, Persistence) | **réellement compilé et testé** dans un conteneur Docker `swift:6.0` (Linux) |
| Couche application + adaptateurs iOS (AVFAudio, CoreMotion, MediaPlayer, SwiftUI) | **parse syntaxique OK**, mais **jamais compilée** — impossible sans macOS |
| Exécution sur iPhone | **NON EXÉCUTÉE** |
| Lecture audio réellement entendue | **NON** — aucune ligne de ce projet n'a encore produit un son |
| Cadence réelle réellement mesurée | **NON** — le capteur n'a jamais été interrogé |
| Câblage app ↔ paquet (chemins de `project.yml`, imports inter-modules, fichiers orphelins) | **vérifié mécaniquement** : 62 fichiers `.swift`, 0 orphelin, 0 import manquant, noyau portable sans framework Apple |
| Archive de transfert `RunSync-phase1.bundle` | **vérifiée** : clone réel de l'archive, puis `swift test` dans le clone → 108 tests, 0 échec |
| Commits créés | historique sur `main`, arbre de travail propre à chaque étape |
| Dépôt distant | **synchronisé** : `https://github.com/kiliankh/RunSync.git` (privé), `main` identique au local, 0 en avance / 0 en retard, 89 fichiers dont le morceau de test (blob vérifié par hachage identique) |

Aucune ligne ci-dessous ne doit être lue comme « testé sur iPhone » : rien ne l'a été.

## 1. Statut par domaine

| Domaine | Statut | Détail |
| --- | --- | --- |
| Arborescence, configuration projet, CI, documentation | **Working** | structure §06, `project.yml` XcodeGen, workflow GitHub Actions, 8 documents |
| Domain pur (modèles, contrats, erreurs) | **Working** | testé, aucune dépendance Apple |
| TempoMatcher (scénarios A, B, C, T004–T006, T011) | **Working** | oracles vérifiés, bornage et rejets explicites |
| Filtre de cadence (T001–T003, exemple F) | **Working** | rejets diagnostiqués, médiane + EMA + hystérésis |
| Contrôleurs Follow / Pace (T007–T010) | **Working** | bornage, ramp, suggestion de morceau, politique de perte de cadence |
| Rampe de rate audio (NFR-004, §05) | **Working** | 16 tests : dérivée ≤ 1 point de %/s, écriture ≤ 4 Hz, pas de rattrapage après inactivité |
| Garde de conformité des sources (T013, RS-040) | **Working** | capacité **et** conformité exigées ; refus testés |
| Simulateur déterministe (RS-004) | **Working** | scénarios JSON/CSV, source factice, reproduction stricte |
| Import local : validation, copie, erreurs, BPM, réconciliation (RS-020) | **Working au niveau logique** | 25 tests, dont écriture réelle sur disque ; adaptateur iOS non exécuté |
| Moteur audio réel : `AVAudioEngine` + time-pitch, interruptions, route, Now Playing (RS-021) | **Écrit, non compilé** | code complet (438 lignes), jamais exécuté ni écouté |
| Capteur de cadence Core Motion (RS-010) | **Écrit, non compilé** | `CMPedometer`, autorisation, conversion pas/s → SPM, échecs typés |
| Morceau de test embarqué (168 BPM, domaine public) | **Working** | généré de façon déterministe et **mesuré** : 84 attaques, 168,0000 BPM |
| Machine à états de session (T012) | **Partial** | transitions idempotentes testées ; coordinateur unique = RS-013 |
| Écran live | **Partial (non compilé)** | affiche cadence, tempo, audio, qualité, raisons ; ni GPS ni persistance |
| Bibliothèque persistante (RS-033) | **Missing** | la bibliothèque vit en mémoire |
| GPS / allure / distance (FR-005) | **Missing** | RS-012 |
| Signaux sonores de guidage | **Missing** | affichage de l'écart seulement |
| Sources tierces (FR-015) | **Missing — bloqué par conception** | aucune n'est confirmée : garde active |

## 2. Ce qui a réellement été effectué dans cette étape

### RS-021 — moteur audio réel

| Exigence | Réalisé |
| --- | --- |
| FR-008 lecture locale (play/pause/stop/suivant, position) | `AudioEnginePlayback` (actor) : `AVAudioFile` → `AVAudioPlayerNode` → `AVAudioUnitTimePitch` → `mainMixerNode`, `scheduleSegment` avec jeton de génération |
| FR-009 time-stretch sans changement de hauteur intentionnel | `AVAudioUnitTimePitch.rate` (jamais `Varispeed`), `pitch` maintenu à 0, bornage ±5 %/±3 % |
| §05 dérivée limitée et écriture audio contrôlée | `PlaybackRateRamp` dans le **Domain** (donc testé) : 0,01/s, 4 Hz max, pas de saut après inactivité |
| §02 garde de conformité | toute demande de vitesse passe par `TempoAdjustmentGate` **dans le moteur** ; un fichier non attesté est lisible mais jamais altéré |
| NFR-006 interruptions et changements de route | pause immédiate + événement ; reprise décidée par la session, jamais par le moteur |
| FR-017 écran verrouillé | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` : les commandes système deviennent des événements, sans état fantôme |
| FR-019 aucune capture micro | catégorie `playback` uniquement, aucune permission micro déclarée |

### RS-010 — capteur de cadence

| Exigence | Réalisé |
| --- | --- |
| FR-003 cadence Core Motion → SPM | `CMPedometer.startUpdates`, `currentCadence` (pas/s) converti par `CadenceSample.fromStepsPerSecond` |
| Cas D : jamais de 0 inventé | `currentCadence == nil` produit un échantillon `unavailable`, compté comme rejet diagnostiqué |
| Refus sans crash (FR-002) | `CadenceSourceError` typé : appareil sans capteur, autorisation refusée, échec Core Motion ; l'écran l'annonce et le simulateur détecte l'absence de capteur |
| Permissions au bon moment | `NSMotionUsageDescription` déclaré ; la demande a lieu au démarrage de la course et l'écran de réglages décrit l'état réel |

### Étape transversale : pouvoir tester sur appareil

- **Morceau de test intégré** : `Tools/generate_test_tone.py` synthétise des clics à 168 BPM
  (30 s, mono 44,1 kHz), dédié au domaine public, ajouté depuis l'onglet Musique. Il passe par
  le **même chemin d'import** qu'un fichier utilisateur, ce qui vérifie ce chemin sur appareil.
- **Bouton « Démarrer » piloté par la réalité** : actif seulement si un fichier est réellement
  jouable, ou si la course sans audio est explicitement choisie.
- **`Docs/RUN_ON_IPHONE.md` réécrit** : test de la cadence réelle, des clics qui accélèrent,
  des écouteurs débranchés, d'un appel entrant, de l'écran verrouillé.

## 3. Fichiers (89 fichiers, 63 fichiers Swift ≈ 8 740 lignes dont ≈ 2 195 de tests)

Ajoutés à cette étape :

| Fichier | Rôle |
| --- | --- |
| `RunSync/Domain/Tempo/PlaybackRateRamp.swift` (162 l.) | rampe de rate, frontière audio, testable sans iPhone |
| `RunSync/Domain/Contracts/AudioPlaybackEvents.swift` (77 l.) | événements du moteur et état de lecture |
| `RunSync/Infrastructure/Audio/AudioEnginePlayback.swift` (438 l.) | moteur audio réel |
| `RunSync/Infrastructure/Audio/NoAudioPlayback.swift` (38 l.) | lecteur inactif de la course sans audio |
| `RunSync/Infrastructure/Motion/CoreMotionCadenceSource.swift` (156 l.) | capteur de cadence réel |
| `RunSync/Tests/DomainTests/PlaybackRateRampTests.swift` (275 l.) | 16 tests de la rampe |
| `Tools/generate_test_tone.py` | générateur déterministe du morceau de test |
| `RunSync/Resources/TestAudio/` | morceau de test (2,5 Mio) + son README |
| `Docs/RUN_ON_IPHONE.md`, `Docs/AUDIO_ENGINE.md` | réécrits |

Supprimé : `RunSync/Infrastructure/Audio/LocalAudioPlayback.swift` (stub de phase 1, remplacé
par le moteur réel ; son rôle de « non-lecture honnête » est repris par `NoAudioPlayback`).

Modifiés : `AudioPlayback` (contrat), `RunSyncErrors` (erreurs audio et cadence),
`DependencyContainer`, `ActiveRunViewModel`, `ActiveRunView`, `RunSetupView`, `SettingsView`,
`MusicLibraryView`, `LocalLibraryStore`, `project.yml`, `.gitignore`, `README.md`,
`Docs/{ARCHITECTURE,TEST_PLAN,PRIVACY}.md`.

## 4. Tests : commandes et résultats exacts

### Exécuté (PASS)

```bash
docker run --rm -v "<projet>":/workspace -w /workspace swift:6.0 swift build
# => Build complete! 0 avertissement, 0 erreur

docker run --rm -v "<projet>":/workspace -w /workspace swift:6.0 swift test
# => Executed 108 tests, with 0 failures (0 unexpected)
# => EXIT=0

docker run --rm -v "<projet>":/workspace -w /workspace swift:6.0 swiftc -parse ... <couche app + adaptateurs>
# => PARSE_EXIT=0 (syntaxe valide ; les types Apple ne peuvent pas être résolus sans macOS)
```

Répartition : Domain 68 (filtre 11, Follow 10, Pace 5, machine à états 5, garde 6, oracles 15,
**rampe 16**), Simulation 15, Stockage/import 25.

Vérification du morceau de test, réellement exécutée sur le fichier produit : détection des
attaques et mesure du tempo → **84 attaques, intervalle médian 0,357143 s = 168,0000 BPM**,
pic à 0,900 de la pleine échelle.

### Défauts réels trouvés et corrigés (cette étape)

1. **La première évaluation de la rampe appliquait déjà un pas.** L'état initial transmis au
   moteur audio valait 1,01 au lieu de 1,0 : une marche audible au tout premier instant de
   chaque session. Détecté par `testRampsTowardTargetAtOnePercentPerSecond` et
   `testPendingAdjustmentReportsRemainingDistance` ; corrigé dans `PlaybackRateRamp`
   (première évaluation = aucun pas).
2. **`CadenceSourceError` n'était pas `public`.** Le type était déclaré sans `public` dans le
   Domain : la cible application n'aurait jamais pu le voir (deux modules distincts).
   Détecté par un contrôle mécanique de visibilité inter-modules, puis corrigé.
3. **`AudioEventReporting.events()` était synchrone** alors que le moteur réel est un `actor` :
   une méthode isolée à un acteur ne peut pas satisfaire une exigence synchrone. Repéré avant
   compilation, corrigé en `async`.
4. **`AudioPlayback.prepare(trackID:)` était insuffisant** : le moteur a besoin du descripteur
   *et* du fichier pour appliquer la garde de conformité lui-même. Signature changée en
   `prepare(track:fileURL:)` (écart 10 de `ARCHITECTURE.md`).
5. **Deux attentes de test étaient fausses**, pas le code : une consigne non finie doit
   retomber sur le tempo original (et non sur la borne maximale), et la vérification de
   non-marche doit comparer des commandes **consécutives** (elles sautaient la première).
   Tests corrigés, aucun affaibli.
6. **`StatusBanner.tint` n'est pas optionnel** : `tint: nil` aurait échoué à la compilation.
   Repéré en relisant le composant, corrigé dans `ActiveRunView`.

7. **Le plancher de déploiement du paquet empêchait toute exécution sur macOS 13.**
   `Package.swift` déclarait `.macOS(.v14)` alors que le Mac de l'utilisateur est en 13.7.8 :
   `swift build` et `swift test` **réussissaient** (les binaires se construisaient), mais rien ne
   pouvait se lancer — `dyld: Symbol not found: _swift_getTypeByMangledNameInContext2 … built for
   macOS 14.0 which is newer than running OS`. Le plus trompeur : `swift test` affichait `Build
   complete!` et **aucun** test, sans message d'erreur, ce qui ressemblait à un problème de
   harnais. Diagnostiqué grâce à `swift run runsync-demo`, corrigé en `.macOS(.v13)`, puis
   revérifié : 108 tests, 0 échec. **Aucun test n'avait jamais été exécuté sur le Mac avant
   cette correction.**

8. **`Theme.swift` utilisait `DataQuality` sans `import RunSyncDomain`.** `Theme.color(for:)`
   prend ce type en paramètre ; il est déclaré dans le paquet `RunSyncDomain`, alors que le
   fichier n'importait que SwiftUI. La cible applicative n'aurait donc pas compilé sur un Mac.
   Trouvé par le contrôle mécanique des imports inter-modules de **toute** la couche app, puis
   corrigé (0 import manquant restant). C'est exactement la classe d'erreur invisible ici :
   aucun compilateur iOS sur cette machine.

Aucun test n'a été supprimé ni affaibli pour passer.

### Non exécuté (NOT RUN — honnêtement bloqué ici)

| Élément | Raison | Commande / recette |
| --- | --- | --- |
| Compilation de l'application et des adaptateurs iOS | aucun macOS/Xcode | `xcodegen generate && xcodebuild … build` (`RUN_ON_IPHONE.md` §5) |
| Lecture audio réelle, ajustement de tempo audible, artefacts | idem | `RUN_ON_IPHONE.md` §8.2 |
| Cadence réelle, autorisation Core Motion, mode dégradé | idem | `RUN_ON_IPHONE.md` §8.1 |
| Interruptions, écouteurs débranchés, écran verrouillé | idem | `RUN_ON_IPHONE.md` §8.3 |
| Mesures batterie / CPU / latence | idem | `TEST_PLAN.md` (I-01 à I-07, NFR-002/003/005) |
| Import réel via le sélecteur de fichiers | idem | test manuel |

## 5. Démonstration : ce qui marche, ce qui est partiel, ce qui manque

| Outil | Ce qu'il montre | Exécutable ici ? |
| --- | --- | --- |
| `swift run runsync-demo` / `… pace` | chaîne complète cadence → filtre → décision → rampe, avec la raison de chaque décision et les agrégats | **oui**, sortie réelle |
| `swift test` | 108 cas du noyau, dont les 16 de la rampe audio | **oui** |
| `RunSync/Resources/TestAudio/…wav` | la musique de test, vérifiée à 168,0000 BPM | **oui** (mesure du fichier) |
| `Docs/RUN_ON_IPHONE.md` | procédure PC → Mac → iPhone, recette d'appareil complète | document à suivre **sur un Mac** |
| `Docs/design/app-mockup.html` + captures | les 8 écrans tels que le code SwiftUI les décrit | maquette HTML ; **ce n'est pas l'application** |

**Fonctionne (logique testée ; interface écrite mais non compilée) :** onboarding sans
permission anticipée → ajout du morceau de test → import d'un fichier avec attestation de
droits → BPM manuel → préparation de course (Follow/Pace, ±5 %/±3 %, morceau issu de la
**bibliothèque réelle ou du paquet**) → session live (cadence filtrée du capteur ou simulée,
décision de tempo, vitesse réellement appliquée, qualité, raisons, position de lecture) →
résumé → réglages et état de conformité.

**Partiel :** enchaînement des morceaux sans préchargement (le morceau suivant démarre à la fin
du précédent, sans garantie « sans coupure ») ; reprise après pause d'une session simulée qui
repart du début du scénario ; résumé et bibliothèque en mémoire seulement ; écarts de cadence
du mode Pace sans allure, faute de GPS.

**Manque (annoncé à l'écran, jamais simulé) :** GPS, allure, distance, persistance, export,
playlists intelligentes, estimation BPM locale, signaux sonores, tout fournisseur tiers.

## 6. Risques et limitations

| Réf | Risque | État / mitigation |
| --- | --- | --- |
| R1 | Droits de traitement et limites des services musicaux | garde capacitaire + conformité ; toutes les sources tierces désactivées ; import sous attestation |
| R2 | Cadence iPhone instable selon la position | filtre qualifié + scénario simulé ; profils de confiance **à établir sur appareil** |
| R3 | Artefacts audio au time-stretch | rampe 0,01/s, hystérésis, limite ±5 % ; **aucune écoute réelle effectuée à ce jour** |
| R4 | Batterie (audio + Core Motion, puis GPS) | non mesurée |
| R5 | Catalogue BPM fiable et licite | BPM manuel + provenance ; aucune donnée inventée |
| R6 | Promesse Pace trompeuse | cadence cible déclarée séparément, jamais déduite de l'allure |
| R7 | Cohérence sessions/arrière-plan | machine à états idempotente + moteur qui rapporte sans décider ; vérification réelle = RS-013/RS-027 |
| R8 | Politique App Store | checklist prête, aucune case validée |
| R9 | Formats réellement lisibles par AVFoundation | hypothèse à vérifier sur appareil ; FLAC exclu |
| **R10** | **Couche application et adaptateurs jamais compilés** | erreurs de compilation probables au premier build (API Apple, isolation d'acteur) ; `RUN_ON_IPHONE.md` §9 liste les pistes. Aucun contournement possible ici. |
| **R11** | **Arrière-plan audio déclaré mais jamais exercé** | `UIBackgroundModes: audio` est dans `project.yml` ; le comportement réel écran verrouillé reste à constater |
| **R12** | **`AVAudioSession.InterruptionOptions.shouldResume` possiblement obsolète** | éventuel avertissement de compilation selon le SDK ; à moderniser après le premier build |
| — | Retard d'hystérésis connu | consigne pouvant se stabiliser jusqu'à ~1,5 SPM sous la cadence réelle ; compromis contre le pompage, à valider à l'oreille |
| — | Aucune vérification de conformité fournisseur | aucune page officielle consultée par l'agent ; tout reste à recontrôler |

## 7. Prochaines actions ordonnées

1. **Compiler sur un Mac et dérouler `RUN_ON_IPHONE.md`** — c'est la seule action qui
   transforme l'état actuel en preuve. Rien d'autre n'a de sens avant.
2. **RS-013** — `SessionCoordinator` (actor) : propriétaire unique de la session, du capteur et
   du moteur, transitions idempotentes de bout en bout (T012 complet).
3. **RS-027** — vérifier sur appareil l'arrière-plan, l'écran verrouillé, le Bluetooth et les
   appels, puis documenter le comportement réel constaté.
4. **RS-012** — GPS : qualité, rejet des points aberrants, aucune vitesse fictive.
5. **Mesures obligatoires** — écoute A/B 0,95 / 1,0 / 1,05, artefacts, Time Profiler, Energy Log
   sur 30 / 60 / 90 min (NFR-002/003/005), avec le morceau de test intégré.
6. **RS-033** — persistance SwiftData de la bibliothèque (durées, BPM, chemins relatifs).
7. **RS-025 / RS-026** — playlists par plage de BPM, estimation BPM locale avec confiance.
8. **RS-035** — export CSV, effacement complet des données locales.
9. **RS-044** — TestFlight, fiche privacy, QA terrain.
10. **RS-041/042/043** — études fournisseurs, une à la fois, après revue datée et sourcée.

## 8. Ce que ce rapport n'affirme pas

- pas de compilation ni de test de l'application sur iOS, simulateur ou iPhone ;
- **aucun son produit, aucune cadence réelle lue** : le moteur et le capteur n'ont jamais été
  exécutés, seulement écrits et relus ;
- aucune qualité audio, latence, consommation ou stabilité mesurées ;
- aucune conformité de fournisseur tiers vérifiée ;
- pas de session fonctionnelle de bout en bout prouvée.
