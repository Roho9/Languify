import Accelerate
import Foundation
import Synchronization

/// Thread-safe rolling buffer of mono PCM audio used by Live Rewind.
///
/// Samples are stored as 16-bit integers at a fixed sample rate, so 120 s at
/// 16 kHz costs about 3.8 MB. The audio tap thread appends through
/// `append(_:at:)`; any other thread may take a snapshot. All storage is zeroed
/// on `clear()`.
///
/// Appends and snapshots copy whole contiguous segments with Accelerate
/// (vDSP) instead of looping per sample. This matters less for raw CPU than
/// for lock hold time: a snapshot runs under the same lock the audio thread
/// needs, so a slow snapshot would stall capture. See
/// docs/benchmarks/ExperimentLog.md, experiment A.
public final class RollingAudioBuffer: Sendable {
    /// Upper bound on how much audio a buffer can ever hold, independent of the
    /// user's rewind setting.
    public static let maximumSeconds: Double = 120

    /// Float to Int16 scale. Symmetric, so -1 and 1 map to -32767 and 32767.
    private static let scale: Float = 32_767

    public let sampleRate: Double
    public let capacitySeconds: Double
    private let capacity: Int

    private struct State {
        var storage: [Int16]
        /// Conversion scratch, reused across appends so the audio thread
        /// never allocates in steady state.
        var scratch: [Float]
        var writeIndex = 0
        var count = 0
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
        self.capacity = frames
        self.state = Mutex(State(storage: Array(repeating: 0, count: frames), scratch: Array(repeating: 0, count: 8_192)))
    }

    /// Appends float samples in [-1, 1]. `time` is a monotonic timestamp for
    /// the end of this chunk (e.g. `ProcessInfo.systemUptime`).
    public func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) {
        guard let base = samples.baseAddress, samples.count > 0 else { return }
        let capacity = self.capacity
        // Only the newest `capacity` frames of an oversized chunk can survive.
        let n = min(samples.count, capacity)
        let source = base + (samples.count - n)
        state.withLock { state in
            if state.scratch.count < n { state.scratch = Array(repeating: 0, count: n) }
            state.scratch.withUnsafeMutableBufferPointer { scratch in
                var scale = Self.scale
                var low: Float = -Self.scale, high: Float = Self.scale
                vDSP_vsmul(source, 1, &scale, scratch.baseAddress!, 1, vDSP_Length(n))
                vDSP_vclip(scratch.baseAddress!, 1, &low, &high, scratch.baseAddress!, 1, vDSP_Length(n))
                let write = state.writeIndex
                let first = min(n, capacity - write)
                state.storage.withUnsafeMutableBufferPointer { dst in
                    // Round to nearest rather than truncate: halves the worst-case quantisation error.
                    vDSP_vfixr16(scratch.baseAddress!, 1, dst.baseAddress! + write, 1, vDSP_Length(first))
                    if n > first {
                        vDSP_vfixr16(scratch.baseAddress! + first, 1, dst.baseAddress!, 1, vDSP_Length(n - first))
                    }
                }
            }
            state.writeIndex = (state.writeIndex + n) % capacity
            state.count = min(state.count + n, capacity)
            state.lastAppendTime = time
            state.totalFramesWritten += Int64(samples.count)
        }
    }

    public func append(_ samples: [Float], at time: TimeInterval) {
        samples.withUnsafeBufferPointer { append($0, at: time) }
    }

    /// Seconds of audio currently held.
    public var bufferedDuration: Double {
        state.withLock { Double($0.count) / sampleRate }
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
        let capacity = self.capacity
        let samples: [Float] = state.withLock { state in
            var dropFrames = 0
            if let endTime, let last = state.lastAppendTime, endTime < last {
                dropFrames = min(state.count, Int(((last - endTime) * sampleRate).rounded()))
            }
            let available = state.count - dropFrames
            let wanted = min(available, Int((max(0, seconds) * sampleRate).rounded()))
            guard wanted > 0 else { return [] }
            let end = (state.writeIndex - dropFrames + capacity) % capacity
            let start = (end - wanted + capacity) % capacity
            return state.storage.withUnsafeBufferPointer { src in
                [Float](unsafeUninitializedCapacity: wanted) { out, initialized in
                    let first = min(wanted, capacity - start)
                    vDSP_vflt16(src.baseAddress! + start, 1, out.baseAddress!, 1, vDSP_Length(first))
                    if wanted > first {
                        vDSP_vflt16(src.baseAddress!, 1, out.baseAddress! + first, 1, vDSP_Length(wanted - first))
                    }
                    var divisor = Self.scale
                    vDSP_vsdiv(out.baseAddress!, 1, &divisor, out.baseAddress!, 1, vDSP_Length(wanted))
                    initialized = wanted
                }
            }
        }
        return AudioSnapshot(samples: samples, sampleRate: sampleRate)
    }

    /// Discards and zeroes all audio. Called when a session stops, fails or is
    /// cancelled so nothing outlives its purpose.
    public func clear() {
        state.withLock { state in
            state.storage.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            state.scratch.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            state.writeIndex = 0
            state.count = 0
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
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }
}
