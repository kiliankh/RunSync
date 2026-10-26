# Tonalité de test (audio fourni avec l'application)

`runsync-test-clicks-168bpm.wav` — 30 s, 84 battements, **168 BPM exactement**,
mono 44,1 kHz / 16 bits, 2,5 Mio.

## Pourquoi ce fichier existe

Pour vérifier la synchronisation sur un iPhone réel, il faut une musique dont le
tempo est connu **au battement près**. Le cahier des charges prévoit un « audio de
test libre de droits » (§03 E01) ; plutôt que d'en chercher un, le projet le
synthétise. Le signal est entièrement calculé : aucune banque de sons, aucun
échantillon tiers, aucun hasard.

Le résultat est un métronome volontairement audible : quand RunSync accélère la
musique de 5 %, on **entend** les clics accélérer. L'effet du time-stretch devient
donc vérifiable à l'oreille, sans instrument de mesure.

## Droits

Œuvre produite par le projet lui-même, dédiée au domaine public (CC0). Contrairement
à un morceau importé par l'utilisateur, aucun tiers n'y détient de droits : c'est
pourquoi l'application l'ajoute directement comme morceau **tempo-ajustable**, sans
demander d'attestation. Le fichier est versionné par exception explicite dans
`.gitignore` ; tout autre fichier audio reste exclu du dépôt.

## Régénérer

```bash
python3 Tools/generate_test_tone.py
```

Le script est déterministe : relancer la commande doit reproduire un fichier
identique au bit près. Vérification rapide du tempo après génération :

```bash
python3 - <<'PY'
import wave, struct, statistics
with wave.open("RunSync/Resources/TestAudio/runsync-test-clicks-168bpm.wav", "rb") as w:
    n, sr = w.getnframes(), w.getframerate()
    data = struct.unpack("<%dh" % n, w.readframes(n))
peak = max(abs(v) for v in data)
onsets, last = [], -10**9
for i in range(1, len(data)):
    if abs(data[i]) >= 0.6 * peak and abs(data[i]) > abs(data[i-1]) and i - last > sr // 10:
        onsets.append(i); last = i
print("BPM mesuré :", round(60 / statistics.median(
    [(b - a) / sr for a, b in zip(onsets, onsets[1:])]), 4))
PY
```

Attendu : `168.0` (la mesure ci-dessus donne 168.0000 sur 84 attaques).

## Utilisation dans l'application

Onglet **Musique** → *Ajouter le morceau de test intégré*. Le fichier est copié
dans la sandbox privée exactement comme un import utilisateur, puis son BPM (168)
est renseigné. Il devient alors sélectionnable pour une course, et son tempo est
ajustable.
