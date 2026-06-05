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
    @StateObject private var brief = CoachBriefStore()
    @ObservedObject var daily: DailyStore
    @Binding var hasKey: Bool
    @State private var showSettings = false
    @State private var showNutrition = false
    @State private var showSupplements = false
    @State private var showWeekly = false
    @State private var briefExpanded = false
    @State private var expandedAgenda: Set<String> = []

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
                    briefingCard
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
            .sheet(isPresented: $showSupplements) {
                SupplementsView().preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showWeekly) {
                WeeklyReviewSheet(brief: brief, context: clientContext()).preferredColorScheme(.dark)
            }
            .task {
                await vm.load(); await nutrition.load()
                if hasKey { await brief.ensureMorning(context: clientContext()) }
            }
            .refreshable {
                await vm.load(); await nutrition.load()
                if hasKey { await brief.ensureMorning(context: clientContext()) }
            }
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

    // Assemble the live metrics the brief endpoint needs (client-side context).
    private func clientContext() -> String {
        let p = PlanConfig.currentPhase
        let cur = vm.weight7dAvg ?? vm.currentWeight
        var l: [String] = []
        l.append("Phase: Tag \(PlanConfig.currentDay) von \(PlanConfig.totalDays) · Phase \(p.index) (\(p.name)). Phasenziel \(Int(p.goalWeight)) kg, Endziel \(Int(PlanConfig.endGoalWeight)) kg. Start war \(fmt(PlanConfig.startWeight)) kg.")
        if let c = cur { l.append("Gewicht 7-Tage-Mittel: \(fmt(c)) kg (noch \(fmt(c - p.goalWeight)) kg bis Phasenziel).") }
        else { l.append("Gewicht: kein aktueller Wert synchronisiert.") }
        if let r = vm.recovery {
            let hrv = r.avgHrvSdnnMs.map { " HRV \(Int($0)) ms," } ?? ""
            let rhr = r.restingHeartRateBpm.map { " Ruhepuls \(Int($0)) bpm," } ?? ""
            l.append("Recovery heute: \(Int(r.recoveryScore ?? 0))%.\(hrv)\(rhr)")
        } else { l.append("Recovery: heute noch nicht synchronisiert.") }
        if let m = vm.sleepMinutes { l.append("Schlaf letzte Nacht: \(Int(m) / 60)h\(String(format: "%02d", Int(m) % 60)).") }
        l.append("Heutiges Workout laut Plan: \(PlanConfig.workoutForToday()). Training heute \(vm.trainingLoggedToday ? "bereits geloggt" : "noch nicht geloggt").")
        l.append("Ernährung heute bisher: \(nutrition.totalKcal) kcal von \(nutrition.calorieGoalText), \(nutrition.totalProtein) g von \(nutrition.proteinGoal) g Protein (\(nutrition.todayEntries.count) Einträge).")
        l.append("Supplements heute geloggt: \(vm.supplementsLoggedToday).")
        if let alert = PlanConfig.phaseTransitionAlert { l.append("Phasen-Hinweis: \(alert)") }
        return l.joined(separator: "\n")
    }

    // Coach briefing — proactive morning brief (cached/day) + phase alert.
    @ViewBuilder
    private var briefingCard: some View {
        DashCard(title: "Coach-Briefing", systemImage: "brain.head.profile") {
            if let alert = PlanConfig.phaseTransitionAlert {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "flag.checkered").font(.caption).foregroundStyle(Theme.warn)
                    Text(alert).font(.caption).foregroundStyle(Theme.warn)
                }
            }
            if brief.loadingMorning && brief.morningBody == nil {
                HStack(spacing: 8) { ProgressView().tint(Theme.accent); Text("Der Coach bereitet deinen Morgenbrief vor…").font(.subheadline).foregroundStyle(Theme.textSecondary) }
            } else if let head = brief.morningHeadline {
                Text(head).font(.headline).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = brief.morningBody {
                    if briefExpanded {
                        BriefMarkdown(text: body)
                    } else {
                        Text(snippet(body)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                    }
                    Button(briefExpanded ? "Weniger" : "Mehr anzeigen") { withAnimation { briefExpanded.toggle() } }
                        .font(.caption).foregroundStyle(Theme.accent)
                }
            } else if !hasKey {
                Text("Trage deinen API-Key ein, dann erstellt der Coach hier deinen täglichen Morgenbrief.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                Text(brief.error ?? "Noch kein Briefing — tippe auf Aktualisieren.")
                    .font(.subheadline).foregroundStyle(brief.error == nil ? Theme.textSecondary : Theme.danger)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await brief.ensureMorning(context: clientContext(), force: true) }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise").font(.caption)
                }.buttonStyle(.bordered).tint(Theme.accent)
                Button { showWeekly = true } label: {
                    Label("Wochenreview", systemImage: "calendar").font(.caption)
                }.buttonStyle(.bordered).tint(Theme.violet)
            }
            .disabled(!hasKey)
        }
    }

    private func snippet(_ body: String) -> String {
        body.replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "- ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            expandableRow("protein", "Protein \(nutrition.totalProtein)/\(nutrition.proteinGoal) g",
                          done: nutrition.totalProtein >= nutrition.proteinGoal) {
                ManualAddField(placeholder: "Menge", unit: "g", hint: "Eingegebene Gramm werden zum Tagesprotein addiert.") { g in
                    Task { await nutrition.quickAddProtein(g) }
                }
            }
            agendaRow("calories", "Kalorien \(nutrition.totalKcal)/\(nutrition.calorieGoalText) kcal",
                      done: nutrition.totalKcal > 0 && nutrition.totalKcal <= nutrition.calorieGoalValue,
                      action: { showNutrition = true })
            agendaRow("supps", "Supplements (\(vm.supplementsLoggedToday) heute)",
                      done: vm.supplementsLoggedToday > 0, action: { showSupplements = true })
            expandableRow("water", "Wasser \(fmt(daily.waterLiters))/\(fmt(daily.waterGoal)) L",
                          done: daily.waterLiters >= daily.waterGoal) {
                VStack(alignment: .leading, spacing: 8) {
                    ManualAddField(placeholder: "Menge", unit: "ml", hint: "Eingegebene Milliliter werden zur Tagesmenge addiert.") { ml in
                        daily.addWater(ml / 1000.0)
                    }
                    Button("Zurücksetzen") { daily.resetWater() }
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            if Calendar.current.component(.weekday, from: Date()) == 1 {
                agendaRow("waist", "Bauchumfang messen (Sonntag)", done: false)
            }
            agendaRow("bed", "Bettzeit einhalten", done: false)
        }
    }

    private func agendaRow(_ id: String, _ label: String, done: Bool, action: (() -> Void)? = nil) -> some View {
        let checked = done || daily.isChecked(id)
        return Button {
            if let action { action() } else { daily.toggle(id) }
        } label: {
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? Theme.good : Theme.textSecondary)
                Text(label)
                    .foregroundStyle(checked ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(checked, color: Theme.textSecondary)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// An agenda row that expands inline to reveal quick-add controls.
    private func expandableRow<Content: View>(_ id: String, _ label: String, done: Bool,
                                              @ViewBuilder content: () -> Content) -> some View {
        let isOpen = expandedAgenda.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isOpen { expandedAgenda.remove(id) } else { expandedAgenda.insert(id) }
                }
            } label: {
                HStack {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? Theme.good : Theme.textSecondary)
                    Text(label)
                        .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                        .strikethrough(done, color: Theme.textSecondary)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            if isOpen { content().padding(.leading, 28) }
        }
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

/// A manual numeric entry for agenda quick-logs (water ml, protein g). The user
/// types the amount and taps Hinzufügen — no preset suggestions.
struct ManualAddField: View {
    let placeholder: String
    let unit: String
    var hint: String? = nil
    let onAdd: (Double) -> Void
    @State private var text = ""

    private var value: Double? {
        let v = Double(text.replacingOccurrences(of: ",", with: "."))
        return (v ?? 0) > 0 ? v : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .background(Theme.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(unit).foregroundStyle(Theme.textSecondary)
                Button { if let v = value { onAdd(v); text = "" } } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(value == nil)
            }
            if let hint { Text(hint).font(.caption2).foregroundStyle(Theme.textSecondary) }
        }
    }
}
