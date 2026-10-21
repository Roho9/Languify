import AVFoundation
import Foundation

/// Audio session events the listening session reacts to.
nonisolated enum AudioSessionEvent: Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// A private output (AirPods, wired headphones) went away. Any speech in
    /// progress must stop so it does not continue out of the speaker.
    case privateOutputLost
    case routeChanged
    case mediaServicesReset
}

/// Configures `AVAudioSession` for Live Rewind and reports interruptions and
/// route changes.
///
/// Routing decision: the category allows Bluetooth A2DP but not HFP. With
/// AirPods connected, iOS then plays answers through the AirPods in high
/// quality while recording from the iPhone's own microphone. That is what we
/// want: AirPods microphones beam-form toward the wearer and would mostly
/// capture the user, not the family members speaking across the table.
@Observable
final class AudioSessionController {
    private(set) var headphonesConnected = false
    private(set) var outputName = "iPhone"
    private(set) var inputName = "iPhone Microphone"

    private var observers: [NSObjectProtocol] = []
    private var subscribers: [UUID: AsyncStream<AudioSessionEvent>.Continuation] = [:]

    init() {
        observe()
        refreshRoute()
    }

    /// A new stream of session events. Each subscriber gets every event.
    func events() -> AsyncStream<AudioSessionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioSessionEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    private func broadcast(_ event: AudioSessionEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    func configureForListening() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.1)
        try session.setActive(true)
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtIn)
        }
        refreshRoute()
    }

    /// Short-utterance capture for pronunciation and tutor practice. Uses the
    /// same routing so feedback plays in AirPods when they are connected.
    func configureForPractice() throws {
        try configureForListening()
    }

    func configureForPlaybackOnly() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        refreshRoute()
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.audio.error("Session deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshRoute()
    }

    func refreshRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        headphonesConnected = route.outputs.contains { Self.privatePorts.contains($0.portType) }
        outputName = route.outputs.first?.portName ?? "iPhone"
        inputName = route.inputs.first?.portName ?? "No microphone"
    }

    /// Outputs considered private to the listener. Bluetooth A2DP could in
    /// principle be a speaker or car; iOS gives no reliable way to tell, so the
    /// Settings screen explains this.
    nonisolated static let privatePorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]

    private func observe() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
                switch type {
                case .began:
                    self.broadcast(.interruptionBegan)
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
                    self.broadcast(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                @unknown default:
                    break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let lostPrivate = previous?.outputs.contains { Self.privatePorts.contains($0.portType) } ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshRoute()
                if reasonValue == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, lostPrivate {
                    self.broadcast(.privateOutputLost)
                } else {
                    self.broadcast(.routeChanged)
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.broadcast(.mediaServicesReset)
            }
        })
    }
}
