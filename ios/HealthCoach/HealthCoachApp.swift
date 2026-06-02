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
            SupplementsView()
                .tabItem { Label("Supplements", systemImage: "pills.fill") }

            SettingsView(hasKey: $hasKey)
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
    }
}
