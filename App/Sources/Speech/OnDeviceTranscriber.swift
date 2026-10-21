@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import LanguifyKit
import Speech

enum TranscriptionError: Error, LocalizedError, Equatable {
    case localeUnsupported(String)
    case modelNotInstalled(String)
    case audioFormatUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let id): "On-device speech recognition doesn't support \(id) on this device."
        case .modelNotInstalled(let id): "The \(id) speech model isn't downloaded yet. Open Settings \u{203A} Speech models."
        case .audioFormatUnavailable: "The speech model couldn't accept this audio format."
        case .failed(let detail): "Speech recognition failed (\(detail))."
        }
    }
}

/// Converts audio to time-stamped text segments.
protocol SpeechTranscribing: Sendable {
    func transcribe(_ snapshot: AudioSnapshot, localeIdentifier: String) async throws -> [TranscriptSegment]
}

/// On-device transcription with Apple's `SpeechAnalyzer` / `SpeechTranscriber`
/// (iOS 26). Verified during feasibility testing to support ta-IN and ml-IN.
/// Audio never leaves the device in this step. Note that the Tamil and
/// Malayalam models emit romanised text rather than native script.
nonisolated struct OnDeviceTranscriber: SpeechTranscribing {
    func transcribe(_ snapshot: AudioSnapshot, localeIdentifier: String) async throws -> [TranscriptSegment] {
        guard !snapshot.isEmpty else { return [] }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            throw TranscriptionError.localeUnsupported(localeIdentifier)
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.alternativeTranscriptions],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw TranscriptionError.modelNotInstalled(localeIdentifier)
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }
        let pcm = try Self.makeBuffer(snapshot, format: analyzerFormat)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task { () throws -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let confidences = result.text.runs.compactMap { $0.transcriptionConfidence }
                let mean = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
                let alternatives = result.alternatives
                    .map { String($0.characters).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != text }
                segments.append(TranscriptSegment(
                    text: text,
                    start: result.range.start.seconds,
                    end: result.range.end.seconds,
                    confidence: mean,
                    alternatives: Array(alternatives.prefix(3))
                ))
            }
            return segments
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        continuation.yield(AnalyzerInput(buffer: pcm))
        continuation.finish()

        do {
            if let end = try await analyzer.analyzeSequence(stream) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw TranscriptionError.failed(error.localizedDescription)
        }
    }

    /// Wraps 16 kHz mono float samples in a PCM buffer of the analyzer's format.
    static func makeBuffer(_ snapshot: AudioSnapshot, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: snapshot.sampleRate, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(snapshot.samples.count))
        else { throw TranscriptionError.audioFormatUnavailable }
        source.frameLength = AVAudioFrameCount(snapshot.samples.count)
        snapshot.samples.withUnsafeBufferPointer { src in
            source.floatChannelData?[0].update(from: src.baseAddress!, count: src.count)
        }
        if format == sourceFormat { return source }

        guard let converter = AVAudioConverter(from: sourceFormat, to: format) else { throw TranscriptionError.audioFormatUnavailable }
        let capacity = AVAudioFrameCount(Double(source.frameLength) * format.sampleRate / sourceFormat.sampleRate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw TranscriptionError.audioFormatUnavailable }
        nonisolated(unsafe) var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if let error { throw TranscriptionError.failed(error.localizedDescription) }
        return output
    }
}
