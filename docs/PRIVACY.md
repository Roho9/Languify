# Privacy architecture

Languify processes conversations that include other people, so privacy rules are enforced in code, not just in policy.

## Audio

| Rule | Where it is enforced |
|---|---|
| Capture only in sessions the learner explicitly starts (button or Siri) | `ListeningSessionManager.start`; there is no other code path that installs an input tap |
| Visible status the whole time | iOS mic indicator, Live Activity / Dynamic Island, in-app status, bottom accessory on every tab |
| At most the configured window (30, 60, 120 s), in memory | `RollingAudioBuffer` fixed capacity; the hard cap is 120 s regardless of settings |
| Older audio is overwritten continuously | Ring buffer semantics, unit tested |
| Erased on stop, on failure, and on cancelled starts | `buffer.clear()` zeroes every sample; called from `stop()` and capture failure paths |
| Never written to disk, never uploaded, never in backups | The buffer is never serialised; the only thing transcribed audio becomes is text |
| Practice recordings (pronunciation, tutor) are discarded after on-device transcription | `UtteranceRecorder` clears its own buffer in `defer` |
| Languify's own speech is not captured | Capture is suppressed while the synthesizer speaks |
| The learner's question is not analysed as conversation | Snapshot excludes audio after the time the question was asked |

## Text sent to the cloud

- Only after the learner turns on **Allow AI explanations** (off by default, explained during onboarding and in Settings). Without it, Languify still transcribes on device and shows the text, but makes no network request.
- Only the transcript of the requested window, plus the question, a 1 to 5 self-rating, and up to 20 recently saved romanised words for context.
- Silence or empty transcripts never trigger a request.
- Transport is HTTPS (ATS); local networking is allowed only for development against a LAN backend.
- The backend validates and size-limits input, never logs request bodies (only latency, status and language), and stores no transcripts. It stores per-subject daily usage counts and the subscription tier.
- The AI provider is Anthropic's API, which does not train on API inputs under its commercial terms and may retain them for a limited period for trust and safety. Zero data retention is available from Anthropic for eligible organisations and should be requested before launch. The in-app wording says exactly this.

## What is stored

On device: vocabulary entries with one context sentence each, review history, preferences, skill profile, daily usage counts, tokens in the Keychain. Session answers ("This session" list) are memory-only and cleared when the session stops.

Server: usage counters per day and the verified subscription tier per subject. Nothing else.

## Learner controls

Settings, Profile:

- Allow or revoke AI explanations
- Proactive suggestions (off by default, Premium; analyses only the final rewind window once, at session end)
- iCloud sync on or off (audio is never synced; there is none to sync)
- Export all learning data as JSON (share sheet)
- Delete learning history (keeps words)
- Delete all data: local store, preferences, profile, Keychain identity, and server-side records via `DELETE /v1/account`
- Edit or delete any word

## Consent from other people

The app shows guidance during onboarding, on the Live Rewind screen and in Privacy settings: tell the people you are talking with that you use a listening app, and follow local recording laws, some of which require all-party consent even for audio that is never saved. Languify does not assume one person's permission covers everyone.

## App Store privacy details (draft)

- Data linked to the user: Purchases (subscription status), Identifiers (Apple user id, only if signed in), Usage data (daily counts).
- Data not collected: audio, contacts, location, browsing.
- Data used to provide functionality only. No tracking. No third-party advertising SDKs.
- "Other user content": transcribed text is processed (not stored) to provide explanations; declare it per Apple's guidance.
