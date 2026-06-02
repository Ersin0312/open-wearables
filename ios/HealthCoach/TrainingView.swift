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
                await vm.loadActive()
                await vm.loadHistory()
                await vm.loadExercisesForActiveSession()
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
                        Menu {
                            Button { Task { await vm.reopen(s) } } label: {
                                Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                            }
                            Button { Task { await vm.duplicate(s) } } label: {
                                Label("Duplizieren", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) { Task { await vm.deleteSession(s) } } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        } label: {
                            HStack {
                                Text(SPLIT_LABELS[s.splitTag] ?? s.splitTag).font(.headline)
                                Spacer()
                                Text(shortDate(s.startedAt)).font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await vm.deleteSession(s) } } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button { Task { await vm.duplicate(s) } } label: {
                                Label("Dup.", systemImage: "plus.square.on.square")
                            }.tint(.blue)
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
                    ExerciseThumb(imageURL: ex.imageURL, size: 56)
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
                            Button {
                                selected = ex; search = ""
                            } label: {
                                HStack(spacing: 10) {
                                    ExerciseThumb(imageURL: ex.imageURL)
                                    Text(ex.name).foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Small thumbnail for a Gym80 machine image (served by the frontend container).
struct ExerciseThumb: View {
    let imageURL: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let path = imageURL, let url = URL(string: AppConfig.imageBaseURL.absoluteString + path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .overlay(Image(systemName: "dumbbell").foregroundStyle(.secondary).font(.caption))
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
