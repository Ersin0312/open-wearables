import SwiftUI

// MARK: - Model

struct CardioSession: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let performedAt: String
    let durationMin: String
    let avgHr: Int?
    let distanceKm: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, notes
        case performedAt = "performed_at"
        case durationMin = "duration_min"
        case avgHr = "avg_hr"
        case distanceKm = "distance_km"
    }

    var minutes: Double { Double(durationMin) ?? 0 }
    var distance: Double? { distanceKm.flatMap(Double.init) }
}

let CARDIO_KINDS: [(String, String)] = [
    ("zone2", "Zone 2"), ("intervals", "Intervalle"), ("other", "Sonstiges"),
]
func cardioLabel(_ kind: String) -> String { CARDIO_KINDS.first { $0.0 == kind }?.1 ?? kind }

// MARK: - Store

@MainActor
final class CardioStore: ObservableObject {
    @Published var sessions: [CardioSession] = []
    @Published var error: String?

    func load() async {
        do { sessions = try await APIClient.shared.cardioSessions() }
        catch { self.error = error.localizedDescription }
    }

    func add(kind: String, durationMin: Double, avgHr: Int?, distanceKm: Double?, notes: String?) async {
        do {
            _ = try await APIClient.shared.createCardio(kind: kind, durationMin: durationMin,
                                                        avgHr: avgHr, distanceKm: distanceKm, notes: notes)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ s: CardioSession) async {
        do { try await APIClient.shared.deleteCardio(id: s.id); sessions.removeAll { $0.id == s.id } }
        catch { self.error = error.localizedDescription }
    }

    /// Minutes of Zone-2-style cardio in the last 7 days (plan adherence).
    var minutesLast7Days: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return Int(sessions
            .filter { (parseTimestamp($0.performedAt) ?? .distantPast) >= cutoff }
            .reduce(0) { $0 + $1.minutes })
    }
}

// MARK: - Log sheet

struct CardioLogSheet: View {
    @ObservedObject var store: CardioStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind = "zone2"
    @State private var duration = ""
    @State private var avgHr = ""
    @State private var distance = ""
    @State private var saving = false

    private var durationValue: Double? { Double(duration.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Art") {
                    Picker("Art", selection: $kind) {
                        ForEach(CARDIO_KINDS, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.segmented)
                }
                Section("Werte") {
                    HStack { Text("Dauer"); Spacer()
                        TextField("min", text: $duration).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("min").foregroundStyle(.secondary) }
                    HStack { Text("Ø Herzfrequenz"); Spacer()
                        TextField("optional", text: $avgHr).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("bpm").foregroundStyle(.secondary) }
                    HStack { Text("Distanz"); Spacer()
                        TextField("optional", text: $distance).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("km").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Cardio loggen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let d = durationValue, d > 0 else { return }
                        saving = true
                        Task {
                            await store.add(kind: kind, durationMin: d, avgHr: Int(avgHr),
                                            distanceKm: Double(distance.replacingOccurrences(of: ",", with: ".")), notes: nil)
                            saving = false; dismiss()
                        }
                    }.disabled(durationValue == nil || (durationValue ?? 0) <= 0 || saving)
                }
            }
        }
    }
}
