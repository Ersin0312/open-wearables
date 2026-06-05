import Foundation
import SwiftUI

// MARK: - Backend model

/// A single logged food/meal entry. Macros are stored already-scaled to the
/// logged quantity, so daily totals are a plain sum. Numeric columns arrive as
/// strings ("300.00") from the backend — same convention as TrainingSet.weightKg.
struct NutritionEntry: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let eatenAt: String
    let quantityG: String?
    let calories: String
    let proteinG: String?
    let carbsG: String?
    let fatG: String?
    let source: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, calories, source, notes
        case eatenAt = "eaten_at"
        case quantityG = "quantity_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    var kcal: Double { Double(calories) ?? 0 }
    var protein: Double { proteinG.flatMap(Double.init) ?? 0 }
    var carbs: Double { carbsG.flatMap(Double.init) ?? 0 }
    var fat: Double { fatG.flatMap(Double.init) ?? 0 }
    var grams: Double? { quantityG.flatMap(Double.init) }
}

// MARK: - Open Food Facts (client-side lookup, no key)

/// One product from an Open Food Facts text search. Nutriments are per 100 g;
/// the UI scales them by the entered quantity before logging.
struct FoodHit: Identifiable, Hashable {
    let id: String          // OFF product code (barcode), used only as list id
    let name: String
    let brand: String?
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double

    /// Macros scaled to a gram amount.
    func scaled(toGrams g: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let f = g / 100.0
        return (kcalPer100g * f, proteinPer100g * f, carbsPer100g * f, fatPer100g * f)
    }
}

// MARK: - Open Food Facts decoding

struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
    }

    func toFoodHit() -> FoodHit? {
        let name = (productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let n = nutriments, n.kcal100 != nil else { return nil }
        return FoodHit(
            id: code ?? UUID().uuidString,
            name: name,
            brand: brands?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) },
            kcalPer100g: n.kcal100 ?? 0,
            proteinPer100g: n.protein100 ?? 0,
            carbsPer100g: n.carbs100 ?? 0,
            fatPer100g: n.fat100 ?? 0)
    }
}

/// OFF nutriment values arrive inconsistently as Double or String — decode each
/// leniently. Energy is read from the kcal field (not the kJ `energy_100g`).
struct OFFNutriments: Decodable {
    let kcal100: Double?
    let protein100: Double?
    let carbs100: Double?
    let fat100: Double?

    enum CodingKeys: String, CodingKey {
        case kcal100 = "energy-kcal_100g"
        case protein100 = "proteins_100g"
        case carbs100 = "carbohydrates_100g"
        case fat100 = "fat_100g"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func num(_ key: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }
        kcal100 = num(.kcal100)
        protein100 = num(.protein100)
        carbs100 = num(.carbs100)
        fat100 = num(.fat100)
    }
}

// MARK: - Store

/// Loads today's nutrition entries and exposes running totals for the HEUTE
/// agenda + the nutrition log. Goals come from the active plan phase.
@MainActor
final class NutritionStore: ObservableObject {
    @Published var todayEntries: [NutritionEntry] = []
    @Published var loading = false
    @Published var error: String?

    var totalKcal: Int { Int(todayEntries.reduce(0) { $0 + $1.kcal }.rounded()) }
    var totalProtein: Int { Int(todayEntries.reduce(0) { $0 + $1.protein }.rounded()) }
    var totalCarbs: Int { Int(todayEntries.reduce(0) { $0 + $1.carbs }.rounded()) }
    var totalFat: Int { Int(todayEntries.reduce(0) { $0 + $1.fat }.rounded()) }

    var proteinGoal: Int { PlanConfig.currentPhase.proteinGrams }
    var calorieGoalText: String { PlanConfig.currentPhase.calories }
    /// Upper bound of the phase calorie range (e.g. "2400-2500" → 2500) for ring math.
    var calorieGoalValue: Int {
        let digits = PlanConfig.currentPhase.calories.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return digits.max() ?? 2500
    }

    private static func dayString(_ offset: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            // Query a ±1-day window (UTC vs. local-midnight skew), then filter to local today.
            let all = try await APIClient.shared.nutrition(startDate: Self.dayString(-1), endDate: Self.dayString(1))
            todayEntries = all.filter { isLocalToday($0.eatenAt) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(name: String, grams: Double?, kcal: Double, protein: Double?, carbs: Double?, fat: Double?, source: String) async {
        do {
            _ = try await APIClient.shared.createNutrition(
                name: name, grams: grams, kcal: kcal, protein: protein, carbs: carbs, fat: fat, source: source)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Quick protein tally (e.g. a shake/scoop) — logs a minimal entry so it
    /// flows into the same total. kcal = protein × 4 keeps calories honest.
    func quickAddProtein(_ grams: Double) async {
        await add(name: "Protein (Schnell)", grams: nil, kcal: grams * 4,
                  protein: grams, carbs: 0, fat: 0, source: "manual")
    }

    func delete(_ entry: NutritionEntry) async {
        do {
            try await APIClient.shared.deleteNutrition(id: entry.id)
            todayEntries.removeAll { $0.id == entry.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func isLocalToday(_ iso: String) -> Bool {
        // eaten_at is a naive UTC timestamp ("2026-06-05T15:06:57.643841").
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withZ = iso.hasSuffix("Z") ? iso : iso + "Z"
        let date = f.date(from: withZ)
            ?? ISO8601DateFormatter().date(from: withZ)
            ?? .distantPast
        return Calendar.current.isDateInToday(date)
    }
}
