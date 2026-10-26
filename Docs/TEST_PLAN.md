# RunSync — Plan de test

## Comment exécuter

### 1. Noyau portable (Domain + Simulation), sans Xcode

```bash
swift build          # compilation du noyau
swift test           # tests unitaires Domain + Simulation
```

Valable sur macOS (Xcode ou toolchain Swift) **et** sur Linux (par exemple l'image Docker
officielle `swift:6.0`), car le nom exact de la suite ne dépend d'aucun framework Apple.

### 2. Application iOS complète (macOS requis)

```bash
brew install xcodegen
xcodegen generate
xcrun simctl list devices available        # découvrir les appareils réellement installés
xcodebuild -project RunSync.xcodeproj -scheme RunSync \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project RunSync.xcodeproj -scheme RunSync \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

> Le nom `iPhone 16` est indicatif : le cahier des charges §14 impose de découvrir les
> appareils installés avant d'exécuter.

## Résultat d'exécution (état au 2026-10-26, v0.3.0)

| Commande | Environnement | Résultat exact |
| --- | --- | --- |
| `swift test` (image `swift:6.0`, Linux) | outil de développement sans Xcode | **108 tests exécutés, 0 échec, code de sortie 0** |
| `swift build` (même image) | idem | **code de sortie 0, aucun avertissement ni erreur de compilation** |
| `swiftc -parse` sur la couche app et les adaptateurs iOS | idem | **parse OK** — syntaxe valide, mais aucune vérification de types possible sans les SDK Apple |
| `xcodebuild ... build test` | **non exécuté** — aucun macOS/Xcode disponible | **NOT RUN** |
| Tests sur iPhone physique (I-01 à I-07, §8 de `RUN_ON_IPHONE.md`) | **non exécuté** | **NOT RUN** |
| Workflow GitHub Actions | **non exécuté** | **NOT RUN** |

Dans le tableau ci-dessous, « écrit » signifie que le test existe et a été exécuté avec
succès lors de la campagne ci-dessus ; le statut indique la **couverture du périmètre**, pas
seulement l'existence du test.

## Inventaire des tests unitaires (phase 1)

| Cas | Sujet | Fichier | Statut |
| --- | --- | --- | --- |
| T001 | 2,833333 pas/s → ~170 SPM | `CadenceFilterTests` | écrit — exécution : voir PROJECT_STATUS |
| T002 | nil/NaN/inf/négatif/aberrant rejetés, jamais 0 | `CadenceFilterTests` | écrit |
| T003 | outlier isolé sans saut brutal | `CadenceFilterTests` | écrit |
| T004 / A | 168 BPM, 170 SPM → 1,01190476 | `TempoMatchingOracleTests` | écrit |
| T005 / B | 85 BPM, 170 SPM, ratio 2 → 1,0 | `TempoMatchingOracleTests` | écrit |
| T006 / C | 168 BPM, 150 SPM → borné à 0,95 | `TempoMatchingOracleTests` | écrit |
| T007 | suivi soutenu, borné, sans oscillation | `FollowControllerTests` | écrit |
| T008 | Pace : cible insensible à la cadence observée | `PaceControllerTests` | écrit |
| T009 | changement de morceau seulement si écart durable | `FollowControllerTests` | écrit |
| T010 / D | HOLD puis retour politique contrôlé | `FollowControllerTests` | écrit |
| T011 | BPM 0/négatif/non fini/nil : aucune division | `TempoMatchingOracleTests` | écrit |
| T012 | pas de double session, transitions idempotentes | `RunSessionStateMachineTests` | écrit — **partiel** (coordinateur audio = RS-013) |
| T013 | source sans droit d'adaptation → refus explicite | `TempoAdjustmentGateTests` | écrit |
| T014 | import invalide / fichier effacé | `LocalTrackImportTests`, `FileSystemTrackStorageTests` | **fait côté logique** (format, taille, espace, accès, fichier supprimé, chemin relatif) ; sélecteur iOS non exécuté |
| T015 | session persistée, export, suppression | — | **non démarré** (RS-033/RS-035) |
| T016 | unités temps/allure/distance | `PaceUnits` (couvert indirectement) | **partiel** — GPS = RS-012 |
| T017 | interruption / changement de route | — | **non démarré** (RS-027) |
| T018 | hors ligne sans requête réseau | architecture (aucun client réseau) | **partiel** |
| RS-021 | rampe de rate : dérivée ≤ 1 point de %/s, écriture ≤ 4 Hz, bornage, maintien sans consigne, pas de rattrapage après inactivité | `PlaybackRateRampTests` | **fait** (16 cas) |
| RS-010 | conversion pas/s → SPM et traitement d'une absence de cadence | `CadenceFilterTests`, `CadenceSample.fromStepsPerSecond` | **fait côté logique** ; adaptateur Core Motion non compilé, capteur non exercé |
| RS-021 | lecture audio, interruptions, changement de route, écran verrouillé | — | **écrit, non exécuté** : exige un iPhone (`RUN_ON_IPHONE.md` §8.3) |
| RS-020 | import local : validation avant copie, erreurs typées, attestation de droits | `LocalTrackImportTests` | **fait** (14 cas) |
| RS-020 | stockage disque : copie, taille réelle, suppression idempotente, remontée de chemin | `FileSystemTrackStorageTests` | **fait** (7 cas, écriture réelle en répertoire temporaire) |
| §09 | fichier supprimé jamais faussement jouable + refus du matcher et de la garde | `FileSystemTrackStorageTests` | **fait** |
| FR-007 | BPM manuel prioritaire, BPM invalide refusé | `LocalTrackImportTests` | **fait** |

Cas supplémentaires déjà couverts : décodage des fixtures JSON/CSV et rejet des scénarios
invalides, déterminisme de la source simulée, gestion de perte de cadence, stabilité du
rate pour la gigue ±1 SPM (§05 exemple F), refus de configuration de politique invalide.

### Note de conception : retard d'hystérésis

La bande d'hystérésis (1,5 SPM confirmés sur 2 s) implique que la consigne peut se stabiliser
jusqu'à ~1,5 SPM sous la cadence réelle et ne la rejoint pas exactement. Les tests affirment
donc des bornes (≤ cible, écart ≤ 1 %) et jamais une convergence exacte : c'est le compromis
retenu contre le pompage. À mesurer en écoute réelle (RS-023).

## Tests à exécuter sur appareil (NON EXÉCUTÉS à ce jour)

| Test | Objectif | Statut |
| --- | --- | --- |
| I-01 | lecture du morceau de test intégré à 0,95 / 1,0 / 1,05, écoute A/B | **code écrit, jamais exécuté** — `RUN_ON_IPHONE.md` §8.2 |
| I-02 | cadence simulée enregistrée rejouée pendant une lecture réelle | **code écrit, jamais exécuté** |
| I-03 | application en arrière-plan et écran verrouillé | **code écrit, jamais exécuté** — `RUN_ON_IPHONE.md` §8.3 |
| I-04 | déconnexion d'un casque Bluetooth en pleine course | **code écrit, jamais exécuté** — `RUN_ON_IPHONE.md` §8.3 |
| I-05 | appel entrant, Siri, changement de route | **code écrit, jamais exécuté** — `RUN_ON_IPHONE.md` §8.3 |
| I-06 | permissions accordées puis refusées, appareil sans capteur, fichier supprimé | **code écrit, jamais exécuté** — `RUN_ON_IPHONE.md` §8.1 |
| I-07 | Time Profiler + Energy Log (30/60/90 min) | à faire (NFR-005), après compilation |

## Tests de terrain (manuel, 3 séquences minimum)

1. Allure stable 10 min : la cadence suit sans pompage perceptible.
2. Accélération puis ralentissement progressifs : réactivité utile, pas gênante.
3. Variation erratique + perte de capteur : aucun pompage, aucun crash, état affiché.

## Définition de fait (DoD)

- code compilable sur l'outil cible, sinon état **BLOCKED** documenté ;
- tests pertinents écrits **et** exécutés avec résultat exact rapporté ;
- aucun secret, logs non sensibles, erreurs UX claires ;
- mise à jour de `README.md`, `CHANGELOG.md`, `PROJECT_STATUS.md` et de la documentation
  concernée ;
- rapport explicite sur ce qui a réellement été testé — et sur ce qui ne l'a pas été.
