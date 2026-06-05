import SwiftUI
import Charts

/// A body KPI whose history can be charted. Direct metrics come straight from
/// the scale timeseries; derived ones are computed per day from weight + body
/// fat (+ height), so no extra data source is needed.
enum BodyMetricKind: String, CaseIterable, Identifiable {
    case weight, bodyFat, muscle, ffm, ffmi, fatMass, bmi
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "Gewicht"
        case .bodyFat: return "Körperfett"
        case .muscle: return "Muskelmasse"
        case .ffm: return "Fettfreie Masse"
        case .ffmi: return "FFMI"
        case .fatMass: return "Fettmasse"
        case .bmi: return "BMI"
        }
    }
    var unit: String {
        switch self {
        case .weight, .muscle, .ffm, .fatMass: return "kg"
        case .bodyFat: return "%"
        case .ffmi, .bmi: return ""
        }
    }
    var color: Color {
        switch self {
        case .weight: return Theme.accent
        case .bodyFat: return Theme.warn
        case .muscle: return Theme.good
        case .ffm: return Theme.teal
        case .ffmi: return Theme.violet
        case .fatMass: return Theme.danger
        case .bmi: return Theme.accent
        }
    }
    /// Timeseries types to fetch in order to compute this metric.
    var sourceTypes: [String] {
        switch self {
        case .weight, .bmi: return ["weight"]
        case .bodyFat: return ["body_fat_percentage"]
        case .muscle: return ["muscle_mass"]
        case .ffm, .ffmi, .fatMass: return ["weight", "body_fat_percentage"]
        }
    }
    /// Lower-is-better metrics turn green when they drop.
    var lowerIsBetter: Bool {
        switch self { case .bodyFat, .fatMass, .bmi, .weight: return true; default: return false }
    }
}

struct MetricPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Woche", month = "Monat", quarter = "3 Monate", year = "Jahr"
    var id: String { rawValue }
    var days: Int { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .year: 365 } }
}

@MainActor
final class MetricDetailModel: ObservableObject {
    @Published var points: [MetricPoint] = []
    @Published var loading = false

    func load(kind: BodyMetricKind, range: TimeRange, heightCm: Double?) async {
        loading = true; defer { loading = false }
        let start = Self.iso(range.days), end = Self.iso(0)
        let samples = (try? await APIClient.shared.bodyMetricSamples(
            types: kind.sourceTypes, startDate: start, endDate: end)) ?? []
        points = Self.buildSeries(kind: kind, samples: samples, heightCm: heightCm)
    }

    private static func iso(_ daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    /// Reduce raw samples to one value per day, then compute the metric.
    static func buildSeries(kind: BodyMetricKind, samples: [TimeseriesSample], heightCm: Double?) -> [MetricPoint] {
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        // type → (dayString → latest value)
        var byType: [String: [String: (Date, Double)]] = [:]
        for s in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let d = parseTimestamp(s.timestamp) else { continue }
            let key = dayFmt.string(from: d)
            byType[s.type, default: [:]][key] = (d, s.value)
        }
        let h = (heightCm ?? 0) / 100
        let weightDays = byType["weight"] ?? [:]
        let fatDays = byType["body_fat_percentage"] ?? [:]
        let muscleDays = byType["muscle_mass"] ?? [:]

        func compute(_ day: String) -> (Date, Double)? {
            switch kind {
            case .weight: return weightDays[day]
            case .bodyFat: return fatDays[day]
            case .muscle: return muscleDays[day]
            case .bmi:
                guard let (d, w) = weightDays[day], h > 0 else { return nil }
                return (d, w / (h * h))
            case .fatMass:
                guard let (d, w) = weightDays[day], let (_, bf) = fatDays[day] else { return nil }
                return (d, w * bf / 100)
            case .ffm:
                guard let (d, w) = weightDays[day], let (_, bf) = fatDays[day] else { return nil }
                return (d, w - w * bf / 100)
            case .ffmi:
                guard let (d, w) = weightDays[day], let (_, bf) = fatDays[day], h > 0 else { return nil }
                return (d, (w - w * bf / 100) / (h * h))
            }
        }

        let days = Set(weightDays.keys).union(fatDays.keys).union(muscleDays.keys)
        return days.compactMap { compute($0) }
            .sorted { $0.0 < $1.0 }
            .map { MetricPoint(date: $0.0, value: $0.1) }
    }
}

/// Full history of one KPI with a Woche/Monat/3 Monate/Jahr range switch.
struct KPIDetailView: View {
    let kind: BodyMetricKind
    let heightCm: Double?
    @StateObject private var model = MetricDetailModel()
    @State private var range: TimeRange = .month
    @Environment(\.dismiss) private var dismiss

    private var current: Double? { model.points.last?.value }
    private var delta: Double? {
        guard let first = model.points.first?.value, let last = model.points.last?.value,
              model.points.count >= 2 else { return nil }
        return last - first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    DashCard(title: kind.title, systemImage: "chart.xyaxis.line") {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(current != nil ? fmt(current!) : "–")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text(kind.unit).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if let d = delta {
                                let good = kind.lowerIsBetter ? d < 0 : d > 0
                                Text("\(d > 0 ? "+" : "")\(fmt(d)) \(kind.unit)")
                                    .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                                    .foregroundStyle(d == 0 ? Theme.textSecondary : (good ? Theme.good : Theme.warn))
                            }
                        }
                        if model.loading {
                            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else if model.points.isEmpty {
                            Text("Keine Daten im Zeitraum. Diese Werte kommen von der Körperwaage über Apple Health.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                        } else {
                            chart
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } } }
            .task(id: range) { await model.load(kind: kind, range: range, heightCm: heightCm) }
        }
        .preferredColorScheme(.dark)
    }

    private var chart: some View {
        Chart(model.points) { p in
            LineMark(x: .value("Datum", p.date), y: .value(kind.title, p.value))
                .foregroundStyle(kind.color)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Datum", p.date), y: .value(kind.title, p.value))
                .foregroundStyle(LinearGradient(colors: [kind.color.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Datum", p.date), y: .value(kind.title, p.value))
                .foregroundStyle(kind.color).symbolSize(14)
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .frame(height: 200)
    }
}
