import Foundation
import Testing
@testable import LanguifyKit

@Suite("RingBuffer")
struct RingBufferTests {
    @Test func keepsMostRecentElementsInOrder() {
        var ring = RingBuffer(capacity: 4, zero: 0)
        ring.append(contentsOf: 1...6)
        #expect(ring.count == 4)
        #expect(ring.elements() == [3, 4, 5, 6])
        #expect(ring.suffix(2) == [5, 6])
    }

    @Test func suffixClampsToAvailable() {
        var ring = RingBuffer(capacity: 10, zero: 0)
        ring.append(contentsOf: [1, 2, 3])
        #expect(ring.suffix(100) == [1, 2, 3])
        #expect(ring.suffix(0).isEmpty)
        #expect(ring.suffix(-5).isEmpty)
    }

    @Test func exactCapacityBoundary() {
        var ring = RingBuffer(capacity: 3, zero: 0)
        ring.append(contentsOf: [1, 2, 3])
        #expect(ring.isFull)
        #expect(ring.elements() == [1, 2, 3])
        ring.append(4)
        #expect(ring.elements() == [2, 3, 4])
    }

    @Test func removeAllResetsState() {
        var ring = RingBuffer(capacity: 3, zero: 0)
        ring.append(contentsOf: [7, 8, 9, 10])
        ring.removeAll()
        #expect(ring.isEmpty)
        #expect(ring.elements().isEmpty)
        ring.append(1)
        #expect(ring.elements() == [1])
    }
}

@Suite("RollingAudioBuffer")
struct RollingAudioBufferTests {
    func tone(seconds: Double, rate: Double = 1_000, value: Float = 0.5) -> [Float] {
        Array(repeating: value, count: Int(seconds * rate))
    }

    @Test func memoryIsBoundedByCapacity() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 30)
        for i in 0..<100 { buffer.append(tone(seconds: 1), at: Double(i)) }
        #expect(buffer.bufferedDuration == 30)
        #expect(buffer.totalFramesWritten == 100_000)
    }

    @Test func capacityIsCappedAtMaximum() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 999)
        #expect(buffer.capacitySeconds == RollingAudioBuffer.maximumSeconds)
    }

    @Test(arguments: RewindDuration.allCases)
    func snapshotHonoursRewindDuration(_ duration: RewindDuration) {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: RollingAudioBuffer.maximumSeconds)
        buffer.append(tone(seconds: 150), at: 150)
        let snap = buffer.snapshot(lastSeconds: duration.seconds)
        #expect(snap.duration == duration.seconds)
    }

    @Test func snapshotReturnsMostRecentAudio() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 10)
        buffer.append(tone(seconds: 5, value: 0.1), at: 5)
        buffer.append(tone(seconds: 5, value: 0.9), at: 10)
        let snap = buffer.snapshot(lastSeconds: 3)
        #expect(snap.samples.allSatisfy { abs($0 - 0.9) < 0.001 })
    }

    @Test func snapshotExcludesAudioAfterRequestTime() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 60)
        buffer.append(tone(seconds: 10, value: 0.2), at: 10)
        // The user's own question, captured after they asked at t = 10.
        buffer.append(tone(seconds: 2, value: 0.8), at: 12)
        let snap = buffer.snapshot(lastSeconds: 5, endingAt: 10)
        #expect(snap.duration == 5)
        #expect(snap.samples.allSatisfy { abs($0 - 0.2) < 0.001 })
    }

    @Test func samplesAreClampedAndQuantised() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 1)
        buffer.append([2, -2, 0], at: 1)
        let snap = buffer.snapshot(lastSeconds: 1)
        #expect(snap.samples == [1, -1, 0])
    }

    @Test func clearDiscardsEverything() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 30)
        buffer.append(tone(seconds: 20), at: 20)
        buffer.clear()
        #expect(buffer.bufferedDuration == 0)
        #expect(buffer.lastAppendTime == nil)
        #expect(buffer.snapshot(lastSeconds: 30).isEmpty)
    }

    @Test func repeatedSessionsDoNotLeakAudio() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 30)
        for session in 0..<20 {
            buffer.append(tone(seconds: 5, value: Float(session) / 100), at: Double(session))
            #expect(buffer.bufferedDuration == 5)
            buffer.clear()
        }
        #expect(buffer.bufferedDuration == 0)
    }

    @Test func concurrentAppendAndSnapshotIsSafe() async {
        let buffer = RollingAudioBuffer(sampleRate: 16_000, capacitySeconds: 2)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<200 { buffer.append(self.tone(seconds: 0.02, rate: 16_000), at: Double(i)) }
            }
            group.addTask {
                for _ in 0..<200 { _ = buffer.snapshot(lastSeconds: 1) }
            }
        }
        #expect(buffer.bufferedDuration <= 2)
    }

    @Test func rmsOfSilenceIsZero() {
        #expect(AudioSnapshot(samples: Array(repeating: 0, count: 100), sampleRate: 1_000).rms == 0)
        #expect(abs(AudioSnapshot(samples: [0.5, -0.5], sampleRate: 1_000).rms - 0.5) < 0.0001)
    }
}

@Suite("ListeningStateMachine")
struct ListeningStateMachineTests {
    @Test func happyPath() {
        var m = ListeningStateMachine()
        #expect(m.handle(.startRequested) == .requestingPermission)
        #expect(m.handle(.permissionGranted) == .starting)
        #expect(m.handle(.captureStarted) == .listening)
        #expect(m.handle(.processingBegan) == .processing)
        #expect(m.handle(.processingEnded) == .listening)
        #expect(m.handle(.stopRequested) == .stopping)
        #expect(m.handle(.stopped) == .idle)
    }

    @Test func permissionDenied() {
        var m = ListeningStateMachine()
        m.handle(.startRequested)
        #expect(m.handle(.permissionDenied) == .failed(.microphonePermissionDenied))
        #expect(m.handle(.startRequested) == .requestingPermission)
    }

    @Test func siriInterruptionKeepsSessionAndRecovers() {
        var m = ListeningStateMachine(state: .listening)
        #expect(m.handle(.interruptionBegan(.systemAudio)) == .interrupted(.systemAudio))
        #expect(m.state.isSessionActive)
        #expect(!m.state.isCapturing)
        // A question can be answered from the kept buffer during the interruption.
        #expect(m.handle(.processingBegan) == .interrupted(.systemAudio))
        #expect(m.handle(.interruptionEnded) == .starting)
        #expect(m.handle(.captureStarted) == .listening)
    }

    @Test func invalidTransitionsAreRejected() {
        var m = ListeningStateMachine()
        #expect(m.handle(.captureStarted) == nil)
        #expect(m.state == .idle)
        #expect(m.handle(.processingEnded) == nil)
        #expect(ListeningStateMachine.transition(from: .stopping, on: .startRequested) == nil)
    }

    @Test func stopIsAlwaysReachableFromActiveStates() {
        let states: [ListeningSessionState] = [.requestingPermission, .starting, .listening, .processing, .paused, .interrupted(.routeLost)]
        for state in states {
            #expect(ListeningStateMachine.transition(from: state, on: .stopRequested) == .stopping)
        }
    }

    @Test func repeatedActivation() {
        var m = ListeningStateMachine()
        for _ in 0..<50 {
            m.handle(.startRequested)
            m.handle(.permissionGranted)
            m.handle(.captureStarted)
            m.handle(.stopRequested)
            m.handle(.stopped)
        }
        #expect(m.state == .idle)
    }

    @Test func pauseAndResume() {
        var m = ListeningStateMachine(state: .listening)
        #expect(m.handle(.pauseRequested) == .paused)
        #expect(m.handle(.resumeRequested) == .starting)
    }
}

/// Regression guards for the vDSP buffer (experiment A in
/// docs/benchmarks/ExperimentLog.md).
@Suite("RollingAudioBuffer regression")
struct RollingAudioBufferRegressionTests {
    /// Values chosen to survive Int16 quantisation exactly: k / 32767.
    func ramp(_ range: Range<Int>) -> [Float] { range.map { Float($0 % 30_000) / 32_767 } }

    @Test(arguments: [1, 7, 1_365, 1_600, 4_096, 40_000])
    func wrapAroundIsSampleExact(chunk: Int) {
        let rate = 1_000.0
        let buffer = RollingAudioBuffer(sampleRate: rate, capacitySeconds: 10)
        let total = 37_123
        var written = 0
        while written < total {
            let n = min(chunk, total - written)
            buffer.append(ramp(written..<(written + n)), at: Double(written + n) / rate)
            written += n
        }
        let snap = buffer.snapshot(lastSeconds: 10)
        let expected = ramp((total - 10_000)..<total)
        #expect(snap.samples.count == 10_000)
        #expect(zip(snap.samples, expected).allSatisfy { abs($0 - $1) < 1e-6 })
    }

    @Test func roundsToNearestLevel() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 1)
        // 0.6 of a step rounds up, 0.4 rounds down; truncation would give 0 for both.
        let step = 1 / Float(32_767)
        buffer.append([0.6 * step, 0.4 * step, -0.6 * step], at: 1)
        let out = buffer.snapshot(lastSeconds: 1).samples.map { ($0 / step).rounded() }
        #expect(out == [1, 0, -1])
    }

    @Test func quantisationErrorIsAtMostHalfAStep() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 5)
        let input = (0..<5_000).map { Float(sin(Double($0) * 0.0137)) * 0.9 }
        buffer.append(input, at: 5)
        let out = buffer.snapshot(lastSeconds: 5).samples
        let maxError = zip(input, out).map { abs($0 - $1) }.max() ?? 1
        #expect(maxError <= 0.5 / 32_767 + 1e-7)
    }

    @Test func oversizedChunkKeepsNewestAudio() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 2)
        buffer.append(ramp(0..<5_000), at: 5)
        #expect(buffer.snapshot(lastSeconds: 2).samples.first.map { abs($0 - Float(3_000) / 32_767) < 1e-6 } == true)
        #expect(buffer.totalFramesWritten == 5_000)
    }

    @Test func endingAtBeyondBufferedAudioReturnsEmpty() {
        let buffer = RollingAudioBuffer(sampleRate: 1_000, capacitySeconds: 2)
        buffer.append(ramp(0..<1_000), at: 10)
        #expect(buffer.snapshot(lastSeconds: 2, endingAt: 5).isEmpty)
    }
}
