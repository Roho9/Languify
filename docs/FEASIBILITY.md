# Feasibility: Live Rewind, Siri and AirPods

Researched against the iOS 26.5 SDK shipped with Xcode 26.6 (the SDK headers and Swift interfaces are the source of truth used here), plus hands-on tests on this Mac and the iOS 26.5 Simulator on 2026-10-21.

Status key:

- **Verified**: confirmed by running code or by the SDK's own interface and documentation comments.
- **Implemented, needs device test**: built on public APIs as documented, but the behaviour depends on hardware or system services the Simulator cannot reproduce.
- **Not supported**: iOS does not allow it; a fallback is implemented instead.

## Evidence gathered

| Test | Result |
|---|---|
| `SFSpeechRecognizer.supportedLocales()` (legacy API) | No `ta-IN` or `ml-IN`. Only `en-IN`, `hi-IN`. The legacy API cannot serve Tamil or Malayalam. |
| `SpeechTranscriber.supportedLocales` (iOS 26 / macOS 26 `SpeechAnalyzer`) on this Mac | Includes `ta-IN`, `ml-IN`, `en-IN`. `DictationTranscriber` does not include ta/ml. |
| Transcribed synthetic Tamil speech ("நான் நாளைக்கு சென்னைக்கு போகிறேன். உனக்கு என்ன வேணும்?") with `ta-IN` | Output: `naan naalaikku chennaikku poagiraen unakku enna vaenum`. Correct words, **romanised (Latin) output, not Tamil script**. 0.58 s wall time. Per-token confidence 0.64 to 0.99 via the `transcriptionConfidence` attribute, plus alternatives. |
| Tamil-English code-switch ("நான் இன்னைக்கு office meeting முடிஞ்சதும் வீட்டுக்கு வரேன், சரியா?") | `naan innaikku office meeting mudindiyathum veettukku varaen sariyaa`. English words kept as English. 0.51 s. |
| Same audio through `en-IN` | `Nani office, meeting, Mudindyadum, Bituk, Barin, Sariya.` with confidence 0.04 to 0.51. Useful only to confirm English words. |
| `SpeechTranscriber` locales in the **iOS 26.5 Simulator** | Reports `ml-IN` and `en-IN` as unsupported (see Live Rewind screen). Transcription must be validated on a physical iPhone. |
| `AVSpeechSynthesisVoice` on this Mac | Tamil voice "Vani" (`ta-IN`) present. No Malayalam voice. iOS device availability unverified; the app detects and labels a missing voice. |
| `AudioRecordingIntent` (AppIntents, iOS 18+) | SDK doc comment: "you must start a Live Activity when you begin the audio recording and keep it active as long as you record audio. If you don't start a Live Activity, the audio recording stops." |
| App Shortcuts extraction | Build produced `Metadata.appintents` with 8 intents and 7 App Shortcuts (phrases listed in [SIRI_COMMANDS.md](SIRI_COMMANDS.md)). |
| Liquid Glass APIs | `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID`, `.glass` / `.glassProminent` button styles, `buttonSizing(.flexible)`, `tabBarMinimizeBehavior`, `tabViewBottomAccessory` (the `isEnabled:` variant needs iOS 26.1) all present and used. |

The biggest risk going in was whether any on-device recogniser handled Tamil and Malayalam at all. It does, with one design consequence: because output is romanised, the AI layer produces native script, and the app validates that script by Unicode block before showing or saving it.

## Feasibility matrix

| Requested feature | Approach | Apple APIs | Known limitations | Fallback | Status / how to verify |
|---|---|---|---|---|---|
| Manual start/stop listening | In-app button starts `AVAudioEngine` capture into a bounded in-memory ring buffer | `AVAudioApplication`, `AVAudioSession`, `AVAudioEngine` | Requires mic permission granted in the foreground | None needed | Implemented. Unit tested state machine and buffer. Device test: checklist A1. |
| Rolling buffer 30 / 60 / 120 s | `RollingAudioBuffer`: 16 kHz mono Int16, fixed capacity, zeroed on clear | n/a | 120 s costs about 3.8 MB | n/a | **Verified** by 30+ unit tests (bounds, concurrency, cleanup, repeated sessions). |
| Keep listening with the screen locked | `UIBackgroundModes: audio`; capture started in the foreground continues | `AVAudioSession` `.playAndRecord` | iOS shows the orange mic indicator; App Review must see a genuine recording feature (it is) | User keeps the app open | Implemented, needs device test (A3). |
| "Siri, start Languify" | `StartListeningIntent: AudioRecordingIntent` + Live Activity | AppIntents, ActivityKit | Permission must already be granted; Siri holds the mic while speaking, so the intent retries start for up to ~2.4 s | Open app and tap Start | Implemented, needs device test (B1). |
| "Siri, stop Languify" | `StopListeningIntent: LiveActivityIntent` (also the Live Activity's Stop button) | AppIntents | None known | In-app Stop, Live Activity button | Implemented, needs device test (B2). |
| "Siri, ask Languify what that word meant" while listening | App Shortcut runs in Languify's process; reads the buffer captured *before* Siri interrupted the mic; returns dialog Siri speaks | AppIntents (`ProvidesDialog`, `ShowsSnippetView`), `AVAudioSession` interruption | Siri's own utterance is not captured (Siri owns the mic); exact phrase matching is Siri's; intent time budget is system-defined | In-app quick question buttons | Implemented, needs device test (B3 to B6). The key assumption, that the pre-interruption buffer survives, is guaranteed by our code (interruption pauses capture, never clears). |
| Spoken clarification ("which word?") | `AskWordIntent` throws `needsValueError` on its "sounds like" parameter so Siri asks the follow-up in the same exchange; the transcript is cached for 2 minutes | AppIntents | Siri dictates the reply in English, so "madi" may arrive as "Maddie"; the AI matches phonetically | `Tell Languify which word` shortcut; in-app option buttons | Implemented, needs device test (B5). |
| Custom wake word / always-on listening without starting a session | Not built | n/a | **Not supported**: third parties cannot add wake words or listen without an explicit, indicated session | Explicit sessions + Siri | n/a |
| Reading what Siri heard | Not built | n/a | **Not supported**: apps receive only intent parameters, never Siri's audio or history | Siri parameters for "sounds like" | n/a |
| Private answers in AirPods | Session allows Bluetooth A2DP output, prefers the built-in mic. Siri speaks intent dialog through the current route. In-app answers use `AVSpeechSynthesizer` only when the policy allows | `AVAudioSession` options `.allowBluetoothA2DP`, `.defaultToSpeaker`; `setPreferredInput` | A2DP speakers or cars look like headphones to iOS | Silent mode | Policy **verified** by unit test; routing needs device test (C1 to C4). |
| Use the iPhone mic, not AirPods mic, for the room | HFP is deliberately not allowed, so iOS cannot switch input to AirPods | `AVAudioSession` | Phone in a pocket muffles speech | Advise phone on the table | Needs device test (C2). |
| Stop speech if AirPods disconnect | Route-change `oldDeviceUnavailable` stops synthesis immediately | `AVAudioSession.routeChangeNotification` | n/a | n/a | Implemented, needs device test (C3). |
| Own voice not captured into the buffer | Capture is suppressed while Languify speaks, plus 300 ms tail | n/a | n/a | n/a | Implemented. |
| Tamil / Malayalam transcription | On-device `SpeechTranscriber`, heritage + `en-IN` in parallel | Speech (`SpeechAnalyzer`, `AssetInventory`) | Romanised output; accuracy on real family speech unmeasured; Simulator lacks models | Cloud ASR provider slot (see AI_PROVIDERS.md) | Tamil **verified on macOS**; iOS device verification pending (D1, D2). |
| Native script, meaning, context | Backend calls Claude with structured outputs; app validates script by Unicode block | n/a | Depends on network and consent | Transcript shown on device, retry later | Contract and validation **verified** by tests; live model quality pending an API key (smoke script provided). |
| Pronunciation feedback | Re-transcribe the learner on device and compare normalised romanisations | Speech | Intelligibility only, not phoneme scoring (no validated Tamil/Malayalam phoneme scorer exists on Apple platforms) | n/a | Scorer **verified** by unit tests. |
| Pronunciation playback | `AVSpeechSynthesizer` | AVFAudio | Malayalam voice may be missing | Label in UI; cloud TTS slot documented | Implemented. |
| Live Activity / Dynamic Island | ActivityKit widget extension with Stop button | ActivityKit, WidgetKit | User can disable Live Activities; then `AudioRecordingIntent` recording would stop, so Siri start would fail and the app explains it | In-app start | Implemented, needs device test (B1). |
| Speaker identity ("my mom said") | Not inferred from audio. The learner can type context ("my mom was talking about dinner") | n/a | No consented voice-ID; deliberately not built | Free-text context | By design. |

## Remaining risks, in order

1. **On-device Malayalam accuracy on natural family speech.** Only Tamil synthetic speech was tested. Run the benchmark in [AI_PROVIDERS.md](AI_PROVIDERS.md) on real recordings (with consent) before launch.
2. **Siri plus active recording on device.** Interruption, resume and intent timing must be checked on hardware (checklist B).
3. **Malayalam text-to-speech.** If iOS has no Malayalam voice, add the documented cloud TTS provider.
4. **End-to-end latency.** Measured transcription is about 0.5 s per sentence on an M-series Mac; device and network times must be measured (the app logs per-stage durations without content).
