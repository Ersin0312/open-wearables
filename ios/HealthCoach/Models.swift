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
