import AVFoundation
import Foundation
import LanguifyKit
import Observation

/// Records one spoken attempt (pronunciation, tutor turn, assessment) and
/// transcribes it on device. The recording lives only in memory and is
/// discarded after transcription.
///
/// If a Live Rewind session is capturing, it is paused for the attempt and
/// resumed afterwards, so the learner's practice never enters the rewind
/// buffer.
@Observable
final class UtteranceRecorder {
    enum State: Equatable { case idle, recording, transcribing }

    private(set) var state: State = .idle
    private(set) var levels: [Float] = Array(repeating: 0, count: 32)
    private(set) var errorMessage: String?

    private let services: AppServices
    private let capture = AudioCaptureEngine()
    private let buffer = RollingAudioBuffer(capacitySeconds: 20)
    private var pausedListening = false

    init(services: AppServices) {
        self.services = services
    }

    func start() async {
        guard state == .idle else { return }
        errorMessage = nil
        if AVAudioApplication.shared.recordPermission != .granted {
            guard await AVAudioApplication.requestRecordPermission() else {
                errorMessage = ListeningFailure.microphonePermissionDenied.userMessage
                return
            }
        }
        if services.listening.state.isCapturing {
            services.listening.pause()
            pausedListening = true
        }
        services.delivery.stop()
        buffer.clear()
        do {
            try services.audioSession.configureForPractice()
            try capture.start(into: buffer) { [weak self] level in
                Task { @MainActor in self?.push(level) }
            }
            state = .recording
        } catch {
            errorMessage = "The microphone couldn't start."
            restoreListening()
        }
    }

    /// Stops recording and returns what the recogniser heard, or nil.
    func stopAndTranscribe() async -> TranscriptSegment? {
        guard state == .recording else { return nil }
        capture.stop()
        state = .transcribing
        defer {
            buffer.clear()
            state = .idle
            levels = Array(repeating: 0, count: levels.count)
            restoreListening()
        }
        let snapshot = buffer.snapshot(lastSeconds: buffer.capacitySeconds)
        guard snapshot.duration > 0.3, snapshot.rms >= LiveRewindService.silenceThreshold else {
            errorMessage = "I didn't hear anything. Try again a little closer to the phone."
            return nil
        }
        do {
            let segments = try await services.transcriber.transcribe(snapshot, localeIdentifier: services.preferences.language.configuration.speechLocaleIdentifier)
            let text = segments.map(\.text).joined(separator: " ")
            let confidences = segments.compactMap(\.confidence)
            return TranscriptSegment(
                text: text,
                start: 0,
                end: snapshot.duration,
                confidence: confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count),
                alternatives: segments.first?.alternatives ?? []
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Speech recognition failed."
            return nil
        }
    }

    func cancel() {
        capture.stop()
        buffer.clear()
        state = .idle
        restoreListening()
    }

    private func restoreListening() {
        if pausedListening {
            pausedListening = false
            services.listening.resume()
        } else if !services.listening.state.isSessionActive {
            services.audioSession.deactivate()
        }
    }

    private func push(_ level: Float) {
        guard state == .recording else { return }
        let db = 20 * log10(max(level, 1e-6))
        levels.removeFirst()
        levels.append(max(0, min(1, (db + 60) / 60)))
    }
}
