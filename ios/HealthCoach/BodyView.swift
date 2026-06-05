import SwiftUI
import Charts

@MainActor
final class BodyViewModel: ObservableObject {
    @Published var snapshot: BodySlowChanging?
    @Published var weightTrend: [TimeseriesSample] = []
    @Published var fatTrend: [TimeseriesSample] = []
    @Published var loading = false
    @Published var error: String?

    private static func iso(_ daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    func load(days: Int = 90) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let body = APIClient.shared.bodySummary()
            async let trend = APIClient.shared.bodyTrend(startDate: Self.iso(days), endDate: Self.iso(0))
            let (b, t) = try await (body, trend)
            snapshot = b.slowChanging
            weightTrend = t.filter { $0.type == "weight" }.sorted { $0.timestamp < $1.timestamp }
            fatTrend = t.filter { $0.type == "body_fat_percentage" }.sorted { $0.timestamp < $1.timestamp }
        } catch { self.error = error.localizedDescription }
    }

    func delta(_ samples: [TimeseriesSample]) -> Double? {
        guard samples.count >= 2 else { return nil }
        return (samples.last!.value - samples.first!.value)
    }

    /// Change over the last `days`: latest value minus the earliest sample
    /// within that window. nil when there isn't enough data.
    func deltaOver(days: Int, _ samples: [TimeseriesSample]) -> Double? {
        guard let last = samples.last else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let window = samples.filter { (parseTimestamp($0.timestamp) ?? .distantPast) >= cutoff }
        guard let base = window.first, window.count >= 2 else { return nil }
        return last.value - base.value
    }

    var currentWeight: Double? { snapshot?.weightKg ?? weightTrend.last?.value }
}

/// Body-composition metrics derived purely from scale data (weight, body-fat %,
/// height) — no tape measure or photos needed.
struct BodyComposition {
    let weight: Double
    let bodyFatPct: Double?
    let heightCm: Double?

    var fatMass: Double? { bodyFatPct.map { weight * $0 / 100 } }
    var fatFreeMass: Double? { fatMass.map { weight - $0 } }     // FFM / lean mass
    /// Fat-Free Mass Index = FFM(kg) / height(m)². A lean-mass benchmark.
    var ffmi: Double? {
        guard let ffm = fatFreeMass, let h = heightCm, h > 0 else { return nil }
        let m = h / 100
        return ffm / (m * m)
    }
}

struct BodyView: View {
    @StateObject private var vm = BodyViewModel()
    @StateObject private var blood = BloodworkStore()
    @State private var detailMetric: BodyMetricKind?
    @State private var showBloodLog = false

    private var composition: BodyComposition? {
        guard let w = vm.currentWeight else { return nil }
        return BodyComposition(weight: w, bodyFatPct: vm.snapshot?.bodyFatPercent,
                               heightCm: vm.snapshot?.heightCm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if vm.snapshot == nil && vm.currentWeight == nil && !vm.loading {
                        emptyState
                    } else {
                        weightHero
                        compositionGrid
                        phaseProgress
                        trendCard(title: "Gewicht", unit: "kg", samples: vm.weightTrend, color: Theme.accent)
                        trendCard(title: "Körperfett", unit: "%", samples: vm.fatTrend, color: Theme.warn)
                    }
                    bloodworkCard
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Fortschritt")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
            } }
            .task { await vm.load(); await blood.load() }
            .refreshable { await vm.load(); await blood.load() }
            .sheet(item: $detailMetric) { kind in
                KPIDetailView(kind: kind, heightCm: vm.snapshot?.heightCm)
            }
            .sheet(isPresented: $showBloodLog) {
                BloodworkLogSheet(store: blood).preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        DashCard(title: "Körperwerte", systemImage: "figure.stand") {
            Text("Noch keine Waagendaten. Synchronisiere deine Körperwaage über Apple Health (Renpho → Health Auto Export).")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    // Big weight + 7/30-day deltas (down = good in a cut → green). Tap → history.
    private var weightHero: some View {
        Button { detailMetric = .weight } label: {
            DashCard(title: "Gewicht", systemImage: "scalemass") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmt(vm.currentWeight ?? 0)).font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("kg").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chart.xyaxis.line").foregroundStyle(Theme.accent)
                }
                HStack(spacing: 10) {
                    deltaChip("7 Tage", vm.deltaOver(days: 7, vm.weightTrend), unit: "kg")
                    deltaChip("30 Tage", vm.deltaOver(days: 30, vm.weightTrend), unit: "kg")
                    deltaChip("90 Tage", vm.delta(vm.weightTrend), unit: "kg")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func deltaChip(_ label: String, _ value: Double?, unit: String) -> some View {
        let color: Color = value == nil ? Theme.textSecondary : (value! < 0 ? Theme.good : (value! > 0 ? Theme.warn : Theme.textSecondary))
        let text = value == nil ? "–" : "\(value! > 0 ? "+" : "")\(fmt(value!)) \(unit)"
        return VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(.subheadline, design: .rounded)).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Composition KPIs, all derived from the scale. Tap any → full history.
    private var compositionGrid: some View {
        DashCard(title: "Körperzusammensetzung", systemImage: "chart.pie") {
            let c = composition
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 10) {
                kpiChip(.bodyFat, kpi(vm.snapshot?.bodyFatPercent, "%"), "Körperfett", Theme.warn)
                kpiChip(.muscle, kpi(vm.snapshot?.muscleMassKg, "kg"), "Muskelmasse", Theme.good)
                kpiChip(.ffm, kpi(c?.fatFreeMass, "kg"), "Fettfreie Masse", Theme.teal)
                kpiChip(.ffmi, kpi(c?.ffmi, ""), "FFMI", Theme.violet)
                kpiChip(.fatMass, kpi(c?.fatMass, "kg"), "Fettmasse", Theme.danger)
                kpiChip(.bmi, kpi(vm.snapshot?.bmi, ""), "BMI", Theme.accent)
            }
        }
    }

    private func kpiChip(_ kind: BodyMetricKind, _ value: String, _ label: String, _ color: Color) -> some View {
        Button { detailMetric = kind } label: {
            StatChip(value: value, label: label, color: color)
        }
        .buttonStyle(.plain)
    }

    private func kpi(_ value: Double?, _ unit: String) -> String {
        guard let v = value else { return "–" }
        return unit.isEmpty ? fmt(v) : "\(fmt(v)) \(unit)"
    }

    // Progress toward the active phase's goal weight (ties FORTSCHRITT to PLAN).
    @ViewBuilder
    private var phaseProgress: some View {
        if let cur = vm.currentWeight {
            let start = PlanConfig.startWeight
            let goal = PlanConfig.currentPhase.goalWeight
            let total = max(0.1, start - goal)
            let progress = min(max((start - cur) / total, 0), 1)
            DashCard(title: "Phasenziel", systemImage: "target") {
                HStack {
                    Text("\(fmt(cur)) kg").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Ziel \(fmt(goal)) kg · Phase \(PlanConfig.currentPhase.index)").foregroundStyle(Theme.textSecondary)
                }.font(.caption)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cardElevated).frame(height: 8)
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * progress, height: 8)
                    }
                }.frame(height: 8)
                let remaining = cur - goal
                Text(remaining > 0 ? "Noch \(fmt(remaining)) kg bis zum Phasenziel" : "Phasenziel erreicht ✓")
                    .font(.caption2).foregroundStyle(remaining > 0 ? Theme.textSecondary : Theme.good)
            }
        }
    }

    // Bloodwork — latest reading per marker, manual log (no scale source).
    private var bloodworkCard: some View {
        DashCard(title: "Blutwerte", systemImage: "drop.fill") {
            if blood.latestPerMarker.isEmpty {
                Text("Noch keine Blutwerte. Logge Laborwerte (z. B. Testosteron, Vitamin D), um den Trend zu verfolgen.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(blood.latestPerMarker.prefix(8)) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.marker).foregroundStyle(Theme.textPrimary).font(.subheadline)
                            Text(weekdayDateShort(e.takenAt)).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("\(fmt(e.number)) \(e.unit)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
            Button { showBloodLog = true } label: {
                Label("Blutwert hinzufügen", systemImage: "plus").font(.caption)
            }.buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    @ViewBuilder
    private func trendCard(title: String, unit: String, samples: [TimeseriesSample], color: Color) -> some View {
        DashCard(title: "\(title)-Trend", systemImage: "chart.xyaxis.line") {
            if samples.isEmpty {
                Text("Keine Daten im Zeitraum.").foregroundStyle(Theme.textSecondary).font(.footnote)
            } else {
                Chart(samples, id: \.timestamp) { s in
                    LineMark(x: .value("Zeit", parseTimestamp(s.timestamp) ?? Date(timeIntervalSince1970: 0)),
                             y: .value(title, s.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Zeit", parseTimestamp(s.timestamp) ?? Date(timeIntervalSince1970: 0)),
                             y: .value(title, s.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 150)
            }
        }
    }
}
