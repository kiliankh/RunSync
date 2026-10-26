#!/usr/bin/env python3
"""Génère la tonalité de test de RunSync — clics à 168 BPM.

Pourquoi ce fichier existe : pour vérifier la synchronisation sur un iPhone réel,
il faut une musique dont on connaît exactement le tempo. Le cahier des charges
prévoit un « audio de test libre de droits » (§03 E01) ; plutôt que d'en chercher
un, le projet le synthétise. Le signal est entièrement calculé : aucune banque de
sons, aucun échantillon tiers, aucun hasard. Le fichier produit est donc dédié au
domaine public (CC0) et peut être versionné sans question de droits.

Le résultat est volontairement un métronome audible : quand RunSync accélère la
musique à +5 %, on entend les clics accélérer, ce qui rend l'effet du time-stretch
vérifiable à l'oreille sans matériel de mesure.

Usage :
    python3 Tools/generate_test_tone.py

Sortie : RunSync/Resources/TestAudio/runsync-test-clicks-168bpm.wav
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
BPM = 168.0
DURATION_SECONDS = 30.0
AMPLITUDE = 0.9
OUTPUT_NAME = "runsync-test-clicks-168bpm.wav"

# Enveloppes : courtes, pour que le clic reste net et identifiable.
CLICK_DECAY_SECONDS = 0.012
CLICK_LENGTH_SECONDS = 0.06
CLICK_FREQUENCY_HZ = 1_100.0
CLICK_ACCENT_FREQUENCY_HZ = 1_600.0
ATTACK_SECONDS = 0.001

THUMP_DECAY_SECONDS = 0.09
THUMP_LENGTH_SECONDS = 0.18
THUMP_FREQUENCY_HZ = 70.0


def envelope(elapsed: float, decay: float, length: float) -> float:
    """Décroissance exponentielle avec attaque courte (pas de claquement à zéro)."""
    if elapsed < 0 or elapsed >= length:
        return 0.0
    attack = min(1.0, elapsed / ATTACK_SECONDS) if ATTACK_SECONDS > 0 else 1.0
    return attack * math.exp(-elapsed / decay)


def click(elapsed: float, accent: bool) -> float:
    frequency = CLICK_ACCENT_FREQUENCY_HZ if accent else CLICK_FREQUENCY_HZ
    gain = 1.0 if accent else 0.7
    shape = envelope(elapsed, CLICK_DECAY_SECONDS, CLICK_LENGTH_SECONDS)
    return gain * shape * math.sin(2 * math.pi * frequency * elapsed)


def thump(elapsed: float, accent: bool) -> float:
    gain = 0.55 if accent else 0.38
    shape = envelope(elapsed, THUMP_DECAY_SECONDS, THUMP_LENGTH_SECONDS)
    return gain * shape * math.sin(2 * math.pi * THUMP_FREQUENCY_HZ * elapsed)


def render() -> list[float]:
    total_samples = int(SAMPLE_RATE * DURATION_SECONDS)
    period = 60.0 / BPM
    samples = [0.0] * total_samples

    beat_index = 0
    while beat_index * period < DURATION_SECONDS:
        start = beat_index * period
        accent = beat_index % 4 == 0
        first_sample = int(start * SAMPLE_RATE)
        span = int(max(CLICK_LENGTH_SECONDS, THUMP_LENGTH_SECONDS) * SAMPLE_RATE) + 1
        for offset in range(span):
            index = first_sample + offset
            if index >= total_samples:
                break
            elapsed = (index / SAMPLE_RATE) - start
            samples[index] += click(elapsed, accent) + thump(elapsed, accent)
        beat_index += 1

    # Fondu de 10 ms aux extrémités : aucun clic de bord dans la boucle.
    fade_samples = int(0.01 * SAMPLE_RATE)
    for index in range(min(fade_samples, total_samples)):
        gain = index / fade_samples
        samples[index] *= gain
        samples[total_samples - 1 - index] *= gain

    peak = max(abs(value) for value in samples) or 1.0
    scale = AMPLITUDE / peak
    return [value * scale for value in samples]


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for value in samples:
            clipped = max(-1.0, min(1.0, value))
            frames += struct.pack("<h", int(round(clipped * 32_767)))
        handle.writeframes(bytes(frames))


def main() -> None:
    samples = render()
    output = Path(__file__).resolve().parent.parent / "RunSync" / "Resources" / "TestAudio" / OUTPUT_NAME
    write_wav(output, samples)
    beats = int(DURATION_SECONDS / (60.0 / BPM))
    print(f"BPM               : {BPM:g}")
    print(f"Durée             : {DURATION_SECONDS:g} s")
    print(f"Battements        : {beats}")
    print(f"Échantillons      : {len(samples)} ({len(samples) / SAMPLE_RATE:.2f} s à {SAMPLE_RATE} Hz)")
    print(f"Taille            : {output.stat().st_size / 1_048_576:.2f} Mio")
    print(f"Écrit             : {output}")


if __name__ == "__main__":
    main()
