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

## C. Explanation prompt length and output cap (ADOPTED)

**Hypothesis.** With a local model decoding at about 12 to 16 tokens/s, latency is dominated by output length, not prompt length. The original prompt (v1) let the model fill every optional field (usage, cultural and regional notes, examples, related words). A prompt that asks for only what the learner needs to hear, plus a hard `num_predict` cap, should roughly halve latency without losing correctness.

**Baseline.** v1 = `backend/src/ai/prompts.ts` at git `efb50fe` (copied to `backend/bench/prompts/v1.ts`). v2 = current prompts.

**Configuration.** Gemma 3 27B via Ollama on the M5 Pro, 20 cases (sounds-like and sentence-before), real Apple ta-IN transcripts of synthetic speech, ABAB order alternating per case to cancel drift, model kept warm, 180 s client abort, `num_predict` 1500 for both arms. Run `prompt-20261022T213328Z`, commit `f320a5e`.

**Result (Measured (Mac), real local model).**

| | v1 | v2 |
|---|---|---|
| Latency P50 / P95 | 37.4 s / 59.0 s | **19.4 s / 28.2 s** |
| Output tokens, mean | 461 | **242** |
| Prompt tokens, mean | 993 | 1,272 |
| Valid output | 17/20 (1 hit the token cap) | **20/20** |
| Valid and correct (all calls) | 13/20 | 14/20 |

- Paired mean change on the 17 cases where both arms were valid: **-17.2 s** (95% bootstrap CI -22.0 to -13.1 s), **-45.8%**.
- Prompt processing is about 1.7 s for both arms, so the extra 280 prompt tokens in v2 cost almost nothing; output length is what matters.
- Correctness: 5 cases changed (3 gained by v2, 2 lost); n = 20 cannot show a difference in either direction. Claim is "no measured accuracy loss", not "more accurate".
- Cold start (model not loaded): mean 24.3 s, of which 3.2 s is model load.

**Bug found.** The first run of this experiment hung indefinitely: v1 sometimes generated without end inside the JSON schema, and Node's fetch headers timeout fired only after 5 minutes. Fixed with a 180 s abort in the harness and, in the product, `num_predict` caps per task (explain 800/1400, tutor 600, suggestions 1500, lesson 2000) plus rejecting `done_reason: "length"` as invalid output rather than parsing a truncated answer.

**Decision.** Adopted v2 and the output caps (already the shipping prompts at `f320a5e`).

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

## F. Backend backpressure for the local model (ADOPTED)

**Hypothesis.** A local model serves roughly one generation at a time. Without admission control, concurrent requests all wait in Ollama's queue and most of them hit the 55 s server timeout, so users wait nearly a minute for an error while the machine still spends compute on answers nobody will read. A concurrency limiter with a short queue should turn those into fast, retryable 503s and keep accepted requests' latency bounded, at no cost to successful throughput.

**Change.** `ConcurrencyLimiter` (`backend/src/ai/limiter.ts`) in front of every AI call: `AI_MAX_CONCURRENCY`, `AI_MAX_QUEUE`, `AI_MAX_QUEUE_WAIT_MS`. Overflow returns 503 with `Retry-After`; quota is only consumed after a successful answer. The app already treats 503 as retryable and keeps the transcript (`AppTests/ReliabilityTests.swift`).

**Configuration.** Single Node server and a load client in separate processes on the same Mac, loopback, real Gemma 3 27B, explain requests, concurrency 1/2/4/8 with 2 requests per worker. Limiter arm: 1 concurrent, queue 2, 20 s wait. Runs `load-real-20261022T214010Z` (off) and `load-real-20261022T214434Z` (on). Plus a mock-AI capacity run (`load-mock-20261022T213437Z`, 300 ms lognormal mock latency, 10 s per stage) to measure the server itself.

**Result (Measured (Mac), real local model).**

| Concurrency | Limiter | Succeeded | Success P50 / max | Failures | Failure latency P50 |
|---|---|---|---|---|---|
| 4 | off | 4/8 | 39.8 s / 54.6 s | 4 × 504 timeout | 55.0 s |
| 4 | on | 4/8 | 32.8 s / 36.0 s | 4 × 503 busy | 10.0 s |
| 8 | off | 4/16 | 43.4 s / 54.6 s | 12 × 504 timeout | 55.0 s |
| 8 | on | 3/16 | **29.5 s / 35.7 s** | 13 × 503 busy | **6 ms** |

- At 8 concurrent users, failed requests are rejected in **6 ms instead of hanging 55 s**, and the slowest successful answer drops from 54.6 s to 35.7 s.
- Successful throughput is unchanged (4 vs 3 answers in the window; one local model is the bottleneck either way). The limiter does not add capacity; it makes overload fast and honest.
- At concurrency 1 the limiter arm was slower (P50 26.1 s vs 15.7 s, n = 2 each); with one request in flight the limiter does nothing, so this is case-to-case output length variation. Small samples: these are behaviour checks, not capacity figures.
- Mock AI: the Fastify server sustained **631 req/s at 200 concurrent with 100% success**, P50 285 ms against a mock with 300 ms mean latency (server overhead is not distinguishable from the mock's spread), server CPU 36%, RSS at most 154 MB. Server overhead is negligible next to model time.

**Not done, by design.** No load test against any third-party AI provider. Claude-backed capacity is bounded by account rate limits and is not measured.

**Decision.** Adopted. Defaults for a single local model: concurrency 1, short queue.

---

## G. Phonetic candidate retrieval before the model (ADOPTED)

**Hypothesis.** For "what did the word that sounded like X mean", the model saw the whole transcript and had to find the word itself. In the baseline it rarely asked for clarification when two different words matched (1/8), and it sometimes picked the wrong word. A deterministic step that finds candidate words by phonetic skeleton distance before the model is called should (a) decide ambiguity itself and return a clarification without any model call, and (b) pass the single best match to the model as a hint.

**Change.** `backend/src/rewind/candidates.ts` and `pipeline.ts`. Skeleton matching (`MATCH_THRESHOLD` 0.34, short-prefix rule 0.25, tie margin 0.1), candidates distinct by spelling, "X or Y" handled. Paths: `phonetic_clarification` (no model call), `model_with_phonetic_hint`, `model`. Server-only `phonetic_match` field, so a client cannot inject a hint.

**Configuration.** Same 72 cases (56 sounds-like, 8 ambiguous, 8 unanswerable), same model and prompts, same commit `f320a5e`; only `--retrieval off|on` differs. Runs `context-ollama-f320a5e-retrieval_off-20261022T203847Z` and `..._retrieval_on-20261022T211117Z` (the on-run also covers the other 26 cases of the full suite).

**Result (Measured (Mac), real recogniser transcripts of synthetic speech, real local model).**

| Metric | Off | On |
|---|---|---|
| Target word identified | 50/56 (89.3%) [79, 95] | **53/56 (94.6%)** [85, 98] |
| Clarifies when ambiguous | 1/8 | **6/8** (6/7 excluding amb-5, where both "candidates" are the same word) |
| Unnecessary clarification on clear lookups | 0/56 | 0/56 |
| Abstains when the word is absent | 8/8 | 8/8 |
| Confident wrong answer when absent | 0/8 | 0/8 |
| Schema-valid output | 72/72 | 98/98 (full suite) |
| P50 latency, ambiguous | 18.6 s | **under 1 ms** for the 6 answered by retrieval |
| P50 latency, sounds-like | 19.6 s | 20.7 s |

- Paired: target identification 3 gained, 0 lost (exact McNemar p = 0.25); clarification 5 gained, 0 lost (p = 0.06). Direction is consistent and nothing regressed, but n is small, so the improvement is not statistically established.
- 3 sounds-like answers moved from "uncertain" to "answered" with the hint, all with the right word.
- Remaining misses: 2 where retrieval found no candidate (long inflected forms "saappittiyaa", "sapituten"), and 1 where the right word was found but the model gave the wrong meaning (pasikkuthu glossed as "nauseous"; it means "hungry"). Retrieval cannot fix meaning errors; that needs a stronger model or a lexicon check.
- Sounds-like latency is about 1 s higher (hint adds tokens); within run-to-run spread of earlier runs (20.3 s at `ddebcc0`).

**Bugs found while building it** (all fixed before the measured run, each with a unit test in `backend/test/candidates.test.ts`): the short query "pal" matched too many words (prefix rule added); the skeleton merged kadai "shop" and kathai "story" into one candidate (candidates now distinct by spelling); "paal" vs "paalam" was de-duplicated as one word (containment de-duplication limited to two-word spans).

**Decision.** Adopted.
