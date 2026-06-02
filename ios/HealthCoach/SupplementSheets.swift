import SwiftUI

private let UNIT_OPTIONS = ["mg", "g", "ml", "iu", "capsule", "tablet", "scoop", "drop"]
private let CATEGORY_OPTIONS = [
    ("protein", "Protein"), ("performance", "Performance"), ("recovery", "Recovery"),
    ("fatty_acid", "Omega/Fettsäuren"), ("vitamin", "Vitamine"), ("mineral", "Mineralien"),
    ("amino_acid", "Aminosäuren"), ("nootropic", "Nootropika"), ("other", "Sonstiges"),
]

// MARK: - Log a single intake

struct LogSingleSheet: View {
    let supplements: [Supplement]
    let onLog: (Supplement, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selected: Supplement?
    @State private var doseText = ""

    private var filtered: [Supplement] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return supplements }
        return supplements.filter { $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sel = selected {
                    Section("NEM") {
                        HStack {
                            Text(sel.name)
                            Spacer()
                            Button("Ändern") { selected = nil }
                        }
                    }
                    Section("Dosis") {
                        HStack {
                            TextField("Menge", text: $doseText)
                                .keyboardType(.decimalPad)
                            Text(sel.defaultUnit).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        TextField("Suche…", text: $search)
                            .autocorrectionDisabled()
                    }
                    Section {
                        ForEach(filtered) { sup in
                            Button {
                                selected = sup
                                if let d = sup.defaultDose, let v = Double(d) { doseText = fmt(v) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(sup.name).foregroundStyle(.primary)
                                    if let d = sup.defaultDose {
                                        Text("Standard: \(fmt(Double(d) ?? 0)) \(sup.defaultUnit)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Einzeln loggen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Loggen") {
                        if let sel = selected, let dose = Double(doseText) {
                            onLog(sel, dose); dismiss()
                        }
                    }
                    .disabled(selected == nil || Double(doseText) == nil)
                }
            }
        }
    }
}

// MARK: - Create a stack

struct CreateStackSheet: View {
    let supplements: [Supplement]
    let onCreate: (String, [(supplementID: String, dose: Double?, unit: String?)]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var search = ""
    // supplement_id -> dose text
    @State private var chosen: [String: String] = [:]

    private var filtered: [Supplement] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return supplements }
        return supplements.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name (optional)") {
                    TextField("z. B. Morning Stack", text: $name)
                }
                Section("Suche") {
                    TextField("NEM suchen…", text: $search).autocorrectionDisabled()
                }
                Section("NEMs (\(chosen.count) gewählt)") {
                    ForEach(filtered) { sup in
                        let isOn = chosen[sup.id] != nil
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if isOn { chosen[sup.id] = nil }
                                else { chosen[sup.id] = sup.defaultDose.map { fmt(Double($0) ?? 0) } ?? "" }
                            } label: {
                                HStack {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? .green : .secondary)
                                    Text(sup.name).foregroundStyle(.primary)
                                }
                            }
                            if isOn {
                                HStack {
                                    TextField("Dosis", text: Binding(
                                        get: { chosen[sup.id] ?? "" },
                                        set: { chosen[sup.id] = $0 }))
                                        .keyboardType(.decimalPad)
                                        .frame(width: 90)
                                    Text(sup.defaultUnit).foregroundStyle(.secondary)
                                }
                                .padding(.leading, 28)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stack anlegen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        let items = chosen.map { (id, doseStr) -> (supplementID: String, dose: Double?, unit: String?) in
                            let sup = supplements.first { $0.id == id }
                            return (id, Double(doseStr), sup?.defaultUnit)
                        }
                        let finalName = name.trimmingCharacters(in: .whitespaces)
                        onCreate(finalName.isEmpty ? autoName() : finalName, items)
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }

    private func autoName() -> String {
        let names = chosen.keys.compactMap { id in supplements.first { $0.id == id }?.name }
        if names.count <= 2 { return names.joined(separator: " + ") }
        return names.prefix(2).joined(separator: " + ") + " +\(names.count - 2)"
    }
}

// MARK: - Create a custom supplement

struct SupplementDraft {
    var name: String
    var brand: String?
    var category: String
    var defaultDose: Double?
    var defaultUnit: String
    var recommendedDailyDose: Double?
    var notes: String?
}

struct CreateSupplementSheet: View {
    let onCreate: (SupplementDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var category = "other"
    @State private var doseText = ""
    @State private var unit = "mg"
    @State private var dailyText = ""
    @State private var notes = ""

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
                Section("Notizen (optional)") {
                    TextField("Wirkung, Timing…", text: $notes)
                }
            }
            .navigationTitle("Eigene NEM")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        onCreate(SupplementDraft(
                            name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.isEmpty ? nil : brand,
                            category: category,
                            defaultDose: Double(doseText),
                            defaultUnit: unit,
                            recommendedDailyDose: Double(dailyText),
                            notes: notes.isEmpty ? nil : notes))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// Shared number formatter (whole numbers without decimals).
func fmt(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
}
