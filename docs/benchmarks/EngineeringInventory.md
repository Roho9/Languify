# Engineering inventory

Verified against the repository on 2026-10-22 (commit history from `b5f8803`). "Testable here" means on this Mac (Apple M5 Pro, 48 GB, macOS 27) without an iPhone, real recordings or paid credentials.

| Component | Implementation (verified) | Dependencies | Testable here | Primary performance risks |
|---|---|---|---|---|
| Audio capture | `AudioCaptureEngine`: AVAudioEngine input tap, AVAudioConverter to 16 kHz mono float | AVFAudio, microphone | No (needs device mic); conversion path unit-testable | Tap thread blocking, route changes, dropped buffers |
| Live Rewind buffer | `RollingAudioBuffer` (LanguifyKit): Int16 ring under a `Mutex`, 30/60/120 s | Synchronization, Accelerate | **Yes**, fully (macOS) | Lock hold time during snapshot, memory, boundary correctness |
| Session state | `ListeningStateMachine` (pure) + `ListeningSessionManager` | AVAudioSession, ActivityKit | State machine yes; manager needs device | Interruption recovery, leaked mic |
| Speech recognition | `OnDeviceTranscriber`: Apple `SpeechAnalyzer`/`SpeechTranscriber`, ta-IN or ml-IN plus en-IN in parallel | Speech (iOS/macOS 26) | **Yes on macOS** for Tamil (models installed); Malayalam needs audio | Accuracy on real speech, fixed per-request cost, window length |
| Language detection | None as a separate stage: the user picks the heritage language; English is transcribed in parallel; the LLM reconciles code-switching | n/a | Indirectly (code-switch recall) | Mixed-language words lost |
| AI explanation | Backend `LanguageAI`: Gemma 3 27B via Ollama (default, local) or Claude (`AI_PROVIDER=claude`); structured JSON + validation | Ollama / Anthropic API | **Yes** with Ollama (free). Claude: no key available | Latency (local decode speed), wrong target, invented answers |
| Siri integration | 8 App Intents, 7 App Shortcuts, `AudioRecordingIntent` start | AppIntents, ActivityKit | Metadata only; behaviour needs device | Platform limits, intent time budget |
| Vocabulary journal | SwiftData `VocabularyEntry`/`ReviewRecord`, `VocabularyRepository` | SwiftData | Yes (simulator unit tests) | Query speed at scale, dedupe correctness |
| Learning engine | FSRS v4.5 scheduler, learner profile, quiz generator, pronunciation scorer | LanguifyKit | Logic yes; learning effect needs people | Effectiveness unproven |
| Backend | Fastify API, JWT auth, rate limit, quotas, StoreKit JWS verification | Node 22 | **Yes** (mock and real local AI) | Throughput, backpressure, timeouts, cost |
| Sync | SwiftData CloudKit (opt-in) | CloudKit, paid team | No | Conflicts |
| Auth / subscriptions | Guest tokens, Sign in with Apple, StoreKit 2 | Apple services | Server side yes; client needs device/sandbox | n/a for performance |

## Baseline status per component before this work

| Component | Baseline existed? |
|---|---|
| Buffer | Correctness unit tests only; no performance or memory measurement |
| ASR | One manual synthetic sentence test (feasibility) |
| AI | Three manual smoke questions (16 to 38 s) |
| Backend | Functional tests only; no load test |
| Privacy | Documented, not tested |
