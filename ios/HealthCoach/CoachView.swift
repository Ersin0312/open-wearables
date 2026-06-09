import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" | "assistant"
    let content: String
}

@MainActor
final class CoachViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var sending = false
    @Published var enabled: Bool?       // nil = unknown/checking
    @Published var error: String?

    func checkStatus() async {
        do { enabled = try await APIClient.shared.coachEnabled() }
        catch let e { enabled = false; error = e.localizedDescription }
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        messages.append(ChatMessage(role: "user", content: text))
        sending = true
        defer { sending = false }
        do {
            let history = messages.dropLast().map { (role: $0.role, content: $0.content) }
            let reply = try await APIClient.shared.coachChat(message: text, history: Array(history))
            messages.append(ChatMessage(role: "assistant", content: reply))
        } catch {
            messages.append(ChatMessage(role: "assistant", content: "⚠️ \(error.localizedDescription)"))
        }
    }

    func suggestPlan() {
        input = "Erstelle mir auf Basis meiner aktuellen Daten einen anpassbaren Tagesplan für heute (Ernährung, Flüssigkeit, NEMs, Recovery, Training)."
    }

    /// One-tap holistic review: send a thorough check across all logged data.
    func reviewEverything() async {
        input = """
        Mach bitte einen Gesamt-Check und geh einmal komplett durch ALLE meine \
        Daten der letzten 7 Tage: Training (Volumen, Frequenz, Progression), \
        Ernährung (kcal/Protein pro Tag), Supplements, Wasser, Schritte (Ziel \
        10.000/Tag), Recovery, Schlaf und meine Körperwerte. Prüfe sie auf \
        Konsistenz, Lücken und Plausibilität: Wo logge ich unvollständig, wo \
        passt etwas nicht zusammen, und liege ich auf Kurs zum Phasenziel? Nenne \
        mir am Ende die drei wichtigsten Stellschrauben. Antworte in \
        vollständigen, zusammenhängenden Sätzen.
        """
        await send()
    }
}

struct CoachView: View {
    @StateObject private var vm = CoachViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.enabled == false {
                    notConfigured
                } else {
                    chatScroll
                    inputBar
                }
            }
            .navigationTitle("Coach")
            .task { if vm.enabled == nil { await vm.checkStatus() } }
        }
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Der Wissenschaftler")
                                .font(.headline)
                            Text("Datengetriebener Coach. Fragt deine Trainings-, Supplement- und Körperdaten ab und baut dir einen anpassbaren Tagesplan.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button {
                                vm.suggestPlan()
                            } label: {
                                Label("Tagesplan vorschlagen", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                            Button {
                                Task { await vm.reviewEverything() }
                            } label: {
                                Label("Gesamt-Check (alle Daten prüfen)", systemImage: "checklist.checked")
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.sending)
                        }
                        .padding()
                    }
                    ForEach(vm.messages) { msg in
                        bubble(msg).id(msg.id)
                    }
                    if vm.sending {
                        HStack { ProgressView(); Text("Der Coach denkt…").foregroundStyle(.secondary) }
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages) { _, msgs in
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == "user" { Spacer(minLength: 40) }
            Text(msg.content)
                .padding(10)
                .background(msg.role == "user" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if msg.role == "assistant" { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Frag den Coach…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task { await vm.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty || vm.sending)
        }
        .padding(8)
    }

    private var notConfigured: some View {
        ContentUnavailableView {
            Label("Coach nicht aktiv", systemImage: "brain.head.profile")
        } description: {
            Text("Der In-App-Coach braucht einen Anthropic-API-Key im Backend (backend/config/.env → ANTHROPIC_API_KEY). Danach Backend neu starten.")
        }
    }
}
