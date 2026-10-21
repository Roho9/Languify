import AppIntents
import SwiftData
import SwiftUI

@main
struct LanguifyApp: App {
    @State private var services: AppServices

    init() {
        let services = AppServices(inMemoryStore: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
        _services = State(initialValue: services)
        // App Intents (Siri, Shortcuts, Live Activity buttons) resolve the same
        // service graph as the UI.
        AppDependencyManager.shared.add(dependency: services)
    }

    var body: some Scene {
        WindowGroup {
            Text("Languify")
                .environment(services)
                .modelContainer(services.modelContainer)
                .task { await services.bootstrap() }
        }
    }
}
