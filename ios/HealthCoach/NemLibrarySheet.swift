import SwiftUI

private let UNIT_OPTIONS = ["mg", "g", "ml", "iu", "capsule", "tablet", "scoop", "drop"]
private let CATEGORY_OPTIONS = [
    ("protein", "Protein"), ("performance", "Performance"), ("recovery", "Recovery"),
    ("fatty_acid", "Omega/Fettsäuren"), ("vitamin", "Vitamine"), ("mineral", "Mineralien"),
    ("amino_acid", "Aminosäuren"), ("nootropic", "Nootropika"), ("other", "Sonstiges"),
]

/// The NEM library: search, edit (name/brand/dose/unit/daily dose), and delete.
/// Mirrors the web app. Delete is guarded by the backend (409 if still used).
struct NemLibrarySheet: View {
    let supplements: [Supplement]
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var editTarget: Supplement?
    @State private var working: [Supplement] = []
    @State private var error: String?
    @State private var forceTarget: Supplement?   // pending force-delete confirmation
    @State private var forceMessage = ""

    private var filtered: [Supplement] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let base = working.isEmpty ? supplements : working
        guard !q.isEmpty else { return base.sorted { $0.name < $1.name } }
        return base.filter {
            $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                ForEach(filtered) { sup in
                    Button { editTarget = sup } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sup.name).foregroundStyle(.primary)
                            Text(subtitle(sup)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await delete(sup) } } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name oder Hersteller")
            .navigationTitle("NEM-Bibliothek")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(item: $editTarget) { sup in
                EditSupplementSheet(supplement: sup) { onChanged() }
            }
            .alert("Trotzdem löschen?", isPresented: Binding(
                get: { forceTarget != nil },
                set: { if !$0 { forceTarget = nil } }
            )) {
                Button("Abbrechen", role: .cancel) { forceTarget = nil }
                Button("Löschen", role: .destructive) {
                    if let s = forceTarget { Task { await delete(s, force: true) } }
                    forceTarget = nil
                }
            } message: {
                Text(forceMessage)
            }
            .onAppear { working = supplements }
        }
    }

    private func subtitle(_ s: Supplement) -> String {
        var parts: [String] = []
        if let b = s.brand, !b.isEmpty { parts.append(b) }
        if let d = s.defaultDose { parts.append("\(fmt(Double(d) ?? 0)) \(s.defaultUnit)") }
        if let r = s.recommendedDailyDose { parts.append("Ziel \(fmt(Double(r) ?? 0)) \(s.defaultUnit)/Tag") }
        return parts.joined(separator: " · ")
    }

    private func delete(_ s: Supplement, force: Bool = false) async {
        do {
            try await APIClient.shared.deleteSupplement(id: s.id, force: force)
            working.removeAll { $0.id == s.id }
            onChanged()
            error = nil
        } catch let APIError.http(code, body) where code == 409 {
            // Still referenced — offer a force delete with the server's explanation.
            forceMessage = serverDetail(body) ?? "Dieses NEM wird noch verwendet. Trotzdem löschen entfernt auch die zugehörigen Einträge."
            forceTarget = s
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Pull the human-readable `detail` out of the FastAPI error body.
    private func serverDetail(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = obj["detail"] as? String else { return nil }
        return detail
    }
}

/// Edit an existing supplement (reuses the create form layout).
struct EditSupplementSheet: View {
    let supplement: Supplement
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand: String
    @State private var category: String
    @State private var doseText: String
    @State private var unit: String
    @State private var dailyText: String
    @State private var notes: String

    init(supplement: Supplement, onSaved: @escaping () -> Void) {
        self.supplement = supplement
        self.onSaved = onSaved
        _name = State(initialValue: supplement.name)
        _brand = State(initialValue: supplement.brand ?? "")
        _category = State(initialValue: supplement.category)
        _doseText = State(initialValue: supplement.defaultDose.map { fmt(Double($0) ?? 0) } ?? "")
        _unit = State(initialValue: supplement.defaultUnit)
        _dailyText = State(initialValue: supplement.recommendedDailyDose.map { fmt(Double($0) ?? 0) } ?? "")
        _notes = State(initialValue: supplement.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Produkt") {
                    TextField("Name", text: $name)
                    TextField("Hersteller (optional)", text: $brand)
                }
                Section("Kategorie") {
                    Picker("Kategorie", selection: $category) {
                        ForEach(CATEGORY_OPTIONS, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Dosierung") {
                    HStack {
                        TextField("Standard-Dosis", text: $doseText).keyboardType(.decimalPad)
                        Picker("", selection: $unit) {
                            ForEach(UNIT_OPTIONS, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    TextField("Empf. Tagesdosis (optional)", text: $dailyText).keyboardType(.decimalPad)
                }
                Section("Notizen (optional)") { TextField("Wirkung, Timing…", text: $notes) }
            }
            .navigationTitle("NEM bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            do {
                                _ = try await APIClient.shared.updateSupplement(
                                    id: supplement.id, name: name.trimmingCharacters(in: .whitespaces),
                                    brand: brand.isEmpty ? nil : brand, category: category,
                                    defaultDose: Double(doseText), defaultUnit: unit,
                                    recommendedDailyDose: Double(dailyText),
                                    notes: notes.isEmpty ? nil : notes)
                                onSaved()
                                dismiss()
                            } catch { }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
