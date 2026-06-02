import Foundation

private let kActiveSession = "active_training_session_id"

let MUSCLE_LABELS: [String: String] = [
    "chest": "Brust", "back": "Rücken", "shoulders": "Schultern",
    "biceps": "Bizeps", "triceps": "Trizeps", "legs": "Beine",
    "glutes": "Gesäß", "core": "Rumpf", "fullbody": "Ganzkörper",
]
let MUSCLE_ORDER = ["chest", "back", "shoulders", "biceps", "triceps", "legs", "glutes", "core", "fullbody"]

let SPLIT_LABELS: [String: String] = ["push": "Push", "pull": "Pull", "legs": "Beine", "custom": "Custom"]
let SPLIT_TAGS = ["push", "pull", "legs", "custom"]

@MainActor
final class TrainingViewModel: ObservableObject {
    @Published var activeSessionID: String? = UserDefaults.standard.string(forKey: kActiveSession)
    @Published var activeSession: TrainingSession?
    @Published var sets: [TrainingSet] = []
    @Published var exercises: [Exercise] = []
    @Published var pastSessions: [TrainingSession] = []
    @Published var loading = false
    @Published var error: String?

    private var exerciseByID: [String: Exercise] = [:]
    func exerciseName(_ id: String) -> String { exerciseByID[id]?.name ?? "Unbekannt" }
    func muscle(_ id: String) -> String { exerciseByID[id]?.primaryMuscleGroup ?? "" }

    func loadExercises() async {
        guard exercises.isEmpty else { return }
        do {
            let ex = try await APIClient.shared.exercises()
            exercises = ex
            exerciseByID = Dictionary(uniqueKeysWithValues: ex.map { ($0.id, $0) })
        } catch { self.error = error.localizedDescription }
    }

    func loadHistory() async {
        do { pastSessions = try await APIClient.shared.trainingSessions(limit: 20) }
        catch { self.error = error.localizedDescription }
    }

    func loadActive() async {
        guard let id = activeSessionID else { activeSession = nil; sets = []; return }
        loading = true
        defer { loading = false }
        do {
            async let s = APIClient.shared.sets(sessionID: id)
            async let sessions = APIClient.shared.trainingSessions(limit: 20)
            let (fetchedSets, allSessions) = try await (s, sessions)
            // find this session in the list; if it's ended or gone, clear active
            if let match = allSessions.first(where: { $0.id == id }), match.endedAt == nil {
                activeSession = match
                sets = fetchedSets
            } else {
                clearActive()
            }
            pastSessions = allSessions
        } catch { self.error = error.localizedDescription }
    }

    func start(split: String) async {
        do {
            let s = try await APIClient.shared.startSession(splitTag: split)
            activeSessionID = s.id
            activeSession = s
            sets = []
            UserDefaults.standard.set(s.id, forKey: kActiveSession)
        } catch { self.error = error.localizedDescription }
    }

    func end() async {
        guard let id = activeSessionID else { return }
        do { _ = try await APIClient.shared.endSession(sessionID: id) }
        catch { self.error = error.localizedDescription }
        clearActive()
        await loadHistory()
    }

    private func clearActive() {
        activeSessionID = nil
        activeSession = nil
        sets = []
        UserDefaults.standard.removeObject(forKey: kActiveSession)
    }

    func nextSetNumber(for exerciseID: String) -> Int {
        sets.filter { $0.exerciseID == exerciseID }.count + 1
    }

    func addSet(exerciseID: String, reps: Int, weight: Double) async {
        guard let id = activeSessionID else { return }
        do {
            _ = try await APIClient.shared.addSet(sessionID: id, exerciseID: exerciseID,
                                                  setNumber: nextSetNumber(for: exerciseID),
                                                  reps: reps, weightKg: weight)
            sets = try await APIClient.shared.sets(sessionID: id)
        } catch { self.error = error.localizedDescription }
    }

    func deleteSet(_ s: TrainingSet) async {
        guard let id = activeSessionID else { return }
        do {
            try await APIClient.shared.deleteSet(sessionID: id, setID: s.id)
            sets = try await APIClient.shared.sets(sessionID: id)
        } catch { self.error = error.localizedDescription }
    }

    /// Sets grouped by exercise, ordered by muscle region.
    struct ExerciseGroup: Identifiable {
        let id: String          // exercise id
        let name: String
        let muscle: String
        let sets: [TrainingSet]
    }

    var groupedSets: [ExerciseGroup] {
        var byEx: [String: [TrainingSet]] = [:]
        for s in sets { byEx[s.exerciseID, default: []].append(s) }
        return byEx.map { (exID, exSets) in
            ExerciseGroup(id: exID, name: exerciseName(exID), muscle: muscle(exID),
                          sets: exSets.sorted { $0.setNumber < $1.setNumber })
        }
        .sorted { a, b in
            let ia = MUSCLE_ORDER.firstIndex(of: a.muscle) ?? MUSCLE_ORDER.count
            let ib = MUSCLE_ORDER.firstIndex(of: b.muscle) ?? MUSCLE_ORDER.count
            return ia < ib
        }
    }

    /// Exercises filtered by token-AND search, grouped by muscle for the picker.
    func pickerGroups(search: String) -> [(muscle: String, label: String, items: [Exercise])] {
        let tokens = search.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let filtered = exercises.filter { ex in
            tokens.isEmpty || tokens.allSatisfy { ex.name.lowercased().contains($0) }
        }
        var byMuscle: [String: [Exercise]] = [:]
        for ex in filtered { byMuscle[ex.primaryMuscleGroup, default: []].append(ex) }
        return MUSCLE_ORDER.compactMap { m in
            guard let items = byMuscle[m], !items.isEmpty else { return nil }
            return (m, MUSCLE_LABELS[m] ?? m, items.sorted { $0.name < $1.name })
        }
    }
}
