# AI service selection

## Speech recognition

| Option | Tamil / Malayalam | Where it runs | Notes |
|---|---|---|---|
| Apple `SFSpeechRecognizer` (legacy) | No | Device / Apple | Not usable: neither locale is supported (checked on this machine). |
| Apple `SpeechTranscriber` (iOS 26 `SpeechAnalyzer`) | Yes (`ta-IN`, `ml-IN`) | **Device** | Chosen as the default. Free, private, fast (about 0.5 s per sentence on Apple silicon), real per-token confidence and alternatives. Output is romanised. Needs a one-time model download. Not available in the Simulator. |
| Apple `DictationTranscriber` | No | Device | Not usable. |
| Cloud ASR (for example Google Chirp, Sarvam, Azure, Whisper-family) | Varies | Cloud | Not integrated. Would require uploading audio, which conflicts with the privacy model. Kept as a documented provider slot (`SpeechTranscribing` protocol) to be used only if the device benchmark shows unacceptable accuracy, and only with separate, explicit consent to upload audio. |

Decision: on-device first. The `SpeechTranscribing` protocol lets a cloud provider be added without touching the pipeline.

## Language understanding

The explanation step needs contextual translation, native-script rendering from romanised input, transliteration, register and cultural notes, structured JSON, and good judgement about ambiguity. The backend uses **Claude (`claude-opus-5-5`)** through the official `@anthropic-ai/sdk`:

- Structured outputs (`output_config.format` with a Zod schema) make every response schema-valid; server and client then apply semantic checks (status consistency, native script in the right Unicode block, content limits).
- Effort is configurable per route: `low` for Live Rewind (latency-sensitive), `medium` for lessons. Model and effort are environment variables, so they can be tuned from measurements without an app release.
- Server-side refusal fallbacks (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`) are enabled, so a rare classifier false positive on ordinary conversation is retried server-side instead of failing.
- The static system prompts are marked for prompt caching.
- Provider swap: everything goes through the `LanguageAI` interface in `backend/src/ai/provider.ts`.

A free alternative, **Gemma 3 served locally by Ollama** (`AI_PROVIDER=ollama`, the default for development), uses the same prompts, schemas and validation. Ollama enforces the JSON schema during generation, so answers are always well-formed; quality on Tamil and Malayalam should be compared with Claude in the benchmark below. Apple's on-device Foundation Models were checked on 2026-10-21 and support 24 languages, not including Tamil, Malayalam or Hindi, so they cannot do this job.

Privacy and retention: Anthropic's API does not train on customer inputs under its commercial terms. Request zero data retention for the production organisation before launch.

### Local model measurements (2026-10-22, Apple M5 Pro, 48 GB)

Same three questions on a real on-device Tamil transcript (`npm run smoke`):

| Model | Time per answer | Quality |
|---|---|---|
| `gemma3:12b` | 17 to 22 s | Not acceptable: often left native script empty, one wrong meaning ("because I finished" for mudinjathum), and suggested replies that aren't real Tamil |
| `gemma3:27b`, first prompt | 24 to 38 s | Good meanings, but verbose and assumed the speaker's gender |
| `gemma3:27b`, current prompt | 16 to 19 s | Correct meanings, natural replies (நேரா வர்றீங்களா?, "Are you coming straight home?"), no gender assumption. Pronunciation hints are sometimes off (for example "vaa-NUM" for வேணும்) |

Generation runs at about 16 tokens per second, so answer length drives latency. Conclusion: `gemma3:27b` is good enough to develop and test with; 16 to 19 s is too slow for comfortable Siri use. Malayalam has not been tested yet with either model.

## Text to speech

- English explanations: iOS voices (`en-IN`), on device.
- Tamil words: iOS ships a Tamil voice (verified on macOS as "Vani"). Device check pending.
- Malayalam words: no Malayalam voice was found on macOS. If the device also lacks one, add a cloud TTS provider behind the backend (candidates with `ml-IN` neural voices include Google Cloud TTS and Azure). Until then the app labels playback as approximate and encourages hearing the word from family.

## Benchmark plan (required before launch)

Run on real, consented recordings. Suggested set: 50 clips per language, family-dinner conditions (phone on table, 1 to 3 m), mixed ages and regions (for Malayalam: at least central and northern Kerala; for Tamil: Chennai and Madurai/Kongu speech), 30% code-switched.

Measure per clip:

1. Recognition: word error rate on a hand-romanised reference (normalise spelling variants with `PronunciationScorer.normalize`), and target-word hit rate (is the word the learner asked about present in the transcript?).
2. Explanation: two bilingual reviewers grade correctness of meaning in context (0 to 2), script correctness, transliteration readability, and whether ambiguity was handled (asked vs guessed).
3. Latency: transcription ms and explanation ms (the app already logs both per question, without content).
4. Cost per answered question from `usage` in the API responses.

Acceptance bar before a public release: target-word hit rate of at least 80% and meaning correctness of at least 90% on answered questions, with a clarification rather than a wrong answer for the remainder.

`backend/scripts/smoke-explain.ts` exercises the live model on a real on-device Tamil transcript and is the starting point for the explanation half of this benchmark.
