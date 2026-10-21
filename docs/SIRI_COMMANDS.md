# Siri and Shortcuts

These App Shortcuts are registered automatically on install (verified in the built app's `Metadata.appintents`). iOS requires the app name in every phrase. Siri also accepts close variations, but matching is decided by Siri, so the exact phrases below are the reliable ones.

| Say | Intent | What happens |
|---|---|---|
| "Start Languify" / "Start listening with Languify" / "Turn on Languify" | `StartListeningIntent` (`AudioRecordingIntent`) | Starts a session and its Live Activity. Works from the lock screen once mic permission was granted in the app. |
| "Stop Languify" / "Stop listening with Languify" / "Turn off Languify" | `StopListeningIntent` | Stops capture and erases the buffer. Same as the Live Activity's Stop button. |
| "Ask Languify what that word meant" (also "what that last word meant", "what that word means") | `AskWordIntent` | Explains the latest unfamiliar word. If several words are plausible, Siri asks "Which word? A or B?" and you answer in the same exchange. |
| "Ask Languify what that sentence meant" | `AskSentenceIntent` | Natural English meaning of the last sentence. |
| "Ask Languify what was just said" / "Ask Languify to explain that" | `ExplainRecentSpeechIntent` | Gist of the recent conversation. |
| "Ask Languify how to respond" / "how to reply" / "what I should say" | `HowToRespondIntent` | One to three natural replies in the heritage language. |
| "Tell Languify which word" | `AnswerClarificationIntent` | Answers a pending clarification (valid for 2 minutes). |

The **Ask Languify** action (free-form question) is available in the Shortcuts app and can be bound to the Action button or Back Tap.

## How a hands-free question works

1. A session is running (the Live Activity shows it). The iPhone microphone fills the rolling buffer.
2. You say "Siri, ask Languify what that word meant". Siri takes the microphone; Languify's capture pauses, but the buffer, which holds the speech from just before, is kept.
3. The intent runs inside Languify, transcribes the window on device, gets the explanation, and returns a one or two sentence dialog. Siri speaks it through your AirPods (or the current output).
4. The word is saved to the journal. When Siri finishes, capture resumes if iOS allows it.

## Limitations

- Third-party apps cannot change "Hey Siri", add a wake word, or listen without an explicit session.
- Siri's own recording and transcription are not available to apps. "Sounds like" text arrives through Siri's English dictation.
- The first use of the microphone must be approved inside the app; Siri cannot show that prompt.
- If Live Activities are turned off for Languify, iOS stops recordings started from Siri. Start from the app instead.
- Everything in this file except metadata registration needs confirmation on a physical iPhone (see TESTING_CHECKLIST.md, section B).
