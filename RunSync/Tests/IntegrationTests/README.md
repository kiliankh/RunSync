# Tests d'intégration

Répertoire réservé aux tests qui nécessitent du matériel ou des frameworks Apple :
`AVAudioEngine` sur appareil, Core Motion, Core Location, interruptions audio, écran
verrouillé, Bluetooth (voir `Docs/TEST_PLAN.md`, section « Tests à exécuter sur appareil »).

Ils ne sont pas encore écrits, et **rien ne peut y être exécuté dans cet environnement** : les
adaptateurs qu'ils exercent existent désormais (RS-010 cadence Core Motion, RS-021 moteur audio,
RS-020 import, RS-027 arrière-plan/écran verrouillé) mais n'ont jamais été compilés, faute de
macOS. La recette manuelle correspondante est décrite pas à pas dans `Docs/RUN_ON_IPHONE.md` §8.
Aucun fichier ici ne doit simuler un succès.
