import Foundation
import Synchronization

/// Thread-safe rolling buffer of mono PCM audio used by Live Rewind.
///
/// Samples are stored as 16-bit integers at a fixed sample rate, so 120 s at
/// 16 kHz costs about 3.8 MB. The audio render thread appends through
/// `append(_:at:)`; any other thread may take a snapshot. All storage is zeroed
/// on `clear()`.
public final class RollingAudioBuffer: Sendable {
    /// Upper bound on how much audio a buffer can ever hold, independent of the
    /// user's rewind setting.
    public static let maximumSeconds: Double = 120

    public let sampleRate: Double
    public let capacitySeconds: Double

    private struct State {
        var ring: RingBuffer<Int16>
        var lastAppendTime: TimeInterval?
        var totalFramesWritten: Int64 = 0
    }

    private let state: Mutex<State>

    public init(sampleRate: Double = 16_000, capacitySeconds: Double) {
        precondition(sampleRate > 0)
        let seconds = min(max(capacitySeconds, 1), Self.maximumSeconds)
        self.sampleRate = sampleRate
        self.capacitySeconds = seconds
        let frames = Int((seconds * sampleRate).rounded(.up))
        self.state = Mutex(State(ring: RingBuffer(capacity: frames, zero: 0)))
    }

    /// Appends float samples in [-1, 1]. `time` is a monotonic timestamp for
    /// the end of this chunk (e.g. `ProcessInfo.systemUptime`).
    public func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) {
        state.withLock { state in
            for sample in samples {
                let clamped = max(-1, min(1, sample))
                state.ring.append(Int16(clamped * Float(Int16.max)))
            }
            state.lastAppendTime = time
            state.totalFramesWritten += Int64(samples.count)
        }
    }

    public func append(_ samples: [Float], at time: TimeInterval) {
        samples.withUnsafeBufferPointer { append($0, at: time) }
    }

    /// Seconds of audio currently held.
    public var bufferedDuration: Double {
        state.withLock { Double($0.ring.count) / sampleRate }
    }

    public var lastAppendTime: TimeInterval? {
        state.withLock { $0.lastAppendTime }
    }

    public var totalFramesWritten: Int64 {
        state.withLock { $0.totalFramesWritten }
    }

    /// Returns up to `seconds` of the most recent audio as floats, oldest first.
    ///
    /// When `endingAt` is earlier than the newest sample, audio captured after
    /// that moment is excluded. This keeps the user's own question (spoken
    /// after tapping Ask) out of the analysed window. Timing assumes the newest
    /// samples are contiguous, which holds because an interruption stops
    /// appends rather than inserting silence.
    public func snapshot(lastSeconds seconds: Double, endingAt endTime: TimeInterval? = nil) -> AudioSnapshot {
        state.withLock { state in
            var dropFrames = 0
            if let endTime, let last = state.lastAppendTime, endTime < last {
                dropFrames = Int(((last - endTime) * sampleRate).rounded())
            }
            let available = max(0, state.ring.count - dropFrames)
            let wanted = min(available, Int((max(0, seconds) * sampleRate).rounded()))
            let recent = state.ring.suffix(min(state.ring.count, wanted + dropFrames))
            let window = recent.prefix(wanted)
            let samples = window.map { Float($0) / Float(Int16.max) }
            return AudioSnapshot(samples: samples, sampleRate: sampleRate)
        }
    }

    /// Discards and zeroes all audio. Called when a session stops, fails or is
    /// cancelled so nothing outlives its purpose.
    public func clear() {
        state.withLock { state in
            state.ring.removeAll()
            state.lastAppendTime = nil
        }
    }
}

/// An immutable copy of buffered audio handed to speech recognition.
public struct AudioSnapshot: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: Double { Double(samples.count) / sampleRate }
    public var isEmpty: Bool { samples.isEmpty }

    /// Root-mean-square level, used to skip transcription of pure silence.
    public var rms: Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }
}
