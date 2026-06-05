import Foundation
import SwiftUI

/// Local store for manually tracked daily values (calories, protein, water,
/// agenda check-offs) until nutrition tracking (Prio 3) lands. Keyed by the
/// local calendar day so each day resets cleanly.
@MainActor
final class DailyStore: ObservableObject {
    @Published var caloriesConsumed: Int
    @Published var proteinConsumed: Int
    @Published var waterLiters: Double
    @Published var checked: Set<String>

    private let day: String

    init() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let d = f.string(from: Date())
        self.day = d
        let ud = UserDefaults.standard
        caloriesConsumed = ud.integer(forKey: "cal_\(d)")
        proteinConsumed = ud.integer(forKey: "pro_\(d)")
        waterLiters = ud.double(forKey: "water_\(d)")
        checked = Set(ud.stringArray(forKey: "checked_\(d)") ?? [])
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(caloriesConsumed, forKey: "cal_\(day)")
        ud.set(proteinConsumed, forKey: "pro_\(day)")
        ud.set(waterLiters, forKey: "water_\(day)")
        ud.set(Array(checked), forKey: "checked_\(day)")
    }

    func toggle(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
        save()
    }
    func isChecked(_ id: String) -> Bool { checked.contains(id) }

    /// Add (or subtract) water in litres; never goes below zero.
    func addWater(_ liters: Double) {
        waterLiters = max(0, waterLiters + liters)
        save()
    }
    func resetWater() { waterLiters = 0; save() }

    /// Water (litres) logged on a day N days ago — for multi-day context.
    static func water(daysAgo: Int) -> Double {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return UserDefaults.standard.double(forKey: "water_\(f.string(from: d))")
    }

    // Goals (defaults from the current phase; protein from phase config).
    var calorieGoalText: String { PlanConfig.currentPhase.calories }
    var proteinGoal: Int { PlanConfig.currentPhase.proteinGrams }
    var waterGoal: Double { 3.0 }
}
