# Roadmap and status

Legend: **Done** means implemented and covered by automated tests or a build check. **Needs device** means implemented but not yet run on an iPhone. **Not started** is not built.

## Phase 0: Feasibility and architecture (Done)

Environment inspected, SDK APIs verified, on-device Tamil transcription tested, feasibility matrix and architecture written. See [FEASIBILITY.md](FEASIBILITY.md), [ARCHITECTURE.md](ARCHITECTURE.md).

## Phase 1: Live Rewind MVP

| Item | Status |
|---|---|
| SwiftUI app, onboarding, Tamil/Malayalam selection, no account | Done (UI tested) |
| Microphone permission, privacy explanation first | Done |
| Manual start/stop, explicit session states | Done (state machine unit tested) |
| Rolling buffer, 30/60/120 s, cleanup | Done (unit tested) |
| On-device transcription, heritage + English | Done; needs device (Simulator lacks models) |
| Contextual AI explanation, native script, transliteration | Done (pipeline tested with doubles, backend tested); live model output pending API key |
| Spoken answers with privacy policy | Done; routing needs device |
| Error handling: offline, quota, no speech, model missing, consent, invalid AI output | Done (unit tested) |

## Phase 2: Siri and AirPods

| Item | Status |
|---|---|
| App Intents and 7 App Shortcuts | Done (metadata verified in build) |
| Siri start via `AudioRecordingIntent` + Live Activity | Needs device |
| Questions answered from pre-interruption buffer | Needs device |
| In-dialog clarification | Needs device |
| A2DP output with built-in mic, stop on disconnect | Needs device |
| Interruption recovery | Needs device |

## Phase 3: Vocabulary journal (Done)

Auto-save with de-duplication and context sentence, search, language and status filters, favorites, mastery, edit with preserved original, delete, pronunciation playback, manual add. Repository unit tested; add, review and delete covered by UI tests.

## Phase 4: Learning (Done, AI parts need an API key)

FSRS flashcards, on-device quizzes from saved words, pronunciation practice (intelligibility feedback), learner profile with estimated vs measured scores, optional quick check, progress chart, AI conversation practice, AI lessons, opt-in post-session suggestions.

## Phase 5: Accounts and sync

| Item | Status |
|---|---|
| Guest mode, install tokens | Done |
| Sign in with Apple, guest usage merge | Done (backend tested); needs paid team + device |
| iCloud sync via SwiftData CloudKit (opt-in) | Done in code; needs paid team + two devices |
| Export JSON, delete history, delete all incl. server data | Done |
| Conflict handling | CloudKit last-writer-wins per field; review counts can diverge on simultaneous offline reviews on two devices. Acceptable for v1; revisit with real usage. |

## Phase 6: Monetization

| Item | Status |
|---|---|
| StoreKit 2 products, purchase, restore, updates listener | Done; local `.storekit` config |
| Configurable plans and quotas, served by backend | Done (tested) |
| Server-side quota enforcement and JWS verification | Done (tested with a stand-in verifier; Apple library wired for real JWS) |
| Paywall with App Store prices and trial terms | Done |
| Sandbox purchase on device | Needs paid team + device |

## Phase 7: Polish and release (In progress)

Done: Liquid Glass controls and tab accessory, Dynamic Type friendly layouts, VoiceOver labels, Reduce Motion, privacy manifest, zero compiler warnings in project code.

Remaining, in priority order:

1. Run the real-device checklist ([TESTING_CHECKLIST.md](TESTING_CHECKLIST.md)), sections B, C and D first.
2. Add an Anthropic key, run `npm run smoke`, and review answer quality with bilingual reviewers; then the benchmark in [AI_PROVIDERS.md](AI_PROVIDERS.md).
3. Deploy the backend over HTTPS; add App Attest and a shared usage store.
4. Decide on Malayalam TTS after checking device voices.
5. Replace the placeholder privacy policy URL (`languify.app/privacy`) with a real hosted policy.
6. String Catalog extraction and localisation review.
7. Items in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

Future languages (Hindi, Telugu, Kannada, Spanish): add a `HeritageLanguage` case with its configuration and starter words, confirm `SpeechTranscriber` locale support, extend the backend `Language` enum. None are implemented or tested yet.
