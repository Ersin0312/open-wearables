import SwiftUI
import Charts

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var recovery: [RecoveryDay] = []
    @Published var sleep: [SleepDay] = []
    @Published var todayVolume: Double = 0
    @Published var todaySets: Int = 0
    @Published var nemAdherence: [(name: String, pct: Int)] = []
    @Published var weight: Double?
    @Published var loading = false
    @Published var error: String?

    var latestRecovery: RecoveryDay? { recovery.last }
    var latestSleep: SleepDay? { sleep.last }

    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func iso(_ daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let rec = APIClient.shared.recovery(startDate: Self.iso(7), endDate: Self.iso(0))
            async let slp = APIClient.shared.sleep(startDate: Self.iso(7), endDate: Self.iso(0))
            async let body = APIClient.shared.bodySummary()
            async let sessions = APIClient.shared.trainingSessions(limit: 10)
            async let sups = APIClient.shared.supplements()
            async let intakes = APIClient.shared.intakes(startDate: Self.today(), endDate: Self.today())
            let (r, s, b, sess, supList, todayIntakes) = try await (rec, slp, body, sessions, sups, intakes)

            recovery = r
            sleep = s
            weight = b.slowChanging?.weightKg

            let todayStr = Self.today()
            var vol = 0.0, setCount = 0
            for ses in sess where String(ses.startedAt.prefix(10)) == todayStr {
                let setsOf = try await APIClient.shared.sets(sessionID: ses.id)
                for st in setsOf { vol += Double(st.reps) * (Double(st.weightKg) ?? 0); setCount += 1 }
            }
            todayVolume = vol; todaySets = setCount

            let byID = Dictionary(uniqueKeysWithValues: supList.map { ($0.id, $0) })
            var totals: [String: Double] = [:]
            for i in todayIntakes { totals[i.supplementID, default: 0] += Double(i.dose) ?? 0 }
            nemAdherence = totals.compactMap { (sid, total) in
                guard let sup = byID[sid], let recStr = sup.recommendedDailyDose,
                      let rec2 = Double(recStr), rec2 > 0 else { return nil }
                return (sup.name, Int((total / rec2 * 100).rounded()))
            }.sorted { $0.name < $1.name }
        } catch { self.error = error.localizedDescription }
    }
}

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @Binding var hasKey: Bool
    @State private var showSettings = false

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !hasKey {
                        Button { showSettings = true } label: {
                            Label("API-Key eintragen, um Daten zu laden", systemImage: "key.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    ringsRow
                    if !vm.nemAdherence.isEmpty { supplementsCard }
                    recoveryTrendCard
                    sleepTrendCard
                    if let w = vm.weight { weightCard(w) }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Heute")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(hasKey: $hasKey) }.preferredColorScheme(.dark)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
        .preferredColorScheme(.dark)
    }

    // Three headline rings: Recovery, Sleep, Training volume.
    private var ringsRow: some View {
        HStack(spacing: 18) {
            let rec = vm.latestRecovery?.recoveryScore ?? 0
            MetricRing(value: rec / 100,
                       displayValue: vm.latestRecovery?.recoveryScore.map { String(Int($0)) } ?? "–",
                       unit: "%", label: "Recovery",
                       color: Theme.scoreColor(rec), size: 92, lineWidth: 9)

            let eff = vm.latestSleep?.efficiencyPercent ?? 0
            let dur = vm.latestSleep?.durationMinutes ?? 0
            MetricRing(value: dur / 480,  // 8h reference
                       displayValue: dur > 0 ? hm(dur) : "–",
                       unit: eff > 0 ? "\(Int(eff))%" : nil, label: "Schlaf",
                       color: Theme.violet, size: 92, lineWidth: 9)

            MetricRing(value: min(vm.todayVolume / 6000, 1),
                       displayValue: vm.todayVolume > 0 ? "\(Int(vm.todayVolume/1000))k" : "0",
                       unit: "kg", label: "Volumen",
                       color: Theme.accent, size: 92, lineWidth: 9)
        }
        .frame(maxWidth: .infinity)
    }

    private var supplementsCard: some View {
        DashCard(title: "Supplements heute", systemImage: "pills.fill") {
            ForEach(vm.nemAdherence, id: \.name) { a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(a.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(a.pct)%").font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Theme.scoreColor(Double(a.pct)))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.cardElevated).frame(height: 6)
                            Capsule().fill(Theme.scoreColor(Double(a.pct)))
                                .frame(width: geo.size.width * min(Double(a.pct)/100, 1), height: 6)
                        }
                    }.frame(height: 6)
                }
            }
        }
    }

    private var recoveryTrendCard: some View {
        DashCard(title: "Recovery · 7 Tage", systemImage: "heart.fill") {
            if vm.recovery.isEmpty {
                Text("Keine Daten.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                Chart(vm.recovery) { d in
                    BarMark(x: .value("Tag", String(d.date.suffix(5))),
                            y: .value("Recovery", d.recoveryScore ?? 0))
                        .foregroundStyle(Theme.scoreColor(d.recoveryScore ?? 0))
                        .cornerRadius(4)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 130)
                HStack(spacing: 8) {
                    StatChip(value: vm.latestRecovery?.restingHeartRateBpm.map { "\(Int($0))" } ?? "–",
                             label: "Ruhepuls bpm", color: Theme.danger)
                    StatChip(value: vm.latestRecovery?.avgHrvSdnnMs.map { "\(Int($0))" } ?? "–",
                             label: "HRV ms", color: Theme.teal)
                    StatChip(value: vm.latestRecovery?.avgSpo2Percent.map { "\(Int($0))" } ?? "–",
                             label: "SpO₂ %", color: Theme.accent)
                }
            }
        }
    }

    private var sleepTrendCard: some View {
        DashCard(title: "Schlaf · 7 Tage", systemImage: "moon.stars.fill") {
            if vm.sleep.isEmpty {
                Text("Keine Daten.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                Chart(vm.sleep) { d in
                    BarMark(x: .value("Tag", String(d.date.suffix(5))),
                            y: .value("Stunden", (d.durationMinutes ?? 0) / 60))
                        .foregroundStyle(Theme.violet)
                        .cornerRadius(4)
                }
                .frame(height: 130)
            }
        }
    }

    private func weightCard(_ w: Double) -> some View {
        DashCard(title: "Körper", systemImage: "figure.stand") {
            HStack {
                Text("Gewicht").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(fmt(w)) kg").font(.title3).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private func hm(_ minutes: Double) -> String {
        let m = Int(minutes); return "\(m/60):\(String(format: "%02d", m%60))"
    }
}
