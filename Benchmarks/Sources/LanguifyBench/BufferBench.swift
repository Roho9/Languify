import Foundation
import LanguifyKit

/// Live Rewind buffer benchmarks: performance, memory, boundary correctness
/// and time-compressed sustained sessions. Workload mirrors the app: 16 kHz
/// mono float chunks as produced by the AVAudioEngine tap after conversion.
enum BufferBench {
    static let sampleRate = 16_000.0
    static let durations: [Double] = [30, 60, 120]
    /// 100 ms chunks: the app requests 4096-frame taps at 48 kHz (85 ms) and
    /// iOS commonly delivers ~100 ms; both sizes are exercised.
    static let chunkSizes = [1_365, 1_600]

    struct PerfResult: Codable {
        let implementation: String
        let capacitySeconds: Double
        let chunkFrames: Int
        let storageBytes: Int
        let footprintDeltaBytes: Int64
        let initNs: Double
        let clearNs: Double
        let appendNsSamples: [Double]
        let appendNs: Summary
        /// CPU time per second of audio, as a fraction (0.001 = 0.1%).
        let realTimeFraction: Double
        let snapshotNs: Summary
        let heapBlocksAllocatedPerAppend: Double
        let heapBytesRetainedAfterAppends: Int
    }

    static func makeSine(_ count: Int, offset: Int) -> [Float] {
        (0..<count).map { Float(0.4 * sin(2 * .pi * 220 * Double($0 + offset) / sampleRate)) }
    }

    static func perf<S: RollingStore>(_ type: S.Type, seconds: Double, chunk: Int, appends: Int, snapshots: Int) -> PerfResult {
        let chunkData = makeSine(chunk, offset: 0)
        let before = physFootprint()
        var store: S!
        let initNs = timeNs { store = S(sampleRate: sampleRate, capacitySeconds: seconds) }
        // Fill to steady state (buffer full) so measurements include trimming.
        var t = 0.0
        let fillChunks = Int(seconds * sampleRate) / chunk + 10
        chunkData.withUnsafeBufferPointer { ptr in
            for _ in 0..<fillChunks { t += Double(chunk) / sampleRate; store.append(ptr, at: t) }
        }
        let footprint = Int64(physFootprint()) - Int64(before)

        var appendSamples: [Double] = []
        appendSamples.reserveCapacity(appends)
        let heapBefore = mallocStats()
        let cpuBefore = cpuTime()
        chunkData.withUnsafeBufferPointer { ptr in
            for _ in 0..<appends {
                t += Double(chunk) / sampleRate
                appendSamples.append(timeNs { store.append(ptr, at: t) })
            }
        }
        let cpu = cpuTime() - cpuBefore
        let heapAfter = mallocStats()

        var snapSamples: [Double] = []
        for _ in 0..<snapshots {
            var out: [Float] = []
            snapSamples.append(timeNs { out = store.snapshot(lastSeconds: seconds, endingAt: nil) })
            blackHole(out)
        }
        let clearNs = timeNs { store.clear() }
        let audioSeconds = Double(appends * chunk) / sampleRate
        return PerfResult(
            implementation: S.name,
            capacitySeconds: seconds,
            chunkFrames: chunk,
            storageBytes: Int((seconds * sampleRate).rounded(.up)) * S.bytesPerSample,
            footprintDeltaBytes: footprint,
            initNs: initNs,
            clearNs: clearNs,
            appendNsSamples: appendSamples.count > 400 ? stride(from: 0, to: appendSamples.count, by: appendSamples.count / 400).map { appendSamples[$0] } : appendSamples,
            appendNs: Summary(appendSamples),
            realTimeFraction: cpu / audioSeconds,
            snapshotNs: Summary(snapSamples),
            heapBlocksAllocatedPerAppend: Double(heapAfter.blocks - heapBefore.blocks) / Double(appends),
            heapBytesRetainedAfterAppends: heapAfter.bytes - heapBefore.bytes
        )
    }

    // MARK: Boundary correctness

    struct BoundaryCase: Codable {
        let implementation: String
        let capacitySeconds: Double
        let chunkFrames: Int
        let askDelaySeconds: Double
        /// Audio that keeps arriving between the question and the snapshot.
        /// 0 models the in-app button (snapshot is immediate); 2 models a
        /// slow path where capture continues before extraction.
        let postAskSeconds: Double
        let label: String
        let expected: String
        let observed: String
        let retrievedWordFrames: Int
        let expectedWordFrames: Int
        let windowEndErrorFrames: Int
        let windowFrames: Int
        let expectedWindowFrames: Int
        let extractionNs: Double
        let pass: Bool
    }

    /// Plays a timeline with a 0.5 s "word" (constant marker level) in
    /// silence and asks `delay` seconds after the word ends. Each frame's
    /// value is known, so the extracted window is checked sample-exactly.
    static func boundary<S: RollingStore>(_ type: S.Type, seconds: Double, chunk: Int, delay: Double, postAsk: Double, label: String) -> BoundaryCase {
        let store = S(sampleRate: sampleRate, capacitySeconds: seconds)
        let capacityFrames = Int(seconds * sampleRate)
        let wordFrames = Int(0.5 * sampleRate)
        let marker: Float = 0.5
        let tick: Float = 0.25
        let wordStart = Int(3 * sampleRate)
        let wordEnd = wordStart + wordFrames
        let askFrame = wordEnd + Int((delay * sampleRate).rounded())
        let totalFrames = askFrame + Int(postAsk * sampleRate)
        func value(_ f: Int) -> Float {
            if f >= wordStart && f < wordEnd { return marker }
            return f == askFrame - 1 ? tick : 0
        }
        var frame = 0
        var buffer = [Float](repeating: 0, count: chunk)
        while frame < totalFrames {
            let n = min(chunk, totalFrames - frame)
            for i in 0..<n { buffer[i] = value(frame + i) }
            frame += n
            let time = Double(frame) / sampleRate
            buffer.withUnsafeBufferPointer { store.append(UnsafeBufferPointer(rebasing: $0[0..<n]), at: time) }
        }
        let askTime = Double(askFrame) / sampleRate
        var window: [Float] = []
        let ns = timeNs { window = store.snapshot(lastSeconds: seconds, endingAt: askTime) }

        let retrieved = window.filter { abs($0 - marker) < 0.01 }.count
        // The last sample must be the frame just before the question.
        let expectedLast = value(askFrame - 1)
        let endError = window.last.map { abs($0 - expectedLast) < 0.01 ? 0 : 1 } ?? 1
        // The oldest retained frame is limited both by the window and by what
        // the ring still holds after post-question audio.
        let oldestHeld = max(0, totalFrames - capacityFrames)
        let windowStart = max(askFrame - capacityFrames, oldestHeld, 0)
        let expectedWindow = askFrame - windowStart
        let expectedFrames = max(0, wordEnd - max(wordStart, windowStart))
        func describe(_ n: Int) -> String { n == wordFrames ? "full" : n == 0 ? "absent" : "partial" }
        return BoundaryCase(
            implementation: S.name, capacitySeconds: seconds, chunkFrames: chunk, askDelaySeconds: delay, postAskSeconds: postAsk, label: label,
            expected: describe(expectedFrames), observed: describe(retrieved), retrievedWordFrames: retrieved, expectedWordFrames: expectedFrames,
            windowEndErrorFrames: endError, windowFrames: window.count, expectedWindowFrames: expectedWindow, extractionNs: ns,
            pass: retrieved == expectedFrames && endError == 0 && window.count == expectedWindow
        )
    }

    static func boundaryCases(for seconds: Double) -> [(Double, String)] {
        var cases: [(Double, String)] = [
            (0, "immediately after the word"), (5, "5 s after"), (15, "15 s after"), (29, "29 s after"),
        ]
        if seconds > 30 { cases += [(30, "30 s after"), (59, "59 s after")] }
        if seconds > 60 { cases += [(90, "90 s after"), (119, "119 s after")] }
        cases += [
            (seconds - 0.5, "word starts exactly at window start"),
            (seconds - 0.25, "word straddles window start"),
            (seconds, "word ends exactly at window start"),
            (seconds + 1, "beyond the window"),
        ]
        return cases
    }

    // MARK: Sustained session

    struct SustainedPoint: Codable {
        let simulatedMinutes: Double
        let footprintBytes: UInt64
        let heapBytes: Int
        let bufferedSeconds: Double
        let snapshotMs: Double
    }

    struct SustainedResult: Codable {
        let implementation: String
        let capacitySeconds: Double
        let simulatedMinutes: Double
        let wallSeconds: Double
        let points: [SustainedPoint]
        let footprintGrowthAfterFirstFillBytes: Int64
        let bounded: Bool
    }

    /// Appends `minutes` of audio as fast as possible (time-compressed) and
    /// samples memory every simulated minute, taking a full-window snapshot
    /// each time as a rewind request would.
    static func sustained<S: RollingStore>(_ type: S.Type, seconds: Double, minutes: Double) -> SustainedResult {
        let chunk = 1_600
        let data = makeSine(chunk, offset: 7)
        let store = S(sampleRate: sampleRate, capacitySeconds: seconds)
        let chunksPerMinute = Int(60 * sampleRate) / chunk
        var points: [SustainedPoint] = []
        var t = 0.0
        let start = Date()
        data.withUnsafeBufferPointer { ptr in
            for minute in 1...Int(minutes) {
                for _ in 0..<chunksPerMinute { t += 0.1; store.append(ptr, at: t) }
                var snap: [Float] = []
                let ns = timeNs { snap = store.snapshot(lastSeconds: seconds, endingAt: nil) }
                blackHole(snap)
                snap = []
                points.append(SustainedPoint(simulatedMinutes: Double(minute), footprintBytes: physFootprint(), heapBytes: mallocStats().bytes, bufferedSeconds: store.bufferedDuration, snapshotMs: ns / 1e6))
            }
        }
        let firstFull = points.first { $0.simulatedMinutes * 60 >= seconds + 60 } ?? points[0]
        let growth = Int64(points.last!.footprintBytes) - Int64(firstFull.footprintBytes)
        return SustainedResult(
            implementation: S.name, capacitySeconds: seconds, simulatedMinutes: minutes,
            wallSeconds: Date().timeIntervalSince(start), points: points,
            footprintGrowthAfterFirstFillBytes: growth,
            bounded: abs(growth) < 1_048_576
        )
    }

    // MARK: Runner

    struct Report: Codable {
        let metadata: RunMetadata
        let perf: [PerfResult]
        let boundary: [BoundaryCase]
        let sustained: [SustainedResult]
        let quantization: [QuantizationResult]
    }

    struct QuantizationResult: Codable {
        let implementation: String
        let maxAbsError: Double
        let meanBias: Double
        let snrDb: Double
    }

    /// Round-trip precision: what Int16 storage does to the signal.
    static func quantization<S: RollingStore>(_ type: S.Type) -> QuantizationResult {
        let store = S(sampleRate: sampleRate, capacitySeconds: 2)
        var rng = SplitMix(seed: 42)
        let input = (0..<16_000).map { _ in Float(Double(rng.next() % 20_001) / 10_000 - 1) * 0.8 }
        input.withUnsafeBufferPointer { store.append($0, at: 1) }
        let out = store.snapshot(lastSeconds: 1, endingAt: nil)
        var maxErr = 0.0, sumErr = 0.0, sig = 0.0, noise = 0.0
        for (a, b) in zip(input, out) {
            let e = Double(b) - Double(a)
            maxErr = max(maxErr, abs(e)); sumErr += e
            sig += Double(a) * Double(a); noise += e * e
        }
        return QuantizationResult(implementation: S.name, maxAbsError: maxErr, meanBias: sumErr / Double(out.count), snrDb: noise == 0 ? 999 : 10 * log10(sig / noise))
    }

    static func run(implementations: [String], quick: Bool) throws {
        let all: [any RollingStore.Type] = [ShippingStore.self, BaselineV1Store.self, NaiveAppendTrimStore.self, Float32RingStore.self]
        let selected = all.filter { implementations.isEmpty || implementations.contains($0.name) }
        let meta = RunMetadata.capture(
            benchmark: "buffer",
            environment: "macOS host, \(sysctlString("machdep.cpu.brand_string")); synthetic audio; not an iPhone measurement",
            notes: ["Workload: 16 kHz mono float chunks", "Sustained runs are time-compressed (appends as fast as possible)"]
        )
        var perfResults: [PerfResult] = []
        var boundaryResults: [BoundaryCase] = []
        var sustainedResults: [SustainedResult] = []
        var quant: [QuantizationResult] = []
        for impl in selected {
            func go<S: RollingStore>(_ s: S.Type) {
                quant.append(quantization(s))
                for seconds in durations {
                    for chunk in chunkSizes {
                        let r = perf(s, seconds: seconds, chunk: chunk, appends: quick ? 500 : 3_000, snapshots: quick ? 20 : 100)
                        print(String(format: "%-26@ %4.0fs chunk %4d  append p50 %8.0f ns  p95 %8.0f ns  RT %.5f  snapshot p50 %7.2f ms  heap blocks/append %.2f",
                                     s.name as NSString, seconds, chunk, r.appendNs.p50, r.appendNs.p95, r.realTimeFraction, r.snapshotNs.p50 / 1e6, r.heapBlocksAllocatedPerAppend))
                        perfResults.append(r)
                    }
                    for chunk in chunkSizes {
                        for (delay, label) in boundaryCases(for: seconds) {
                            for postAsk in [0.0, 2.0] {
                                boundaryResults.append(boundary(s, seconds: seconds, chunk: chunk, delay: delay, postAsk: postAsk, label: label))
                            }
                        }
                    }
                    sustainedResults.append(sustained(s, seconds: seconds, minutes: quick ? 5 : 60))
                }
            }
            go(impl)
        }
        let passed = boundaryResults.filter(\.pass).count
        print("Boundary cases: \(passed)/\(boundaryResults.count) passed")
        for b in boundaryResults where !b.pass {
            print("  FAIL \(b.implementation) \(Int(b.capacitySeconds))s chunk \(b.chunkFrames) post \(b.postAskSeconds)s \(b.label): window \(b.windowFrames)/\(b.expectedWindowFrames) expected \(b.expected) (\(b.expectedWordFrames)) got \(b.observed) (\(b.retrievedWordFrames)), end error \(b.windowEndErrorFrames)")
        }
        for s in sustainedResults {
            print(String(format: "Sustained %@ %3.0fs over %.0f min: footprint growth after fill %+.1f KB, bounded %@", s.implementation as NSString, s.capacitySeconds, s.simulatedMinutes, Double(s.footprintGrowthAfterFirstFillBytes) / 1024, s.bounded ? "yes" : "NO"))
        }
        let url = try writeResult(Report(metadata: meta, perf: perfResults, boundary: boundaryResults, sustained: sustainedResults, quantization: quant), category: "buffer", runID: meta.runID)
        print("Wrote \(url.path)")
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
