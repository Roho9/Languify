import Foundation
import LanguifyKit
import Observation
import Speech

/// Tracks and installs the on-device speech models Languify needs: the
/// heritage language plus Indian English for code-switched speech.
@Observable
final class SpeechModelManager {
    enum ModelState: Equatable {
        case unknown
        case unsupported
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)

        var isReady: Bool { self == .installed }
    }

    private(set) var states: [String: ModelState] = [:]

    func state(for localeIdentifier: String) -> ModelState {
        states[localeIdentifier] ?? .unknown
    }

    func requiredLocales(for language: HeritageLanguage) -> [String] {
        [language.configuration.speechLocaleIdentifier, LanguageConfiguration.companionEnglishLocaleIdentifier]
    }

    func isReady(for language: HeritageLanguage) -> Bool {
        state(for: language.configuration.speechLocaleIdentifier).isReady
    }

    func refresh(for language: HeritageLanguage) async {
        for id in requiredLocales(for: language) {
            states[id] = await Self.currentState(id)
        }
    }

    /// Downloads any missing models for `language`, reporting progress.
    func install(for language: HeritageLanguage) async {
        for id in requiredLocales(for: language) {
            await install(localeIdentifier: id)
        }
    }

    func install(localeIdentifier id: String) async {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            states[id] = .unsupported
            return
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            _ = try await AssetInventory.reserve(locale: locale)
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
                states[id] = .installed
                return
            }
            states[id] = .downloading(0)
            let progress = request.progress
            let poll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.states[id] = .downloading(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { poll.cancel() }
            try await request.downloadAndInstall()
            states[id] = await Self.currentState(id)
        } catch {
            states[id] = .failed(error.localizedDescription)
            Log.speech.error("Model install failed for \(id, privacy: .public)")
        }
    }

    private static func currentState(_ id: String) async -> ModelState {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else { return .unsupported }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .installed
        case .downloading: return .downloading(0)
        case .supported: return .notInstalled
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
    }
}
