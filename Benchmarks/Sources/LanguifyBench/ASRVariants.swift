@preconcurrency import AVFoundation
import Foundation
import Speech

/// Compares transcriber configurations and finishing strategies on the same
/// clip to explain the fixed ~430 ms finalisation cost.
enum ASRVariants {
    struct Variant {
        let name: String
        let make: (Locale) -> SpeechTranscriber
        let finish: String
    }

    static func run(path: String, iterations: Int) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let url = root.appending(path: path)
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ta-IN"))!
        let variants: [Variant] = [
            Variant(name: "shipping (alts+time+conf), finalizeAndFinish", make: { SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence]) }, finish: "finalizeAndFinish"),
            Variant(name: "no options, finalizeAndFinish", make: { SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [], attributeOptions: []) }, finish: "finalizeAndFinish"),
            Variant(name: "preset .transcription", make: { SpeechTranscriber(locale: $0, preset: .transcription) }, finish: "finalizeAndFinish"),
            Variant(name: "shipping, finalizeAndFinishThroughEndOfInput", make: { SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence]) }, finish: "throughEnd"),
            Variant(name: "shipping, volatile results, finalizeAndFinish", make: { SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions, .volatileResults], attributeOptions: [.audioTimeRange, .transcriptionConfidence]) }, finish: "finalizeAndFinish"),
        ]
        for v in variants {
            var times: [Double] = []
            var text = ""
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                let transcriber = v.make(locale)
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let file = try AVAudioFile(forReading: url)
                let collector = Task { () throws -> String in
                    var out = ""
                    for try await r in transcriber.results where r.isFinal { out += String(r.text.characters) }
                    return out
                }
                if v.finish == "throughEnd" {
                    try await analyzer.start(inputSequence: AsyncStream<AnalyzerInput> { $0.finish() })
                    _ = try await analyzer.analyzeSequence(from: file)
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                } else if let end = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: end)
                }
                text = try await collector.value
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            print(String(format: "%-48@ p50 %6.1f ms  min %6.1f  | %@", v.name as NSString, percentile(Array(times.dropFirst()), 50), times.dropFirst().min() ?? 0, text as NSString))
        }
    }
}

extension SpeechTranscriber.Result {
    var isFinal: Bool { resultsFinalizationTime >= range.end }
}
