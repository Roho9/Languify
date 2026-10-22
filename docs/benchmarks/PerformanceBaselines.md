# Performance baselines

Current measured baselines, the run each number comes from, and what has not been measured. Every number on this page is **Measured (Mac)**: Apple M5 Pro, 48 GB, macOS 27, release builds, at commit `f320a5e` or the working tree that became it. Speech inputs are **synthetic** (macOS Tamil voice "Vani", one speaker) unless stated. Nothing here is an iPhone measurement.

Raw results: `Results/Raw/<category>/<runID>.json`. Dashboard: `Results/Reports/dashboard.html` (`python3 Benchmarks/scripts/report.py`). Regression thresholds: `Benchmarks/regression-thresholds.json`, enforced by `Benchmarks/scripts/check_regressions.py` and CI.

## Live Rewind buffer

| Metric | Baseline (ddebcc0) | Current | Source |
|---|---|---|---|
| Append, 100 ms chunk, P50 | 6.5 µs | 0.17 µs | buffer-20261022T184317Z, 184331Z, 184345Z |
| Extract 120 s window (lock held), P50 | 8.21 ms | 0.15 ms | same |
| Peak memory during 120 s extraction | 14.7 MB | 11.1 MB | memory-20261022T184305Z |
| Steady memory, 120 s window | 3.8 MB | 3.8 MB | same |
| Quantisation SNR | 88.4 dB | 94.4 dB | same buffer runs |
| Sample-exact boundary cases | 480/480 | 480/480 per run | same |
| 60 min session growth after first fill | | within one 16 KB page | same |

## Tamil recognition (Apple SpeechTranscriber, ta-IN, on device)

Run `asr-20261022T184830Z`, 56 sentences × 10 conditions, Wilson or sentence-level bootstrap 95% CIs.

| Condition | Target-word hit | CER |
|---|---|---|
| Clean, normal rate | 91.1% (51/56) [80.7, 96.1] | 0.108 [0.075, 0.148] |
| Pink noise +10 dB / 0 dB / -5 dB | 78.6% / 48.2% / 8.9% | |
| Babble +10 dB / 0 dB | 82.1% / 7.1% | |
| Overlapping second speaker | 73.2% | |

- English words in code-switched speech: 69.2% recall from the Tamil pass, 76.9% with the parallel English pass (39 words).
- Confidence is informative: AUROC 0.78 for predicting a missed target; miss rate 39.9% when minimum confidence < 0.5 vs 6.8% at ≥ 0.5.
- Recognition latency P50 by rewind window: 15 s 473 ms, 30 s 543 ms, 60 s 991 ms, 120 s 1,936 ms. About 430 ms is a fixed finalisation cost inside Apple's model.
- Parallel Tamil + English recognisers: 60 ms (11.1%) faster than sequential, CI 56 to 64 ms.

## Explanation pipeline (Gemma 3 27B via Ollama, local)

Run `context-ollama-f320a5e-retrieval_on-20261022T211117Z`, 98 cases on real recogniser transcripts of synthetic speech.

| Metric | Result |
|---|---|
| Schema and semantic valid output | 98/98 |
| Target word identified (rough spelling) | 53/56 (94.6%) [85.4, 98.2] |
| Clarifies when two words match | 6/8 (answered without a model call) |
| Unnecessary clarification on clear lookups | 0/56 |
| Abstains when the word is absent | 8/8, 0 confident wrong |
| Suggested replies for "how do I respond" | 9/10 |
| Native script valid | 80/84 (95.2%) |
| Latency P50 / P95, all cases | 20.6 s / 28.9 s |
| Cold start (model not loaded) | 24.3 s mean, 3.2 s of it model load |

Sentence localisation ("what did they say before X") is weak: 3/16 by the strict automatic metric. Explanation quality is not auto-scored; see the human rubric.

## Backend

| Metric | Result | Source |
|---|---|---|
| Mock-AI capacity, 200 concurrent | 631 req/s, 100% success, server CPU 36%, RSS ≤ 154 MB | load-mock-20261022T213437Z |
| Real model, 8 concurrent, limiter off | 4/16 succeed, 12 time out after 55 s | load-real-20261022T214010Z |
| Real model, 8 concurrent, limiter on | 3/16 succeed (max 35.7 s), 13 rejected in 6 ms (P50) with 503 | load-real-20261022T214434Z |

## Reliability and privacy

- Privacy: 21/21 checks (16 static, 5 runtime) pass, `privacy-20261022T214657Z`.
- App unit tests on the iOS 26 simulator: 29/29, including 7 fault-injection tests (competing requests, timeout, 429, 503, truncated JSON, recovery, rapid requests). LanguifyKit: 69 tests. Backend: 38 tests.

## Not measured

| Metric | Why |
|---|---|
| iPhone CPU, memory, energy, thermal; Siri and AirPods end-to-end latency | No device runs yet. Protocol: `DeviceTestProtocol.md` |
| Malayalam recognition | No Malayalam voice; no consented recordings. The simulator also reports ml-IN unsupported |
| Real speakers, accents, distance, AirPods microphone | Needs consented human recordings |
| Explanation quality as judged by bilingual reviewers | Review sheets exported to `Results/Reviews/`, not yet scored |
| Claude provider latency, quality and cost | No API key configured |
| Learning outcomes | Needs a consented study (`LearningStudyProtocol.md`) |
| Multi-instance or networked backend capacity | Loopback, single machine only |

## Next optimisation priorities

Ordered by expected user impact per unit of effort.

1. **Run the device protocol on an iPhone with AirPods.** Every latency budget above is Mac-only; on-device recognition and the Siri round trip are the largest unknowns.
2. **Explanation latency (20.6 s P50 locally).** Output tokens dominate. Next steps: stream `spoken_summary` first so speech can start before the full JSON finishes; test a smaller model (Gemma 3 12B) against the same 98 cases; measure Claude once a key exists.
3. **Transcribe only the recent part of the window for single-word questions.** Recognition grows from 473 ms (15 s) to 1,936 ms (120 s). Unlike the rejected silence trimmer (Experiment D), this does not splice audio.
4. **Retrieval misses on long inflected forms** (2 of 3 remaining misses). Try morphological suffix stripping before skeleton matching; re-run the dry run and the A/B.
5. **Meaning errors on correctly found words** (pasikkuthu). Add a small curated lexicon check for high-frequency words; flag disagreement as uncertain instead of answering.
6. **Sentence localisation (3/16).** Pass segment timestamps and the question's anchor explicitly; evaluate with the segment-picking metric.
7. **Human quality review** of the exported sheets with the rubric, so quality is measured, not assumed.
