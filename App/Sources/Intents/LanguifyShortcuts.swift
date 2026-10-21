import AppIntents

/// Siri phrases. iOS requires the app name in every App Shortcut phrase and
/// matches phrases flexibly, but exact wording is decided by Siri, not us.
/// See docs/SIRI_COMMANDS.md for the verified list and limitations.
struct LanguifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start listening with \(.applicationName)",
                "Turn on \(.applicationName)",
            ],
            shortTitle: "Start Listening",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StopListeningIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop listening with \(.applicationName)",
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Stop Listening",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: AskWordIntent(),
            phrases: [
                "Ask \(.applicationName) what that word meant",
                "Ask \(.applicationName) what that last word meant",
                "Ask \(.applicationName) what that word means",
                "What did that word mean in \(.applicationName)",
            ],
            shortTitle: "That Word",
            systemImageName: "character.bubble"
        )
        AppShortcut(
            intent: AskSentenceIntent(),
            phrases: [
                "Ask \(.applicationName) what that sentence meant",
                "Ask \(.applicationName) what that last sentence meant",
            ],
            shortTitle: "That Sentence",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: ExplainRecentSpeechIntent(),
            phrases: [
                "Ask \(.applicationName) what was just said",
                "Ask \(.applicationName) to explain that",
            ],
            shortTitle: "What Was Said",
            systemImageName: "text.alignleft"
        )
        AppShortcut(
            intent: HowToRespondIntent(),
            phrases: [
                "Ask \(.applicationName) how to respond",
                "Ask \(.applicationName) how to reply",
                "Ask \(.applicationName) what I should say",
            ],
            shortTitle: "How to Reply",
            systemImageName: "arrowshape.turn.up.left"
        )
        AppShortcut(
            intent: AnswerClarificationIntent(),
            phrases: [
                "Tell \(.applicationName) which word",
                "Tell \(.applicationName) which word I meant",
            ],
            shortTitle: "Answer Languify",
            systemImageName: "checkmark.bubble"
        )
    }
}
