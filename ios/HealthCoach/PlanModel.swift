import Foundation

/// The 12-month body-recomposition plan: phases, day counter, and targets.
/// Values are editable later (PLAN tab); these are the defaults from the brief.
enum PlanConfig {
    /// Plan start date. Stored in UserDefaults so it can be set once.
    private static let startKey = "plan_start_date"

    static var startDate: Date {
        get {
            if let t = UserDefaults.standard.object(forKey: startKey) as? Date { return t }
            // Default: today, so day 1 = today until the user sets a real date.
            let today = Calendar.current.startOfDay(for: Date())
            UserDefaults.standard.set(today, forKey: startKey)
            return today
        }
        set { UserDefaults.standard.set(Calendar.current.startOfDay(for: newValue), forKey: startKey) }
    }

    static let totalDays = 365
    static let startWeight = 104.4      // kg
    static let endGoalWeight = 85.0     // kg

    struct Phase {
        let index: Int
        let name: String
        let startDay: Int          // 1-based
        let endDay: Int
        let goalWeight: Double
        let calories: String
        let proteinGrams: Int
    }

    static let phases: [Phase] = [
        Phase(index: 1, name: "Aggressiver Cut", startDay: 1, endDay: 120,
              goalWeight: 92, calories: "2400–2500", proteinGrams: 220),
        Phase(index: 2, name: "Moderater Cut", startDay: 121, endDay: 240,
              goalWeight: 86, calories: "2500–2700", proteinGrams: 210),
        Phase(index: 3, name: "Lean Maintenance", startDay: 241, endDay: 365,
              goalWeight: 85, calories: "2700–2900", proteinGrams: 200),
    ]

    /// 1-based current day on the journey.
    static var currentDay: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return max(1, min(days + 1, totalDays))
    }

    static var currentPhase: Phase {
        let d = currentDay
        return phases.first { d >= $0.startDay && d <= $0.endDay } ?? phases[0]
    }

    static var daysLeftInPhase: Int {
        max(0, currentPhase.endDay - currentDay)
    }

    /// Deterministic phase-transition alert (no AI, instant) — surfaced when a
    /// phase change is near. nil when nothing noteworthy.
    static var phaseTransitionAlert: String? {
        guard daysLeftInPhase <= 10 else { return nil }
        let p = currentPhase
        if let next = phases.first(where: { $0.index == p.index + 1 }) {
            return "Noch \(daysLeftInPhase) Tage in Phase \(p.index) (\(p.name)) → dann Phase \(next.index): \(next.name), Ziel \(Int(next.goalWeight)) kg, \(next.calories) kcal."
        }
        return "Noch \(daysLeftInPhase) Tage — letzte Phase (\(p.name)). Endspurt zum Ziel \(Int(endGoalWeight)) kg."
    }

    /// Weekly training template (Mon…Sun).
    static func workoutForToday() -> String {
        switch Calendar.current.component(.weekday, from: Date()) {
        case 2: return "Upper Push"          // Monday
        case 3: return "Zone-2 Cardio 45 min"
        case 4: return "Lower"
        case 5: return "Zone-2 + Intervalle"
        case 6: return "Upper Pull"
        case 7: return "Long Zone-2 60–90 min"
        default: return "Rest"               // Sunday
        }
    }
}
