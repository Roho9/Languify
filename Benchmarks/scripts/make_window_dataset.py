#!/usr/bin/env python3 -I
"""Builds rewind-window clips: several synthetic Tamil sentences separated by
pauses of low-level room tone, the way a Live Rewind buffer looks after a
stretch of conversation. The question always targets the LAST sentence.

SYNTHETIC: single TTS voice (Vani), synthetic pink room tone at about
-50 dBFS. Requires make_asr_dataset.py to have run first.

Usage: python3 -I Benchmarks/scripts/make_window_dataset.py
"""
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import make_asr_dataset as base  # noqa: E402

ROOT = base.ROOT
OUT = ROOT / "BenchmarkData/Audio/asr_windows_v1"
MANIFEST = ROOT / "BenchmarkData/Manifests/asr_windows_v1.json"
DURATIONS = [15, 30, 60, 120]
PER_DURATION = 10


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sentences = json.loads(base.ANNOTATIONS.read_text())["sentences"]
    rng = random.Random(4242)
    room_level = 32767 * 10 ** (-50 / 20)
    clips = []
    for duration in DURATIONS:
        total = duration * base.RATE
        for k in range(PER_DURATION):
            order = rng.sample(sentences, len(sentences))
            last = order[0]
            parts, used = [], []
            # Fill backwards so the target sentence ends near the window end.
            length = 0
            for s in order:
                speech = list(base.read(base.AUDIO / f"{s['id']}_normal.wav"))
                gap = int(rng.uniform(0.8, 3.5) * base.RATE)
                if length + len(speech) + gap > total and used:
                    break
                parts.insert(0, (speech, gap))
                used.insert(0, s["id"])
                length += len(speech) + gap
            samples = [0.0] * (total - length)
            speech_frames = 0
            for speech, gap in parts:
                samples.extend([0.0] * gap)
                samples.extend(speech)
                speech_frames += len(speech)
            noise = base.pink_noise(len(samples), rng)
            scale = room_level / (base.rms(noise) or 1)
            samples = [x + scale * n for x, n in zip(samples, noise)]
            path = OUT / f"w{duration:03d}_{k:02d}.wav"
            base.write(path, samples)
            clips.append(dict(
                clip_id=f"window{duration}/{k:02d}", sentence_id=last["id"], condition=f"window_{duration}s", rate="normal", snr_db=None,
                path=str(path.relative_to(ROOT)), sentences=used, speech_seconds=round(speech_frames / base.RATE, 2), window_seconds=duration,
            ))
    MANIFEST.write_text(json.dumps(dict(
        dataset="asr_windows_v1",
        source_label="SYNTHETIC: Tamil TTS sentences (voice Vani) with synthetic room tone at -50 dBFS; target is the last sentence",
        clips=clips,
    ), ensure_ascii=False, indent=1))
    print(f"{len(clips)} windows -> {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
