# Languify

A native iOS companion for receptive bilinguals: people who understand Tamil or Malayalam from growing up around it, but reply in English.

Start a listening session before a family conversation. When you hear something you don't know, ask (in the app, or "Siri, ask Languify what that word meant" with AirPods in). Languify transcribes the last few seconds **on your iPhone**, explains what was meant in context, says it privately in your ear, and saves the word with the sentence it came from. Later it turns those words into flashcards, quizzes, pronunciation practice, and conversation practice aimed at getting you to speak.

## Status

Built and tested so far (2026-10-21):

| Suite | Result |
|---|---|
| `LanguifyKit` core (`swift test`) | 64 tests pass |
| Backend (`npm test`) | 13 tests pass |
| App unit and integration tests (Simulator) | 22 tests pass |
| App UI journeys (Simulator) | 4 tests pass |
| App + widget build | Succeeds, no warnings in project code |

Verified on this Mac: Apple's on-device recogniser transcribes Tamil (including Tamil-English code-switching) in about half a second, with real confidence scores. Its output is romanised, so the AI layer produces native script.

**Not yet verified:** anything that needs an iPhone (microphone capture, locked-screen listening, Siri while recording, AirPods routing, on-device Malayalam accuracy) and live AI answer quality (no API key was available here). See [docs/FEASIBILITY.md](docs/FEASIBILITY.md) and the device checklist in [docs/TESTING_CHECKLIST.md](docs/TESTING_CHECKLIST.md).

## Quick start

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # team id, backend URL
xcodegen generate && open Languify.xcodeproj

cd backend && npm install && cp .env.example .env && npm run dev
```

Full instructions: [docs/SETUP.md](docs/SETUP.md).

## Documentation

- [Feasibility matrix](docs/FEASIBILITY.md): what iOS allows, what was verified, fallbacks
- [Architecture](docs/ARCHITECTURE.md): modules, pipeline and state diagrams, data model
- [Privacy](docs/PRIVACY.md): how audio and text are handled, user controls
- [AI services](docs/AI_PROVIDERS.md): provider choices and the benchmark plan
- [Siri commands](docs/SIRI_COMMANDS.md)
- [Backend](docs/BACKEND.md): API, security, deployment
- [Setup](docs/SETUP.md)
- [Real-device checklist](docs/TESTING_CHECKLIST.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)
- [Roadmap and status](docs/ROADMAP.md)

## Stack

Swift 6, SwiftUI with Liquid Glass (iOS 26), SwiftData, `SpeechAnalyzer`, AVFoundation, App Intents, ActivityKit, StoreKit 2, Sign in with Apple, CloudKit. Backend: TypeScript, Fastify, Zod, Anthropic SDK (Claude), App Store Server Library.

The minimum iOS version is 26.0 because Tamil and Malayalam on-device transcription only exists in iOS 26's `SpeechAnalyzer`.
