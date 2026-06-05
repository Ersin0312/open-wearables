import SwiftUI

/// A full smart-scale measurement (Renpho), including metrics Apple Health can't
/// carry. Numeric columns arrive as strings ("18.40") like the rest of the API.
struct BodyScan: Codable, Identifiable, Hashable {
    let id: String
    let measuredAt: String
    let source: String
    let weightKg: String?
    let bmi: String?
    let bodyFatPercent: String?
    let muscleMassKg: String?
    let bodyWaterPercent: String?
    let boneMassKg: String?
    let bmrKcal: String?
    let visceralFat: String?
    let subcutaneousFatPercent: String?
    let proteinPercent: String?

    enum CodingKeys: String, CodingKey {
        case id, source, bmi
        case measuredAt = "measured_at"
        case weightKg = "weight_kg"
        case bodyFatPercent = "body_fat_percent"
        case muscleMassKg = "muscle_mass_kg"
        case bodyWaterPercent = "body_water_percent"
        case boneMassKg = "bone_mass_kg"
        case bmrKcal = "bmr_kcal"
        case visceralFat = "visceral_fat"
        case subcutaneousFatPercent = "subcutaneous_fat_percent"
        case proteinPercent = "protein_percent"
    }

    func d(_ s: String?) -> Double? { s.flatMap(Double.init) }
}

@MainActor
final class RenphoStore: ObservableObject {
    @Published var enabled = false
    @Published var scans: [BodyScan] = []
    @Published var syncing = false
    @Published var message: String?

    var latest: BodyScan? { scans.first }

    func load() async {
        enabled = (try? await APIClient.shared.renphoStatus()) ?? false
        scans = (try? await APIClient.shared.bodyScans()) ?? []
    }

    func sync() async {
        syncing = true; message = nil
        defer { syncing = false }
        do {
            let new = try await APIClient.shared.renphoSync()
            await load()
            message = new > 0 ? "\(new) neue Messung(en) synchronisiert." : "Keine neuen Messungen."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// FORTSCHRITT card for the Renpho-exclusive metrics + on-demand sync.
struct RenphoCard: View {
    @ObservedObject var store: RenphoStore

    var body: some View {
        DashCard(title: "Renpho Körperscan", systemImage: "sensor.tag.radiowaves.forward") {
            if !store.enabled {
                Text("Renpho-Sync nicht konfiguriert. Hinterlege RENPHO_EMAIL und RENPHO_PASSWORD im Backend, dann erscheinen hier Werte wie Viszeralfett, Körperwasser und Grundumsatz.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else if let s = store.latest {
                Text("Letzte Messung: \(weekdayDateShort(s.measuredAt))")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 10) {
                    chip(s.d(s.muscleMassKg), "kg", "Muskelmasse", Theme.good)
                    chip(s.d(s.bodyWaterPercent), "%", "Körperwasser", Theme.teal)
                    chip(s.d(s.visceralFat), "", "Viszeralfett", Theme.danger)
                    chip(s.d(s.subcutaneousFatPercent), "%", "Subkutanfett", Theme.warn)
                    chip(s.d(s.boneMassKg), "kg", "Knochenmasse", Theme.violet)
                    chip(s.d(s.proteinPercent), "%", "Protein", Theme.accent)
                    chip(s.d(s.bmrKcal), "kcal", "Grundumsatz", Theme.accent)
                    chip(s.d(s.bmi), "", "BMI", Theme.accent)
                }
            } else {
                Text("Noch keine Scans. Tippe auf Synchronisieren.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }

            if store.enabled {
                Button { Task { await store.sync() } } label: {
                    HStack(spacing: 6) {
                        if store.syncing { ProgressView().tint(Theme.accent) }
                        Label(store.syncing ? "Synchronisiere…" : "Synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                }.buttonStyle(.bordered).tint(Theme.accent).disabled(store.syncing)
            }
            if let m = store.message {
                Text(m).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func chip(_ value: Double?, _ unit: String, _ label: String, _ color: Color) -> some View {
        StatChip(value: value == nil ? "–" : (unit.isEmpty ? fmt(value!) : "\(fmt(value!)) \(unit)"),
                 label: label, color: color)
    }
}
