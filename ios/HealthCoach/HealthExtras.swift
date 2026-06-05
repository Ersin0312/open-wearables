import SwiftUI

// MARK: - Models

struct PullupEntry: Codable, Identifiable, Hashable {
    let id: String
    let reps: Int
    let addedWeightKg: String?
    let performedAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, reps, notes
        case addedWeightKg = "added_weight_kg"
        case performedAt = "performed_at"
    }
    var added: Double { addedWeightKg.flatMap(Double.init) ?? 0 }
}

struct BloodworkEntry: Codable, Identifiable, Hashable {
    let id: String
    let marker: String
    let value: String
    let unit: String
    let takenAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, marker, value, unit, notes
        case takenAt = "taken_at"
    }
    var number: Double { Double(value) ?? 0 }
}

// MARK: - Pull-up store + sheet

@MainActor
final class PullupStore: ObservableObject {
    @Published var entries: [PullupEntry] = []

    func load() async { entries = (try? await APIClient.shared.pullups()) ?? [] }
    func add(reps: Int, added: Double?) async {
        _ = try? await APIClient.shared.createPullup(reps: reps, addedWeightKg: added)
        await load()
    }
    func delete(_ e: PullupEntry) async {
        try? await APIClient.shared.deletePullup(id: e.id); entries.removeAll { $0.id == e.id }
    }
    /// Best clean bodyweight set (added weight 0) — the headline benchmark.
    var bestBodyweight: Int { entries.filter { $0.added == 0 }.map(\.reps).max() ?? 0 }
}

struct PullupLogSheet: View {
    @ObservedObject var store: PullupStore
    @Environment(\.dismiss) private var dismiss
    @State private var reps = ""
    @State private var added = ""

    private var repsValue: Int? { Int(reps) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Klimmzüge") {
                    HStack { Text("Wiederholungen"); Spacer()
                        TextField("max. Reps", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    HStack { Text("Zusatzgewicht"); Spacer()
                        TextField("optional", text: $added).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("kg").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Klimmzüge loggen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let r = repsValue, r > 0 else { return }
                        Task { await store.add(reps: r, added: Double(added.replacingOccurrences(of: ",", with: "."))); dismiss() }
                    }.disabled(repsValue == nil || (repsValue ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Bloodwork store + sheet

@MainActor
final class BloodworkStore: ObservableObject {
    @Published var entries: [BloodworkEntry] = []

    func load() async { entries = (try? await APIClient.shared.bloodwork()) ?? [] }
    func add(marker: String, value: Double, unit: String, takenAt: Date) async {
        _ = try? await APIClient.shared.createBloodwork(marker: marker, value: value, unit: unit, takenAt: takenAt)
        await load()
    }
    func delete(_ e: BloodworkEntry) async {
        try? await APIClient.shared.deleteBloodwork(id: e.id); entries.removeAll { $0.id == e.id }
    }
    /// Most recent reading per marker, for the summary list.
    var latestPerMarker: [BloodworkEntry] {
        var seen = Set<String>(); var out: [BloodworkEntry] = []
        for e in entries { if !seen.contains(e.marker) { seen.insert(e.marker); out.append(e) } }
        return out
    }
}

/// Common male body-recomp markers as quick presets (with typical units).
let BLOOD_MARKERS: [(String, String)] = [
    ("Testosteron", "ng/ml"), ("Freies Testosteron", "pg/ml"), ("SHBG", "nmol/l"),
    ("Östradiol", "pg/ml"), ("HbA1c", "%"), ("Nüchternglukose", "mg/dl"),
    ("Vitamin D", "ng/ml"), ("Ferritin", "ng/ml"), ("LDL", "mg/dl"),
    ("HDL", "mg/dl"), ("Triglyceride", "mg/dl"), ("TSH", "mU/l"), ("CRP", "mg/l"),
]

struct BloodworkLogSheet: View {
    @ObservedObject var store: BloodworkStore
    @Environment(\.dismiss) private var dismiss
    @State private var marker = "Testosteron"
    @State private var value = ""
    @State private var unit = "ng/ml"
    @State private var takenAt = Date()

    private var valueNum: Double? { Double(value.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Marker") {
                    Picker("Marker", selection: $marker) {
                        ForEach(BLOOD_MARKERS, id: \.0) { Text($0.0).tag($0.0) }
                    }
                    .onChange(of: marker) { _, m in
                        if let u = BLOOD_MARKERS.first(where: { $0.0 == m })?.1 { unit = u }
                    }
                }
                Section("Wert") {
                    HStack { TextField("Wert", text: $value).keyboardType(.decimalPad)
                        TextField("Einheit", text: $unit).multilineTextAlignment(.trailing).frame(width: 90) }
                    DatePicker("Datum", selection: $takenAt, displayedComponents: .date)
                }
            }
            .navigationTitle("Blutwert loggen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let v = valueNum else { return }
                        Task { await store.add(marker: marker, value: v, unit: unit, takenAt: takenAt); dismiss() }
                    }.disabled(valueNum == nil)
                }
            }
        }
    }
}
