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

- Un **Mac** avec Xcode (App Store, ou <https://developer.apple.com/xcode/>) : lancez-le une
  première fois et laissez-le installer ses composants.
- Un **iPhone sous iOS 17 ou plus**, avec son câble.
- Un **Apple ID gratuit suffit** pour installer sur votre propre appareil : l'application ainsi
  signée **expire après 7 jours**, il suffit de la réinstaller. Le compte Apple Developer payant
  (99 $/an) n'est nécessaire que pour TestFlight et l'App Store.
- **XcodeGen** : `brew install xcodegen`
- **Docker** (facultatif, sur le PC) pour exécuter le noyau de tests sans Mac.

`RunSync.xcodeproj` n'est pas versionné : [project.yml](../project.yml) est la source de
vérité et la génération est déterministe (aucun conflit de merge dans le `pbxproj`).

---

## 3. Passer du PC au Mac

Le dépôt local contient un commit initial (`f4138e5`, 89 fichiers) et un remote `origin`
déjà configuré vers `https://github.com/kiliankh/RunSync.git`. Ce dépôt GitHub **n'existe pas
encore** : tant qu'il n'est pas créé, un `git push` répond `remote: Repository not found`.
Quatre routes, de la plus simple à la plus automatisable :

1. **Bundle Git (recommandé : un seul fichier)** — `RunSync-phase1.bundle` (1,9 Mio, historique
   complet vérifié) est prêt à la racine du projet. Copiez-le sur le Mac, puis :

   ```bash
   git clone RunSync-phase1.bundle RunSync
   cd RunSync
   git log --oneline          # doit afficher f4138e5
   ```

   Plus tard, `git remote set-url origin <URL du dépôt>` puis `git push -u origin main` depuis
   le Mac suffit à le rattacher à GitHub.
2. **Par Git, une fois le dépôt GitHub créé** — créez un dépôt **vide** (sans README, sans
   `.gitignore`, sans licence) nommé `RunSync` sur <https://github.com/new>, puis depuis le PC :
   `git push -u origin main`. Avantage : tous les aller-retours PC → Mac deviennent `git pull`.
3. **Copie directe** — copiez le dossier du projet (OneDrive, clé USB, partage réseau).
   Inutile de copier `.build/` (cache de compilation du PC, inutilisable sur Mac).
4. **Copie ciblée** — si vous ne voulez transférer que le minimum : `RunSync/`, `project.yml`,
   `Package.swift`, `Docs/`, `Tools/`. Le reste n'est pas nécessaire au build.

> Le morceau de test `RunSync/Resources/TestAudio/runsync-test-clicks-168bpm.wav` (2,5 Mio) doit
> suivre le transfert : c'est lui qui rend la synchronisation audible dès la première
> installation. Il est versionné par exception explicite dans `.gitignore`.

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
