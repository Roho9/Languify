import LanguifyKit
import SwiftUI

struct PrivacyView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var prefs = services.preferences
        Form {
            Section {
                Toggle(isOn: $prefs.preferences.cloudProcessingConsent) {
                    VStack(alignment: .leading) {
                        Text("Allow AI explanations")
                        Text("Sends the transcribed text of the rewind window, only when you ask.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("When off, Languify still transcribes on your iPhone and shows you what it heard, but can't explain it.")
            }

            Section("How audio is handled") {
                PrivacyRow(symbol: "hand.raised", text: "Listening only happens in sessions you start. iOS shows the microphone indicator and a Live Activity the whole time.")
                PrivacyRow(symbol: "memorychip", text: "Audio is held in memory only: at most your rewind window (30 s to 2 min). Older audio is overwritten continuously.")
                PrivacyRow(symbol: "trash", text: "Stopping a session, or an error, erases the buffer immediately.")
                PrivacyRow(symbol: "iphone", text: "Speech recognition runs on your iPhone. Audio is never uploaded, saved to disk, or included in backups.")
                PrivacyRow(symbol: "text.bubble", text: "When you ask, only the text of the rewind window goes to Languify's server, which passes it to its AI provider (Anthropic) to write the explanation. Languify's server doesn't store it. Under its API terms the provider doesn't train on it, and may keep it for a limited time for abuse monitoring.")
                PrivacyRow(symbol: "character.book.closed", text: "Your journal keeps each word plus the one sentence it appeared in, nothing more.")
            }

            Section("Other people") {
                RecordingConsentNote()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Privacy")
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol).font(.subheadline)
    }
}

struct DataManagementView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SyncSettings.key) private var syncEnabled = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmHistory = false
    @State private var confirmAll = false
    @State private var deletionMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Sync vocabulary with iCloud", isOn: $syncEnabled)
            } footer: {
                Text(FileManager.default.ubiquityIdentityToken == nil
                     ? "Sign in to iCloud in the Settings app to use sync. "
                     : "Takes effect next time Languify opens. Uses your iCloud account, independent of Sign in with Apple. Audio is never synced.")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export file", systemImage: "square.and.arrow.up") }
                } else {
                    Button { export() } label: { Label("Export my learning data", systemImage: "arrow.down.doc") }
                }
                if let exportError { Text(exportError).foregroundStyle(.orange) }
            } footer: {
                Text("A JSON file with your words, review history, preferences and skill profile.")
            }

            Section {
                Button("Delete learning history", role: .destructive) { confirmHistory = true }
                Button("Delete all my data", role: .destructive) { confirmAll = true }
            } footer: {
                Text("Learning history resets reviews and progress but keeps your words. Deleting all data removes words, history, settings, your guest or Apple sign-in identity, and Languify's server-side usage records.")
            }

            if let deletionMessage {
                Section { Text(deletionMessage) }
            }
        }
        .navigationTitle("Your Data")
        .confirmationDialog("Delete learning history?", isPresented: $confirmHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) {
                services.repository.deleteLearningHistory()
                services.preferences.profile = .seeded(from: services.preferences.preferences.selfRating)
                deletionMessage = "Learning history deleted."
            }
        }
        .confirmationDialog("Delete everything?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                Task {
                    let serverOK = await services.deleteEverything()
                    deletionMessage = serverOK ? "All data deleted." : "Local data deleted. Server records couldn't be reached; try again when online."
                }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func export() {
        do {
            exportURL = try services.exportData()
        } catch {
            exportError = "Couldn't create the export."
        }
    }
}
