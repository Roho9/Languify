import Foundation

/// Explicit states of a Live Rewind listening session.
public enum ListeningSessionState: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case listening
    /// The user paused capture; the buffer is kept.
    case paused
    /// A rewind question is being answered. Capture continues.
    case processing
    /// The system took the microphone (Siri, a phone call). The buffer is kept
    /// so questions about pre-interruption speech still work.
    case interrupted(InterruptionReason)
    case failed(ListeningFailure)
    case stopping

    /// True while the microphone is, or is about to be, delivering audio.
    public var isCapturing: Bool {
        switch self {
        case .listening, .processing: true
        default: false
        }
    }

    /// True while a session exists, i.e. the buffer may hold audio.
    public var isSessionActive: Bool {
        switch self {
        case .listening, .processing, .paused, .interrupted, .starting: true
        default: false
        }
    }
}

public enum InterruptionReason: String, Equatable, Sendable {
    case systemAudio
    case routeLost
    case mediaServicesReset
}

public enum ListeningFailure: Equatable, Sendable, Error {
    case microphonePermissionDenied
    case speechModelUnavailable
    case audioEngineFailed(String)
    case cannotStartInBackground

    public var userMessage: String {
        switch self {
        case .microphonePermissionDenied:
            "Languify needs microphone access to listen. You can allow it in Settings."
        case .speechModelUnavailable:
            "The on-device speech model for this language isn't installed yet."
        case .audioEngineFailed(let detail):
            "The microphone couldn't start (\(detail))."
        case .cannotStartInBackground:
            "iOS only lets Languify start listening while the app is open or from Siri. Open Languify and tap Start Listening."
        }
    }
}

/// Events that drive `ListeningStateMachine`.
public enum ListeningEvent: Equatable, Sendable {
    case startRequested
    case permissionGranted
    case permissionDenied
    case captureStarted
    case captureFailed(ListeningFailure)
    case pauseRequested
    case resumeRequested
    case processingBegan
    case processingEnded
    case interruptionBegan(InterruptionReason)
    case interruptionEnded
    case stopRequested
    case stopped
}

/// Pure transition function for the listening session. Invalid events are
/// rejected (return nil) rather than silently producing an inconsistent state.
public struct ListeningStateMachine: Sendable {
    public private(set) var state: ListeningSessionState = .idle

    public init(state: ListeningSessionState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: ListeningEvent) -> ListeningSessionState? {
        guard let next = Self.transition(from: state, on: event) else { return nil }
        state = next
        return next
    }

    public static func transition(from state: ListeningSessionState, on event: ListeningEvent) -> ListeningSessionState? {
        switch (state, event) {
        case (.idle, .startRequested), (.failed, .startRequested):
            return .requestingPermission
        case (.requestingPermission, .permissionGranted):
            return .starting
        case (.requestingPermission, .permissionDenied):
            return .failed(.microphonePermissionDenied)
        case (.starting, .captureStarted):
            return .listening
        case (.starting, .captureFailed(let failure)),
             (.listening, .captureFailed(let failure)),
             (.processing, .captureFailed(let failure)),
             (.interrupted, .captureFailed(let failure)),
             (.paused, .captureFailed(let failure)):
            return .failed(failure)
        case (.listening, .pauseRequested):
            return .paused
        case (.paused, .resumeRequested):
            return .starting
        case (.listening, .processingBegan):
            return .processing
        case (.processing, .processingEnded):
            return .listening
        // Questions can be answered from the kept buffer while paused or interrupted.
        case (.paused, .processingBegan), (.interrupted, .processingBegan):
            return state
        case (.paused, .processingEnded), (.interrupted, .processingEnded):
            return state
        case (.listening, .interruptionBegan(let reason)),
             (.processing, .interruptionBegan(let reason)),
             (.starting, .interruptionBegan(let reason)):
            return .interrupted(reason)
        case (.interrupted, .interruptionEnded):
            return .starting
        case (.interrupted, .interruptionBegan(let reason)):
            return .interrupted(reason)
        case (.requestingPermission, .stopRequested),
             (.starting, .stopRequested),
             (.listening, .stopRequested),
             (.processing, .stopRequested),
             (.paused, .stopRequested),
             (.interrupted, .stopRequested):
            return .stopping
        case (.stopping, .stopped), (.failed, .stopped), (.failed, .stopRequested):
            return .idle
        default:
            return nil
        }
    }
}
