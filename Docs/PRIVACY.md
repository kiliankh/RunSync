# RunSync — Confidentialité

## Principes

1. **Minimisation** : on ne collecte que ce qui est nécessaire à la course en cours.
2. **Local-first** : aucune donnée ne quitte l'appareil à ce stade ; aucun backend, aucun
   compte, aucun analytics tiers.
3. **Transparence** : l'interface indique toujours si une donnée est bonne, dégradée ou
   indisponible, et si le tempo est réellement piloté.

## Ce qui est collecté (état actuel)

| Donnée | Usage | Conservation |
| --- | --- | --- |
| Cadence filtrée, qualité, décision tempo | affichage et diagnostic à l'écran | **en mémoire seulement** (aucune écriture disque) |
| Agrégats de session (durée, cadence moyenne, temps synchronisé) | résumé de fin de course | **en mémoire seulement** |
| Réglages (limite d'ajustement, source de cadence, guidage) | préférences | en mémoire (SwiftData = RS-033) |
| Fichiers audio **importés par l'utilisateur** | lecture pendant la course | copiés dans l'espace privé de l'application, supprimables depuis l'onglet Musique |

## Ce qui n'est **pas** collecté

- aucune position GPS brute (RS-012 décidera si une trace est réellement nécessaire — par
  défaut, seules des métriques agrégées seront conservées) ;
- aucune donnée de santé (HealthKit hors périmètre MVP) ;
- aucun contenu audio, aucune capture micro : **aucune autorisation microphone n'est
  déclarée**, et aucun contenu de streaming n'est capturé (FR-019) ;
- aucun identifiant publicitaire, aucun événement analytique, aucun crash reporting tiers.

## Permissions

| Permission | Demandée maintenant | Quand exactement |
| --- | --- | --- |
| Mouvement et condition physique (Core Motion) | **oui** | au démarrage d'une course utilisant le capteur, **jamais** au lancement de l'application (FR-002) |
| Localisation pendant l'utilisation | non (déclarée dans `project.yml`) | au démarrage d'une course avec GPS (RS-012) |
| Bluetooth | non | non nécessaire : l'audio passe par le système, aucun appairage par l'application |
| Microphone | **jamais** | aucune capture audio n'existe (FR-019) |

La lecture audio utilise la catégorie `AVAudioSession` `.playback` : elle indique au système
« je joue du son », elle ne donne accès à aucune donnée personnelle et n'enregistre rien.

Un refus doit laisser l'application utilisable : mode démonstration, cadence simulée,
sans audio (FR-002).

## Droits de l'utilisateur (planifiés)

- export CSV de l'historique et effacement complet des données locales → **RS-035**
  (annoncés comme indisponibles dans les réglages tant que ce n'est pas fait) ;
- suppression d'un fichier importé : il ne doit pas rester d'élément faussement jouable
  (RS-020, champ `isFileAvailable`).

## Journalisation

Les logs de diagnostic (RS-045) seront **opt-in** et ne contiendront ni chemin de fichier
privé, ni coordonnées, ni identifiant d'utilisateur, ni jeton. Les erreurs exposent un code
stable et un message utilisateur, jamais une donnée sensible.

## À faire avant soumission

- remplir les étiquettes « Confidentialité de l'app » d'App Store Connect à partir de ce
  document, en cohérence avec les permissions réellement déclarées ;
- rédiger la politique de confidentialité publique dès qu'une fonctionnalité réseau est
  ajoutée (aucune aujourd'hui).
