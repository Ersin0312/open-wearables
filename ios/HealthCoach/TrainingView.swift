import SwiftUI

struct TrainingView: View {
    @StateObject private var vm = TrainingViewModel()
    @StateObject private var favorites = FavoritesStore()

    var body: some View {
        NavigationStack {
            Group {
                if vm.activeSessionID != nil {
                    ActiveSessionView(vm: vm, favorites: favorites)
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
    @State private var detailSession: TrainingSession?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.start(split: "custom") }
                } label: {
                    Label("Neue Session starten", systemImage: "play.circle.fill")
                        .font(.headline)
                }
            }
            if !vm.pastSessions.isEmpty {
                Section("Letzte Sessions") {
                    ForEach(vm.pastSessions.filter { $0.endedAt != nil }.prefix(15)) { s in
                        Button { detailSession = s } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary).font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(weekdayDateShort(s.startedAt)).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(clockTime(s.startedAt)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button { Task { await vm.reopen(s) } } label: {
                                Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                            }
                            Button { Task { await vm.duplicate(s) } } label: {
                                Label("Duplizieren", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) { Task { await vm.deleteSession(s) } } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await vm.deleteSession(s) } } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                            Button { Task { await vm.reopen(s) } } label: {
                                Label("Öffnen", systemImage: "arrow.uturn.backward")
                            }.tint(.blue)
                        }
                    }
                }
            }
        }
        .refreshable { await vm.loadHistory() }
        .sheet(item: $detailSession) { s in
            SessionDetailView(session: s, vm: vm).preferredColorScheme(.dark)
        }
    }
}

/// Read-only breakdown of a past session: weekday/date/time header, duration +
/// volume, and the chronological timeline (exercises with times + rest pauses).
struct SessionDetailView: View {
    let session: TrainingSession
    @ObservedObject var vm: TrainingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sets: [TrainingSet] = []
    @State private var loading = true

    private var totalVolume: Double {
        sets.reduce(0) { $0 + Double($1.reps) * (Double($1.weightKg) ?? 0) }
    }
    private var duration: String? {
        guard let endIso = session.endedAt,
              let start = parseTimestamp(session.startedAt),
              let end = parseTimestamp(endIso) else { return nil }
        return formatInterval(end.timeIntervalSince(start))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(weekdayDateTime(session.startedAt)).font(.headline)
                        HStack(spacing: 16) {
                            stat("\(sets.count)", "Sätze")
                            if let d = duration { stat(d, "Dauer") }
                            stat("\(fmt(totalVolume)) kg", "Volumen")
                        }
                    }
                }
                if loading {
                    HStack { ProgressView(); Text("Lade…").foregroundStyle(.secondary) }
                } else if sets.isEmpty {
                    Text("Keine Sätze in dieser Session.").foregroundStyle(.secondary)
                } else {
                    Section("Verlauf") {
                        SessionTimelineView(entries: buildTimeline(sets: sets, name: vm.exerciseName, image: vm.imageURL))
                    }
                }
            }
            .navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.reopen(session); dismiss() } } label: {
                        Label("Öffnen", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .task {
                sets = (try? await APIClient.shared.sets(sessionID: session.id)) ?? []
                loading = false
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Active session

struct ActiveSessionView: View {
    @ObservedObject var vm: TrainingViewModel
    @ObservedObject var favorites: FavoritesStore

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Live: Session", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Spacer()
                    if let start = vm.activeSession?.startedAt {
                        Text("seit \(clockTime(start))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("\(vm.sets.count) Sätze").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Volumen \(fmt(vm.totalVolume)) kg").font(.caption).foregroundStyle(.secondary)
                }
                Button(role: .destructive) { Task { await vm.end() } } label: {
                    Label("Session beenden", systemImage: "stop.circle")
                }
            }

            SetLoggerSection(vm: vm, favorites: favorites)

            if !vm.sets.isEmpty {
                Section("Verlauf dieser Session") {
                    SessionTimelineView(
                        entries: vm.timeline,
                        onSave: { s, reps, w in Task { await vm.updateSet(s, reps: reps, weight: w) } },
                        onDelete: { s in Task { await vm.deleteSet(s) } })
                }
            }
        }
    }
}

// MARK: - Set logger (pick exercise, enter reps/weight)

struct SetLoggerSection: View {
    @ObservedObject var vm: TrainingViewModel
    @ObservedObject var favorites: FavoritesStore
    @State private var selected: Exercise?
    @State private var search = ""
    @State private var reps = ""
    @State private var weight = ""

    private var favoriteExercises: [Exercise] {
        let q = search.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return vm.exercises
            .filter { favorites.isFavorite($0.id) }
            .filter { ex in q.isEmpty || q.allSatisfy { ex.name.lowercased().contains($0) } }
            .sorted { $0.name < $1.name }
    }

    private func addSet(_ ex: Exercise) {
        if let r = Int(reps), let w = Double(weight.replacingOccurrences(of: ",", with: ".")) {
            Task { await vm.addSet(exerciseID: ex.id, reps: r, weight: w) }
            weight = ""  // keep reps, clear weight for fast entry
        }
    }

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
                        .submitLabel(.next)
                    Text("×").foregroundStyle(.secondary)
                    TextField("kg", text: $weight).keyboardType(.decimalPad).frame(width: 80)
                        .submitLabel(.done)
                        .onSubmit { addSet(ex) }
                    Text("kg").foregroundStyle(.secondary)
                }
                Button { addSet(ex) } label: { Label("Satz hinzufügen", systemImage: "plus.circle.fill") }
                .disabled(Int(reps) == nil || Double(weight.replacingOccurrences(of: ",", with: ".")) == nil)
            } else {
                TextField("Gerät suchen (z. B. 3014, Brustpresse)…", text: $search)
                    .autocorrectionDisabled()

                // Favourites first, before the muscle-group categories.
                if !favoriteExercises.isEmpty {
                    Section {
                        ForEach(favoriteExercises) { ex in pickerRow(ex) }
                    } header: {
                        Label("Favoriten", systemImage: "star.fill").foregroundStyle(.yellow)
                    }
                }

                ForEach(vm.pickerGroups(search: search), id: \.muscle) { grp in
                    DisclosureGroup(grp.label) {
                        ForEach(grp.items) { ex in pickerRow(ex) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickerRow(_ ex: Exercise) -> some View {
        HStack(spacing: 10) {
            Button {
                selected = ex; search = ""
            } label: {
                HStack(spacing: 10) {
                    ExerciseThumb(imageURL: ex.imageURL)
                    Text(ex.name).foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            Button {
                favorites.toggle(ex.id)
            } label: {
                Image(systemName: favorites.isFavorite(ex.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.isFavorite(ex.id) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Small thumbnail for a Gym80 machine image. Tap to zoom to full screen.
struct ExerciseThumb: View {
    let imageURL: String?
    var size: CGFloat = 44
    @State private var zoomed = false

    private var fullURL: URL? {
        guard let path = imageURL else { return nil }
        return URL(string: AppConfig.imageBaseURL.absoluteString + path)
    }

    var body: some View {
        Group {
            if let url = fullURL {
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
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { if fullURL != nil { zoomed = true } }
        .sheet(isPresented: $zoomed) {
            ImageLightbox(url: fullURL)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .overlay(Image(systemName: "dumbbell").foregroundStyle(.secondary).font(.caption))
    }
}

/// Full-screen zoomable image viewer (pinch + drag).
struct ImageLightbox: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                            .scaleEffect(scale)
                            .gesture(MagnificationGesture()
                                .onChanged { scale = max(1, $0) }
                                .onEnded { _ in withAnimation { scale = max(1, min(scale, 4)) } })
                    case .failure:
                        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}
