# RunSync — PRD (extrait opérationnel)

Version 0.1.0 — phase 1 (M0 + noyau de M1). Référence amont : `RunSync_AGENT_MASTER_SPEC_FR.txt` v1.0.

## Promesse

« La musique suit tes pas et t'accompagne vers ton rythme idéal. » Application iPhone
native, **local-first**, sans compte obligatoire, sans backend.

## Utilisateur

Coureur amateur à régulier, iPhone + écouteurs, qui veut lancer une course très vite et
voir cadence, allure, distance, durée et état audio — sans oscillation de tempo, sans
interruption à l'écran verrouillé.

## Modes

| Mode | Cible du tempo | Écart affiché |
| --- | --- | --- |
| **Follow** | cadence mesurée **filtrée** | non applicable |
| **Pace** | cadence cible **déclarée** | `cadence observée − cadence cible` en SPM, séparément |

L'allure seule ne détermine jamais la cadence : la longueur de foulée est individuelle.
En mode Pace, la musique **n'accélère pas** quand le coureur ralentit (sinon le guidage
serait contradictoire).

## Périmètre de la phase 1 (livré)

- Noyau Domain pur : modèles, contrats, erreurs typées, machine à états de session.
- `TempoMatcher` : ratios 1:1 et 2:1, bornage ±5 %/±3 %, classement par coût de sélection.
- `CadenceFilter` : validation, fenêtre médiane, lissage EMA, hystérésis avec confirmation.
- Contrôleurs `FollowController` et `PaceController` avec rampe de rate et politique
  de perte de cadence (maintien puis retour doux).
- Simulateur de cadence déterministe (fixtures JSON/CSV) et source factice.
- **Import local des fichiers audio (RS-020)** : validation avant copie, erreurs typées,
  attestation de droits obligatoire pour rendre le tempo ajustable, BPM manuel,
  réconciliation des fichiers disparus, stockage disque confiné, tests sur disque réel.
- Application SwiftUI : 4 onglets, onboarding, bibliothèque (import/BPM/suppression),
  préparation de course, **écran live de démonstration**, résumé, réglages, statut de
  conformité des sources.
- Moteur de lecture audio locale réel (`AVAudioEngine` + `AVAudioUnitTimePitch`), **écrit et
  non compilé** : aucune écoute n'a encore été faite.

## Hors périmètre de la phase 1 (assumé, non simulé)

| Sujet | Étape | Comportement actuel |
| --- | --- | --- |
| Capteur Core Motion réel | RS-010 | **livré** (`CMPedometer`), jamais exécuté sur appareil |
| GPS, allure, distance | RS-012 | affiché « — », aucune valeur inventée |
| Moteur audio réel + time-stretch | RS-021 | **livré** (`AVAudioEngine`), jamais compilé ni écouté |
| Import de fichiers locaux | RS-020 | **livré côté logique** ; l'adaptateur iOS (sélecteur, security-scoped) n'a pas été exécuté |
| Persistance des sessions | RS-033 | résumé en mémoire uniquement |
| Export CSV / effacement | RS-035 | réglages annoncés indisponibles |
| Playlists intelligentes | RS-025 | sélection d'un morceau de démo |
| Estimation BPM locale | RS-026 | BPM manuel/description seulement |
| Sources tierces | RS-041/042/043 | désactivées par la garde de conformité |

## Exigences fonctionnelles — état vérifiable

| ID | Sujet | État phase 1 |
| --- | --- | --- |
| FR-001 | lancement sans login, hors ligne | **fait** (aucun réseau, aucun compte) |
| FR-002 | onboarding, refus sans crash | **fait** (aucune permission demandée en phase 1) |
| FR-003 | cadence Core Motion → SPM, nil jamais 0 | **fait** (conversion + filtre testés ; adaptateur écrit, non exécuté) |
| FR-004 | cadence simulée déterministe | **fait** (fixtures + tests) |
| FR-005 | allure/distance GPS | **non démarré** (RS-012) |
| FR-006 | import audio autorisé | **fait au niveau logique** (validation, copie, erreurs typées, suppression) ; adaptateur iOS non exécuté |
| FR-007 | BPM manuel ou calculé avec confiance | **partiel** (BPM manuel prioritaire et provenance), analyse locale = RS-026 |
| FR-008 | playback local (play/pause/stop/suivant, position) | **écrit, non compilé** (RS-021) |
| FR-009 | time-stretch ±5 % sans changement de hauteur | **fait côté logique** (politique, rampe testée) ; moteur écrit, non écouté |
| FR-010 | mode Follow | **fait** (noyau + tests) |
| FR-011 | mode Pace (cible ≠ mesurée) | **fait** (noyau + tests) |
| FR-012 | playlists par cadence | **partiel** (classement par proximité de BPM ; playlists = RS-025) |
| FR-013 | contrôles et états de session | **partiel** (machine à états ; coordinateur audio = RS-013) |
| FR-014 | sauvegarde locale | **partiel** — la bibliothèque vit en mémoire (RS-033 pour la persistance) |
| FR-015 | streaming compatibles | **non démarré** (aucune source ne satisfait la garde) |
| FR-016 | accessibilité et localisation | **partiel** (labels VoiceOver, Dynamic Type ; audit à faire) |
| FR-017 | Now Playing / commandes système | **non démarré** (RS-027) |
| FR-018 | statistiques cadence/allure | **partiel** (agrégats de session en mémoire) |
| FR-019 | aucune capture micro | **fait** (aucune permission, aucun code audio d'entrée) |
| FR-020 | absence de réseau | **fait** (aucun appel réseau) |

## Critère ultime

Aucune promesse de streaming altéré : l'application n'adapte que de l'audio dont le droit
d'adaptation est établi, et l'interface dit toujours si le tempo est ajusté, borné,
maintenu ou indisponible.
