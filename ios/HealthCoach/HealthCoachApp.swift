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
        // Exactly 5 tabs (Arda IA) so iOS never collapses them into a "More"
        // menu. Supplements moved to a sheet reachable from HEUTE's agenda.
        TabView {
            TodayView(daily: daily, hasKey: $hasKey)
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }

            PlanView()
                .tabItem { Label("Plan", systemImage: "map.fill") }

            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell.fill") }

            BodyView()
                .tabItem { Label("Fortschritt", systemImage: "chart.line.uptrend.xyaxis") }

            CoachView()
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
        }
    }
}
