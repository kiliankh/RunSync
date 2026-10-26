# RunSync — Moteur audio

**État : implémenté (RS-021), jamais exécuté ici.** Le code est écrit
(`RunSync/Infrastructure/Audio/AudioEnginePlayback.swift`) et sa logique de contrôle est
**réellement testée** ; le moteur lui-même n'a **jamais été compilé ni écouté** : aucun macOS,
donc aucun `AVFAudio`. Tout ce qui suit décrit une conception exécutable, pas une qualité
mesurée.

## Graphe audio

```
AVAudioEngine
 ├─ AVAudioPlayerNode      (fichiers locaux importés dans la sandbox)
 ├─ AVAudioUnitTimePitch   (`rate` : vitesse sans transposition ; `pitch` reste à 0)
 └─ mainMixerNode → sortie
```

- **`AVAudioUnitTimePitch` et non `AVAudioUnitVarispeed`** : le second modifie la hauteur, ce
  qui contredit la promesse produit (FR-009). `rate` est borné à ±5 % (ou ±3 %) par la
  politique, très loin des bornes matérielles (1/32 à 32).
- Le format de connexion est celui du fichier (`file.processingFormat`) ; la reconnexion se
  fait **moteur arrêté** (changer un format sur un graphe en marche produit des artefacts).
- Planification par segment (`scheduleSegment`) avec un **jeton de génération** : la fin d'un
  segment abandonné (arrêt, déplacement, changement de morceau) n'est jamais confondue avec une
  fin naturelle de morceau.
- Aucun travail lourd dans le thread audio : la seule écriture est la propriété `rate` de
  l'unité de temps, à 4 Hz au maximum.

## Boucle de contrôle du tempo

| Paramètre | Valeur initiale (à mesurer) | Où |
| --- | --- | --- |
| Fréquence de mise à jour du paramètre audio | ≤ 4 Hz (250 ms) | `PlaybackRateRamp.minimumCommandInterval` |
| Dérivée maximale du rate | 0,01 par seconde | `PlaybackRateRamp.maximumSlewPerSecond` |
| Pas maximal d'une écriture | 1 point de % (borne le rattrapage après inactivité) | `maximumEvaluationStepSeconds` |
| Limite d'ajustement | ±5 % (option ±3 %) | `TempoMatchingPolicy` |
| Hystérésis de consigne | 1,5 SPM confirmés sur 2 s | `CadenceFilterConfiguration` |
| Maintien si cadence perdue | 5 s puis retour doux en 10 s | `FollowTimingConfiguration` |

Séparation des responsabilités, volontaire et testable sans iPhone :

```
CadenceSample → CadenceFilter → FollowController / PaceController → TempoDecision.appliedRate
                                                                          ↓ consigne
                                                              PlaybackRateRamp  (noyau, testé)
                                                                          ↓ 4 Hz max
                                                          AVAudioUnitTimePitch.rate (iOS)
```

`PlaybackRateRamp` (`RunSync/Domain/Tempo/PlaybackRateRamp.swift`) est la frontière : il décide
**quand** et **de combien** le paramètre audio bouge réellement. C'est là que se joue la
défense contre la marche audible, et c'est du Swift pur — donc couvert par 16 tests
(`PlaybackRateRampTests`), dont les deux cas critiques :

- une consigne qui saute de 1,0 à 1,05 ne produit **jamais** une écriture unique de 5 points ;
- après une longue inactivité, aucun rattrapage brutal (le temps pris en compte est borné).

## Garde de conformité

`TempoAdjustmentGate` est le passage obligé de **toute** demande de vitesse, y compris depuis
le moteur audio : `AudioEnginePlayback.setRate` commence par `gate.validatedRate(...)`, et
n'écrit dans le graphe qu'après. Elle vérifie :

1. `provider.isTempoAdjustmentPermitted` (capacité technique **et** conformité `confirmed`) ;
2. `track.canAlterTempo` et `track.isAdaptationRightsAttested` (légitimité distincte de la
   faisabilité) ;
3. l'existence réelle du fichier (`isFileAvailable`) ;
4. la présence d'un BPM exploitable ;
5. puis borne la valeur dans `[1 − max, 1 + max]`.

Un fichier local non attesté **est lisible** (aucune altération), mais son tempo n'est jamais
ajusté : l'écran affiche « Tempo non ajustable » et la raison exacte.

## Session audio, interruptions, écran verrouillé

- Catégorie `AVAudioSession` = `.playback`, mode `.default`, activée seulement au moment de
  jouer ; désactivée avec `.notifyOthersOnDeactivation` en fin de session pour rendre la main
  aux autres applications. **Aucune permission micro** n'est demandée (FR-019).
- `interruptionNotification` : le moteur **met en pause immédiatement** (exigence système) et
  rapporte l'événement. La reprise n'est jamais automatique côté moteur : la session décide,
  et seulement si le système la recommande.
- `routeChangeNotification` avec `oldDeviceUnavailable` (écouteurs débranchés, casque Bluetooth
  perdu) : pause, jamais de bascule surprise sur le haut-parleur.
- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` : le moteur rapporte les commandes
  système (play, pause, suivant) sous forme d'événements ; il ne change jamais l'état de la
  session lui-même. C'est ce qui empêche l'écran d'afficher « en cours » alors que l'audio
  s'est arrêté (état fantôme, §07).

## Ce qui reste à faire, et à mesurer

1. **RS-013** — `SessionCoordinator` (acteur) : propriétaire unique de la session, transitions
   idempotentes de bout en bout, au-delà de la machine à états actuelle.
2. **RS-027** — vérification réelle de l'arrière-plan et de l'écran verrouillé sur iPhone
   (le mode `audio` est déjà déclaré dans `project.yml`, il n'a jamais été exercé).
3. **RS-025** — enchaînement « sans coupure » : aujourd'hui le morceau suivant démarre à la fin
   du précédent ; aucun préchargement, donc aucune garantie d'enchaînement parfait.
4. **Mesures obligatoires avant toute affirmation de qualité** : écoute A/B à 0,95 / 1,0 / 1,05
   sur iPhone avec le morceau de test intégré, détection d'artefacts, Time Profiler, Energy Log
   sur 30 / 60 / 90 minutes. **Aucune de ces mesures n'a été réalisée.**

## Comment entendre la synchronisation sans matériel de mesure

Le morceau de test intégré (`RunSync/Resources/TestAudio/`, clics à 168 BPM, domaine public)
existe précisément pour cela : à +5 %, les clics sont **17 battements par minute plus rapides**,
ce qui s'entend sans instrument. La procédure est décrite dans `Docs/RUN_ON_IPHONE.md` §8.2.
