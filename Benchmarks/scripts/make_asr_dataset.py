#!/usr/bin/env python3 -I
"""Synthesizes the Tamil pilot ASR dataset and its stress-test variants.

Every clip is SYNTHETIC: macOS text-to-speech (voice "Vani", the only Tamil
voice on the machine), so there is exactly one speaker. Noise conditions are
ARTIFICIALLY MIXED at a controlled signal-to-noise ratio. Results from this
dataset must never be presented as real-speaker accuracy.

Usage: python3 -I Benchmarks/scripts/make_asr_dataset.py
Writes audio to BenchmarkData/Audio/ (git-ignored, regenerable) and the
manifest to BenchmarkData/Manifests/asr_tamil_synthetic_v1.json.
"""
import array
import json
import math
import random
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANNOTATIONS = ROOT / "BenchmarkData/Annotations/tamil_pilot_v1.json"
AUDIO = ROOT / "BenchmarkData/Audio/asr_tamil_synthetic_v1"
MANIFEST = ROOT / "BenchmarkData/Manifests/asr_tamil_synthetic_v1.json"
RATE = 16_000
VOICE = "Vani"
RATES_WPM = {"slow": 130, "normal": 185, "fast": 250}
PINK_SNRS = [20, 10, 0, -5]
BABBLE_SNRS = [10, 0]
BABBLE_VOICES = ["Aman", "Rishi", "Albert", "Fred", "Kathy"]
BABBLE_TEXT = [
    "Did you see the score last night? I think we should leave early tomorrow.",
    "The traffic on the highway was terrible this morning, it took an hour.",
    "Can you pass the rice please, and some more of the curry too.",
    "My phone battery is almost dead, does anyone have a charger here.",
    "We should plan the trip before the tickets get too expensive.",
]


def say(text: str, voice: str, wpm: int, out: Path) -> None:
    subprocess.run(
        ["say", "-v", voice, "-r", str(wpm), "-o", str(out), "--file-format=WAVE", f"--data-format=LEI16@{RATE}", text],
        check=True,
    )


def read(path: Path) -> array.array:
    with wave.open(str(path)) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
        return data


def write(path: Path, samples) -> None:
    clipped = array.array("h", (max(-32768, min(32767, int(round(s)))) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(clipped.tobytes())


def rms(samples) -> float:
    return math.sqrt(sum(s * s for s in samples) / max(1, len(samples)))


def active_rms(samples) -> float:
    """RMS over 20 ms frames louder than -40 dB of peak, so leading and
    trailing silence does not dilute the speech level used for SNR."""
    frame = RATE // 50
    peak = max(1, max(abs(s) for s in samples))
    frames = [samples[i:i + frame] for i in range(0, len(samples), frame)]
    active = [f for f in frames if rms(f) > peak * 0.01]
    flat = [s for f in active for s in f] or list(samples)
    return rms(flat)


def pink_noise(n: int, rng: random.Random):
    # Paul Kellet's economy pink filter.
    b0 = b1 = b2 = 0.0
    out = []
    for _ in range(n):
        white = rng.uniform(-1, 1)
        b0 = 0.99765 * b0 + white * 0.0990460
        b1 = 0.96300 * b1 + white * 0.2965164
        b2 = 0.57000 * b2 + white * 1.0526913
        out.append(b0 + b1 + b2 + white * 0.1848)
    return out


def mix(speech, noise, snr_db: float):
    speech_level = active_rms(speech)
    noise = list(noise[: len(speech)]) + [0.0] * max(0, len(speech) - len(noise))
    noise_level = rms(noise) or 1.0
    gain = speech_level / (noise_level * 10 ** (snr_db / 20))
    mixed = [s + gain * x for s, x in zip(speech, noise)]
    peak = max(abs(m) for m in mixed)
    if peak > 32000:  # avoid clipping; scales speech and noise together so SNR is unchanged
        mixed = [m * 32000 / peak for m in mixed]
    return mixed


def main() -> None:
    AUDIO.mkdir(parents=True, exist_ok=True)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    doc = json.loads(ANNOTATIONS.read_text())
    sentences = doc["sentences"]
    rng = random.Random(20261022)

    # Babble bed: several English voices summed, looped as needed.
    babble = None
    for i, (voice, text) in enumerate(zip(BABBLE_VOICES, BABBLE_TEXT)):
        tmp = AUDIO / f"_babble_{i}.wav"
        if not tmp.exists():
            say(text, voice, 190, tmp)
        part = list(read(tmp))
        babble = part if babble is None else [a + b for a, b in zip(babble + [0] * max(0, len(part) - len(babble)), part + [0] * max(0, len(babble) - len(part)))]

    clips = []
    for idx, s in enumerate(sentences):
        base = {}
        for label, wpm in RATES_WPM.items():
            path = AUDIO / f"{s['id']}_{label}.wav"
            if not path.exists():
                say(s["text"], VOICE, wpm, path)
            base[label] = path
            clips.append(dict(clip_id=f"{s['id']}/{label}", sentence_id=s["id"], condition="clean", rate=label, snr_db=None, noise=None, path=str(path.relative_to(ROOT))))
        speech = list(read(base["normal"]))
        for snr in PINK_SNRS:
            path = AUDIO / f"{s['id']}_pink{snr:+d}.wav"
            if not path.exists():
                write(path, mix(speech, pink_noise(len(speech), rng), snr))
            clips.append(dict(clip_id=f"{s['id']}/pink{snr:+d}", sentence_id=s["id"], condition="pink_noise", rate="normal", snr_db=snr, noise="pink (synthetic)", path=str(path.relative_to(ROOT))))
        for snr in BABBLE_SNRS:
            path = AUDIO / f"{s['id']}_babble{snr:+d}.wav"
            if not path.exists():
                offset = rng.randrange(0, max(1, len(babble) - len(speech)))
                loop = (babble * (1 + len(speech) // len(babble) + 1))[offset: offset + len(speech)]
                write(path, mix(speech, loop, snr))
            clips.append(dict(clip_id=f"{s['id']}/babble{snr:+d}", sentence_id=s["id"], condition="english_babble", rate="normal", snr_db=snr, noise="5 English TTS voices (synthetic)", path=str(path.relative_to(ROOT))))
        # Competing Tamil speaker: a different sentence, same voice, 6 dB quieter.
        other = sentences[(idx + 7) % len(sentences)]
        path = AUDIO / f"{s['id']}_overlap.wav"
        if not path.exists():
            competing = list(read(base_path := AUDIO / f"{other['id']}_normal.wav")) if (AUDIO / f"{other['id']}_normal.wav").exists() else None
            if competing is None:
                say(other["text"], VOICE, RATES_WPM["normal"], AUDIO / f"{other['id']}_normal.wav")
                competing = list(read(AUDIO / f"{other['id']}_normal.wav"))
            write(path, mix(speech, competing, 6))
        clips.append(dict(clip_id=f"{s['id']}/overlap", sentence_id=s["id"], condition="overlapping_speaker", rate="normal", snr_db=6, noise=f"competing Tamil sentence {other['id']} (same synthetic voice)", path=str(path.relative_to(ROOT))))
        print(f"\r{idx + 1}/{len(sentences)} sentences", end="", file=sys.stderr)

    manifest = dict(
        dataset="asr_tamil_synthetic_v1",
        annotations=str(ANNOTATIONS.relative_to(ROOT)),
        source_label="SYNTHETIC: macOS TTS voice Vani (single speaker); noise artificially mixed",
        sample_rate=RATE,
        voice=VOICE,
        rates_wpm=RATES_WPM,
        clips=clips,
    )
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    print(f"\n{len(clips)} clips -> {MANIFEST.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
