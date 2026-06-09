import SwiftUI

@MainActor
final class SupplementsViewModel: ObservableObject {
    @Published var stacks: [SupplementStack] = []
    @Published var supplements: [Supplement] = []
    @Published var todayIntakes: [SupplementIntake] = []
    @Published var loading = false
    @Published var error: String?

    private var supplementByID: [String: Supplement] = [:]

    func name(for id: String) -> String { supplementByID[id]?.name ?? "Unbekannt" }

    private static func dayString(_ offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Keep only intakes whose taken_at falls on the LOCAL calendar today.
    /// The backend stores UTC, so a query window of ±1 day plus local filtering
    /// avoids losing entries logged near local midnight.
    private static func isLocalToday(_ iso: String) -> Bool {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return false }
        return Calendar.current.isDateInToday(d)
    }

    func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let sups = APIClient.shared.supplements()
            async let stk = APIClient.shared.stacks()
            async let intk = APIClient.shared.intakes(startDate: Self.dayString(-1), endDate: Self.dayString(1))
            let (s, k, i) = try await (sups, stk, intk)
            supplements = s
            supplementByID = Dictionary(uniqueKeysWithValues: s.map { ($0.id, $0) })
            stacks = k
            todayIntakes = i.filter { Self.isLocalToday($0.takenAt) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logStack(_ stack: SupplementStack) async {
        do {
            _ = try await APIClient.shared.logStackNow(stackID: stack.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logSingle(supplement: Supplement, dose: Double) async {
        do {
            _ = try await APIClient.shared.addIntake(supplementID: supplement.id, dose: dose, unit: supplement.defaultUnit)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteIntake(_ intake: SupplementIntake) async {
        do {
            try await APIClient.shared.deleteIntake(intakeID: intake.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Per-supplement total taken today vs. recommended daily dose.
    struct DailyProgress: Identifiable {
        let id: String
        let name: String
        let total: Double
        let recommended: Double
        let unit: String
        var pct: Int { recommended > 0 ? Int((total / recommended * 100).rounded()) : 0 }
    }

    var dailyProgress: [DailyProgress] {
        var totals: [String: Double] = [:]
        for i in todayIntakes {
            totals[i.supplementID, default: 0] += Double(i.dose) ?? 0
        }
        return totals.compactMap { (sid, total) -> DailyProgress? in
            guard let sup = supplementByID[sid],
                  let recStr = sup.recommendedDailyDose, let rec = Double(recStr), rec > 0
            else { return nil }
            return DailyProgress(id: sid, name: sup.name, total: total,
                                 recommended: rec, unit: sup.defaultUnit)
        }
        .sorted { $0.name < $1.name }
    }
}

/// One enum drives all supplement sheets. Multiple stacked `.sheet(isPresented:)`
/// modifiers conflict — especially when this view is itself presented in a sheet
/// — so a single `.sheet(item:)` is the reliable pattern.
enum SupplementSheet: Int, Identifiable {
    case logSingle, createStack, createSupplement, library
    var id: Int { rawValue }
}

struct SupplementsView: View {
    @StateObject private var vm = SupplementsViewModel()
    @State private var activeSheet: SupplementSheet?

    var body: some View {
        NavigationStack {
            Group {
                if vm.loading && vm.stacks.isEmpty {
                    ProgressView("Lade…")
                } else if let error = vm.error, vm.stacks.isEmpty {
                    ContentUnavailableView {
                        Label("Fehler", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") { Task { await vm.load() } }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Supplements")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { activeSheet = .logSingle } label: { Label("Einzeln loggen", systemImage: "pills") }
                        Button { activeSheet = .createStack } label: { Label("Stack anlegen", systemImage: "square.stack.3d.up") }
                        Button { activeSheet = .createSupplement } label: { Label("Eigene NEM", systemImage: "plus.circle") }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { activeSheet = .library } label: { Image(systemName: "books.vertical") }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .logSingle:
                    LogSingleSheet(supplements: vm.supplements) { sup, dose in
                        Task { await vm.logSingle(supplement: sup, dose: dose) }
                    }
                case .createStack:
                    CreateStackSheet(supplements: vm.supplements) { name, items in
                        Task {
                            do {
                                _ = try await APIClient.shared.createStack(name: name, items: items)
                                await vm.load()
                            } catch { vm.error = error.localizedDescription }
                        }
                    }
                case .createSupplement:
                    CreateSupplementSheet { draft in
                        Task {
                            do {
                                _ = try await APIClient.shared.createSupplement(
                                    name: draft.name, brand: draft.brand, category: draft.category,
                                    defaultDose: draft.defaultDose, defaultUnit: draft.defaultUnit,
                                    recommendedDailyDose: draft.recommendedDailyDose, notes: draft.notes)
                                await vm.load()
                            } catch { vm.error = error.localizedDescription }
                        }
                    }
                case .library:
                    NemLibrarySheet(supplements: vm.supplements, onChanged: { Task { await vm.load() } })
                }
            }
            .task { await vm.load() }
        }
    }

    private var list: some View {
        List {
            Section("Daily Stacks") {
                if vm.stacks.isEmpty {
                    Text("Noch keine Stacks angelegt.").foregroundStyle(.secondary)
                }
                ForEach(vm.stacks) { stack in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stack.name).font(.headline)
                            Text("\(stack.items.count) NEMs").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Loggen") { Task { await vm.logStack(stack) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(stack.items.isEmpty)
                    }
                }
            }

            if !vm.dailyProgress.isEmpty {
                Section("Tagesdosis heute") {
                    ForEach(vm.dailyProgress) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.name).font(.subheadline)
                                Spacer()
                                Text("\(fmt(p.total)) / \(fmt(p.recommended)) \(p.unit) · \(p.pct)%")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(Double(p.pct) / 100.0, 1.0))
                                .tint(color(for: p.pct))
                        }
                    }
                }
            }

            Section("Heute geloggt (\(vm.todayIntakes.count))") {
                if vm.todayIntakes.isEmpty {
                    Text("Heute noch nichts geloggt.").foregroundStyle(.secondary)
                }
                ForEach(vm.todayIntakes) { intake in
                    HStack {
                        Text(vm.name(for: intake.supplementID))
                        Spacer()
                        Text("\(fmt(Double(intake.dose) ?? 0)) \(intake.unit)")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.deleteIntake(intake) }
                        } label: { Label("Löschen", systemImage: "trash") }
                    }
                }
            }
        }
        .refreshable { await vm.load() }
    }

    private func color(for pct: Int) -> Color {
        switch pct {
        case ..<1: return .red
        case ..<34: return .orange
        case ..<67: return .mint
        case ..<100: return .green
        default: return Color(red: 0.08, green: 0.5, blue: 0.24)
        }
    }
}
