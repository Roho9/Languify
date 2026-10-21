import AppIntents
import SwiftData
import SwiftUI

@main
struct LanguifyApp: App {
    @State private var services: AppServices

    init() {
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if uiTesting, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let services = AppServices(inMemoryStore: uiTesting)
        _services = State(initialValue: services)
        // App Intents (Siri, Shortcuts, Live Activity buttons) resolve the same
        // service graph as the UI.
        AppDependencyManager.shared.add(dependency: services)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .modelContainer(services.modelContainer)
                .task { await services.bootstrap() }
        }
    }
}
