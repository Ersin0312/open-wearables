import SwiftUI

/// PLAN tab — the 12-month body-recomposition roadmap: editable start date,
/// a proportional phase timeline, and per-phase target cards (tap to edit).
struct PlanView: View {
    @State private var startDate = PlanConfig.startDate
    @State private var editingPhase: PlanConfig.Phase?
    @State private var rev = 0   // bump to re-read PlanConfig after edits

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    journeyCard
                    startDateCard
                    timelineCard
                    ForEach(PlanConfig.phases, id: \.index) { phase in
                        phaseCard(phase)
                    }
                    resetButton
                }
                .padding(16)
                .id(rev)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Plan")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $editingPhase) { phase in
                PhaseEditor(phase: phase) { rev += 1 }.preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var journeyCard: some View {
        DashCard(title: "Die Reise", systemImage: "map") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fmt(PlanConfig.startWeight)).font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.right").foregroundStyle(Theme.textSecondary)
                Text(fmt(PlanConfig.endGoalWeight)).font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("kg").foregroundStyle(Theme.textSecondary)
            }
            Text("\(PlanConfig.totalDays) Tage · 3 Phasen · Tag \(PlanConfig.currentDay) heute")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var startDateCard: some View {
        DashCard(title: "Startdatum", systemImage: "calendar") {
            DatePicker("Plan-Start", selection: $startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(Theme.accent)
                .foregroundStyle(Theme.textPrimary)
                .onChange(of: startDate) { _, newValue in
                    PlanConfig.startDate = newValue
                    rev += 1
                }
            Text("Bestimmt den Tageszähler und die aktive Phase. Setze hier deinen echten Startpunkt.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    // Proportional phase bar with a current-day marker.
    private var timelineCard: some View {
        DashCard(title: "Timeline", systemImage: "chart.bar.xaxis") {
            GeometryReader { geo in
                let w = geo.size.width
                let total = Double(PlanConfig.totalDays)
                HStack(spacing: 2) {
                    ForEach(PlanConfig.phases, id: \.index) { p in
                        let frac = Double(p.endDay - p.startDay + 1) / total
                        let isCurrent = p.index == PlanConfig.currentPhase.index
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isCurrent ? Theme.accent : Theme.cardElevated)
                            .frame(width: max(2, w * frac - 2))
                            .overlay(
                                Text("P\(p.index)").font(.caption2.weight(.bold))
                                    .foregroundStyle(isCurrent ? .white : Theme.textSecondary)
                            )
                    }
                }
                .overlay(alignment: .leading) {
                    let x = w * (Double(PlanConfig.currentDay) / total)
                    Rectangle().fill(Theme.good).frame(width: 2, height: 28)
                        .offset(x: min(max(x, 0), w - 2))
                }
            }
            .frame(height: 28)
            HStack {
                Text("Start").font(.caption2).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Tag \(PlanConfig.currentDay)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.good)
                Spacer()
                Text("Tag 365").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func phaseCard(_ p: PlanConfig.Phase) -> some View {
        let isCurrent = p.index == PlanConfig.currentPhase.index
        return Button { editingPhase = p } label: {
            DashCard(title: nil) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Phase \(p.index)").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                            if isCurrent {
                                Text("AKTIV").font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.good.opacity(0.2)).foregroundStyle(Theme.good)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(p.name).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Tag \(p.startDay)–\(p.endDay)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "pencil.circle").foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 10) {
                    StatChip(value: "\(fmt(p.goalWeight)) kg", label: "Zielgewicht", color: Theme.accent)
                    StatChip(value: p.calories, label: "kcal", color: Theme.teal)
                    StatChip(value: "\(p.proteinGrams) g", label: "Protein", color: Theme.violet)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isCurrent ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            PlanConfig.resetPhases(); rev += 1
        } label: {
            Label("Phasen auf Standard zurücksetzen", systemImage: "arrow.counterclockwise")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(Theme.textSecondary)
    }
}

/// Edit one phase's targets (goal weight, calories, protein). Day ranges and
/// names stay fixed — they define the plan's skeleton.
struct PhaseEditor: View {
    let phase: PlanConfig.Phase
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var goal: String
    @State private var calories: String
    @State private var protein: String

    init(phase: PlanConfig.Phase, onSave: @escaping () -> Void) {
        self.phase = phase
        self.onSave = onSave
        _goal = State(initialValue: String(format: "%.0f", phase.goalWeight))
        _calories = State(initialValue: phase.calories)
        _protein = State(initialValue: String(phase.proteinGrams))
    }

    private var goalValue: Double? { Double(goal.replacingOccurrences(of: ",", with: ".")) }
    private var proteinValue: Int? { Int(protein) }
    private var valid: Bool { (goalValue ?? 0) > 0 && (proteinValue ?? 0) > 0 && !calories.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DashCard(title: "Phase \(phase.index) · \(phase.name)", systemImage: "slider.horizontal.3") {
                        editorField("Zielgewicht (kg)", text: $goal, keyboard: .decimalPad)
                        editorField("Kalorien (z. B. 2400–2500)", text: $calories, keyboard: .default)
                        editorField("Protein (g)", text: $protein, keyboard: .numberPad)
                    }
                    Button {
                        if let g = goalValue, let p = proteinValue {
                            PlanConfig.savePhase(index: phase.index, goalWeight: g, calories: calories, proteinGrams: p)
                            onSave(); dismiss()
                        }
                    } label: {
                        Label("Speichern", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!valid)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Phase bearbeiten").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private func editorField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            TextField("", text: text)
                .keyboardType(keyboard)
                .foregroundStyle(Theme.textPrimary)
                .padding(10)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
