# RunSync

Application iPhone native de course à pied qui adapte **doucement** le tempo de morceaux
audio **autorisés** aux pas du coureur, et propose des playlists adaptées à son rythme.

> **État : phase 2 en cours — capteur et musique réels branchés (RS-010, RS-021), jamais
> exécutés sur un iPhone.**
> Le noyau de synchronisation est testé (`swift test` : 108 tests, 0 échec) et l'application
> sait désormais **lire un fichier audio local en ajustant son tempo** et **mesurer la cadence
> réelle avec Core Motion**, avec interruptions, écouteurs débranchés et écran verrouillé
> gérés. En revanche, **aucune ligne de la couche application n'a jamais été compilée** ici
> (pas de macOS, donc pas d'`AVFAudio`, `CoreMotion`, `SwiftUI`) : le premier build sur un Mac
> reste à faire, puis le test sur appareil.
> **Absents : GPS, allure, distance, persistance de l'historique, signaux sonores.** Chaque
> absence est annoncée à l'écran : aucun écran ne prétend faire ce qui n'existe pas.
> Voir [PROJECT_STATUS.md](PROJECT_STATUS.md) et [Docs/RUN_ON_IPHONE.md](Docs/RUN_ON_IPHONE.md).

Promesse produit : « La musique suit tes pas et t'accompagne vers ton rythme idéal. »

## Sources musicales

Seul chemin actif : **fichiers locaux importés par l'utilisateur, dont le droit
d'adaptation est établi**. Aucun service de streaming n'est branché, aucun flux protégé
n'est traité, aucun contournement de DRM n'existe dans ce dépôt. Les sources tierces sont
déclarées avec leur statut de conformité et restent désactivées tant qu'une revue
technique et juridique datée ne les a pas confirmées
([Docs/PROVIDER_COMPLIANCE.md](Docs/PROVIDER_COMPLIANCE.md)).

## Structure

```
Package.swift              noyau portable (Domain + Simulation) — testable sans Xcode
project.yml               définition XcodeGen de l'application iOS (génère RunSync.xcodeproj)
RunSync/
  App/                      composition root, navigation, réglages
  DesignSystem/             thème et composants réutilisables
  Features/                 Onboarding, Home, MusicLibrary, RunSetup, ActiveRun,
                            RunSummary, Statistics, Settings
  Domain/                   Models, Contracts, Tempo, UseCases  ← Swift pur, aucun framework iOS
  Simulation/               scénarios déterministes, source factice, catalogue de démo
  Infrastructure/
    Audio/                  moteur réel AVAudioEngine + time-pitch, lecteur inactif
    Motion/                 capteur de cadence Core Motion (adaptateur)
    Importer/               adaptateur iOS d'import (security-scoped) + bibliothèque observable
    Persistence/            stockage disque des fichiers importés (Foundation pur, testé)
  Resources/                Assets.xcassets (Info.plist généré par XcodeGen)
    TestAudio/              morceau de test intégré (clics 168 BPM, domaine public, généré)
  Tools/DemoTrace/          outil de diagnostic en ligne de commande (`runsync-demo`)
Tools/                      scripts hors application (génération du morceau de test)
  Tests/                    DomainTests, SimulationTests, StorageTests, Fixtures,
                            IntegrationTests, UITests
Docs/                       PRD, ARCHITECTURE, AUDIO_ENGINE, PROVIDER_COMPLIANCE,
                            PRIVACY, TEST_PLAN, APP_STORE_CHECKLIST, RUN_ON_IPHONE
  design/                   aperçu statique des écrans (HTML + captures PNG)
```

## Construire et tester

### Noyau (sans Xcode, macOS ou Linux)

```bash
swift build
swift test
```

### Application iOS (macOS requis)

```bash
brew install xcodegen
xcodegen generate
open RunSync.xcodeproj
# ou, en ligne de commande :
xcrun simctl list devices available
# Le nom du simulateur dépend de l'Xcode installé : « iPhone 16 » avec Xcode 16,
# « iPhone 15 » avec Xcode 15 (iOS 17.2). Utilisez celui que la commande ci-dessus liste.
xcodebuild -project RunSync.xcodeproj -scheme RunSync \
  -destination 'platform=iOS Simulator,name=iPhone 15' build test
```

`RunSync.xcodeproj` n'est pas versionné : `project.yml` est la source de vérité.

### Tester sur votre iPhone

Procédure complète (prérequis, signature, mode développeur, recette de test écran par écran) :
[Docs/RUN_ON_IPHONE.md](Docs/RUN_ON_IPHONE.md). En résumé : `xcodegen generate`, ouvrir
`RunSync.xcodeproj`, laisser Xcode gérer la signature avec votre Apple ID (**compte gratuit
suffisant**, application valable 7 jours), activer le mode développeur sur l'iPhone, puis ⌘R.
Compiler une application iOS exige macOS : aucune route Windows ne l'évite, et les autres
options (Mac loué, runner CI) sont comparées dans le même document.

Avant de signer quoi que ce soit, lancez `swift test` sur le Mac : si le noyau échoue, le
problème n'est pas la signature. Le document détaille aussi la recette de test sur appareil :
autorisation « Mouvement et forme », cadence réelle, clics qui accélèrent, écouteurs
débranchés, appel entrant, écran verrouillé.

### Voir le moteur tourner sans Xcode

```bash
swift run runsync-demo        # suivi de cadence (Follow) sur le scénario 170 → 176 → 160 → ∅ → 170
swift run runsync-demo pace   # mode Pace : cible déclarée, insensible à la cadence observée
```

L'outil rejoue le scénario déterministe et affiche, seconde par seconde, la cadence mesurée,
la cadence filtrée, la qualité, le rate requis puis appliqué (avec la rampe), l'écart en % et
la raison de la décision — puis les agrégats de la session. Aucun accès capteur, aucun audio.

### Aperçu des écrans

L'application iOS n'a pas été compilée dans cet environnement (pas de macOS). Pour montrer
la mise en page réellement décrite par le code SwiftUI, [Docs/design/app-mockup.html](Docs/design/app-mockup.html)
reproduit les 8 écrans en HTML en reprenant le thème et les libellés de `RunSync/Features/`.
**C'est une maquette, pas l'application** — et le HTML a été mis à jour pour la v0.3.0
(audio et capteur réels), alors que les deux captures jointes datent encore de la v0.2.1 :
[app-mockup-1.png](Docs/design/app-mockup-1.png) (onboarding, accueil, musique, préparation)
et [app-mockup-2.png](Docs/design/app-mockup-2.png) (session, session dégradée, résumé, réglages).

## Algorithme en une page

- `targetTrackBPM = cadence cible / n` avec `n ∈ {1, 2}` pas par battement ;
- `requiredRate = targetTrackBPM / BPM nominal` ; admissible si `|requiredRate − 1| ≤ max` ;
- bornage ±5 % (option ±3 %), dérivée du rate limitée à 0,01 par seconde ;
- cadence mesurée : rejet des valeurs invalides (diagnostiqué), médiane sur 5 mesures,
  lissage EMA α = 0,25, hystérésis 1,5 SPM **confirmée sur 2 s** (pas de pompage) ;
- cadence perdue : maintien 5 s puis retour doux vers le tempo original en 10 s ;
- mode Pace : la cible musicale reste la cadence **déclarée**, jamais la cadence observée.

Détail et justification : [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

## Conventions

- Branches `feat/rs-XXX-titre-court`, `fix/rs-XXX-titre-court`.
- Commits `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
- TDD : les tests du Domain précèdent les changements de logique.
- Aucune clé, aucun token, aucun fichier audio importé dans le dépôt.
- Chaque étape livrée met à jour `README.md`, `CHANGELOG.md`, `PROJECT_STATUS.md` et la
  documentation concernée.

## Import de vos morceaux (RS-020)

Onglet **Musique** → bouton **Importer** : le fichier choisi est copié dans l'espace privé de
l'application, après validation du format, de la taille et de l'espace disponible. Le BPM se
saisit à la main sur le morceau (aucune estimation à ce stade) et **le morceau n'est
rendu synchronisable que si vous attestez en avoir les droits** : sans attestation, il est
rangé dans la bibliothèque avec la mention « Tempo non ajustable ». Un fichier disparu du
stockage est immédiatement signalé et n'est plus proposé pour une course.

Limites actuelles : la bibliothèque n'est pas conservée entre deux lancements (RS-033) et
l'adaptateur iOS du sélecteur de fichiers n'a pas pu être exécuté (pas de macOS ici).

## Morceau de test intégré (pour entendre la synchronisation)

Onglet **Musique** → *Ajouter le morceau de test intégré* : des clics synthétisés par le projet
à **168 BPM exactement** ([`Tools/generate_test_tone.py`](Tools/generate_test_tone.py), domaine
public, vérifié : 84 attaques, intervalle médian 0,357143 s). À +5 %, les clics accélèrent
audiblement : c'est la façon la plus simple de vérifier à l'oreille que le time-stretch
fonctionne, sans instrument de mesure.

## Prochaine étape

**RS-013** — coordinateur de session (acteur) qui détient l'état, le capteur et le moteur audio
au même endroit, puis **RS-012** (GPS, allure, distance). Le premier objectif concret reste
cependant de compiler l'application sur un Mac et de dérouler la recette d'appareil de
[Docs/RUN_ON_IPHONE.md](Docs/RUN_ON_IPHONE.md) §8. Plan détaillé :
[PROJECT_STATUS.md](PROJECT_STATUS.md).
