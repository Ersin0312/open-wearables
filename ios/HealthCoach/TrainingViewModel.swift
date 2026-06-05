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
    func imageURL(_ id: String) -> String? { exerciseByID[id]?.imageURL }

    /// Load the exercise library, optionally filtered to a split (push/pull/legs).
    /// Custom split shows everything. Always keep a full lookup for name resolution.
    func loadExercises(split: String? = nil) async {
        do {
            let filter = (split == "custom") ? nil : split
            let ex = try await APIClient.shared.exercises(splitTag: filter)
            exercises = ex
            // Keep the name lookup complete (load all once) so history/sets resolve.
            if exerciseByID.isEmpty {
                let all = filter == nil ? ex : (try? await APIClient.shared.exercises()) ?? ex
                exerciseByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            } else {
                for e in ex where exerciseByID[e.id] == nil { exerciseByID[e.id] = e }
            }
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
            await loadExercises(split: split)   // only this split's exercises
        } catch { self.error = error.localizedDescription }
    }

    /// When resuming a persisted session, load its split's exercises too.
    func loadExercisesForActiveSession() async {
        if let split = activeSession?.splitTag {
            await loadExercises(split: split)
        }
    }

    func end() async {
        guard let id = activeSessionID else { return }
        do { _ = try await APIClient.shared.endSession(sessionID: id) }
        catch { self.error = error.localizedDescription }
        clearActive()
        await loadHistory()
    }

    func reopen(_ session: TrainingSession) async {
        do {
            let s = try await APIClient.shared.reopenSession(sessionID: session.id)
            activeSessionID = s.id
            UserDefaults.standard.set(s.id, forKey: kActiveSession)
            await loadActive()
            await loadExercises(split: s.splitTag)
        } catch { self.error = error.localizedDescription }
    }

    func duplicate(_ session: TrainingSession) async {
        do {
            let s = try await APIClient.shared.duplicateSession(sessionID: session.id)
            activeSessionID = s.id
            UserDefaults.standard.set(s.id, forKey: kActiveSession)
            await loadActive()
            await loadExercises(split: s.splitTag)
        } catch { self.error = error.localizedDescription }
    }

    func deleteSession(_ session: TrainingSession) async {
        do {
            try await APIClient.shared.deleteSession(sessionID: session.id)
            await loadHistory()
        } catch { self.error = error.localizedDescription }
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

    func updateSet(_ s: TrainingSet, reps: Int, weight: Double) async {
        guard let id = activeSessionID else { return }
        do {
            _ = try await APIClient.shared.updateSet(sessionID: id, setID: s.id, reps: reps, weightKg: weight)
            sets = try await APIClient.shared.sets(sessionID: id)
        } catch { self.error = error.localizedDescription }
    }

    /// Chronological timeline of the active session's sets, with rest deltas.
    var timeline: [TimelineEntry] {
        buildTimeline(sets: sets, name: exerciseName, image: imageURL)
    }

    /// Total tonnage of the active session (Σ reps × weight).
    var totalVolume: Double {
        sets.reduce(0) { $0 + Double($1.reps) * (Double($1.weightKg) ?? 0) }
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
