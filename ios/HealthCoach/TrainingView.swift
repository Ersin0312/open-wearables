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
                // Always load the full library so history rows resolve machine
                // names + photos even when no session is active.
                await vm.loadExercises()
            }
        }
    }
}

// MARK: - Start screen (choose split) + history

struct StartSessionView: View {
    @ObservedObject var vm: TrainingViewModel
    @StateObject private var cardio = CardioStore()
    @StateObject private var pullups = PullupStore()
    @State private var detailDay: TrainingViewModel.DayGroup?
    @State private var showCardioLog = false
    @State private var showPullupLog = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await vm.start(split: "custom") }
                } label: {
                    Label("Session starten / fortsetzen", systemImage: "play.circle.fill")
                        .font(.headline)
                }
                if vm.currentStreak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("\(vm.currentStreak) \(vm.currentStreak == 1 ? "Tag" : "Tage") in Folge trainiert")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            Section {
                Button { showCardioLog = true } label: {
                    Label("Cardio / Zone-2 loggen", systemImage: "figure.run")
                }
                if cardio.minutesLast7Days > 0 {
                    HStack {
                        Text("Zone-2 (7 Tage)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(cardio.minutesLast7Days) min").font(.caption.weight(.semibold))
                    }
                }
                ForEach(cardio.sessions.prefix(5)) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(cardioLabel(c.kind)) · \(Int(c.minutes)) min").font(.subheadline)
                            Text(weekdayDateShort(c.performedAt)
                                 + (c.avgHr.map { " · \($0) bpm" } ?? "")
                                 + (c.distance.map { " · \(fmt($0)) km" } ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await cardio.delete(c) } } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            } header: { Text("Cardio") }

            Section {
                Button { showPullupLog = true } label: {
                    Label("Klimmzüge loggen", systemImage: "figure.strengthtraining.functional")
                }
                if pullups.bestBodyweight > 0 {
                    HStack {
                        Text("Bestleistung (Körpergewicht)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(pullups.bestBodyweight) Wdh.").font(.caption.weight(.semibold))
                    }
                }
                ForEach(pullups.entries.prefix(5)) { p in
                    HStack {
                        Text("\(p.reps) Wdh." + (p.added > 0 ? " + \(fmt(p.added)) kg" : "")).font(.subheadline)
                        Spacer()
                        Text(weekdayDateShort(p.performedAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await pullups.delete(p) } } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            } header: { Text("Klimmzüge") }

            let days = vm.historyByDay
            if !days.isEmpty {
                Section("Trainingstage") {
                    ForEach(days.prefix(20)) { day in
                        Button { detailDay = day } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary).font(.subheadline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(day.label).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("ab \(clockTime(day.firstStart))"
                                         + (day.sessions.count > 1 ? " · \(day.sessions.count) Einheiten" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { for s in day.sessions { await vm.deleteSession(s) } }
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .refreshable { await vm.loadHistory(); await cardio.load(); await pullups.load() }
        .task { await cardio.load(); await pullups.load() }
        .sheet(item: $detailDay) { day in
            DayDetailView(day: day, vm: vm).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCardioLog) {
            CardioLogSheet(store: cardio).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPullupLog) {
            PullupLogSheet(store: pullups).preferredColorScheme(.dark)
        }
    }
}

/// Read-only breakdown of one training DAY (all sessions merged): weekday/date
/// header, sets/duration/volume stats, then sets grouped by muscle → machine,
/// each set with its clock time + the rest computed across the whole day.
struct DayDetailView: View {
    let day: TrainingViewModel.DayGroup
    @ObservedObject var vm: TrainingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sets: [TrainingSet] = []
    @State private var loading = true

    private var totalVolume: Double {
        sets.reduce(0) { $0 + Double($1.reps) * (Double($1.weightKg) ?? 0) }
    }
    /// Span from the day's first set to its last set.
    private var duration: String? {
        let times = sets.compactMap { parseTimestamp($0.createdAt) }.sorted()
        guard let first = times.first, let last = times.last, last > first else { return nil }
        return formatInterval(last.timeIntervalSince(first))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(weekdayDateTime(day.firstStart)).font(.headline)
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
                    Text("Keine Sätze an diesem Tag.").foregroundStyle(.secondary)
                } else {
                    MuscleGroupedView(
                        sets: sets, name: vm.exerciseName, image: vm.imageURL, muscle: vm.muscle,
                        onSave: { s, reps, w in Task { await editSet(s, reps: reps, weight: w) } },
                        onDelete: { s in Task { await removeSet(s) } })

                    Section {
                        Button(role: .destructive) { Task { await deleteDay() } } label: {
                            Label("Trainingstag löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Trainingstag").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let last = day.sessions.last {
                        Button { Task { await vm.reopen(last); dismiss() } } label: {
                            Label("Fortsetzen", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        // Merge sets across every session that started this day.
        var all: [TrainingSet] = []
        for s in day.sessions {
            if let part = try? await APIClient.shared.sets(sessionID: s.id) { all.append(contentsOf: part) }
        }
        sets = all
        loading = false
    }

    private func editSet(_ s: TrainingSet, reps: Int, weight: Double) async {
        _ = try? await APIClient.shared.updateSet(sessionID: s.sessionID, setID: s.id, reps: reps, weightKg: weight)
        await reload()
    }

    private func removeSet(_ s: TrainingSet) async {
        try? await APIClient.shared.deleteSet(sessionID: s.sessionID, setID: s.id)
        sets.removeAll { $0.id == s.id }
    }

    private func deleteDay() async {
        for s in day.sessions { await vm.deleteSession(s) }
        dismiss()
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
    @State private var lastPerf: ExercisePerformance?
    @State private var loadingPerf = false

    private func loadPerf(_ ex: Exercise) async {
        loadingPerf = true; lastPerf = nil
        lastPerf = try? await APIClient.shared.lastExercisePerformance(
            exerciseID: ex.id, excludeSession: vm.activeSessionID)
        loadingPerf = false
    }

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
                    Button("Ändern") { selected = nil; search = ""; lastPerf = nil }
                }

                if let perf = lastPerf {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Letztes Mal (\(weekdayDateShort(perf.performedAt))): \(summarizeSets(perf.sets))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let sugg = doubleProgression(from: perf.sets) {
                            Button {
                                reps = String(sugg.reps)
                                weight = fmt(sugg.weight)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "wand.and.stars")
                                    Text("Vorschlag: \(sugg.reps) × \(fmt(sugg.weight)) kg")
                                        .fontWeight(.semibold)
                                    Text("· \(sugg.rationale)").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else if loadingPerf {
                    Text("Lade letzte Leistung…").font(.caption).foregroundStyle(.secondary)
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
        .task(id: selected?.id) {
            if let ex = selected { await loadPerf(ex) }
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
