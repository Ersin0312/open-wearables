import SwiftUI

struct TrainingView: View {
    @StateObject private var vm = TrainingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.activeSessionID != nil {
                    ActiveSessionView(vm: vm)
                } else {
                    StartSessionView(vm: vm)
                }
            }
            .navigationTitle("Training")
            .task {
                await vm.loadExercises()
                await vm.loadActive()
                await vm.loadHistory()
            }
        }
    }
}

// MARK: - Start screen (choose split) + history

struct StartSessionView: View {
    @ObservedObject var vm: TrainingViewModel

    var body: some View {
        List {
            Section("Neue Session") {
                ForEach(SPLIT_TAGS, id: \.self) { tag in
                    Button {
                        Task { await vm.start(split: tag) }
                    } label: {
                        Label(SPLIT_LABELS[tag] ?? tag, systemImage: "dumbbell.fill")
                    }
                }
            }
            if !vm.pastSessions.isEmpty {
                Section("Letzte Sessions") {
                    ForEach(vm.pastSessions.filter { $0.endedAt != nil }.prefix(10)) { s in
                        HStack {
                            Text(SPLIT_LABELS[s.splitTag] ?? s.splitTag).font(.headline)
                            Spacer()
                            Text(shortDate(s.startedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable { await vm.loadHistory() }
    }
}

// MARK: - Active session

struct ActiveSessionView: View {
    @ObservedObject var vm: TrainingViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Live: \(SPLIT_LABELS[vm.activeSession?.splitTag ?? ""] ?? "Session")",
                          systemImage: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Spacer()
                    Text("\(vm.sets.count) Sätze").font(.caption).foregroundStyle(.secondary)
                }
                Button(role: .destructive) { Task { await vm.end() } } label: {
                    Label("Session beenden", systemImage: "stop.circle")
                }
            }

            SetLoggerSection(vm: vm)

            if !vm.groupedSets.isEmpty {
                Section("Sätze in dieser Session") {
                    ForEach(vm.groupedSets) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name).font(.subheadline).bold()
                            ForEach(group.sets) { s in
                                HStack {
                                    Text("#\(s.setNumber)").font(.caption).foregroundStyle(.secondary)
                                    Text("\(s.reps) reps × \(fmt(Double(s.weightKg) ?? 0)) kg")
                                    Spacer()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await vm.deleteSet(s) }
                                    } label: { Label("Löschen", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Set logger (pick exercise, enter reps/weight)

struct SetLoggerSection: View {
    @ObservedObject var vm: TrainingViewModel
    @State private var selected: Exercise?
    @State private var search = ""
    @State private var reps = ""
    @State private var weight = ""

    var body: some View {
        Section("Satz erfassen") {
            if let ex = selected {
                HStack {
                    VStack(alignment: .leading) {
                        Text(ex.name).font(.subheadline)
                        Text("\(MUSCLE_LABELS[ex.primaryMuscleGroup] ?? "") · Satz #\(vm.nextSetNumber(for: ex.id))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ändern") { selected = nil; search = "" }
                }
                HStack {
                    TextField("Wdh.", text: $reps).keyboardType(.numberPad).frame(width: 70)
                    Text("×").foregroundStyle(.secondary)
                    TextField("kg", text: $weight).keyboardType(.decimalPad).frame(width: 80)
                    Text("kg").foregroundStyle(.secondary)
                }
                Button {
                    if let r = Int(reps), let w = Double(weight.replacingOccurrences(of: ",", with: ".")) {
                        Task { await vm.addSet(exerciseID: ex.id, reps: r, weight: w) }
                        weight = ""  // keep reps, clear weight for fast entry
                    }
                } label: { Label("Satz hinzufügen", systemImage: "plus.circle.fill") }
                .disabled(Int(reps) == nil || Double(weight.replacingOccurrences(of: ",", with: ".")) == nil)
            } else {
                TextField("Übung suchen (z. B. 3014, Brustpresse)…", text: $search)
                    .autocorrectionDisabled()
                ForEach(vm.pickerGroups(search: search), id: \.muscle) { grp in
                    DisclosureGroup(grp.label) {
                        ForEach(grp.items) { ex in
                            Button(ex.name) {
                                selected = ex; search = ""
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}

func shortDate(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let d = date else { return "" }
    let out = DateFormatter()
    out.dateFormat = "EE dd.MM."
    out.locale = Locale(identifier: "de_DE")
    return out.string(from: d)
}
