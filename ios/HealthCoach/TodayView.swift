import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var recovery: RecoveryDay?
    @Published var sleepMinutes: Double?
    @Published var weight7dAvg: Double?
    @Published var currentWeight: Double?
    @Published var trainingLoggedToday = false
    @Published var supplementsLoggedToday = 0
    @Published var loading = false

    private static func iso(_ daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func load() async {
        loading = true
        defer { loading = false }
        async let rec = try? APIClient.shared.recovery(startDate: Self.iso(2), endDate: Self.iso(0))
        async let slp = try? APIClient.shared.sleep(startDate: Self.iso(2), endDate: Self.iso(0))
        async let body = try? APIClient.shared.bodySummary()
        async let trend = try? APIClient.shared.bodyTrend(startDate: Self.iso(7), endDate: Self.iso(0))
        async let sessions = try? APIClient.shared.trainingSessions(limit: 10)
        async let intakes = try? APIClient.shared.intakes(startDate: Self.iso(1), endDate: Self.iso(0))

        let (r, s, b, t, sess, intk) = await (rec, slp, body, trend, sessions, intakes)

        recovery = r?.last
        sleepMinutes = s?.last?.durationMinutes
        currentWeight = b?.slowChanging?.weightKg

        // 7-day weight average from the trend timeseries.
        let weights = (t ?? []).filter { $0.type == "weight" }.map { $0.value }
        weight7dAvg = weights.isEmpty ? nil : weights.reduce(0, +) / Double(weights.count)

        let today = Self.iso(0)
        trainingLoggedToday = (sess ?? []).contains { String($0.startedAt.prefix(10)) == today }
        supplementsLoggedToday = (intk ?? []).filter { Calendar.current.isDateInToday(
            ISO8601DateFormatter().date(from: $0.takenAt) ?? .distantPast) }.count
    }
}

struct TodayView: View {
    @StateObject private var vm = TodayViewModel()
    @StateObject private var nutrition = NutritionStore()
    @ObservedObject var daily: DailyStore
    @Binding var hasKey: Bool
    @State private var showSettings = false
    @State private var showNutrition = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !hasKey {
                        Button { showSettings = true } label: {
                            Label("API-Key eintragen", systemImage: "key.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }

                    statusLine
                    northStar
                    nutritionCard
                    agenda
                    recoveryCard
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
            .sheet(isPresented: $showNutrition) {
                NutritionView(store: nutrition).preferredColorScheme(.dark)
            }
            .task { await vm.load(); await nutrition.load() }
            .refreshable { await vm.load(); await nutrition.load() }
        }
        .preferredColorScheme(.dark)
    }

    // Status line: Tag n/365 · Phase X · Name
    private var statusLine: some View {
        let p = PlanConfig.currentPhase
        return Text("Tag \(PlanConfig.currentDay) von \(PlanConfig.totalDays) · Phase \(p.index) · \(p.name)")
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // North-Star: current 7d weight → phase goal → end goal, as a progress bar.
    private var northStar: some View {
        let cur = vm.weight7dAvg ?? vm.currentWeight ?? PlanConfig.startWeight
        let phaseGoal = PlanConfig.currentPhase.goalWeight
        let endGoal = PlanConfig.endGoalWeight
        let start = PlanConfig.startWeight
        let lost = max(0, start - cur)
        // progress toward END goal
        let total = start - endGoal
        let progress = total > 0 ? min(max((start - cur) / total, 0), 1) : 0

        return DashCard(title: "North Star", systemImage: "scope") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fmt(cur)).font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("kg").foregroundStyle(Theme.textSecondary)
                Text("(7-T-Mittel)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardElevated).frame(height: 8)
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * progress, height: 8)
                }
            }.frame(height: 8)
            HStack {
                Text("\(fmt(cur)) kg").foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("→ \(fmt(phaseGoal)) (Phase)").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("→ \(fmt(endGoal)) (Ziel)").foregroundStyle(Theme.textSecondary)
            }.font(.caption)
            Text("Bisher \(fmt(lost)) kg verloren · \(PlanConfig.daysLeftInPhase) Tage in dieser Phase")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    // Ernährung heute — real totals from logged entries; tap to open the log.
    private var nutritionCard: some View {
        let kcal = nutrition.totalKcal
        let pro = nutrition.totalProtein
        let kcalGoal = nutrition.calorieGoalValue
        let proPct = nutrition.proteinGoal > 0 ? Double(pro) / Double(nutrition.proteinGoal) : 0
        let kcalPct = kcalGoal > 0 ? Double(kcal) / Double(kcalGoal) : 0
        return Button { showNutrition = true } label: {
            DashCard(title: "Ernährung heute", systemImage: "fork.knife") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(kcal)").font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("/ \(nutrition.calorieGoalText) kcal").font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text("Protein \(pro)/\(nutrition.proteinGoal) g · \(nutrition.todayEntries.count) Einträge")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                }
                progressBar(kcalPct, color: kcalColorToday(kcalPct))
                progressBar(proPct, color: Theme.violet)
            }
        }
        .buttonStyle(.plain)
    }

    private func progressBar(_ pct: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardElevated).frame(height: 6)
                Capsule().fill(color).frame(width: geo.size.width * min(max(pct, 0), 1), height: 6)
            }
        }.frame(height: 6)
    }

    private func kcalColorToday(_ pct: Double) -> Color {
        switch pct { case ..<0.85: return Theme.good; case ..<1.0: return Theme.warn; default: return Theme.danger }
    }

    // Daily agenda — checkable items.
    private var agenda: some View {
        DashCard(title: "Tagesagenda", systemImage: "checklist") {
            agendaRow("training", "Training: \(PlanConfig.workoutForToday())",
                      done: vm.trainingLoggedToday)
            agendaRow("protein", "Protein \(nutrition.totalProtein)/\(nutrition.proteinGoal) g",
                      done: nutrition.totalProtein >= nutrition.proteinGoal)
            agendaRow("calories", "Kalorien \(nutrition.totalKcal)/\(nutrition.calorieGoalText) kcal",
                      done: nutrition.totalKcal > 0 && nutrition.totalKcal <= nutrition.calorieGoalValue)
            agendaRow("supps", "Supplements (\(vm.supplementsLoggedToday) heute)",
                      done: vm.supplementsLoggedToday > 0)
            agendaRow("water", "Wasser \(fmt(daily.waterLiters))/\(fmt(daily.waterGoal)) L",
                      done: daily.waterLiters >= daily.waterGoal)
            if Calendar.current.component(.weekday, from: Date()) == 1 {
                agendaRow("waist", "Bauchumfang messen (Sonntag)", done: false)
            }
            agendaRow("bed", "Bettzeit einhalten", done: false)
        }
    }

    private func agendaRow(_ id: String, _ label: String, done: Bool) -> some View {
        let checked = done || daily.isChecked(id)
        return Button {
            daily.toggle(id)
        } label: {
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Theme.good : Theme.textSecondary)
                Text(label)
                    .foregroundStyle(checked ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(checked, color: Theme.textSecondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var recoveryCard: some View {
        Group {
            if let i = RecoveryInterpretation.make(recovery: vm.recovery, sleepMinutes: vm.sleepMinutes) {
                DashCard(title: "Recovery heute", systemImage: "heart.fill") {
                    Text(i.headline).font(.headline).foregroundStyle(i.color)
                    Text(i.detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text(i.recommendation).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    if let limit = i.mainLimit {
                        Text("Hauptlimit heute: \(limit)").font(.caption).foregroundStyle(Theme.warn)
                    }
                }
            } else {
                DashCard(title: "Recovery heute", systemImage: "heart.fill") {
                    Text("Noch keine WHOOP-Recovery synchronisiert.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
