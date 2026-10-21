import LanguifyKit
import SwiftUI

struct RootView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        if services.preferences.preferences.hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingFlow()
        }
    }
}

struct MainTabView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var services = services
        TabView(selection: $services.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Rewind", systemImage: "waveform.badge.magnifyingglass", value: AppTab.rewind) {
                LiveRewindView()
            }
            Tab("Vocabulary", systemImage: "character.book.closed", value: AppTab.vocabulary) {
                VocabularyListView()
            }
            Tab("Learn", systemImage: "graduationcap", value: AppTab.learn) {
                LearnView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(ListeningAccessoryModifier(isActive: services.listening.state.isSessionActive))
    }
}

/// iOS 26.1 can hide the accessory when no session is active. On 26.0 the
/// accessory is always present, so it is only attached during a session.
private struct ListeningAccessoryModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isActive) { ListeningAccessory() }
        } else if isActive {
            content.tabViewBottomAccessory { ListeningAccessory() }
        } else {
            content
        }
    }
}

/// Floating Liquid Glass accessory shown above the tab bar whenever a session
/// is active, so listening status and Stop are reachable from every tab.
struct ListeningAccessory: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let listening = services.listening
        HStack(spacing: 12) {
            Image(systemName: listening.state.isCapturing ? "waveform" : "pause.circle")
                .symbolEffect(.variableColor.iterative, isActive: listening.state.isCapturing)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(statusText(listening.state)).font(.subheadline.weight(.semibold))
                if let started = listening.startedAt {
                    Text(started, style: .timer).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                services.selectedTab = .rewind
            } label: {
                Image(systemName: "questionmark.bubble")
            }
            .accessibilityLabel("Ask about what was just said")
            Button(role: .destructive) {
                Task { await listening.stop() }
            } label: {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop listening")
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private func statusText(_ state: ListeningSessionState) -> String {
        switch state {
        case .listening: "Listening"
        case .processing: "Thinking\u{2026}"
        case .paused: "Paused"
        case .interrupted: "Mic in use by iOS"
        default: "Starting\u{2026}"
        }
    }
}
