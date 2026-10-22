# Resume metrics

Bullets built only from measurements in this repository. Each number traces to a run ID in the evidence table. Where a result is from a Mac or synthetic speech, the bullet says so or uses only the relative figure; none of these is an iPhone or real-user measurement. Pick bullets, do not combine numbers from different rows into new claims.

## Evidence

| # | Claim | Value | Conditions | Source |
|---|---|---|---|---|
| E1 | Audio append time per 100 ms chunk | 6.5 µs → 0.17 µs (97% lower) | Mac, release, 3 runs | ExperimentLog A; buffer-20261022T184317Z/184331Z/184345Z |
| E2 | 120 s extraction time holding the audio lock | 8.21 ms → 0.15 ms (98.2% lower) | same | same |
| E3 | Peak memory during 120 s extraction | 14.7 → 11.1 MB (24.5% lower) | fresh process per measurement | memory-20261022T184305Z |
| E4 | Buffer correctness | 480/480 sample-exact boundary cases; bounded over 60 min sessions | same runs | same |
| E5 | Explanation latency from prompt redesign | P50 37.4 s → 19.4 s; paired mean -17.2 s (-45.8%), CI -22.0 to -13.1 s; valid output 17/20 → 20/20 | Mac, Gemma 3 27B local, 20 cases | prompt-20261022T213328Z |
| E6 | Phonetic retrieval before the model | target word 50/56 → 53/56; clarification when ambiguous 1/8 → 6/8; 0 regressions | Mac, local model, real ASR transcripts of synthetic speech | ExperimentLog G; context-ollama-f320a5e-retrieval_off/on |
| E7 | Ambiguous questions answered without a model call | 6 of 8, under 1 ms vs 18.6 s P50 | same | same |
| E8 | Abstention when the word was not said | 8/8, 0 confident wrong answers | same | same |
| E9 | Overload behaviour with a concurrency limiter | at 8 concurrent: failures 55 s timeouts → 503 in 6 ms; slowest success 54.6 s → 35.7 s | Mac, loopback, real local model, small n | ExperimentLog F |
| E10 | Backend server capacity, mock AI | 631 req/s at 200 concurrent, 100% success, ≤ 154 MB RSS | Mac, loopback, mock AI | load-mock-20261022T213437Z |
| E11 | Tamil ASR evaluation | 560 clips, 10 noise/rate/overlap conditions; clean target-word hit 91.1% [80.7, 96.1] | Mac, synthetic single speaker | asr-20261022T184830Z |
| E12 | Recogniser confidence as a miss signal | AUROC 0.78 | same | same |
| E13 | Negative result | silence trimming made recognition 11% slower and cut overlap accuracy 73.2% → 62.5%; rejected | Mac, synthetic | ExperimentLog D |
| E14 | Privacy validation | 21/21 automated checks (16 static, 5 runtime) | Mac, simulator | privacy-20261022T214657Z |
| E15 | Tests | 136 automated tests (69 core, 38 backend, 29 app incl. 7 fault-injection) | | swift test, vitest, xcodebuild test |

## Top 3 (use these first)

1. Cut audio buffer lock hold time **98%** (8.2 ms → 0.15 ms per 120 s extraction) and append cost **97%** by rewriting a real-time Swift ring buffer with Accelerate vDSP block conversion; verified sample-exact on 480 boundary cases and bounded over 60-minute sessions. (E1, E2, E4)
2. Raised target-word identification from **50/56 to 53/56** and correct clarification on ambiguous questions from **1/8 to 6/8** by adding deterministic phonetic candidate retrieval ahead of the LLM, in a paired A/B on 72 Tamil questions with zero regressions. (E6)
3. Built a reproducible benchmarking framework for a Tamil speech + LLM iOS app: 560-clip ASR noise/overlap suite, 98-case LLM eval, load and fault-injection tests, 21 privacy checks, Wilson/bootstrap CIs, and CI regression gates. (E11, E14, E15)

## By role

**Software engineering**
- Built a reproducible benchmarking framework (Swift + TypeScript + Python) with versioned dataset manifests, immutable run records tagged by commit, Wilson and bootstrap confidence intervals, and CI regression thresholds. (E11, E14, E15)
- Measured and rejected an optimisation: silence trimming removed 40% of audio but made speech recognition 11% slower and reduced overlap accuracy 73% → 62%; documented and removed it from the shipping package. (E13)

**Backend**
- Added admission control to a Fastify AI backend; under 8x overload, failing requests return a retryable 503 in **6 ms instead of timing out after 55 s**, and the slowest successful answer fell from 54.6 s to 35.7 s. (E9)
- Load-tested the Node/Fastify API to **631 req/s at 200 concurrent users with 100% success** (mock model, single machine), isolating server overhead from model latency. (E10)

**iOS**
- Rewrote the Live Rewind audio ring buffer with Accelerate vDSP: **98% less time holding the audio lock**, **97% faster appends**, 24.5% lower peak memory, verified sample-exact. (E1 to E4)
- Wrote 29 app tests including 7 fault-injection tests (timeouts, 429/503, truncated JSON, competing requests) and 21 automated privacy checks covering consent gating, buffer zeroing and log redaction. (E14, E15)

**AI/ML**
- Evaluated on-device Tamil speech recognition across 560 clips and 10 noise, speech-rate and overlap conditions with sentence-level bootstrap CIs; found recogniser confidence predicts missed words (AUROC 0.78). (E11, E12)
- Redesigned LLM output prompts for a local Gemma 3 27B, cutting explanation latency **46%** (paired, CI -22 to -13 s) and raising valid structured output from 17/20 to 20/20. (E5)

**Applied AI**
- Added phonetic retrieval ahead of the LLM so ambiguous questions get a clarification instead of a guess (**1/8 → 6/8**, answered in under 1 ms with no model call) and target-word accuracy rose 50/56 → 53/56 with no regressions. (E6, E7)
- Built a 98-case evaluation for an LLM language tutor covering identification, clarification and abstention; the system abstained on 8/8 unanswerable questions with zero confident wrong answers. (E8)

## Do not claim

- Any iPhone, AirPods or Siri latency, battery or thermal figure (not measured).
- Malayalam accuracy (not measured).
- Accuracy on real speakers or real conversations (all ASR inputs are synthetic, one voice).
- Translation or explanation quality (the human rubric has not been scored).
- Statistical significance for E5 correctness or E6 (paired McNemar p = 0.25 and 0.06; say "no regressions", not "significant").
- Production scale or user counts (single machine, loopback, no users).
- Claude-provider performance (no key; not measured).
