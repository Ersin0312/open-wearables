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

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let sups = APIClient.shared.supplements()
            async let stk = APIClient.shared.stacks()
            async let intk = APIClient.shared.intakes(startDate: Self.todayString(), endDate: Self.todayString())
            let (s, k, i) = try await (sups, stk, intk)
            supplements = s
            supplementByID = Dictionary(uniqueKeysWithValues: s.map { ($0.id, $0) })
            stacks = k
            todayIntakes = i
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

struct SupplementsView: View {
    @StateObject private var vm = SupplementsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.loading && vm.stacks.isEmpty {
                    ProgressView("Lade…")
                } else if let error = vm.error {
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
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
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
                }
            }
        }
        .refreshable { await vm.load() }
    }

    private func fmt(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
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
