import Accelerate
import Foundation
import LanguifyKit

/// EXPERIMENTAL, NOT SHIPPED. Experiment D in docs/benchmarks/ExperimentLog.md
/// found that trimming silence made Apple's recogniser slower (+11% on 60 s
/// windows) and hurt overlapping-speech accuracy, so the app does not use it.
/// Kept here so the experiment stays reproducible.
///
/// Removes long silences from a rewind window before speech recognition.
///
/// Apple's recogniser time grows with audio length (about 1 s for a 60 s
/// window in benchmarks), and in conversation much of a window is pauses.
/// Trimming those pauses cuts recognition time without dropping speech.
/// Energy-based, with an adaptive noise floor, generous padding around speech,
/// and a short gap kept wherever silence is removed so sentences stay
/// separated. See docs/benchmarks/ExperimentLog.md, experiment D.
struct SpeechActivityTrimmer: Sendable {
    struct Configuration: Sendable, Equatable {
        /// Analysis frame length in seconds.
        var frameSeconds: Double = 0.02
        /// Frames this many dB above the noise floor count as speech.
        var thresholdAboveFloorDb: Float = 12
        /// Never treat anything quieter than this as speech (dBFS).
        var absoluteFloorDb: Float = -55
        /// Audio kept before and after each speech region.
        var paddingSeconds: Double = 0.3
        /// Silences shorter than this are kept intact.
        var minimumGapSeconds: Double = 0.6
        /// Silence left in place of each removed gap.
        var keptGapSeconds: Double = 0.25

        init() {}
    }

    struct Result: Sendable {
        let snapshot: AudioSnapshot
        let originalSeconds: Double
        let keptSeconds: Double
        let speechRegions: Int

        var removedFraction: Double { originalSeconds > 0 ? 1 - keptSeconds / originalSeconds : 0 }
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func trim(_ snapshot: AudioSnapshot) -> Result {
        let samples = snapshot.samples
        let rate = snapshot.sampleRate
        let frame = max(1, Int(configuration.frameSeconds * rate))
        let frameCount = samples.count / frame
        guard frameCount > 2 else {
            return Result(snapshot: snapshot, originalSeconds: snapshot.duration, keptSeconds: snapshot.duration, speechRegions: snapshot.isEmpty ? 0 : 1)
        }

        // Per-frame RMS in dBFS.
        var levels = [Float](repeating: -120, count: frameCount)
        samples.withUnsafeBufferPointer { ptr in
            for i in 0..<frameCount {
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress! + i * frame, 1, &rms, vDSP_Length(frame))
                levels[i] = 20 * log10(max(rms, 1e-7))
            }
        }
        // Noise floor: 10th percentile of frame levels. If the window has no
        // clear quiet periods (continuous speech, or steady loud noise), the
        // "floor" is really speech, so trimming would delete what matters.
        // In that case return the window untouched.
        let sorted = levels.sorted()
        let floor = sorted[frameCount / 10]
        // Loudest frame: a single word can be under 1% of a 60 s window.
        let loud = sorted[frameCount - 1]
        guard loud >= configuration.absoluteFloorDb else {
            return Result(snapshot: AudioSnapshot(samples: [], sampleRate: rate), originalSeconds: snapshot.duration, keptSeconds: 0, speechRegions: 0)
        }
        guard loud - floor >= configuration.thresholdAboveFloorDb else {
            return Result(snapshot: snapshot, originalSeconds: snapshot.duration, keptSeconds: snapshot.duration, speechRegions: 1)
        }
        let threshold = max(floor + configuration.thresholdAboveFloorDb, configuration.absoluteFloorDb)

        // Speech frames, dilated by padding.
        let pad = Int((configuration.paddingSeconds / configuration.frameSeconds).rounded())
        var keep = [Bool](repeating: false, count: frameCount)
        for i in 0..<frameCount where levels[i] >= threshold {
            for j in max(0, i - pad)...min(frameCount - 1, i + pad) { keep[j] = true }
        }
        // Fill short gaps so pauses inside a sentence are untouched.
        let minGap = Int((configuration.minimumGapSeconds / configuration.frameSeconds).rounded())
        var i = 0
        while i < frameCount {
            if !keep[i] {
                var j = i
                while j < frameCount && !keep[j] { j += 1 }
                let interior = i > 0 && j < frameCount
                if interior && j - i < minGap { for k in i..<j { keep[k] = true } }
                i = j
            } else {
                i += 1
            }
        }

        guard keep.contains(true) else {
            return Result(snapshot: AudioSnapshot(samples: [], sampleRate: rate), originalSeconds: snapshot.duration, keptSeconds: 0, speechRegions: 0)
        }

        // Assemble kept regions separated by a short silence.
        let gapFrames = Int(configuration.keptGapSeconds * rate)
        var output: [Float] = []
        output.reserveCapacity(samples.count)
        var regions = 0
        i = 0
        while i < frameCount {
            guard keep[i] else { i += 1; continue }
            var j = i
            while j < frameCount && keep[j] { j += 1 }
            if regions > 0 { output.append(contentsOf: repeatElement(0, count: gapFrames)) }
            let end = j == frameCount ? samples.count : j * frame
            output.append(contentsOf: samples[(i * frame)..<end])
            regions += 1
            i = j
        }
        let trimmed = AudioSnapshot(samples: output, sampleRate: rate)
        return Result(snapshot: trimmed, originalSeconds: snapshot.duration, keptSeconds: trimmed.duration, speechRegions: regions)
    }
}
