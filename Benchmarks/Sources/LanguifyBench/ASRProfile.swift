@preconcurrency import AVFoundation
import Foundation
import Speech

/// Breaks one transcription into its setup and analysis stages, to find
/// where fixed per-request cost goes.
enum ASRProfile {
    static func run(path: String, iterations: Int) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let url = root.appending(path: path)
        var rows: [[String: Double]] = []
        for _ in 0..<iterations {
            var t = DispatchTime.now().uptimeNanoseconds
            func lap() -> Double { let now = DispatchTime.now().uptimeNanoseconds; defer { t = now }; return Double(now - t) / 1e6 }
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ta-IN"))!
            let localeMs = lap()
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            let initMs = lap()
            _ = await AssetInventory.status(forModules: [transcriber])
            let statusMs = lap()
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let formatMs = lap()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.prepareToAnalyze(in: format)
            let prepareMs = lap()
            let file = try AVAudioFile(forReading: url)
            let collector = Task { () throws -> Int in var n = 0; for try await _ in transcriber.results { n += 1 }; return n }
            let end = try await analyzer.analyzeSequence(from: file)
            let analyzeMs = lap()
            if let end { try await analyzer.finalizeAndFinish(through: end) }
            _ = try await collector.value
            let finalizeMs = lap()
            rows.append(["supportedLocale": localeMs, "transcriberInit": initMs, "assetStatus": statusMs, "bestFormat": formatMs, "analyzerPrepare": prepareMs, "analyze": analyzeMs, "finalizeAndCollect": finalizeMs])
        }
        for key in ["supportedLocale", "transcriberInit", "assetStatus", "bestFormat", "analyzerPrepare", "analyze", "finalizeAndCollect"] {
            let v = rows.dropFirst().map { $0[key]! }
            print(String(format: "%-20@ p50 %7.1f ms   (first %7.1f ms)", key as NSString, percentile(Array(v), 50), rows[0][key]!))
        }
        let totals = rows.dropFirst().map { $0.values.reduce(0, +) }
        print(String(format: "total p50 %.1f ms over %d iterations", percentile(Array(totals), 50), iterations - 1))
    }
}
