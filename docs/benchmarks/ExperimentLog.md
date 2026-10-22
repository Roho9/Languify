# Experiment log

Each experiment: hypothesis, baseline, change, configuration, result, regressions, uncertainty, decision. Baselines are preserved (frozen copies or git revisions), never overwritten. All results are **Measured (Mac)** unless stated.

---

## A. Live Rewind buffer: vDSP block copies instead of per-sample loops (ADOPTED)

**Hypothesis.** The original ring buffer converted, clamped and stored one sample at a time with a modulo per sample, and built two intermediate arrays on extraction. Extraction runs under the same lock the audio tap thread needs, so a slow extraction stalls capture. Block conversion with Accelerate should cut both append cost and lock hold time without changing behaviour.

**Baseline.** `BaselineV1Store` in `Benchmarks/Sources/LanguifyBench/BufferImplementations.swift`, a frozen copy of LanguifyKit's buffer at commit `ddebcc0`.

**Change.** `RollingAudioBuffer` now scales and clips with `vDSP_vsmul`/`vDSP_vclip`, converts with `vDSP_vfixr16` (round to nearest instead of truncation) into at most two contiguous ring segments, and extracts with `vDSP_vflt16` + `vDSP_vsdiv` directly into the output array. Conversion scratch is preallocated, so steady-state appends allocate nothing. Storage is still Int16.

**Configuration.** Release build, Apple M5 Pro, macOS 27; 3,000 appends and 100 extractions per configuration; three separate process runs (`buffer-20261022T184317Z`, `…184331Z`, `…184345Z`); memory from `memory-20261022T184305Z` (fresh process per measurement, 3 repetitions). Runs were taken on the working tree that became commit `3497d18`.

**Result (100 ms chunks, median per run, range across 3 runs).**

| Window | Append, original | Append, optimized | Extraction (lock held), original | Extraction, optimized |
|---|---|---|---|---|
| 30 s | 6.50 to 6.54 µs | 0.17 to 0.21 µs | 2.05 ms | 0.049 to 0.051 ms |
| 60 s | 6.54 to 6.58 µs | 0.17 µs | 4.10 to 4.11 ms | 0.077 to 0.079 ms |
| 120 s | 6.46 to 6.50 µs | 0.17 µs | 8.21 ms | 0.146 to 0.149 ms |

- Append: **97% less time** per chunk (6.5 µs → 0.17 µs). Timer resolution is about 42 ns, so the optimized figure is within a few ticks.
- Extraction of a full 120 s window: **98.2% less time under the lock** (8.21 ms → 0.15 ms).
- Peak memory during a 120 s extraction: **14.7 MB → 11.1 MB (24.5% lower)**, because the intermediate Int16 copy is gone. Steady-state memory unchanged (3.8 MB at 120 s; Float32 storage would be 7.3 MB, a naive append-and-trim array 15.4 MB).
- Quantisation: max round-trip error halved (3.05e-5 → 1.53e-5), SNR 88.4 → 94.4 dB.

**Correctness.** 480/480 sample-exact boundary cases pass for both implementations in every run. 60-minute time-compressed sessions stay bounded (footprint change within one 16 KB page after the first fill) for 30, 60 and 120 s windows. New regression tests: sample-exact wrap-around for chunk sizes 1 to 40,000, rounding to nearest, half-step error bound, oversized chunks, out-of-range `endingAt`.

**Uncertainty.** Run-to-run spread is under 3%; differences are 30x to 55x, far outside it. Absolute numbers are for an M5 Pro; an iPhone will be slower in absolute terms, the ratio should hold but is **not measured on device**.

**Decision.** Adopted (commit `3497d18`).

---

## B. Recogniser choice (NOT RUN)

Only Apple's on-device `SpeechTranscriber` supports Tamil and Malayalam on this platform (legacy `SFSpeechRecognizer` and `DictationTranscriber` do not). No cloud ASR provider was configured, and uploading audio conflicts with the privacy model. Comparison requires consented recordings and a provider with explicit audio-upload consent. Infrastructure is ready: any recogniser can be plugged into `LanguifyBench asr` through the same manifest and scorer.

---

## C. Explanation prompt length

See the result appended below once `prompt-experiment.ts` completes.

---

## D. Silence trimming before recognition (REJECTED)

**Hypothesis.** Recognition time grows with rewind window length (measured P50: 15 s → 473 ms, 30 s → 543 ms, 60 s → 991 ms, 120 s → 1,936 ms) and roughly half of a conversational window is pauses. Removing long silences before recognition should cut recognition time substantially with no accuracy loss.

**Change tested.** `SpeechActivityTrimmer` (now in `Benchmarks/Sources/LanguifyBench/Experimental/`): 20 ms energy frames, adaptive noise floor (10th percentile), speech = 12 dB above floor, 0.3 s padding, gaps under 0.6 s kept, 0.25 s of silence kept in place of each removed gap; windows without clear quiet periods are left untouched.

**Configuration.** Same in-memory input path for both arms (as the app feeds audio), Tamil + English recognisers in parallel. 40 rewind windows, two rounds; plus the full 560-clip noise set.

**Result.**

| Set | Audio kept | Latency change (mean, paired, 95% CI) | Target-word hit |
|---|---|---|---|
| 60 s windows, round 1 | 63% | **+11.2%** (+34 to +225 ms) | 90 → 100% (1 gained) |
| 60 s windows, round 2 | 63% | **+11.9%** (+58 to +214 ms) | 90 → 100% (1 gained) |
| 120 s windows, rounds 1/2 | 65% | **+16.1% / +11.2%** | 100 → 100% |
| All windows | 61% | +11.1% / +7.6% | 97.4 → 100% |
| 560 noise clips | 97% | +0.5% | 65.5 → 63.9% (11 lost, 2 gained) |
| Overlapping speaker (56) | 89% | 0% | **73.2 → 62.5% (6 lost)** |

Trimming made recognition **slower** despite removing about 40% of the audio, and it hurt accuracy when a second speaker overlapped (quieter competing speech was partly cut, and splices removed context). It did reduce CER in long windows (fewer hallucinated words during pauses).

**Bug found during the experiment.** The first version deleted the entire window when speech was continuous (the 10th-percentile "noise floor" was speech). Caught by a unit test before any measurement; fixed by leaving windows without a clear quiet/loud contrast untouched.

**Decision.** Rejected. The trimmer is not used by the app and was moved out of the shipping package. Possible follow-up: transcribe only the most recent N seconds for single-word questions, which reduces audio without splicing (not yet tested).

---

## E. Parallel vs sequential recognisers (CONFIRMED EXISTING DESIGN)

The app runs the Tamil and English recognisers concurrently. Paired comparison on 55 clean clips (cold first clip excluded): sequential P50 537 ms, parallel P50 476 ms; mean saving **60 ms (11.1%)**, 95% CI 56 to 64 ms. Tamil alone P50 466 ms, English alone 71 ms, so the English pass costs almost nothing when parallel and raises English-word recall in code-switched speech from 69.2% to 76.9% (39 words). Kept as is.

**Related finding.** About 430 ms of each Tamil recognition is a fixed finalisation cost inside Apple's model, the same for slow (3.0 s) and fast (1.6 s) speech and for every transcriber configuration tried (no options, `.transcription` preset, finalize-through-end-of-input, volatile results: all 454 to 461 ms). It cannot be removed through configuration.

---

## F. Backend backpressure for the local model

See the result appended below once the load tests complete.
