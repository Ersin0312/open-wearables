import Foundation
import SwiftUI

/// Local store for favourite exercises (machine ids). Favourites surface at the
/// top of the picker, before the muscle-group categories. Persisted in
/// UserDefaults — no backend field needed.
@MainActor
final class FavoritesStore: ObservableObject {
    private let key = "favorite_exercise_ids"
    @Published private(set) var ids: Set<String>

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids = Set(saved)
    }

    func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
