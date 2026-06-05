import Foundation

// MARK: - Supplements

struct Supplement: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String?
    let category: String
    let defaultDose: String?
    let defaultUnit: String
    let recommendedDailyDose: String?
    let notes: String?
    let isSeeded: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, brand, category, notes
        case defaultDose = "default_dose"
        case defaultUnit = "default_unit"
        case recommendedDailyDose = "recommended_daily_dose"
        case isSeeded = "is_seeded"
    }
}

struct SupplementStackItem: Codable, Identifiable, Hashable {
    let id: String
    let supplementID: String
    let dose: String?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case id
        case supplementID = "supplement_id"
        case dose, unit
    }
}

struct SupplementStack: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let items: [SupplementStackItem]
}

struct SupplementIntake: Codable, Identifiable, Hashable {
    let id: String
    let supplementID: String
    let stackID: String?
    let takenAt: String
    let dose: String
    let unit: String

    enum CodingKeys: String, CodingKey {
        case id
        case supplementID = "supplement_id"
        case stackID = "stack_id"
        case takenAt = "taken_at"
        case dose, unit
    }
}

// MARK: - Training

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let primaryMuscleGroup: String
    let defaultSplitTag: String
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case primaryMuscleGroup = "primary_muscle_group"
        case defaultSplitTag = "default_split_tag"
        case imageURL = "image_url"
    }
}

struct TrainingSession: Codable, Identifiable, Hashable {
    let id: String
    let startedAt: String
    let endedAt: String?
    let splitTag: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case splitTag = "split_tag"
        case notes
    }
}

struct TrainingSet: Codable, Identifiable, Hashable {
    let id: String
    let sessionID: String
    let exerciseID: String
    let setNumber: Int
    let reps: Int
    let weightKg: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case setNumber = "set_number"
        case reps
        case weightKg = "weight_kg"
        case createdAt = "created_at"
    }
}

/// The last time a machine was used: its sets from the most recent session.
struct ExercisePerformance: Codable {
    let performedAt: String
    let sets: [TrainingSet]

    enum CodingKeys: String, CodingKey {
        case performedAt = "performed_at"
        case sets
    }
}

// MARK: - Body composition

struct BodySlowChanging: Codable, Hashable {
    let weightKg: Double?
    let heightCm: Double?
    let bodyFatPercent: Double?
    let muscleMassKg: Double?
    let bmi: Double?

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case bodyFatPercent = "body_fat_percent"
        case muscleMassKg = "muscle_mass_kg"
        case bmi
    }
}

struct BodySummary: Codable, Hashable {
    let slowChanging: BodySlowChanging?

    enum CodingKeys: String, CodingKey {
        case slowChanging = "slow_changing"
    }
}

// MARK: - Recovery (WHOOP)

struct RecoveryDay: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let recoveryScore: Double?
    let restingHeartRateBpm: Double?
    let avgHrvSdnnMs: Double?
    let avgSpo2Percent: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case recoveryScore = "recovery_score"
        case restingHeartRateBpm = "resting_heart_rate_bpm"
        case avgHrvSdnnMs = "avg_hrv_sdnn_ms"
        case avgSpo2Percent = "avg_spo2_percent"
    }
}

struct RecoveryResponse: Codable {
    let data: [RecoveryDay]
}

// MARK: - Sleep (WHOOP)

struct SleepDay: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let durationMinutes: Double?
    let efficiencyPercent: Double?
    let avgHeartRateBpm: Double?
    let avgRespiratoryRate: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case durationMinutes = "duration_minutes"
        case efficiencyPercent = "efficiency_percent"
        case avgHeartRateBpm = "avg_heart_rate_bpm"
        case avgRespiratoryRate = "avg_respiratory_rate"
    }
}

struct SleepResponse: Codable {
    let data: [SleepDay]
}

// MARK: - Timeseries (weight / body fat trends)

struct TimeseriesSample: Codable, Hashable {
    let timestamp: String
    let type: String
    let value: Double
}

struct TimeseriesResponse: Codable {
    let data: [TimeseriesSample]
}

// MARK: - Users

struct UserItem: Codable, Identifiable {
    let id: String
    let firstName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
    }
}

struct UsersResponse: Codable {
    let items: [UserItem]
}
