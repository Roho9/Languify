import AVFoundation
import Foundation
import LanguifyKit
import Observation
import UIKit

/// Owns a Live Rewind listening session: permission, capture, the rolling
/// buffer, interruptions, the Live Activity and cleanup.
///
/// Background behaviour: with the `audio` background mode, capture that began
/// in the foreground (or from an `AudioRecordingIntent`) continues when the
/// screen locks. iOS shows the orange microphone indicator the whole time.
/// When Siri or a call takes the microphone, capture pauses but the buffer is
/// kept, so questions about speech before the interruption still work.
@Observable
final class ListeningSessionManager {
    private(set) var state: ListeningSessionState = .idle
    private(set) var startedAt: Date?
    /// Recent input levels (0...1) for the waveform. Only real levels are
    /// shown; when not capturing the waveform is flat.
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var lastError: String?

    private var machine = ListeningStateMachine()
    private(set) var buffer: RollingAudioBuffer
    private let capture = AudioCaptureEngine()
    private let audioSession: AudioSessionController
    private let liveActivity = ListeningActivityController()
    private let preferences: PreferencesStore
    private var eventsTask: Task<Void, Never>?

    /// Called when a session ends, before the buffer is cleared, so opt-in
    /// proactive analysis can run on the final window.
    var onSessionWillEnd: ((RollingAudioBuffer) async -> Void)?

    init(audioSession: AudioSessionController, preferences: PreferencesStore) {
        self.audioSession = audioSession
        self.preferences = preferences
        self.buffer = RollingAudioBuffer(capacitySeconds: preferences.preferences.rewindDuration.seconds)
        capture.onConfigurationChange = { [weak self] in
            Task { @MainActor in self?.handleEngineConfigurationChange() }
        }
        eventsTask = Task { [weak self] in
            guard let events = self?.audioSession.events() else { return }
            for await event in events {
                self?.handle(event)
            }
        }
        liveActivity.endAllStale()
    }

    var rewindSeconds: Double { buffer.capacitySeconds }
    var bufferedSeconds: Double { buffer.bufferedDuration }

    // MARK: - Public controls

    /// Starts listening. `fromBackground` is true when launched by Siri: iOS
    /// cannot show a permission prompt then, so permission must already exist.
    func start(fromBackground: Bool = false) async {
        guard transition(.startRequested) else { return }
        lastError = nil

        let granted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            granted = true
        case .undetermined where !fromBackground:
            granted = await AVAudioApplication.requestRecordPermission()
        default:
            granted = false
        }
        guard granted else {
            transition(.permissionDenied)
            lastError = ListeningFailure.microphonePermissionDenied.userMessage
            return
        }
        transition(.permissionGranted)
        beginCapture(isResume: false)
    }

    func stop() async {
        guard state.isSessionActive || state == .requestingPermission else {
            if case .failed = state { transition(.stopRequested) }
            return
        }
        transition(.stopRequested)
        capture.stop()
        if let onSessionWillEnd { await onSessionWillEnd(buffer) }
        buffer.clear()
        liveActivity.end()
        audioSession.deactivate()
        startedAt = nil
        levels = Array(repeating: 0, count: levels.count)
        transition(.stopped)
        Log.audio.info("Session stopped; buffer cleared")
    }

    func pause() {
        guard transition(.pauseRequested) else { return }
        capture.stop()
        levels = Array(repeating: 0, count: levels.count)
        liveActivity.update(status: .paused)
    }

    func resume() {
        guard transition(.resumeRequested) else { return }
        beginCapture(isResume: true)
    }

    /// Marks a question in progress (drives UI and the Live Activity).
    func beginProcessing() {
        transition(.processingBegan)
        liveActivity.update(status: .processing)
    }

    func endProcessing(answer: String?) {
        transition(.processingEnded)
        liveActivity.update(status: activityStatus, lastAnswer: answer.map { .some($0) })
    }

    /// Prevents Languify's own speech from entering the buffer.
    func setCaptureSuppressed(_ suppressed: Bool) {
        capture.isSuppressed = suppressed
    }

    /// Applies a new rewind duration. Keeps the most recent audio that fits.
    func applyRewindDuration(_ duration: RewindDuration) {
        guard duration.seconds != buffer.capacitySeconds else { return }
        let resized = RollingAudioBuffer(capacitySeconds: duration.seconds)
        let keep = buffer.snapshot(lastSeconds: duration.seconds)
        if !keep.isEmpty { resized.append(keep.samples, at: buffer.lastAppendTime ?? ProcessInfo.processInfo.systemUptime) }
        buffer.clear()
        buffer = resized
        if state.isCapturing {
            beginCapture(isResume: true)
        }
        liveActivity.update(status: activityStatus, rewindSeconds: duration.rawValue)
    }

    // MARK: - Internals

    private func beginCapture(isResume: Bool) {
        do {
            try audioSession.configureForListening()
            try capture.start(into: buffer) { [weak self] level in
                Task { @MainActor in self?.pushLevel(level) }
            }
            if !isResume || startedAt == nil {
                startedAt = Date()
                liveActivity.start(
                    languageName: preferences.language.displayName,
                    rewindSeconds: Int(buffer.capacitySeconds),
                    startedAt: startedAt ?? Date()
                )
            } else {
                liveActivity.update(status: .listening)
            }
            transition(.captureStarted)
            Log.audio.info("Capture started (resume: \(isResume, privacy: .public))")
        } catch {
            let failure: ListeningFailure
            if UIApplication.shared.applicationState == .background, !isResume {
                failure = .cannotStartInBackground
            } else {
                failure = .audioEngineFailed(error.localizedDescription)
            }
            lastError = failure.userMessage
            capture.stop()
            transition(.captureFailed(failure))
            liveActivity.end()
            buffer.clear()
            Log.audio.error("Capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            guard state.isCapturing || state == .starting else { return }
            capture.stop()
            transition(.interruptionBegan(.systemAudio))
            levels = Array(repeating: 0, count: levels.count)
            liveActivity.update(status: .interrupted)
            Log.audio.info("Interrupted; buffer kept (\(self.buffer.bufferedDuration, privacy: .public)s)")
        case .interruptionEnded(let shouldResume):
            guard case .interrupted = state else { return }
            if shouldResume {
                transition(.interruptionEnded)
                beginCapture(isResume: true)
            } else {
                Log.audio.info("Interruption ended without resume permission; staying interrupted")
            }
        case .mediaServicesReset:
            guard state.isSessionActive else { return }
            capture.stop()
            transition(.interruptionBegan(.mediaServicesReset))
            transition(.interruptionEnded)
            beginCapture(isResume: true)
        case .privateOutputLost, .routeChanged:
            break
        }
    }

    private func handleEngineConfigurationChange() {
        guard state.isCapturing else { return }
        Log.audio.info("Engine configuration changed; restarting capture")
        beginCapture(isResume: true)
    }

    private func pushLevel(_ level: Float) {
        guard state.isCapturing else { return }
        // Map RMS to a perceptual 0...1 range (about -60 dB to 0 dB).
        let db = 20 * log10(max(level, 1e-6))
        let normalized = max(0, min(1, (db + 60) / 60))
        levels.removeFirst()
        levels.append(normalized)
    }

    private var activityStatus: ListeningActivityAttributes.Status {
        switch state {
        case .paused: .paused
        case .interrupted: .interrupted
        case .processing: .processing
        default: .listening
        }
    }

    @discardableResult
    private func transition(_ event: ListeningEvent) -> Bool {
        guard let next = machine.handle(event) else {
            Log.audio.debug("Ignored event in state")
            return false
        }
        state = next
        return true
    }
}

/// Lets intents compiled into the shared Live Activity file reach the app's
/// session without the widget extension linking app code.
enum ListeningIntentBridge {
    static weak var manager: ListeningSessionManager?

    static func stop() async -> Bool {
        guard let manager, manager.state.isSessionActive else { return false }
        await manager.stop()
        return true
    }
}
