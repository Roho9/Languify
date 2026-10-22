@preconcurrency import AVFoundation
import Foundation
import LanguifyKit
import Speech

/// Runs Apple's on-device SpeechTranscriber over a dataset manifest, the same
/// way OnDeviceTranscriber does in the app (a fresh transcriber and analyzer
/// per request, time-indexed results with confidence and alternatives).
/// Scoring happens offline in Benchmarks/scripts/score_asr.py.
enum ASRBench {
    struct ManifestClip: Codable {
        let clip_id: String
        let sentence_id: String
        let condition: String
        let rate: String
        let snr_db: Double?
        let path: String
    }

    struct Manifest: Codable {
        let dataset: String
        let source_label: String
        let clips: [ManifestClip]
    }

    struct Hypothesis: Codable {
        let locale: String
        let text: String
        let meanConfidence: Double?
        let minConfidence: Double?
        let alternatives: [String]
        let latencyMs: Double
    }

    struct ClipResult: Codable {
        let clipID: String
        let sentenceID: String
        let condition: String
        let rate: String
        let snrDb: Double?
        let audioSeconds: Double
        /// Audio left after silence trimming, when enabled.
        let keptSeconds: Double?
        let hypotheses: [Hypothesis]
        /// Wall time for all locales, run as the app runs them.
        let combinedLatencyMs: Double
        let error: String?
    }

    struct Report: Codable {
        let metadata: RunMetadata
        let dataset: String
        let sourceLabel: String
        let locales: [String]
        let mode: String
        let inputMode: String
        let vad: Bool
        let results: [ClipResult]
    }

    static func transcribe(url: URL, localeID: String) async throws -> Hypothesis {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw NSError(domain: "asr", code: 1, userInfo: [NSLocalizedDescriptionKey: "unsupported \(localeID)"])
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collector = Task { () throws -> (String, [Double], [String]) in
            var texts: [String] = [], confs: [Double] = [], alts: [String] = []
            for try await result in transcriber.results {
                texts.append(String(result.text.characters))
                confs += result.text.runs.compactMap { $0.transcriptionConfidence }
                alts += result.alternatives.dropFirst().prefix(2).map { String($0.characters) }
            }
            return (texts.joined(separator: " "), confs, alts)
        }
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let (text, confs, alts) = try await collector.value
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        return Hypothesis(
            locale: localeID,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " "),
            meanConfidence: confs.isEmpty ? nil : confs.reduce(0, +) / Double(confs.count),
            minConfidence: confs.min(),
            alternatives: alts,
            latencyMs: ms
        )
    }

    /// Loads a clip as 16 kHz mono floats, like a rewind snapshot.
    static func loadSnapshot(_ url: URL) throws -> AudioSnapshot {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        return AudioSnapshot(samples: samples, sampleRate: file.processingFormat.sampleRate)
    }

    /// Transcribes in-memory samples exactly as OnDeviceTranscriber does in the app.
    static func transcribe(snapshot: AudioSnapshot, localeID: String) async throws -> Hypothesis {
        let start = DispatchTime.now().uptimeNanoseconds
        guard !snapshot.isEmpty else { return Hypothesis(locale: localeID, text: "", meanConfidence: nil, minConfidence: nil, alternatives: [], latencyMs: 0) }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw NSError(domain: "asr", code: 1, userInfo: [NSLocalizedDescriptionKey: "unsupported \(localeID)"])
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])!
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: snapshot.sampleRate, channels: 1, interleaved: false)!
        let pcm = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(snapshot.samples.count))!
        pcm.frameLength = AVAudioFrameCount(snapshot.samples.count)
        snapshot.samples.withUnsafeBufferPointer { pcm.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        var input = pcm
        if format != source {
            let converter = AVAudioConverter(from: source, to: format)!
            let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(pcm.frameLength) * format.sampleRate / source.sampleRate) + 1_024)!
            nonisolated(unsafe) var consumed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if consumed { status.pointee = .endOfStream; return nil }
                consumed = true; status.pointee = .haveData; return pcm
            }
            input = out
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () throws -> (String, [Double], [String]) in
            var texts: [String] = [], confs: [Double] = [], alts: [String] = []
            for try await result in transcriber.results {
                texts.append(String(result.text.characters))
                confs += result.text.runs.compactMap { $0.transcriptionConfidence }
                alts += result.alternatives.dropFirst().prefix(2).map { String($0.characters) }
            }
            return (texts.joined(separator: " "), confs, alts)
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        continuation.yield(AnalyzerInput(buffer: input))
        continuation.finish()
        if let end = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let (text, confs, alts) = try await collector.value
        return Hypothesis(
            locale: localeID,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "  ", with: " "),
            meanConfidence: confs.isEmpty ? nil : confs.reduce(0, +) / Double(confs.count),
            minConfidence: confs.min(),
            alternatives: alts,
            latencyMs: Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        )
    }

    static func run(manifestPath: String, locales: [String], parallel: Bool, limit: Int?, inputMode: String = "file", vad: Bool = false) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appending(path: manifestPath)))
        let clips = limit.map { Array(manifest.clips.prefix($0)) } ?? manifest.clips
        let meta = RunMetadata.capture(
            benchmark: "asr",
            environment: "macOS on-device SpeechTranscriber; \(manifest.source_label)",
            notes: ["locales: \(locales.joined(separator: ","))", "mode: \(parallel ? "parallel" : "sequential")", "input: \(inputMode)", "vad: \(vad)", "First clip includes model load (cold start)"]
        )
        var results: [ClipResult] = []
        for (i, clip) in clips.enumerated() {
            let url = root.appending(path: clip.path)
            let audioSeconds = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
            let start = DispatchTime.now().uptimeNanoseconds
            var hyps: [Hypothesis] = []
            var errorText: String?
            var keptSeconds: Double?
            do {
                var snapshot: AudioSnapshot?
                if inputMode == "buffer" {
                    var s = try loadSnapshot(url)
                    if vad {
                        let trimmed = SpeechActivityTrimmer().trim(s)
                        s = trimmed.snapshot
                        keptSeconds = trimmed.keptSeconds
                    }
                    snapshot = s
                }
                let snap = snapshot
                if parallel {
                    hyps = try await withThrowingTaskGroup(of: Hypothesis.self) { group in
                        for id in locales { group.addTask { if let snap { try await transcribe(snapshot: snap, localeID: id) } else { try await transcribe(url: url, localeID: id) } } }
                        var out: [Hypothesis] = []
                        for try await h in group { out.append(h) }
                        return out.sorted { $0.locale < $1.locale }
                    }
                } else {
                    for id in locales { hyps.append(try await (snap != nil ? transcribe(snapshot: snap!, localeID: id) : transcribe(url: url, localeID: id))) }
                }
            } catch {
                errorText = error.localizedDescription
            }
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            results.append(ClipResult(clipID: clip.clip_id, sentenceID: clip.sentence_id, condition: clip.condition, rate: clip.rate, snrDb: clip.snr_db, audioSeconds: audioSeconds, keptSeconds: keptSeconds, hypotheses: hyps, combinedLatencyMs: ms, error: errorText))
            if i % 25 == 0 || i == clips.count - 1 {
                print("\(i + 1)/\(clips.count) \(clip.clip_id): \(hyps.first { $0.locale.hasPrefix("ta") }?.text ?? errorText ?? "") [\(Int(ms)) ms]")
            }
        }
        let report = Report(metadata: meta, dataset: manifest.dataset, sourceLabel: manifest.source_label, locales: locales, mode: parallel ? "parallel" : "sequential", inputMode: inputMode, vad: vad, results: results)
        print("Wrote \(try writeResult(report, category: "asr", runID: meta.runID).path)")
    }
}
