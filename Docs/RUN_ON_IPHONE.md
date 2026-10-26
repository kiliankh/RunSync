# Tester RunSync sur un iPhone réel

Ce document décrit **la procédure exacte**, depuis un PC, pour installer cette version sur un
iPhone physique et y tester **la vraie cadence et la vraie musique** — pas une maquette.

> **Contrainte incontournable** : compiler une application iOS exige macOS et Xcode
> (`xcodebuild`, `codesign` et le simulateur iOS n'existent que sur macOS). Aucune méthode
> légitime ne permet de compiler ce projet depuis Windows. Le PC sert à écrire le code et à
> exécuter le noyau de tests ; le Mac sert à construire et à installer. C'est exactement le
> partage décrit ici.

---

## 1. Ce qui fonctionne maintenant sur l'iPhone

| Élément | État dans cette version |
| --- | --- |
| **Cadence réelle (Core Motion)** | **Implémenté** — `CMPedometer`, autorisation « Mouvement et forme » demandée au démarrage de la course |
| **Lecture audio locale** | **Implémenté** — `AVAudioEngine` + `AVAudioUnitTimePitch`, fichiers importés ou morceau de test intégré |
| **Ajustement de tempo en course** | **Implémenté** — ±5 % (±3 %), rampe limitée à 1 point de %/s, écriture audio ≤ 4 Hz |
| **Écouteurs débranchés / casque Bluetooth perdu** | **Implémenté** — mise en pause et message à l'écran |
| **Appel entrant, Siri, autre app** | **Implémenté** — pause immédiate, reprise seulement si le système le recommande |
| **Écran verrouillé / commandes système** | **Implémenté** — Now Playing + play/pause/suivant, la session reste seule décisionnaire |
| **Morceau de test intégré (clics 168 BPM)** | **Fourni** — ajouté depuis l'onglet Musique, droits établis (domaine public) |
| Import d'un fichier à vous, attestation de droits, BPM manuel | **Implémenté** — jamais exécuté sur appareil jusqu'ici |
| Suivi GPS, allure, distance | **Absent** — RS-012 ; affiché en tirets, rien d'inventé |
| Historique et bibliothèque persistés | **Absent** — RS-033 ; tout est perdu à la fermeture |
| Enchaînement de morceaux « sans coupure » | **Partiel** — le morceau suivant démarre à la fin du précédent ; qualité de transition non mesurée |
| Signaux sonores de guidage | **Absent** — affichage de l'écart seulement |

**Ce qui ne se teste pas dans le simulateur** : le simulateur iOS ne fournit **aucune**
cadence. L'application le détecte (`CMPedometer.isCadenceAvailable()`), le dit, et bascule sur
le scénario simulé au lieu d'afficher un chiffre inventé. Toute la partie capteur se teste donc
sur l'appareil.

---

## 2. Prérequis

- Un **Mac sous macOS 13 (Ventura) ou plus** : `Package.swift` déclare `.macOS(.v13)`, ce qui
  couvre macOS 13.7 comme macOS 14 et plus. Ce plancher ne décrit pas seulement la disponibilité
  des API : il fixe la version **minimale d'exécution** des binaires produits (démonstration et
  bundle de tests). Déclaré en 14, tout se compilait encore sur macOS 13 mais plus rien ne
  s'exécutait — `Symbol not found … built for macOS 14.0 which is newer than running OS` — et
  `swift test` s'arrêtait à `Build complete!` **sans lancer un seul test**. Constaté sur
  macOS 13.7.8 + Xcode 15.2.
- **Xcode 15 ou plus** (App Store, ou <https://developer.apple.com/xcode/>) : lancez-le une
  première fois et laissez-le installer ses composants.
- Un **iPhone sous iOS 17 ou plus**, avec son câble.
- Un **Apple ID gratuit suffit** pour installer sur votre propre appareil : l'application ainsi
  signée **expire après 7 jours**, il suffit de la réinstaller. Le compte Apple Developer payant
  (99 $/an) n'est nécessaire que pour TestFlight et l'App Store.
- **XcodeGen** : `brew install xcodegen` s'il y a Homebrew — sinon l'archive précompilée
  (voir ci-dessous). À **ne pas** compiler depuis les sources avec Xcode 15.2 : une dépendance
  exige Swift 6.
- **Docker** (facultatif, sur le PC) pour exécuter le noyau de tests sans Mac.

### Contrôle des prérequis — à lancer avant tout le reste (30 secondes)

Dans le Terminal du Mac :

```bash
sw_vers                 # ProductVersion : 13.x suffit (vérifié sur 13.7.8 + Xcode 15.2)
xcodebuild -version     # Xcode 15.x ou plus
xcode-select -p         # doit pointer DANS /Applications/Xcode.app/…
brew --version          # absent : https://brew.sh
xcodegen --version      # absent : brew install xcodegen
```

Si `xcode-select -p` renvoie `/Library/Developer/CommandLineTools`, c'est le jeu d'outils en
ligne de commande qui est actif, pas Xcode complet : `xcodegen` et le simulateur ne
fonctionneront pas. Corrigez-le vous-même (la commande demande votre mot de passe) :

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### Installer XcodeGen sans Homebrew (voie vérifiée)

**Ne compilez pas XcodeGen 2.46.0 depuis les sources avec Xcode 15.2.** Son propre manifeste
déclare bien `swift-tools-version:5.9`, mais une de ses dépendances (`XcodeProj` >= 8.24.12)
exige `swift-tools-version:6.0.0`, donc **Swift 6 / Xcode 16**. SwiftPM s'arrête sur :

```
error: Dependencies could not be resolved because 'xcodeproj' >= 8.24.12 contains
incompatible tools version (6.0.0) and root depends on 'xcodeproj' 9.14.0.
```

Prenez l'**archive précompilée** de la version 2.46.0. Elle a été inspectée : binaire
universel (**x86_64 et arm64**, donc tout Mac) dont la version minimale de macOS est **11.0** —
il tourne sur macOS 13. Aucune installation globale, aucun `sudo`, et `curl` ne pose pas
l'attribut de quarantaine qu'un téléchargement par navigateur ajouterait.

```bash
cd ~
curl -L -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
unzip -o xcodegen.zip            # crée ~/xcodegen/bin/xcodegen et ~/xcodegen/share/
~/xcodegen/bin/xcodegen --version
```

Puis, **depuis le dossier du projet RunSync** :

```bash
cd /chemin/vers/RunSync
~/xcodegen/bin/xcodegen generate
ls -d RunSync.xcodeproj          # doit maintenant exister
```

Pas besoin de `--spec` tant que la commande est lancée depuis le dossier qui contient
`project.yml`. Conservez le dossier `~/xcodegen` en l'état : le binaire y trouve ses
préréglages de construction dans `share/`.

> **Piège de casse.** Sur macOS, le système de fichiers est **insensible à la casse** par
> défaut : `~/XcodeGen` et `~/xcodegen` désignent le **même dossier**. Un `rm -rf ~/XcodeGen`
> destiné à nettoyer un ancien clone efface donc l'installation fraîchement décompressée. C'est
> arrivé une fois ; le binaire fonctionnait (`--version` répondait) puis a disparu.

`RunSync.xcodeproj` n'est pas versionné : [project.yml](../project.yml) est la source de
vérité et la génération est déterministe (aucun conflit de merge dans le `pbxproj`).

---

## 3. Passer du PC au Mac

Le dépôt distant existe et **`main` y est déjà synchronisé** :
<https://github.com/kiliankh/RunSync.git>. Il est **privé** (il répond 404 aux requêtes
anonymes) : le clone demande donc une authentification. Trois routes :

1. **Clone Git — le chemin normal désormais** :

   ```bash
   git clone https://github.com/kiliankh/RunSync.git RunSync
   cd RunSync
   git log --oneline          # historique complet, commit le plus récent en haut
   ```

   Dépôt privé oblige, GitHub ne demande plus votre mot de passe mais un **jeton d'accès
   personnel** (*Settings -> Developer settings -> Personal access tokens*) : c'est ce jeton
   qu'il faut coller lorsque Git réclame un mot de passe. Deux alternatives plus confortables :
   `git@github.com:kiliankh/RunSync.git` après avoir déposé une clé SSH dans votre compte, ou le
   clone par Xcode ci-dessous, qui gère lui-même la connexion. Ensuite, chaque aller-retour
   PC -> Mac se réduit à `git pull`.
2. **Clone par Xcode** — fenêtre d'accueil -> **Clone Git Repository** -> collez l'URL. **Deux
   pièges** : `RunSync.xcodeproj` n'est **pas** versionné (il est engendré depuis `project.yml`),
   donc Xcode clonera le dépôt sans trouver de projet à ouvrir — lancez `xcodegen generate`,
   puis ouvrez le `.xcodeproj` obtenu. Et si vous ouvrez plutôt `Package.swift`, Xcode ne
   construira que le noyau portable : sans cible applicative, sans Info.plist, sans permission —
   aucune application iOS n'en sortira.
3. **Bundle Git (repli hors ligne)** — `RunSync-phase1.bundle` à la racine du projet est une
   **photo** du dépôt (1,9 Mio, historique complet vérifié) utile si le réseau ou
   l'authentification pose problème :

   ```bash
   git clone RunSync-phase1.bundle RunSync
   ```

   L'archive ne se met pas à jour toute seule : après de nouveaux commits,
   `git bundle create RunSync-phase1.bundle --all` la régénère.

Sans Git du tout, une copie de dossier fonctionne aussi (OneDrive, clé USB, partage réseau) :
inutile de copier `.build/`, cache de compilation du PC inutilisable sur Mac. Le minimum strict
est `RunSync/`, `project.yml`, `Package.swift`, `Docs/`, `Tools/`.

> Le morceau de test `RunSync/Resources/TestAudio/runsync-test-clicks-168bpm.wav` (2,5 Mio)
> **fait partie du dépôt** (versionné par exception explicite dans `.gitignore`) : tout clone le
> contient. C'est lui qui rend la synchronisation audible dès la première installation — une
> copie manuelle ne doit donc pas l'oublier.

---

## 4. Étape 1 — vérifier le noyau sur le Mac (2 minutes, sans signature)

```bash
cd <dossier du projet>
swift test
```

Attendu : **108 tests, 0 échec**. C'est le noyau de calcul (filtre de cadence, matcher,
contrôleurs Follow/Pace, rampe de rate, import de fichiers). Si cette commande échoue, arrêtez
là : le problème est dans le code, pas dans la signature.

Le même résultat s'obtient sur le **PC** sans Mac, via Docker :

```bash
docker run --rm -v "$(pwd)":/workspace -w /workspace swift:6.0 swift test
```

*(Si Docker renvoie `missing required module 'SwiftShims'`, c'est un cache `.build` créé sous un
autre chemin : `rm -rf .build` puis relancez.)*

---

## 5. Étape 2 — générer le projet et compiler pour le simulateur

```bash
xcodegen generate
xcrun simctl list devices available        # choisir un simulateur réellement installé
xcodebuild -project RunSync.xcodeproj -scheme RunSync \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

**C'est le vrai risque de cette étape.** Aucune ligne de `RunSync/App/`, `RunSync/Features/`,
`RunSync/DesignSystem/`, `RunSync/Infrastructure/Audio/` et `RunSync/Infrastructure/Motion/`
n'a jamais vu un compilateur : le PC de développement n'a ni macOS ni les frameworks
`AVFAudio`, `CoreMotion`, `MediaPlayer` et `SwiftUI`. Ces fichiers ont seulement été **parsés**
(syntaxe valide) et leurs références croisées vers le noyau ont été vérifiées mécaniquement.
Les erreurs résiduelles seront donc des erreurs de signature d'API Apple ou d'isolation
d'acteur — voir §9.

Ensuite, ⌘R dans Xcode : l'application tourne dans le simulateur. Vous y verrez toute
l'interface, la cadence **simulée** et le refus honnête du capteur. Le son, lui, marche aussi
dans le simulateur (un morceau importé s'y joue), ce qui permet de vérifier la chaîne audio
avant même de brancher l'iPhone.

---

## 6. Étape 3 — installer sur l'iPhone

1. **Compte** : Xcode → *Settings…* → *Accounts* → ajoutez votre Apple ID.
2. **Signature** : cible **RunSync** → *Signing & Capabilities* : cochez *Automatically manage
   signing* et choisissez votre équipe. Si Xcode signale que l'identifiant est déjà pris,
   remplacez `com.runsync.app` par quelque chose d'unique (ex. `com.<prenom>.runsync`).
3. **Brancher l'iPhone**, accepter « Faire confiance à cet ordinateur ».
4. **Mode développeur** (obligatoire depuis iOS 16) : iPhone → Réglages → Confidentialité et
   sécurité → **Mode développeur** → activer → redémarrer. L'entrée n'apparaît qu'après le
   premier branchement à Xcode.
5. Choisir **votre iPhone** comme destination dans Xcode, puis ⌘R.
6. Si l'application refuse de se lancer : Réglages → Général → **VPN et gestion de
   l'appareil** → faire confiance au certificat, puis relancer.

Variante en ligne de commande :

```bash
xcodebuild -project RunSync.xcodeproj -scheme RunSync \
  -destination "platform=iOS,name=<Nom de votre iPhone>" -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> <chemin du RunSync.app>
```

---

## 7. Étape 4 — préparer la première course (3 minutes)

1. **Onboarding** — quatre pages. Aucune alerte de permission ne doit apparaître ici.
2. **Onglet Musique** → **« Ajouter le morceau de test intégré »**.
   Attendu : « *Clics de test 168 BPM* ajouté : 168 BPM, tempo ajustable ».
   Le fichier est copié dans l'espace privé de l'application, exactement comme un import
   utilisateur.
3. **Onglet Courir** — section *Audio* : « Lecture : **Fichier local** ». Le bouton **Démarrer
   est actif** (il ne l'est plus seulement en mode démo).
4. **Réglages** (engrenage) → section *Cadence* : « Capteur de l'iPhone (Core Motion) » doit
   annoncer « Capteur de cadence disponible ». Si l'autorisation n'a jamais été demandée, le
   message l'explique : elle sera demandée au démarrage.

Si vous préférez votre musique : Musique → *Importer* → choisissez un fichier que **vous
possédez** → attestation de droits → saisie du BPM (sans BPM renseigné, le morceau n'est pas
considéré comme synchronisable). L'attestation n'est pas un détail juridique décoratif : elle
pilote la garde qui autorise ou refuse l'ajustement du tempo.

---

## 8. Étape 5 — le test sur iPhone (le vrai)

Lancez une course en marchant ou en courant, mode **Follow**, écouteurs ou casque Bluetooth
recommandés. À observer, dans l'ordre :

### 8.1 Capteur et autorisation

- Au premier **Démarrer**, iOS doit demander « **Mouvement et forme** ». Accordez.
- La cadence affichée doit réagir à votre allure réelle : marchez lentement (~100–120 SPM),
  puis accélérez (~160–180 SPM). Les premières secondes peuvent afficher « — » : `currentCadence`
  est `nil` tant que le capteur n'a pas de mesure exploitable. **Aucun 0 n'est inventé.**
- Refusez l'autorisation (Réglages → RunSync → Mouvement et forme) et relancez : l'application
  doit afficher un message explicite et continuer à fonctionner, sans cadence inventée.
  Dans le simulateur, le message doit être « Aucune cadence sur cet appareil ».

### 8.2 Le son et la synchronisation (le cœur du produit)

- La musique démarre, et la ligne « **Taux d'ajustement** » bouge de quelques dixièmes de
  pourcent autour de 0 %.
- **Test le plus parlant** : courez à une cadence **nettement au-dessus** de 168 SPM
  (le morceau de test) — mettez-vous à environ 176 SPM. Vous devez **entendre les clics
  accélérer** jusqu'à environ **+4,8 %**, puis se stabiliser. Le taux passe à +5 % au maximum,
  jamais au-delà : c'est le bornage.
- Ralentissez à ~160 SPM : les clics ralentissent et se bornent à **−5 %** (le morceau de test
  168 BPM ne peut pas descendre sous 160 SPM environ). Après **15 s d'écart soutenu**, une
  suggestion de morceau mieux adapté doit apparaître — et **le morceau en cours n'est pas
  coupé**.
- Écoutez la qualité : c'est le test de la §11 (artefacts). Notez si vous entendez des
  craquements ou une voix déformée. Le réglage ±3 % (Réglages) doit réduire nettement ces
  effets : comparez les deux.
- **Ne perdez pas de vue que la hauteur doit rester stable** : `AVAudioUnitTimePitch` ne
  transpose pas, contrairement à un simple changement de vitesse.

### 8.3 Ruptures et interruptions (FR-017, NFR-006)

| Test | Comportement attendu |
| --- | --- |
| Débrancher les écouteurs en course | Musique **en pause**, message « Sortie audio perdue », session en pause ; **aucun** son sur le haut-parleur |
| Appel entrant | Musique en pause pendant l'appel ; à la fin, reprise **seulement** si la session était en course |
| Verrouiller l'écran | La musique continue (mode arrière-plan audio) ; les commandes play/pause/fin apparaissent sur l'écran verrouillé |
| Bouton pause de l'écran verrouillé | L'application affiche « Session en pause » : **aucun état fantôme** |
| Bouton « suivant » de l'écran verrouillé | Passe au morceau suivant de la playlist (message si elle n'en contient qu'un) |
| Verrouiller puis rouvrir l'application | L'écran de session retrouve le même état ; pas de seconde session |

### 8.4 Fin de course

- **Terminer** : la musique s'arrête, la session passe à *Terminée*, le résumé s'affiche
  (cadence moyenne, mesures rejetées, temps synchronisé, **allure et distance en tirets**).
- **Nouvelle session** : l'état repart proprement, sans doubler la lecture.

### 8.5 À noter pendant le test

- **Autorisation refusée** puis relance : pas de crash (FR-002).
- **VoiceOver** et taille de texte maximale : l'écran live doit rester lisible (FR-016).
- **Batterie** : notez le pourcentage avant/après 30 minutes (l'objectif est de mesurer, pas
  d'affirmer un chiffre — NFR-005).

---

## 9. Si le build échoue (le scénario probable au premier essai)

C'est **attendu** : la couche application et les deux adaptateurs iOS n'ont jamais été
compilés. Pour que la correction soit rapide, remontez-moi :

1. la commande exacte lancée ;
2. les 5 à 10 premières erreurs **avec fichier:ligne:colonne** ;
3. `xcodebuild -version` et le nom du simulateur/appareil.

Pistes les plus probables, par ordre de vraisemblance :

| Message | Cause probable | Correction |
| --- | --- | --- |
| `cannot find 'X' in scope` dans `Features/` | appel légèrement différent de la signature réelle du noyau | lire le prototype dans `RunSync/Domain/` |
| erreur d'**isolation d'acteur** sur `AudioEnginePlayback` | `actor` confronté à une exigence non isolée | passer la méthode concernée en `nonisolated` ou l'appel en `await` |
| `'shouldResume' is deprecated` | évolution du SDK | avertissement seul ; à moderniser selon la recommandation Apple |
| erreur sur `CMErrorMotionActivityNotAuthorized` | type d'import Core Motion selon le SDK | comparer via `NSNumber`/codes numériques |
| `AVAudioSession` / `MediaPlayer` introuvable | framework non lié | XcodeGen les lie automatiquement via l'import ; sinon, les ajouter dans *Build Phases* |
| `dyld: Symbol not found: _swift_getTypeByMangledNameInContext2` puis `built for macOS 14.0 which is newer than running OS` | le plancher de déploiement du paquet dépasse la version du système : le binaire se construit puis refuse de se lancer | aligner `platforms:` de `Package.swift` sur la version réellement utilisée — c'est un défaut **déjà corrigé** en `.macOS(.v13)` |
| `swift test` affiche `Build complete!` et **aucun** test, sans message d'erreur | même cause : le bundle de test ne peut pas être exécuté, et SwiftPM le signale à peine | vérifier `platforms:` dans `Package.swift` ; `swift test --verbose` montre la cible réellement visée (`-target x86_64-apple-macosx14.0`) |

---

## 10. Si vous n'avez pas de Mac

| Route | Ce qu'elle permet | Limite |
| --- | --- | --- |
| **Mac emprunté (2 h suffisent)** | La procédure complète ci-dessus | Le plus simple, de loin |
| Mac loué dans le cloud (MacinCloud, MacStadium, AWS EC2 Mac…) | Xcode complet en bureau distant | Votre iPhone n'est **pas** branché dessus : il faut alors une signature de distribution (compte payant + UDID) ou TestFlight |
| Runner CI macOS (GitHub Actions) | Compile et teste à chaque commit | N'installe rien sur votre iPhone |
| Mac virtuel ou « hackintosh » | Interdit par la licence Apple | À ne pas faire |

Freebuff Cloud est une machine **Linux** : elle ne compilera pas davantage ce projet. Le runner
macOS de GitHub Actions (déjà présent, en `swift test` du noyau) est en revanche utile pour
savoir sans Mac si le noyau reste vert après chaque changement.

---

## 11. Ce que ce test ne prouvera toujours pas

- **Aucune mesure instrumentée** : latence réelle commande → son audible, consommation CPU,
  énergie. Cela demande Instruments (Time Profiler, Energy Log) sur iPhone, encore à faire.
- **Aucun rejet de fichier corrompu** testé sur appareil, aucune liste de formats AVFoundation
  validée sur le terrain.
- **Aucune fiabilité de la cadence selon la position** (poche, main, ceinture) : c'est un profil
  de confiance à établir, étape par étape.
- **Aucun GPS, aucune persistance** : le résumé est perdu à la fermeture de l'application.
- **Aucune conformité de fournisseur tiers** : tout ce qui n'est pas un fichier local est
  désactivé, par conception.
