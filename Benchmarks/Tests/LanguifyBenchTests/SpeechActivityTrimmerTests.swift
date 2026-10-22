import Foundation
import LanguifyKit
import Testing
@testable import LanguifyBench

@Suite("SpeechActivityTrimmer")
struct SpeechActivityTrimmerTests {
    let rate = 16_000.0

    func tone(_ seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 200 * Double($0) / rate)) }
    }

    func noise(_ seconds: Double, amplitude: Float, seed: UInt64 = 1) -> [Float] {
        var g = SplitMix(seed: seed)
        return (0..<Int(seconds * rate)).map { _ in amplitude * (Float(g.next() % 2_001) / 1_000 - 1) }
    }

    @Test func removesLongSilenceAndKeepsAllSpeech() {
        let audio = noise(10, amplitude: 0.001) + tone(2, amplitude: 0.3) + noise(20, amplitude: 0.001, seed: 2) + tone(1.5, amplitude: 0.3) + noise(5, amplitude: 0.001, seed: 3)
        let result = SpeechActivityTrimmer().trim(AudioSnapshot(samples: audio, sampleRate: rate))
        #expect(result.speechRegions == 2)
        // Speech (3.5 s) + padding (4 x 0.3 s) + one kept gap (0.25 s), give or take a frame.
        #expect(abs(result.keptSeconds - 4.95) < 0.1)
        #expect(result.removedFraction > 0.85)
        let loud = result.snapshot.samples.filter { abs($0) > 0.2 }.count
        let loudOriginal = audio.filter { abs($0) > 0.2 }.count
        #expect(loud == loudOriginal)
    }

    @Test func keepsShortPausesInsideSpeech() {
        let audio = tone(1, amplitude: 0.3) + noise(0.4, amplitude: 0.001) + tone(1, amplitude: 0.3)
        let result = SpeechActivityTrimmer().trim(AudioSnapshot(samples: audio, sampleRate: rate))
        #expect(result.speechRegions == 1)
        #expect(abs(result.keptSeconds - 2.4) < 0.05)
    }

    @Test func pureSilenceBecomesEmpty() {
        let result = SpeechActivityTrimmer().trim(AudioSnapshot(samples: noise(5, amplitude: 0.0005), sampleRate: rate))
        #expect(result.snapshot.isEmpty)
        #expect(result.speechRegions == 0)
    }

    @Test func continuousSpeechIsUntouched() {
        let audio = tone(6, amplitude: 0.2)
        let result = SpeechActivityTrimmer().trim(AudioSnapshot(samples: audio, sampleRate: rate))
        #expect(result.snapshot.samples.count == audio.count)
    }

    @Test func tinyInputIsReturnedAsIs() {
        let audio: [Float] = [0.1, 0.2]
        #expect(SpeechActivityTrimmer().trim(AudioSnapshot(samples: audio, sampleRate: rate)).snapshot.samples == audio)
    }
}

@Suite("SpeechActivityTrimmer safety")
struct SpeechActivityTrimmerSafetyTests {
    @Test func steadyLoudNoiseIsNotTrimmedAway() {
        var g = SplitMix(seed: 9)
        let audio = (0..<160_000).map { _ in 0.2 * (Float(g.next() % 2_001) / 1_000 - 1) }
        let result = SpeechActivityTrimmer().trim(AudioSnapshot(samples: audio, sampleRate: 16_000))
        #expect(result.snapshot.samples.count == audio.count)
    }
}
