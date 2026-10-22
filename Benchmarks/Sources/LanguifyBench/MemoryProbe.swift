import Foundation

/// Measures one buffer configuration in a fresh process so malloc reuse from
/// earlier work cannot hide allocations. Prints a single JSON line.
enum MemoryProbe {
    struct Result: Codable {
        let implementation: String
        let capacitySeconds: Double
        let footprintBeforeBytes: UInt64
        let footprintAfterFillBytes: UInt64
        let footprintAfterSnapshotBytes: UInt64
        let footprintAfterClearBytes: UInt64
        let fillDeltaBytes: Int64
        let peakDuringSnapshotDeltaBytes: Int64
    }

    static func run(implementation: String, seconds: Double) {
        let all: [any RollingStore.Type] = [ShippingStore.self, BaselineV1Store.self, NaiveAppendTrimStore.self, Float32RingStore.self]
        guard let type = all.first(where: { $0.name == implementation }) else { print("{}"); return }
        func go<S: RollingStore>(_ s: S.Type) -> Result {
            let chunk = BufferBench.makeSine(1_600, offset: 3)
            let before = physFootprint()
            let store = S(sampleRate: 16_000, capacitySeconds: seconds)
            var t = 0.0
            chunk.withUnsafeBufferPointer { p in
                for _ in 0..<(Int(seconds * 10) + 50) { t += 0.1; store.append(p, at: t) }
            }
            let afterFill = physFootprint()
            var snap = store.snapshot(lastSeconds: seconds, endingAt: nil)
            let afterSnap = physFootprint()
            blackHole(snap)
            snap = []
            store.clear()
            let afterClear = physFootprint()
            blackHole(store)
            return Result(
                implementation: s.name, capacitySeconds: seconds,
                footprintBeforeBytes: before, footprintAfterFillBytes: afterFill,
                footprintAfterSnapshotBytes: afterSnap, footprintAfterClearBytes: afterClear,
                fillDeltaBytes: Int64(afterFill) - Int64(before),
                peakDuringSnapshotDeltaBytes: Int64(afterSnap) - Int64(before)
            )
        }
        let r = go(type)
        let data = try! JSONEncoder().encode(r)
        print(String(decoding: data, as: UTF8.self))
    }

    /// Spawns one probe process per implementation and duration.
    static func runAll() throws {
        let exe = CommandLine.arguments[0]
        var results: [Result] = []
        for impl in ["baseline_v1_int16_ring", "shipping", "float32_ring", "naive_append_trim_float"] {
            for seconds in BufferBench.durations {
                for _ in 0..<3 {
                    let out = shell("'\(exe)' memprobe-one \(impl) \(Int(seconds))")
                    if let r = try? JSONDecoder().decode(Result.self, from: Data(out.utf8)) { results.append(r) }
                }
            }
        }
        let meta = RunMetadata.capture(benchmark: "memory", environment: "macOS host process phys_footprint; one fresh process per measurement; not an iPhone measurement")
        struct Report: Codable { let metadata: RunMetadata; let results: [Result] }
        for r in results {
            print(String(format: "%-26@ %4.0fs  fill %+8.1f KB  with snapshot %+8.1f KB  after clear %+8.1f KB", r.implementation as NSString, r.capacitySeconds, Double(r.fillDeltaBytes) / 1024, Double(r.peakDuringSnapshotDeltaBytes) / 1024, (Double(r.footprintAfterClearBytes) - Double(r.footprintBeforeBytes)) / 1024))
        }
        print("Wrote \(try writeResult(Report(metadata: meta, results: results), category: "memory", runID: meta.runID).path)")
    }
}
