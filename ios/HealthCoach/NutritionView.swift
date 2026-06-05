import SwiftUI

/// Full nutrition log for today: macro totals against the phase goals, the
/// day's entries (swipe to delete), and an add flow (OFF search or manual).
struct NutritionView: View {
    @ObservedObject var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    macroSummary
                    logCard
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Ernährung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFoodSheet(store: store).preferredColorScheme(.dark)
            }
            .task { await store.load() }
            .refreshable { await store.load() }
        }
        .preferredColorScheme(.dark)
    }

    private var macroSummary: some View {
        let kcalPct = store.calorieGoalValue > 0 ? Double(store.totalKcal) / Double(store.calorieGoalValue) : 0
        let proPct = store.proteinGoal > 0 ? Double(store.totalProtein) / Double(store.proteinGoal) : 0
        return DashCard(title: "Heute", systemImage: "fork.knife") {
            HStack(spacing: 18) {
                MetricRing(value: kcalPct, displayValue: "\(store.totalKcal)", unit: "kcal",
                           label: "Ziel \(store.calorieGoalText)", color: kcalColor(kcalPct), size: 104, lineWidth: 10)
                MetricRing(value: proPct, displayValue: "\(store.totalProtein)", unit: "g",
                           label: "Protein \(store.proteinGoal) g", color: Theme.violet, size: 104, lineWidth: 10)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                StatChip(value: "\(store.totalCarbs) g", label: "Kohlenhydrate", color: Theme.teal)
                StatChip(value: "\(store.totalFat) g", label: "Fett", color: Theme.warn)
            }
        }
    }

    // Calorie ring: green while under the ceiling, amber near it, red over.
    private func kcalColor(_ pct: Double) -> Color {
        switch pct {
        case ..<0.85: return Theme.good
        case ..<1.0: return Theme.warn
        default: return Theme.danger
        }
    }

    private var logCard: some View {
        DashCard(title: "Logbuch", systemImage: "list.bullet") {
            if store.todayEntries.isEmpty {
                Text(store.loading ? "Lade…" : "Noch nichts geloggt. Tippe oben rechts auf +.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                ForEach(store.todayEntries) { e in
                    entryRow(e)
                    if e.id != store.todayEntries.last?.id {
                        Divider().overlay(Theme.cardElevated)
                    }
                }
            }
            if let err = store.error {
                Text(err).font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private func entryRow(_ e: NutritionEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).foregroundStyle(Theme.textPrimary).font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if let g = e.grams { Text("\(Int(g)) g").foregroundStyle(Theme.textSecondary) }
                    Text("P \(Int(e.protein))").foregroundStyle(Theme.violet)
                    Text("K \(Int(e.carbs))").foregroundStyle(Theme.teal)
                    Text("F \(Int(e.fat))").foregroundStyle(Theme.warn)
                }.font(.caption2)
            }
            Spacer()
            Text("\(Int(e.kcal)) kcal").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Button { Task { await store.delete(e) } } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(Theme.danger)
            }.buttonStyle(.plain).padding(.leading, 6)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Add flow

/// Two ways to log: search Open Food Facts (scaled by grams) or type a manual
/// entry. Both end in the same `store.add(...)` call.
struct AddFoodSheet: View {
    @ObservedObject var store: NutritionStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .search

    enum Mode: String, CaseIterable { case search = "Suche", manual = "Manuell" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modus", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(16)
                Group {
                    switch mode {
                    case .search: FoodSearchPane(store: store, onDone: { dismiss() })
                    case .manual: ManualFoodPane(store: store, onDone: { dismiss() })
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Essen loggen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}

/// Open Food Facts search → pick a product → enter grams → log scaled macros.
private struct FoodSearchPane: View {
    @ObservedObject var store: NutritionStore
    let onDone: () -> Void

    @State private var query = ""
    @State private var hits: [FoodHit] = []
    @State private var searching = false
    @State private var error: String?
    @State private var selected: FoodHit?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("z. B. Magerquark, Banane…", text: $query)
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                if searching { ProgressView().tint(Theme.accent) }
            }
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .onChange(of: query) { _, _ in debounceSearch() }

            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 6)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(hits) { hit in
                        Button { selected = hit } label: { hitRow(hit) }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $selected) { hit in
            PortionSheet(hit: hit, store: store, onLogged: { onDone() }).preferredColorScheme(.dark)
        }
    }

    private func hitRow(_ hit: FoodHit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.name).foregroundStyle(Theme.textPrimary).font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let b = hit.brand { Text(b).font(.caption2).foregroundStyle(Theme.textSecondary) }
            }
            Spacer()
            Text("\(Int(hit.kcalPer100g)) kcal/100g").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func debounceSearch() {
        searchTask?.cancel()
        let q = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled || q != query { return }
            runSearch()
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { hits = []; return }
        searching = true; error = nil
        Task {
            do {
                let results = try await APIClient.shared.searchFoods(query: q)
                if q == query.trimmingCharacters(in: .whitespacesAndNewlines) { hits = results }
            } catch {
                self.error = error.localizedDescription
            }
            searching = false
        }
    }
}

/// Choose a gram amount for a picked product; shows scaled macros live.
private struct PortionSheet: View {
    let hit: FoodHit
    @ObservedObject var store: NutritionStore
    let onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var gramsText = "100"
    @State private var saving = false

    private var grams: Double { Double(gramsText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var macros: (kcal: Double, protein: Double, carbs: Double, fat: Double) { hit.scaled(toGrams: grams) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DashCard(title: hit.name, systemImage: "fork.knife") {
                        HStack {
                            Text("Menge").foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("100", text: $gramsText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .foregroundStyle(Theme.textPrimary)
                            Text("g").foregroundStyle(Theme.textSecondary)
                        }
                        Divider().overlay(Theme.cardElevated)
                        HStack(spacing: 10) {
                            StatChip(value: "\(Int(macros.kcal))", label: "kcal", color: Theme.accent)
                            StatChip(value: "\(Int(macros.protein)) g", label: "Protein", color: Theme.violet)
                        }
                        HStack(spacing: 10) {
                            StatChip(value: "\(Int(macros.carbs)) g", label: "Carbs", color: Theme.teal)
                            StatChip(value: "\(Int(macros.fat)) g", label: "Fett", color: Theme.warn)
                        }
                    }
                    Button {
                        saving = true
                        Task {
                            let m = macros
                            await store.add(name: hit.name, grams: grams, kcal: m.kcal,
                                            protein: m.protein, carbs: m.carbs, fat: m.fat, source: "openfoodfacts")
                            saving = false; dismiss(); onLogged()
                        }
                    } label: {
                        Label("Loggen", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(grams <= 0 || saving)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Portion").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Zurück") { dismiss() } } }
        }
    }
}

/// Manual entry for foods not in OFF (or quick estimates). Only name + kcal
/// are required; macros optional.
private struct ManualFoodPane: View {
    @ObservedObject var store: NutritionStore
    let onDone: () -> Void
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var grams = ""
    @State private var saving = false

    private func d(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (d(kcal) ?? 0) > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DashCard(title: "Manueller Eintrag", systemImage: "square.and.pencil") {
                    field("Name", text: $name, keyboard: .default)
                    field("Kalorien (kcal) *", text: $kcal, keyboard: .numberPad)
                    field("Menge (g, optional)", text: $grams, keyboard: .numberPad)
                    HStack(spacing: 10) {
                        field("Protein g", text: $protein, keyboard: .decimalPad)
                        field("Carbs g", text: $carbs, keyboard: .decimalPad)
                        field("Fett g", text: $fat, keyboard: .decimalPad)
                    }
                }
                Button {
                    saving = true
                    Task {
                        await store.add(name: name.trimmingCharacters(in: .whitespaces),
                                        grams: d(grams), kcal: d(kcal) ?? 0,
                                        protein: d(protein), carbs: d(carbs), fat: d(fat), source: "manual")
                        saving = false; onDone()
                    }
                } label: {
                    Label("Loggen", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!valid || saving)
            }
            .padding(16)
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            TextField("", text: text)
                .keyboardType(keyboard)
                .foregroundStyle(Theme.textPrimary)
                .padding(10)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
