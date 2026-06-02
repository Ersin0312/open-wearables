import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var latestRecovery: RecoveryDay?
    @Published var todayVolume: Double = 0
    @Published var todaySets: Int = 0
    @Published var nemAdherence: [(name: String, pct: Int)] = []
    @Published var weight: Double?
    @Published var loading = false
    @Published var error: String?

    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func iso(_ daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let rec = APIClient.shared.recovery(startDate: Self.iso(2), endDate: Self.iso(0))
            async let body = APIClient.shared.bodySummary()
            async let sessions = APIClient.shared.trainingSessions(limit: 10)
            async let sups = APIClient.shared.supplements()
            async let intakes = APIClient.shared.intakes(startDate: Self.today(), endDate: Self.today())

            let (recovery, b, sess, supList, todayIntakes) = try await (rec, body, sessions, sups, intakes)

            latestRecovery = recovery.last
            weight = b.slowChanging?.weightKg

            // today's training volume across sessions started today
            let todayStr = Self.today()
            var vol = 0.0, setCount = 0
            for s in sess where String(s.startedAt.prefix(10)) == todayStr {
                let setsOf = try await APIClient.shared.sets(sessionID: s.id)
                for st in setsOf {
                    vol += Double(st.reps) * (Double(st.weightKg) ?? 0)
                    setCount += 1
                }
            }
            todayVolume = vol
            todaySets = setCount

            // NEM adherence today
            let byID = Dictionary(uniqueKeysWithValues: supList.map { ($0.id, $0) })
            var totals: [String: Double] = [:]
            for i in todayIntakes { totals[i.supplementID, default: 0] += Double(i.dose) ?? 0 }
            nemAdherence = totals.compactMap { (sid, total) in
                guard let sup = byID[sid], let recStr = sup.recommendedDailyDose,
                      let rec = Double(recStr), rec > 0 else { return nil }
                return (sup.name, Int((total / rec * 100).rounded()))
            }.sorted { $0.name < $1.name }
        } catch { self.error = error.localizedDescription }
    }
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @Binding var hasKey: Bool
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !hasKey {
                    Section {
                        Button {
                            showSettings = true
                        } label: {
                            Label("API-Key eintragen, um Daten zu laden", systemImage: "key.fill")
                        }
                    }
                }
                Section("Recovery") {
                    if let r = vm.latestRecovery {
                        row("Recovery-Score", r.recoveryScore.map { "\(Int($0))%" } ?? "–")
                        row("Ruhepuls", r.restingHeartRateBpm.map { "\(Int($0)) bpm" } ?? "–")
                        row("HRV", r.avgHrvSdnnMs.map { "\(Int($0)) ms" } ?? "–")
                    } else {
                        Text("Keine Recovery-Daten.").foregroundStyle(.secondary)
                    }
                }

                Section("Training heute") {
                    row("Sätze", "\(vm.todaySets)")
                    row("Volumen", "\(fmt(vm.todayVolume)) kg")
                }

                Section("Supplements heute") {
                    if vm.nemAdherence.isEmpty {
                        Text("Noch nichts geloggt oder ohne Tagesdosis.").foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.nemAdherence, id: \.name) { a in
                            row(a.name, "\(a.pct)%")
                        }
                    }
                }

                if let w = vm.weight {
                    Section("Körper") { row("Gewicht", "\(fmt(w)) kg") }
                }
            }
            .navigationTitle("Übersicht")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(hasKey: $hasKey) }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l); Spacer(); Text(v).foregroundStyle(.secondary) }
    }
}
