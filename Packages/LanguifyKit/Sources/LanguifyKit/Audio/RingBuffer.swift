import Foundation

/// A fixed-capacity FIFO that overwrites its oldest elements once full.
///
/// Storage is allocated once at init, so appending never allocates. This is
/// what keeps Live Rewind's memory bounded regardless of session length.
public struct RingBuffer<Element> {
    private var storage: [Element]
    private var writeIndex = 0
    public private(set) var count = 0
    public let capacity: Int
    private let zero: Element

    public init(capacity: Int, zero: Element) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        self.zero = zero
        self.storage = Array(repeating: zero, count: capacity)
    }

    public var isEmpty: Bool { count == 0 }
    public var isFull: Bool { count == capacity }

    public mutating func append(_ element: Element) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = Swift.min(count + 1, capacity)
    }

    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == Element {
        for element in elements { append(element) }
    }

    /// The most recent `n` elements in chronological order (oldest first).
    public func suffix(_ n: Int) -> [Element] {
        let n = Swift.max(0, Swift.min(n, count))
        guard n > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(n)
        var index = (writeIndex - n + capacity) % capacity
        for _ in 0..<n {
            result.append(storage[index])
            index = (index + 1) % capacity
        }
        return result
    }

    public func elements() -> [Element] { suffix(count) }

    /// Overwrites every slot with `zero` so no old audio lingers in memory.
    public mutating func removeAll() {
        for i in storage.indices { storage[i] = zero }
        writeIndex = 0
        count = 0
    }
}
