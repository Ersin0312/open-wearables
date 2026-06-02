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
