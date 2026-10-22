import Foundation
import LanguifyKit
import Synchronization

/// Common surface for comparing rolling-buffer designs on identical workloads.
protocol RollingStore: AnyObject {
    static var name: String { get }
    static var bytesPerSample: Int { get }
    init(sampleRate: Double, capacitySeconds: Double)
    func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval)
    func snapshot(lastSeconds: Double, endingAt: TimeInterval?) -> [Float]
    func clear()
    var bufferedDuration: Double { get }
}

// MARK: - Shipping implementation (whatever LanguifyKit currently contains)

final class ShippingStore: RollingStore {
    static let name = "shipping"
    static let bytesPerSample = 2
    let buffer: RollingAudioBuffer
    init(sampleRate: Double, capacitySeconds: Double) {
        buffer = RollingAudioBuffer(sampleRate: sampleRate, capacitySeconds: capacitySeconds)
    }
    func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) { buffer.append(samples, at: time) }
    func snapshot(lastSeconds: Double, endingAt: TimeInterval?) -> [Float] { buffer.snapshot(lastSeconds: lastSeconds, endingAt: endingAt).samples }
    func clear() { buffer.clear() }
    var bufferedDuration: Double { buffer.bufferedDuration }
}

// MARK: - Baseline v1: frozen copy of LanguifyKit's buffer at commit ddebcc0

/// Per-element ring buffer exactly as first shipped: one modulo and one
/// bounds-checked store per sample on append, element-wise copy and map on
/// snapshot, and truncating Float-to-Int16 conversion.
final class BaselineV1Store: RollingStore {
    static let name = "baseline_v1_int16_ring"
    static let bytesPerSample = 2

    struct Ring {
        var storage: [Int16]
        var writeIndex = 0
        var count = 0
        let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
            storage = Array(repeating: 0, count: capacity)
        }

        mutating func append(_ element: Int16) {
            storage[writeIndex] = element
            writeIndex = (writeIndex + 1) % capacity
            count = Swift.min(count + 1, capacity)
        }

        func suffix(_ n: Int) -> [Int16] {
            let n = Swift.max(0, Swift.min(n, count))
            guard n > 0 else { return [] }
            var result: [Int16] = []
            result.reserveCapacity(n)
            var index = (writeIndex - n + capacity) % capacity
            for _ in 0..<n {
                result.append(storage[index])
                index = (index + 1) % capacity
            }
            return result
        }

        mutating func removeAll() {
            for i in storage.indices { storage[i] = 0 }
            writeIndex = 0
            count = 0
        }
    }

    struct State {
        var ring: Ring
        var lastAppendTime: TimeInterval?
    }

    let sampleRate: Double
    private let state: Mutex<State>

    init(sampleRate: Double, capacitySeconds: Double) {
        self.sampleRate = sampleRate
        let seconds = min(max(capacitySeconds, 1), 120)
        state = Mutex(State(ring: Ring(capacity: Int((seconds * sampleRate).rounded(.up)))))
    }

    func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) {
        state.withLock { state in
            for sample in samples {
                let clamped = max(-1, min(1, sample))
                state.ring.append(Int16(clamped * Float(Int16.max)))
            }
            state.lastAppendTime = time
        }
    }

    func snapshot(lastSeconds seconds: Double, endingAt endTime: TimeInterval?) -> [Float] {
        state.withLock { state in
            var dropFrames = 0
            if let endTime, let last = state.lastAppendTime, endTime < last {
                dropFrames = Int(((last - endTime) * sampleRate).rounded())
            }
            let available = max(0, state.ring.count - dropFrames)
            let wanted = min(available, Int((max(0, seconds) * sampleRate).rounded()))
            let recent = state.ring.suffix(min(state.ring.count, wanted + dropFrames))
            return recent.prefix(wanted).map { Float($0) / Float(Int16.max) }
        }
    }

    func clear() {
        state.withLock { state in
            state.ring.removeAll()
            state.lastAppendTime = nil
        }
    }

    var bufferedDuration: Double { state.withLock { Double($0.ring.count) / sampleRate } }
}

// MARK: - Naive append-and-trim

/// The simplest correct design: a growable Float array trimmed from the
/// front. Every trim shifts the whole buffer.
final class NaiveAppendTrimStore: RollingStore {
    static let name = "naive_append_trim_float"
    static let bytesPerSample = 4
    let sampleRate: Double
    let capacity: Int
    private let state: Mutex<(samples: [Float], last: TimeInterval?)>

    init(sampleRate: Double, capacitySeconds: Double) {
        self.sampleRate = sampleRate
        capacity = Int((min(max(capacitySeconds, 1), 120) * sampleRate).rounded(.up))
        state = Mutex(([], nil))
    }

    func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) {
        state.withLock { s in
            s.samples.append(contentsOf: samples)
            let excess = s.samples.count - capacity
            if excess > 0 { s.samples.removeFirst(excess) }
            s.last = time
        }
    }

    func snapshot(lastSeconds seconds: Double, endingAt endTime: TimeInterval?) -> [Float] {
        state.withLock { s in
            var drop = 0
            if let endTime, let last = s.last, endTime < last { drop = Int(((last - endTime) * sampleRate).rounded()) }
            let end = max(0, s.samples.count - drop)
            let start = max(0, end - Int((max(0, seconds) * sampleRate).rounded()))
            return Array(s.samples[start..<end])
        }
    }

    func clear() { state.withLock { $0 = ([], nil) } }
    var bufferedDuration: Double { state.withLock { Double($0.samples.count) / sampleRate } }
}

// MARK: - Float32 ring (no quantisation)

/// Same ring design as shipping but storing Float32, to quantify what Int16
/// storage saves in memory and costs in precision.
final class Float32RingStore: RollingStore {
    static let name = "float32_ring"
    static let bytesPerSample = 4
    let sampleRate: Double
    private let state: Mutex<(storage: [Float], write: Int, count: Int, last: TimeInterval?)>
    let capacity: Int

    init(sampleRate: Double, capacitySeconds: Double) {
        self.sampleRate = sampleRate
        capacity = Int((min(max(capacitySeconds, 1), 120) * sampleRate).rounded(.up))
        state = Mutex((Array(repeating: 0, count: capacity), 0, 0, nil))
    }

    func append(_ samples: UnsafeBufferPointer<Float>, at time: TimeInterval) {
        let capacity = self.capacity
        state.withLock { s in
            var input = samples[...]
            if input.count > capacity { input = input.suffix(capacity) }
            s.storage.withUnsafeMutableBufferPointer { dst in
                let first = min(input.count, capacity - s.write)
                _ = UnsafeMutableBufferPointer(rebasing: dst[s.write..<(s.write + first)]).initialize(from: input.prefix(first))
                let rest = input.count - first
                if rest > 0 { _ = UnsafeMutableBufferPointer(rebasing: dst[0..<rest]).initialize(from: input.suffix(rest)) }
            }
            s.write = (s.write + input.count) % capacity
            s.count = min(s.count + input.count, capacity)
            s.last = time
        }
    }

    func snapshot(lastSeconds seconds: Double, endingAt endTime: TimeInterval?) -> [Float] {
        let capacity = self.capacity
        return state.withLock { s in
            var drop = 0
            if let endTime, let last = s.last, endTime < last { drop = Int(((last - endTime) * sampleRate).rounded()) }
            let available = max(0, s.count - drop)
            let wanted = min(available, Int((max(0, seconds) * sampleRate).rounded()))
            guard wanted > 0 else { return [] }
            let end = (s.write - drop + capacity) % capacity
            let start = (end - wanted + capacity) % capacity
            if start < end || end == 0 && start > 0 {
                let stop = end == 0 ? capacity : end
                return Array(s.storage[start..<stop])
            }
            return Array(s.storage[start..<capacity]) + Array(s.storage[0..<end])
        }
    }

    func clear() {
        state.withLock { s in
            for i in s.storage.indices { s.storage[i] = 0 }
            s.write = 0
            s.count = 0
            s.last = nil
        }
    }

    var bufferedDuration: Double { state.withLock { Double($0.count) / sampleRate } }
}
