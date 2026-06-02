import SwiftUI

struct SettingsView: View {
    @Binding var hasKey: Bool
    @State private var keyInput: String = Keychain.get(account: AppConfig.apiKeyKeychainAccount) ?? ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        Form {
            Section("Backend") {
                    LabeledContent("URL", value: AppConfig.baseURL.absoluteString)
                    LabeledContent("User", value: String(AppConfig.userID.prefix(8)) + "…")
                }

                Section("API-Key") {
                    SecureField("sk-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Speichern") {
                        Keychain.set(keyInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                     account: AppConfig.apiKeyKeychainAccount)
                        hasKey = !keyInput.isEmpty
                        status = "Gespeichert."
                    }
                }

                Section("Verbindung") {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Verbindung testen")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
        }
        .navigationTitle("Einstellungen")
    }

    private func testConnection() async {
        checking = true
        defer { checking = false }
        do {
            if let user = try await APIClient.shared.currentUser() {
                status = "✅ Verbunden als \(user.firstName ?? "User")."
            } else {
                status = "Verbunden, aber kein User gefunden."
            }
        } catch {
            status = "❌ " + (error.localizedDescription)
        }
    }
}
