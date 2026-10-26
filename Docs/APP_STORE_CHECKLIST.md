# RunSync — Checklist App Store

Aucun élément ci-dessous n'est validé à ce jour : la phase 1 est un prototype local sans
moteur audio, sans GPS et sans distribution. Cette liste sert de garde-fou avant toute
soumission (RS-044).

## Produit et marque

- [ ] Nom commercial vérifié (marque, domaine, disponibilité App Store)
- [ ] Capture d'écran et description conformes à ce que l'application fait réellement
- [ ] Aucune promesse d'altération de contenu de streaming dans le texte de la fiche

## Conformité technique

- [ ] Aucune source tierce non confirmée activée (`Docs/PROVIDER_COMPLIANCE.md` à jour, daté)
- [ ] Aucun scraper, aucun contournement DRM, aucune extraction de flux dans le binaire
- [ ] `UIBackgroundModes: audio` justifié par une lecture audio continue réelle (RS-027)
- [ ] Aucune permission microphone déclarée (FR-019)
- [ ] Autorisations mouvement/localisation accompagnées d'un texte d'usage explicite et
      d'un comportement de repli en cas de refus
- [ ] Fonctionnement correct sans réseau (FR-020)
- [ ] Aucun secret, jeton ou clé dans le dépôt, les logs ou les captures

## Confidentialité

- [ ] Étiquettes « Confidentialité de l'app » remplies et cohérentes avec `Docs/PRIVACY.md`
- [ ] Politique de confidentialité publiée si une fonctionnalité réseau est ajoutée
- [ ] Export et suppression des données locales fonctionnels (RS-035)
- [ ] Logs de diagnostic opt-in et sans donnée personnelle (RS-045)

## Qualité avant bêta

- [ ] Tests unitaires du noyau exécutés en vert dans l'intégration continue (macOS et Linux)
- [ ] Compilation et tests `xcodebuild` verts sur le simulateur cible
- [ ] Tests sur iPhone physique : écran verrouillé, arrière-plan, écouteurs filaires,
      Bluetooth, appel entrant, Siri, changement de route
- [ ] Mesures de consommation (30/60/90 min) consignées avec un seuil défini après baseline
- [ ] Aucune coupure audio perceptible sur transitions normales (écoute A/B)
- [ ] Audit VoiceOver, Dynamic Type, contraste, zones tactiles ≥ 60 pt

## Processus

- [ ] Version de test (`TestFlight`) proposée à un panel restreint
- [ ] Retour de bêta traité et consigné dans `CHANGELOG.md`
- [ ] Décisions produit en attente tranchées : prix, pays, HealthKit, analytics,
      intégrations tierces réelles
