# Benchmark methodology

## Labels used on every result

| Label | Meaning |
|---|---|
| **Measured (Mac)** | Run on the development Mac (Apple M5 Pro, 48 GB, macOS 27). Not an iPhone measurement. |
| **Synthetic speech** | Audio produced by macOS text-to-speech (Tamil voice "Vani", the only Tamil voice installed). One synthetic speaker. |
| **Artificial mix** | Noise or a competing speaker mixed into synthetic speech at a controlled SNR. |
| **Mock AI** | The AI provider replaced by a scripted stand-in with injected latency. Used only to stress infrastructure. |
| **Real local AI** | Gemma 3 27B served by Ollama on the same Mac. |
| **Not measured** | No valid measurement exists. Never filled with estimates. |

Simulated and real results are never combined in one number.

## Run records

Every run writes `Results/Raw/<category>/<runID>.json` (never overwritten) containing the git commit, dirty flag, machine, chip, memory, OS, build configuration, environment label, dataset and configuration, and raw per-sample measurements. Aggregations go to `Results/Aggregated/`; reports to `Results/Reports/`.

## 1. Live Rewind buffer (`LanguifyBench buffer`, `memprobe`)

- Workload: 16 kHz mono float chunks of 1,365 and 1,600 frames (85 ms and 100 ms, matching AVAudioEngine tap sizes after conversion). Buffer filled to steady state before timing so trimming/wrap-around is included.
- Implementations compared on identical input: shipping (LanguifyKit at the commit), frozen baseline v1 (the original per-sample ring), Float32 ring, naive append-and-trim array.
- Timing: `DispatchTime` (mach absolute time, ~42 ns resolution) per call; 3,000 appends and 100 snapshots per configuration; release build; three separate process runs to show run-to-run variation.
- CPU: process user+system time over the timed appends, divided by seconds of audio appended (fraction of real time).
- Memory: `phys_footprint` (the value iOS jetsam uses) measured in a fresh process per configuration (so malloc reuse cannot hide allocations), three repetitions each. Heap blocks per append from `malloc_zone_statistics`.
- Boundary correctness: a timeline with a 0.5 s marker "word" of known sample values; questions asked 0 to 119 s after the word, exactly at, straddling and beyond the window edge; 0 or 2 s of audio arriving after the question. Each case checks the retrieved word frame count and that the window ends exactly at the question frame. Pass requires sample-exact agreement.
- Sustained: 60 simulated minutes appended as fast as possible (time-compressed) with a full-window snapshot and a footprint sample every simulated minute. Bounded = footprint growth after the first fill under 1 MB.

## 2. Speech recognition (`make_asr_dataset.py`, `LanguifyBench asr`, `score_asr.py`)

- Dataset: 56 colloquial Tamil sentences (25 everyday, 8 uncommon, 3 idiom, 20 Tamil-English code-switched), each with one labelled target word. Not yet reviewed by a native speaker.
- Conditions: 3 speaking rates (130/185/250 wpm), pink noise at +20/+10/0/-5 dB SNR, English babble (5 TTS voices) at +10/0 dB, competing Tamil sentence 6 dB below. 560 clips. SNR uses active-speech RMS (20 ms frames above -40 dB of peak).
- Rewind windows: 10 windows each of 15/30/60/120 s built from sentences with 0.8 to 3.5 s pauses of -50 dBFS room tone; the target is in the last sentence.
- Recogniser: Apple `SpeechTranscriber` exactly as the app configures it (fresh transcriber per request, alternatives, time ranges, confidence), Tamil and Indian English in parallel unless stated.
- Normalisation: the reference (Tamil script) is romanised deterministically in the recogniser's style (`tamil_romanize.py`), then both sides are reduced to a phonetic skeleton: voicing merged (k/g, t/d, p/b, c/s/j), aspirate digraphs merged, vowel length merged, doubled letters collapsed. This removes spelling-convention differences but can hide genuine length errors.
- Metrics: CER on the space-free skeleton (primary); WER on skeleton tokens (secondary; inflated by word-splitting differences); target-word hit (the target matches one to three consecutive recognised words, or the edge of a span to allow attached particles, within 20% character error); English-word recall in code-switched sentences; confidence calibration (AUROC of minimum token confidence for detecting target misses).
- Statistics: 95% bootstrap CIs resampling **sentences** (all clips of a sentence move together, because conditions of one sentence are correlated and there is only one speaker); Wilson intervals for hit rates; paired bootstrap for A/B latency differences. The first clip of each run is excluded from A/B latency (cold start).

## 3. Contextual retrieval (`backend/bench/context-eval.ts`)

- Transcripts are the real recogniser outputs for the clean clips, arranged into conversations of one to three utterances.
- Case types: "sounded like" lookups with a learner-style misspelling of the target (56), "the sentence before that" (16), ambiguous pairs of similar-sounding words (8, hand-written), unanswerable lookups where the word is absent (8), and "how do I respond" (10).
- Automatic metrics: target identification (returned word matches the label within 34% skeleton CER), sentence localisation (returned sentence within 45% CER of the labelled sentence), clarification rate on ambiguous cases, abstention and confident-wrong rate on unanswerable cases, unnecessary clarification on clear lookups, schema validity, native-script validity.
- Not automatic: whether the explanation is correct, natural and useful. A CSV review sheet is exported per run for bilingual reviewers using [TranslationReviewRubric.md](TranslationReviewRubric.md).

## 4. AI latency (`backend/bench/prompt-experiment.ts`)

- Same cases, original prompt (git `efb50fe`) vs current prompt, alternating order per case (ABAB) to cancel warm-up and thermal drift. Ollama's own counters record prompt tokens, output tokens, decode speed and load time.
- Cold start: model unloaded (`keep_alive: 0`), 3 s pause, then first request; three repetitions.
- Timing boundary: from HTTP request to Ollama until the full JSON response. Excludes transcription and network to the phone.

## 5. Backend load (`backend/bench/load-test.ts`)

- Server and client in separate processes on the same Mac over loopback. One token per virtual user. Rate limit and quota raised for the test so capacity is measured, not product limits.
- Mock AI stages: concurrency 1 to 200, 10 s each. Real local AI: concurrency 1/2/4/8 with a fixed number of requests per worker, with and without the concurrency limiter, client timeout 60 s (the app's).
- Metrics: throughput, goodput (successful responses per second), success rate, latency percentiles of successful requests (P99 only with at least 100 samples), status breakdown, server CPU and RSS sampled every 500 ms.

## 6. Privacy and reliability

- `privacy_checks.py`: static checks (binary strings scan, forbidden APIs, disk writes, model fields, log interpolation, Keychain attributes, ATS, purpose strings, privacy manifest, consent ordering) and runtime tests (buffer clearing, server log capture at trace level, server-side quota, deletion, consent and silence gating).
- Reliability: fault-injection unit tests in the app (competing requests, timeouts, rate limits, busy server, truncated JSON, recovery, 10 concurrent requests) and backend (provider failures, overload, invalid output).

## Improvement formulas

- Latency or memory reduction: (baseline − optimized) / baseline × 100.
- Throughput improvement: (optimized − baseline) / baseline × 100.
- Accuracy changes are reported in percentage points, with relative change stated separately when used.
- Absolute values are always shown next to relative changes.
