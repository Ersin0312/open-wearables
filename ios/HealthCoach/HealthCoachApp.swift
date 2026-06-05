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
    @StateObject private var daily = DailyStore()

    var body: some View {
        // Exactly 5 tabs so iOS never collapses them into a "More" menu.
        TabView {
            TodayView(daily: daily, hasKey: $hasKey)
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

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
