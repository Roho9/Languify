# Real-device validation checklist

Automated tests cover logic, the rewind pipeline with test doubles, the backend and UI journeys in the Simulator. Everything below needs real hardware and **has not been performed yet**. Record device, iOS version, AirPods model, result and notes for each row. Do not mark a row passed without running it.

Device: ______ iOS: ______ AirPods: ______ Build: ______ Date: ______

## A. Capture and buffer

| # | Step | Expected | Result |
|---|---|---|---|
| A1 | Start Listening in the app | Orange mic indicator, Live Activity, waveform moves with speech | |
| A2 | Speak for 3 minutes with a 60 s window, then ask "What was just said?" | Answer covers only the last minute | |
| A3 | Start, lock the phone for 2 minutes while someone talks, unlock, ask | Speech from the locked period is answered | |
| A4 | Stop, then ask from the app | "Not listening"; buffer gauge gone | |
| A5 | Change window 60 to 30 s during a session | Gauge caps at 30 s, capture continues | |
| A6 | Background the app, open another app for 5 minutes | Session continues (indicator stays) | |
| A7 | Revoke mic permission in Settings mid-session, return | Session fails cleanly with an explanation | |
| A8 | Memory in Xcode gauges over a 30 minute session | Flat; no growth beyond about 4 MB for audio | |
| A9 | Battery over a 60 minute session (Settings, Battery) | Record % used | |

## B. Siri

| # | Step | Expected | Result |
|---|---|---|---|
| B1 | Locked, app not running: "Siri, start Languify" | Live Activity appears, Siri confirms | |
| B2 | "Siri, stop Languify" | Live Activity ends, buffer cleared | |
| B3 | During a session someone says a sentence with an unusual word; "Siri, ask Languify what that word meant" | Siri speaks the meaning; word saved | |
| B4 | Same for "what that sentence meant" and "how to respond" | Correct kind of answer | |
| B5 | Two unfamiliar words in a row, ask about "that word" | Siri asks which; answering continues in the same exchange | |
| B6 | After B3, keep talking for 30 s, then ask from the app | Capture resumed after Siri (record whether it did) | |
| B7 | Measure time from end of the Siri phrase to the start of the answer | Record seconds; note transcription and explanation ms from Console logs (`app.languify` rewind) | |
| B8 | Live Activities disabled for Languify, then "Siri, start Languify" | Clear failure message, no silent recording | |

## C. AirPods and routing

| # | Step | Expected | Result |
|---|---|---|---|
| C1 | Adaptive mode, AirPods in, ask in app | Answer spoken only in AirPods | |
| C2 | Check Control Center route during a session with AirPods | Input stays iPhone microphone; output AirPods | |
| C3 | Remove both AirPods while an answer is being spoken | Speech stops; nothing plays from the speaker | |
| C4 | Adaptive mode, no headphones | Answer shown on screen only | |
| C5 | Spoken mode, no headphones | Answer through the speaker | |
| C6 | Bluetooth disconnect and reconnect mid-session | Session continues | |

## D. Speech models and languages

| # | Step | Expected | Result |
|---|---|---|---|
| D1 | Download ta-IN, ml-IN, en-IN models in onboarding | Progress shown, all Ready | |
| D2 | Malayalam family conversation, ask about a word | Plausible romanised transcript, correct explanation | |
| D3 | Tamil-English code-switched sentence | English kept, Tamil expression explained | |
| D4 | Airplane mode, ask a question | Transcript shown, offline message, retry works when back online | |
| D5 | Pronunciation practice on 5 saved words | Feedback reflects what was said | |
| D6 | Malayalam pronunciation playback | Note whether an ml-IN voice exists | |

## E. Interruptions

| # | Step | Expected | Result |
|---|---|---|---|
| E1 | Incoming phone call during a session | State "Mic in use by iOS"; questions about earlier speech still work | |
| E2 | Call ends | Capture resumes (or stays interrupted with a clear status) | |
| E3 | Start a voice memo during a session | Interruption handled, no crash | |

## F. Accounts, sync, purchases (paid team)

| # | Step | Expected | Result |
|---|---|---|---|
| F1 | Use as guest, then Sign in with Apple | Usage today carries over | |
| F2 | Enable iCloud sync on two devices, relaunch both | Words appear on both | |
| F3 | Sandbox purchase monthly | Premium immediately; backend `/v1/usage` shows premium | |
| F4 | Restore purchases on a second device | Premium restored | |
| F5 | Delete all data | Journal empty, signed out, server usage gone | |

## G. Accessibility

| # | Step | Expected | Result |
|---|---|---|---|
| G1 | VoiceOver through onboarding, Rewind, a flashcard session | Every control labelled, order sensible | |
| G2 | Largest Dynamic Type size | No clipped text in cards | |
| G3 | Reduce Motion | Waveform does not animate | |
