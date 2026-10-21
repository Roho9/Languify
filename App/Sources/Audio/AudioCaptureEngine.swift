@preconcurrency import AVFoundation
import Foundation
import LanguifyKit
import Synchronization

enum AudioCaptureError: Error, LocalizedError {
    case noInputAvailable
    case converterUnavailable
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputAvailable: "No microphone input is available"
        case .converterUnavailable: "Audio format conversion is unavailable"
        case .engineStartFailed(let detail): detail
        }
    }
}

/// Captures microphone audio with `AVAudioEngine`, converts it to 16 kHz mono
/// and writes it into a `RollingAudioBuffer`.
///
/// The tap runs on a real-time audio thread, so this type is not main-actor
/// isolated. Mutable state touched from both threads lives behind a `Mutex`.
nonisolated final class AudioCaptureEngine: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private struct TapState {
        var buffer: RollingAudioBuffer?
        var converter: AVAudioConverter?
        var suppressed = false
        var onLevel: (@Sendable (Float) -> Void)?
    }
    private let state = Mutex(TapState())
    private var configObserver: NSObjectProtocol?

    var isRunning: Bool { engine.isRunning }

    /// While true, captured audio is dropped instead of buffered. Set while
    /// Languify is speaking so its own voice never enters the rewind window.
    var isSuppressed: Bool {
        get { state.withLock { $0.suppressed } }
        set { state.withLock { $0.suppressed = newValue } }
    }

    /// Posted when the hardware format changes (e.g. a route change) and the
    /// engine stopped; the owner should restart capture.
    var onConfigurationChange: (@Sendable () -> Void)?

    init() {
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    func start(into buffer: RollingAudioBuffer, onLevel: @escaping @Sendable (Float) -> Void) throws {
        stop()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioCaptureError.noInputAvailable }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else { throw AudioCaptureError.converterUnavailable }

        state.withLock {
            $0.buffer = buffer
            $0.converter = converter
            $0.onLevel = onLevel
        }

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] pcm, _ in
            self?.process(pcm)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        state.withLock {
            $0.buffer = nil
            $0.converter = nil
            $0.onLevel = nil
        }
    }

    /// Runs on the audio thread.
    private func process(_ input: AVAudioPCMBuffer) {
        let (buffer, converter, suppressed, onLevel) = state.withLock { ($0.buffer, $0.converter, $0.suppressed, $0.onLevel) }
        guard let buffer, let converter else { return }

        let ratio = Self.targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        onLevel?(suppressed ? 0 : rms)

        guard !suppressed else { return }
        buffer.append(samples, at: ProcessInfo.processInfo.systemUptime)
    }
}
