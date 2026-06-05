import SwiftUI

// MARK: - Timestamp helpers

/// Parse a backend ISO timestamp (with or without fractional seconds / Z).
func parseTimestamp(_ iso: String) -> Date? {
    let withZ = iso.hasSuffix("Z") || iso.contains("+") ? iso : iso + "Z"
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = frac.date(from: withZ) { return d }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: withZ)
}

/// "Mittwoch, 05.06.2026 · 18:30"
func weekdayDateTime(_ iso: String) -> String {
    guard let d = parseTimestamp(iso) else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateFormat = "EEEE, dd.MM.yyyy · HH:mm"
    return f.string(from: d)
}

/// "Mittwoch, 05.06." — compact, for list rows.
func weekdayDateShort(_ iso: String) -> String {
    guard let d = parseTimestamp(iso) else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_DE")
    f.dateFormat = "EEEE, dd.MM."
    return f.string(from: d)
}

/// "18:42" clock time.
func clockTime(_ iso: String) -> String {
    guard let d = parseTimestamp(iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    return f.string(from: d)
}

/// A rest/elapsed interval as "1:45" (m:ss) or "0:45".
func formatInterval(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    let m = s / 60, sec = s % 60
    return String(format: "%d:%02d", m, sec)
}

// MARK: - Double progression

/// Next-target suggestion from the last performance, using double progression:
/// add reps within the range until the top is hit at the heaviest weight, then
/// add load and drop back to the bottom of the range.
struct ProgressionSuggestion {
    let weight: Double
    let reps: Int
    let rationale: String
}

func doubleProgression(from sets: [TrainingSet],
                       repRange: ClosedRange<Int> = 8...12,
                       increment: Double = 2.5) -> ProgressionSuggestion? {
    guard !sets.isEmpty else { return nil }
    let weights = sets.compactMap { Double($0.weightKg) }
    guard let top = weights.max() else { return nil }
    let setsAtTop = sets.filter { (Double($0.weightKg) ?? 0) == top }
    let minReps = setsAtTop.map { $0.reps }.min() ?? 0
    if minReps >= repRange.upperBound {
        return ProgressionSuggestion(weight: top + increment, reps: repRange.lowerBound,
                                     rationale: "Top der Range (\(repRange.upperBound)) erreicht → +\(fmt(increment)) kg")
    }
    return ProgressionSuggestion(weight: top, reps: min(minReps + 1, repRange.upperBound),
                                 rationale: "+1 Wdh. bei gleichem Gewicht")
}

/// Compact summary of a performance, e.g. "10×40 · 8×60 · 8×80 kg".
func summarizeSets(_ sets: [TrainingSet]) -> String {
    let ordered = sets.sorted { $0.setNumber < $1.setNumber }
    return ordered.map { "\($0.reps)×\(fmt(Double($0.weightKg) ?? 0))" }.joined(separator: " · ") + " kg"
}

// MARK: - Timeline model

/// One row in a session timeline: a logged set, with the rest since the
/// previous set (chronologically) and whether it starts a new exercise block.
struct TimelineEntry: Identifiable {
    var id: String { self.set.id }
    let set: TrainingSet
    let exerciseName: String
    let imageURL: String?
    let startsNewExercise: Bool
    let restBefore: TimeInterval?   // nil for the very first set
}

/// Build a chronological timeline (by created_at) with rest deltas + exercise
/// grouping. Rest = gap to the previous set, capturing both intra-exercise rest
/// and the transition between machines.
func buildTimeline(sets: [TrainingSet],
                   name: (String) -> String,
                   image: (String) -> String?) -> [TimelineEntry] {
    let ordered = sets.sorted {
        (parseTimestamp($0.createdAt) ?? .distantPast) < (parseTimestamp($1.createdAt) ?? .distantPast)
    }
    var out: [TimelineEntry] = []
    var prevDate: Date?
    var prevExercise: String?
    for s in ordered {
        let date = parseTimestamp(s.createdAt)
        let rest: TimeInterval? = (prevDate != nil && date != nil) ? date!.timeIntervalSince(prevDate!) : nil
        out.append(TimelineEntry(
            set: s,
            exerciseName: name(s.exerciseID),
            imageURL: image(s.exerciseID),
            startsNewExercise: s.exerciseID != prevExercise,
            restBefore: rest))
        prevDate = date
        prevExercise = s.exerciseID
    }
    return out
}

// MARK: - Timeline view

/// Renders a session as a chronological timeline: each exercise block shows its
/// start time; each set shows reps×kg + the rest taken before it. Optional edit
/// and delete handlers make it usable live (active session) and read-only (history).
struct SessionTimelineView: View {
    let entries: [TimelineEntry]
    var onSave: ((TrainingSet, Int, Double) -> Void)? = nil
    var onDelete: ((TrainingSet) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { _, e in
                if e.startsNewExercise {
                    HStack(spacing: 10) {
                        ExerciseThumb(imageURL: e.imageURL, size: 38)
                        Text(e.exerciseName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(clockTime(e.set.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                if let rest = e.restBefore {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle").font(.caption2)
                        Text("Pause \(formatInterval(rest))").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.leading, 48)
                }
                timelineSetRow(e)
            }
        }
    }

    @ViewBuilder
    private func timelineSetRow(_ e: TimelineEntry) -> some View {
        if let onSave, let onDelete {
            EditableTimelineSet(set: e.set, onSave: onSave, onDelete: onDelete)
                .padding(.leading, 48)
        } else {
            HStack(spacing: 8) {
                Text("#\(e.set.setNumber)").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                Text("\(e.set.reps) × \(fmt(Double(e.set.weightKg) ?? 0)) kg").font(.subheadline)
                Spacer()
                Text(clockTime(e.set.createdAt)).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.leading, 48)
        }
    }
}

// MARK: - Muscle-grouped breakdown (session detail)

/// A session/day broken down by muscle group → machine → sets. Each set keeps
/// its clock time and the rest (computed chronologically across the whole day),
/// so grouping by muscle doesn't lose the real pause information. Emits List
/// Sections, so place it directly inside a List.
struct MuscleGroupedView: View {
    let sets: [TrainingSet]
    let name: (String) -> String
    let image: (String) -> String?
    let muscle: (String) -> String

    /// setID → rest before it (global chronological gap).
    private var restMap: [String: TimeInterval] {
        var m: [String: TimeInterval] = [:]
        for e in buildTimeline(sets: sets, name: name, image: image) {
            if let r = e.restBefore { m[e.set.id] = r }
        }
        return m
    }

    private struct ExBlock: Identifiable {
        let id: String
        let name: String
        let image: String?
        let sets: [TrainingSet]
    }
    private struct Section_: Identifiable {
        let id: String
        let label: String
        let exercises: [ExBlock]
    }

    private var sections: [Section_] {
        // First-appearance time per exercise, to order machines as performed.
        var firstTime: [String: Date] = [:]
        for s in sets.sorted(by: { ($0.createdAt) < ($1.createdAt) }) {
            if firstTime[s.exerciseID] == nil { firstTime[s.exerciseID] = parseTimestamp(s.createdAt) }
        }
        var byMuscle: [String: [String: [TrainingSet]]] = [:]
        for s in sets { byMuscle[muscle(s.exerciseID), default: [:]][s.exerciseID, default: []].append(s) }
        let order = MUSCLE_ORDER + byMuscle.keys.filter { !MUSCLE_ORDER.contains($0) }
        return order.compactMap { m -> Section_? in
            guard let exMap = byMuscle[m], !exMap.isEmpty else { return nil }
            let exercises = exMap.map { (exID, exSets) in
                ExBlock(id: exID, name: name(exID), image: image(exID),
                        sets: exSets.sorted { $0.setNumber < $1.setNumber })
            }.sorted { (firstTime[$0.id] ?? .distantPast) < (firstTime[$1.id] ?? .distantPast) }
            return Section_(id: m, label: MUSCLE_LABELS[m] ?? (m.isEmpty ? "Sonstiges" : m), exercises: exercises)
        }
    }

    var body: some View {
        ForEach(sections) { sec in
            Section(sec.label) {
                ForEach(sec.exercises) { ex in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            ExerciseThumb(imageURL: ex.image, size: 38)
                            Text(ex.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let first = ex.sets.first {
                                Text(clockTime(first.createdAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(ex.sets) { s in
                            HStack(spacing: 8) {
                                Text("#\(s.setNumber)").font(.caption).foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .leading)
                                Text("\(s.reps) × \(fmt(Double(s.weightKg) ?? 0)) kg").font(.subheadline)
                                Spacer()
                                if let r = restMap[s.id] {
                                    Label(formatInterval(r), systemImage: "pause.circle")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(clockTime(s.createdAt)).font(.caption2).foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// A timeline set row with inline edit (pencil) + delete, for the live session.
private struct EditableTimelineSet: View {
    let set: TrainingSet
    let onSave: (TrainingSet, Int, Double) -> Void
    let onDelete: (TrainingSet) -> Void

    @State private var editing = false
    @State private var reps = ""
    @State private var weight = ""

    private func commit() {
        if let r = Int(reps), let w = Double(weight.replacingOccurrences(of: ",", with: ".")) {
            onSave(set, r, w)
        }
        editing = false
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(set.setNumber)").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            if editing {
                TextField("Wdh.", text: $reps).keyboardType(.numberPad).frame(width: 46)
                    .submitLabel(.done).onSubmit(commit)
                Text("×").foregroundStyle(.secondary)
                TextField("kg", text: $weight).keyboardType(.decimalPad).frame(width: 56)
                    .submitLabel(.done).onSubmit(commit)
                Spacer()
                Button(action: commit) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                Button { editing = false } label: { Image(systemName: "xmark.circle").foregroundStyle(.secondary) }
            } else {
                Text("\(set.reps) × \(fmt(Double(set.weightKg) ?? 0)) kg").font(.subheadline)
                Spacer()
                Text(clockTime(set.createdAt)).font(.caption2).foregroundStyle(.secondary)
                Button {
                    reps = String(set.reps); weight = fmt(Double(set.weightKg) ?? 0); editing = true
                } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.borderless)
        .swipeActions {
            Button(role: .destructive) { onDelete(set) } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}
