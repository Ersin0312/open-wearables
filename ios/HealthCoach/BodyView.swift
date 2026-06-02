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
}

struct BodyView: View {
    @StateObject private var vm = BodyViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let s = vm.snapshot {
                    Section("Aktuell") {
                        metric("Gewicht", s.weightKg, "kg")
                        metric("Körperfett", s.bodyFatPercent, "%")
                        metric("Muskelmasse", s.muscleMassKg, "kg")
                        metric("BMI", s.bmi, "")
                    }
                }
                trendSection(title: "Gewicht", unit: "kg", samples: vm.weightTrend, color: .blue)
                trendSection(title: "Körperfett", unit: "%", samples: vm.fatTrend, color: .orange)

                if vm.snapshot == nil && !vm.loading {
                    Section {
                        Text("Noch keine Körperdaten. Sync über Renpho/Apple Health.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Körper")
            .toolbar { Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") } }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder
    private func metric(_ label: String, _ value: Double?, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value != nil ? "\(fmt(value!)) \(unit)" : "–").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func trendSection(title: String, unit: String, samples: [TimeseriesSample], color: Color) -> some View {
        Section(title) {
            if samples.isEmpty {
                Text("Keine Daten im Zeitraum.").foregroundStyle(.secondary).font(.footnote)
            } else {
                if let d = vm.delta(samples) {
                    HStack {
                        Text("Veränderung (90 T)")
                        Spacer()
                        Text("\(d > 0 ? "+" : "")\(fmt(d)) \(unit)")
                            .foregroundStyle(d < 0 ? .green : (d > 0 ? .orange : .secondary))
                    }
                    .font(.subheadline)
                }
                Chart(samples, id: \.timestamp) { s in
                    LineMark(x: .value("Zeit", s.timestamp), y: .value(title, s.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
            }
        }
    }
}
