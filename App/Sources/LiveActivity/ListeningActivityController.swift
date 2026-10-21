@preconcurrency import ActivityKit
import Foundation

/// Starts, updates and ends the listening Live Activity.
final class ListeningActivityController {
    private var activity: Activity<ListeningActivityAttributes>?

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(languageName: String, rewindSeconds: Int, startedAt: Date) {
        endAllStale()
        guard areActivitiesEnabled else {
            Log.audio.notice("Live Activities disabled; listening indicator limited to the system mic indicator")
            return
        }
        let state = ListeningActivityAttributes.ContentState(status: .listening, rewindSeconds: rewindSeconds, startedAt: startedAt, lastAnswer: nil)
        do {
            activity = try Activity.request(
                attributes: ListeningActivityAttributes(languageName: languageName),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            Log.audio.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(status: ListeningActivityAttributes.Status, rewindSeconds: Int? = nil, lastAnswer: String?? = nil) {
        guard let activity else { return }
        var state = activity.content.state
        state.status = status
        if let rewindSeconds { state.rewindSeconds = rewindSeconds }
        if let lastAnswer { state.lastAnswer = lastAnswer.map { String($0.prefix(90)) } }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ends activities left over from a previous process (e.g. after a crash),
    /// so a stale "Listening" indicator is never shown.
    func endAllStale() {
        for stale in Activity<ListeningActivityAttributes>.activities where stale.id != activity?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
