import SwiftUI

@main
struct HealthCoachApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var hasKey = Keychain.get(account: AppConfig.apiKeyKeychainAccount)?.isEmpty == false

    var body: some View {
        // Exactly 5 tabs so iOS never collapses them into a "More" menu.
        // Settings live behind a gear in the Übersicht toolbar.
        TabView {
            DashboardView(hasKey: $hasKey)
                .tabItem { Label("Übersicht", systemImage: "square.grid.2x2.fill") }

            CoachView()
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }

            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell.fill") }

            SupplementsView()
                .tabItem { Label("Supplements", systemImage: "pills.fill") }

            BodyView()
                .tabItem { Label("Körper", systemImage: "figure.stand") }
        }
    }
}
