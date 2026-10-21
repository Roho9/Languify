import AppIntents
import AuthenticationServices
import LanguifyKit
import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false

    var body: some View {
        @Bindable var prefs = services.preferences
        NavigationStack {
            Form {
                Section {
                    AccountRow()
                    HStack {
                        Label(services.subscriptions.tier == .premium ? "Premium" : "Free", systemImage: services.subscriptions.tier == .premium ? "crown.fill" : "person")
                        Spacer()
                        if services.subscriptions.tier == .premium {
                            Button("Manage") { showManageSubscriptions = true }
                        } else {
                            Button("Upgrade") { showPaywall = true }
                        }
                    }
                    UsageRow()
                } header: {
                    Text("Account")
                }

                Section("Language") {
                    Picker("Heritage language", selection: $prefs.preferences.language) {
                        ForEach(HeritageLanguage.allCases) { Text("\($0.displayName) \u{00B7} \($0.configuration.nativeName)").tag($0) }
                    }
                    NavigationLink("Speech models") { SpeechModelsView() }
                }

                Section {
                    Picker("Rewind window", selection: $prefs.preferences.rewindDuration) {
                        ForEach(RewindDuration.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Answers", selection: $prefs.preferences.responseMode) {
                        ForEach(ResponseMode.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Live Rewind")
                } footer: {
                    Text(prefs.preferences.responseMode.detail + " Bluetooth speakers and car audio can look like headphones to iOS, so choose Silent if that's a concern.")
                }

                Section("Display") {
                    Picker("Show first", selection: $prefs.preferences.scriptDisplay) {
                        ForEach(ScriptDisplay.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Show \(services.preferences.language.configuration.scriptName)", isOn: $prefs.preferences.showNativeScript)
                }

                Section {
                    Toggle("Save asked-about words automatically", isOn: $prefs.preferences.autoSaveVocabulary)
                    Toggle("Suggest words after a session", isOn: $prefs.preferences.proactiveSuggestions)
                        .disabled(!services.subscriptions.resolver.has(.proactiveSuggestions))
                    Toggle("Daily practice reminder", isOn: Binding(
                        get: { prefs.preferences.dailyReminder },
                        set: { enabled in
                            Task {
                                if enabled {
                                    prefs.preferences.dailyReminder = await ReminderScheduler.enable(hour: prefs.preferences.reminderHour)
                                } else {
                                    ReminderScheduler.disable()
                                    prefs.preferences.dailyReminder = false
                                }
                            }
                        }
                    ))
                } header: {
                    Text("Learning")
                } footer: {
                    Text("Suggestions (Premium) look at the last rewind window when you stop a session, and only if AI explanations are allowed. They never interrupt a conversation.")
                }

                Section {
                    NavigationLink { PrivacyView() } label: { Label("Privacy & consent", systemImage: "lock.shield") }
                    NavigationLink { DataManagementView() } label: { Label("Your data", systemImage: "externaldrive") }
                }

                Section("Siri") {
                    NavigationLink { SiriCommandsView() } label: { Label("What you can say", systemImage: "mic.badge.plus") }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    LabeledContent("AI service", value: AppConfiguration.apiBaseURL == nil ? "Not configured" : "Connected")
                    Link("Privacy policy", destination: AppConfiguration.privacyPolicyURL)
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }
}

private struct AccountRow: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let account = services.account
        VStack(alignment: .leading, spacing: 8) {
            if account.isSignedIn {
                HStack {
                    Label("Signed in with Apple", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    Button("Sign out") { Task { await account.signOut() } }
                }
            } else {
                Text("Optional. Signing in keeps your subscription and usage with you across devices. Your vocabulary syncs separately through iCloud.")
                    .font(.footnote).foregroundStyle(.secondary)
                SignInWithAppleButton(.signIn) { request in
                    account.configure(request)
                } onCompletion: { result in
                    Task { await account.handle(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
                .disabled(account.isWorking)
            }
            if let error = account.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

private struct UsageRow: View {
    @Environment(AppServices.self) private var services
    var body: some View {
        let resolver = services.subscriptions.resolver
        let limit = resolver.plan.dailyLimits[.rewindQuestion] ?? 0
        var ledger = services.preferences.ledger
        let _ = ledger.roll(to: Date())
        LabeledContent("Rewind questions today", value: "\(ledger.used(.rewindQuestion)) of \(limit)")
    }
}

struct SpeechModelsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Form {
            ForEach(HeritageLanguage.allCases) { language in
                Section(language.displayName) {
                    ForEach(services.speechModels.requiredLocales(for: language), id: \.self) { ModelStatusRow(localeIdentifier: $0) }
                }
                .task { await services.speechModels.refresh(for: language) }
            }
            Section {
                Text("Apple's on-device models transcribe speech without sending audio anywhere. Tamil and Malayalam models output romanised text; Languify's AI turns it into native script and explains it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Speech Models")
    }
}

struct SiriCommandsView: View {
    var body: some View {
        List {
            Section {
                Text("Start a session first, then say any of these. Phrases must include \u{201C}Languify\u{201D}; Siri also understands close variations.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Session") {
                Text("\u{201C}Start Languify\u{201D}")
                Text("\u{201C}Stop Languify\u{201D}")
            }
            Section("Questions") {
                Text("\u{201C}Ask Languify what that word meant\u{201D}")
                Text("\u{201C}Ask Languify what that sentence meant\u{201D}")
                Text("\u{201C}Ask Languify what was just said\u{201D}")
                Text("\u{201C}Ask Languify how to respond\u{201D}")
                Text("\u{201C}Tell Languify which word\u{201D} (after it asks you to choose)")
            }
            Section {
                ShortcutsLink()
            } footer: {
                Text("Siri answers through your AirPods when they're connected. Languify uses your iPhone's microphone for the conversation and keeps what was said before Siri started listening.")
            }
        }
        .navigationTitle("Siri")
    }
}
