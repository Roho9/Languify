import Foundation
import LanguifyKit
import SwiftData
import Testing
@testable import Languify

@MainActor
struct VocabularyRepositoryTests {
    let container = LanguifySchema.makeContainer(syncWithICloud: false, inMemory: true)
    var repo: VocabularyRepository { VocabularyRepository(context: container.mainContext) }

    let item = VocabularyExplanation(nativeScript: "മടി", transliteration: "madi", englishMeaning: "laziness", contextualMeaning: "being lazy", pronunciationHint: "MA-di", register: .informal)

    @Test func savesWithContextAndDeduplicates() {
        let heard = HeardUtterance(nativeScript: "", transliteration: "avanu madi aanu", englishNatural: "He's lazy")
        repo.save([item], language: .malayalam, heard: heard, fallbackContext: nil, source: .liveRewind)
        repo.save([item], language: .malayalam, heard: nil, fallbackContext: "other", source: .liveRewind)
        let all = repo.entries()
        #expect(all.count == 1)
        #expect(all[0].encounterCount == 2)
        #expect(all[0].contextSentence == "avanu madi aanu")
        #expect(all[0].status == .new)
    }

    @Test func correctionsSurviveLaterExplanations() {
        let entry = repo.save([item], language: .malayalam, heard: nil, fallbackContext: nil, source: .liveRewind)[0]
        repo.correct(entry, nativeScript: "മടി", transliteration: "madi", englishMeaning: "reluctance")
        #expect(entry.originalEnglishMeaning == "laziness")
        repo.save([item], language: .malayalam, heard: nil, fallbackContext: nil, source: .liveRewind)
        #expect(repo.entries().count == 1)
        #expect(entry.englishMeaning == "reluctance")
        #expect(entry.userEdited)
    }

    @Test func reviewSchedulesWithFSRS() {
        let entry = repo.save([item], language: .malayalam, heard: nil, fallbackContext: nil, source: .liveRewind)[0]
        let now = Date()
        let due = repo.review(entry, grade: .good, now: now)
        #expect(entry.reviewCount == 1)
        #expect(entry.stability == FSRSScheduler.defaultWeights[2])
        #expect(due > now.addingTimeInterval(86_400))
        #expect(entry.reviews?.count == 1)
        #expect(repo.dueCount(language: .malayalam, now: now) == 0)

        repo.review(entry, grade: .again, now: due)
        #expect(entry.lapseCount == 1)
        #expect(repo.dueCount(language: .malayalam, now: due.addingTimeInterval(3_600)) == 1)
    }

    @Test func languageFilterAndExport() {
        repo.save([item], language: .malayalam, heard: nil, fallbackContext: nil, source: .liveRewind)
        let tamil = VocabularyExplanation(nativeScript: "சோம்பல்", transliteration: "sombal", englishMeaning: "laziness", contextualMeaning: "", pronunciationHint: "")
        repo.save([tamil], language: .tamil, heard: nil, fallbackContext: nil, source: .suggestion)
        #expect(repo.entries(language: .tamil).count == 1)
        #expect(repo.entries().count == 2)
        let (vocab, _) = repo.exportPayload()
        #expect(Set(vocab.map(\.language)) == ["ml", "ta"])
    }

    @Test func deleteHistoryKeepsWordsDeleteAllRemovesThem() {
        let entry = repo.save([item], language: .malayalam, heard: nil, fallbackContext: nil, source: .liveRewind)[0]
        repo.review(entry, grade: .easy)
        repo.deleteLearningHistory()
        #expect(repo.entries().count == 1)
        #expect(entry.reviewCount == 0)
        #expect(entry.memory == nil)
        repo.deleteAll()
        #expect(repo.entries().isEmpty)
    }
}

@MainActor
struct PreferencesStoreTests {
    @Test func persistsAndResets() {
        let defaults = UserDefaults(suiteName: "prefs.\(UUID().uuidString)")!
        let store = PreferencesStore(defaults: defaults)
        store.preferences.language = .tamil
        store.preferences.rewindDuration = .twoMinutes
        store.ledger.record(.rewindQuestion, at: Date())
        let reloaded = PreferencesStore(defaults: defaults)
        #expect(reloaded.preferences.language == .tamil)
        #expect(reloaded.preferences.rewindDuration == .twoMinutes)
        #expect(reloaded.ledger.used(.rewindQuestion) == 1)
        reloaded.resetAll()
        #expect(PreferencesStore(defaults: defaults).preferences == UserPreferences())
    }

    @Test func onboardingSeedsProfile() {
        let store = PreferencesStore(defaults: UserDefaults(suiteName: "prefs.\(UUID().uuidString)")!)
        store.preferences.selfRating = SelfRating(comprehension: 5, speaking: 1, reading: 1)
        store.completeOnboarding()
        #expect(store.preferences.hasCompletedOnboarding)
        #expect(store.profile.score(.listening).estimated == 100)
        #expect(store.profile.score(.speaking).estimated == 0)
    }
}

/// Verifies the transcriber's buffer conversion, which runs before Apple's
/// speech model sees any audio.
struct TranscriberBufferTests {
    @Test func wrapsSamplesWithoutConversion() throws {
        let snapshot = AudioSnapshot(samples: [0.1, -0.2, 0.3], sampleRate: 16_000)
        let format = AudioCaptureEngine.targetFormat
        let buffer = try OnDeviceTranscriber.makeBuffer(snapshot, format: format)
        #expect(buffer.frameLength == 3)
        #expect(abs(buffer.floatChannelData![0][1] + 0.2) < 0.0001)
    }

    @Test func resamplesToAnalyzerFormat() throws {
        let snapshot = AudioSnapshot(samples: Array(repeating: 0.1, count: 16_000), sampleRate: 16_000)
        let target = try #require(AVAudioFormatFactory.int16(sampleRate: 8_000))
        let buffer = try OnDeviceTranscriber.makeBuffer(snapshot, format: target)
        #expect(buffer.format.sampleRate == 8_000)
        #expect(abs(Int(buffer.frameLength) - 8_000) < 200)
    }
}

import AVFoundation

enum AVAudioFormatFactory {
    static func int16(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
    }
}
