# RunSync — Conformité des sources musicales

> **Avertissement de statut.** L'agent qui a produit cette phase **n'a vérifié aucune
> condition de fournisseur tiers** : il n'a consulté aucune page officielle et ne dispose
> d'aucun accès aux portails développeurs. Le contenu ci-dessous reprend l'état décrit par
> le cahier des charges §02 et doit être **recontrôlé à la date d'implémentation**, sur les
> sources officielles listées, par une personne habilitée.
>
> Par construction logicielle, aucune fonctionnalité d'adaptation de tempo n'est active
> pour une source non confirmée (`MusicProviderCapabilities.isTempoAdjustmentPermitted`).

## Principe non négociable

Métadonnées, commandes de lecture et **accès au flux PCM** sont trois capacités distinctes.
Disposer de l'une ne donne jamais le droit d'altérer un flux. La capacité technique
déclarée par un adaptateur ne suffit pas : il faut en plus un statut de conformité
`confirmed`, daté et sourcé.

## Matrice (à recontrôler)

| Source | Lecture | PCM | Tempo ajustable | Statut revue | Sources à consulter |
| --- | --- | --- | --- | --- | --- |
| **Fichiers locaux importés** | oui | oui | **oui** (chemin MVP) | `confirmed` (décision produit interne) | — |
| **Apple Music (MusicKit)** | oui | non | non | `underReview` | https://developer.apple.com/documentation/musickit |
| **Spotify** | oui | non | non | `underReview` | https://developer.spotify.com/policy · https://developer.spotify.com/documentation/ios/getting-started |
| **YouTube / YouTube Music** | non | non | non | `prohibited` | https://developers.google.com/youtube/terms/developer-policies |
| **SoundCloud / autres** | non | non | non | `underReview` | conditions d'API et licences de diffusion à vérifier |

Références techniques à recontrôler également :

- `AVAudioUnitTimePitch` : https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch
- `CMPedometerData.currentCadence` : https://developer.apple.com/documentation/coremotion/cmpedometerdata/currentcadence

## Décisions

| ID | Décision | Motif |
| --- | --- | --- |
| D-P1 | **GO** sur les fichiers locaux importés avec attestation de droits | seul chemin où le droit d'adapter est établi ; hors ligne (FR-020) |
| D-P2 | **NO-GO** sur toute altération audio d'une source de streaming | absence d'accès PCM ; altération du contenu proscrite |
| D-P3 | **NO-GO** YouTube / YouTube Music dans l'application | règles d'API : isolation/modification audio interdite ; aucun adaptateur caché |
| D-P4 | **POC isolé uniquement** pour MusicKit (`playbackRate`) | `playbackRate` n'équivaut pas à un accès PCM ni à un time-stretch conforme à la promesse |
| D-P5 | **Report** sur SoundCloud et autres | droits, restrictions d'API et disponibilité non vérifiés |

## Interdits absolus (implémentés comme garde-fous)

- pas de scraping de flux, pas d'extraction YouTube, pas de contournement DRM, pas
  d'interception de flux, pas de réencodage de musique protégée sans permission ;
- pas de bouton « adapter le tempo » pour une source non autorisée : `TempoAdjustmentGate`
  refuse par erreur typée (`TempoAdjustmentError.providerNotPermitted`) ;
- pas de mélange de flux de fournisseurs différents.

## Procédure de passage d'une source à `confirmed`

1. Lire les conditions et la documentation officielles **à la date du jour**.
2. Consigner ici : date, URLs exactes, extraits pertinents, restrictions, quotas,
   compatibilité App Store.
3. Vérifier techniquement l'accès au flux nécessaire **sur appareil réel**.
4. Faire valider la décision GO/NO-GO par le commanditaire avant toute publication.
5. Écrire les tests qui prouvent la garde (le refus doit être testé, pas seulement espéré).
