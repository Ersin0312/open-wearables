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
        TabView {
            DashboardView()
                .tabItem { Label("Übersicht", systemImage: "square.grid.2x2.fill") }

            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell.fill") }

            SupplementsView()
                .tabItem { Label("Supplements", systemImage: "pills.fill") }

            BodyView()
                .tabItem { Label("Körper", systemImage: "figure.stand") }

            SettingsView(hasKey: $hasKey)
                .tabItem { Label("Mehr", systemImage: "gearshape.fill") }
        }
    }
}
