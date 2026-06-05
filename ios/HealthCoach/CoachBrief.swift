import Foundation
import SwiftUI

/// Caches the proactive coach briefings so Claude is called at most once per day
/// (morning) / per week (weekly) — explicit refresh aside. Token cost stays low.
@MainActor
final class CoachBriefStore: ObservableObject {
    @Published var morningHeadline: String?
    @Published var morningBody: String?
    @Published var weeklyHeadline: String?
    @Published var weeklyBody: String?
    @Published var loadingMorning = false
    @Published var loadingWeekly = false
    @Published var error: String?

    private let ud = UserDefaults.standard

    init() {
        let d = Self.dayKey()
        morningHeadline = ud.string(forKey: "brief_m_head_\(d)")
        morningBody = ud.string(forKey: "brief_m_body_\(d)")
        let w = Self.weekKey()
        weeklyHeadline = ud.string(forKey: "brief_w_head_\(w)")
        weeklyBody = ud.string(forKey: "brief_w_body_\(w)")
    }

    /// Ensure today's morning brief exists; only calls the API when missing or
    /// forced. `context` is assembled by the caller (it has the live metrics).
    func ensureMorning(context: String, force: Bool = false) async {
        if !force, morningBody != nil { return }
        loadingMorning = true; error = nil
        defer { loadingMorning = false }
        do {
            let r = try await APIClient.shared.coachBrief(kind: "morning", clientContext: context)
            morningHeadline = r.headline; morningBody = r.body
            let d = Self.dayKey()
            ud.set(r.headline, forKey: "brief_m_head_\(d)")
            ud.set(r.body, forKey: "brief_m_body_\(d)")
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadWeekly(context: String, force: Bool = false) async {
        if !force, weeklyBody != nil { return }
        loadingWeekly = true; error = nil
        defer { loadingWeekly = false }
        do {
            let r = try await APIClient.shared.coachBrief(kind: "weekly", clientContext: context)
            weeklyHeadline = r.headline; weeklyBody = r.body
            let w = Self.weekKey()
            ud.set(r.headline, forKey: "brief_w_head_\(w)")
            ud.set(r.body, forKey: "brief_w_body_\(w)")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func dayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private static func weekKey() -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }
}

/// The weekly review, shown on demand. Generated once per week (cached), with a
/// manual regenerate. Reuses the same brief endpoint with kind="weekly".
struct WeeklyReviewSheet: View {
    @ObservedObject var brief: CoachBriefStore
    let context: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if brief.loadingWeekly && brief.weeklyBody == nil {
                        HStack(spacing: 8) {
                            ProgressView().tint(Theme.accent)
                            Text("Wochenreview wird erstellt…").foregroundStyle(Theme.textSecondary)
                        }.padding(.top, 24)
                    } else if let head = brief.weeklyHeadline {
                        DashCard(title: "Wochenreview", systemImage: "calendar") {
                            Text(head).font(.headline).foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let body = brief.weeklyBody { BriefMarkdown(text: body) }
                        }
                    } else {
                        Text(brief.error ?? "Noch kein Review.")
                            .foregroundStyle(brief.error == nil ? Theme.textSecondary : Theme.danger)
                            .padding(.top, 24)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Woche").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await brief.loadWeekly(context: context, force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await brief.loadWeekly(context: context) }
        }
        .preferredColorScheme(.dark)
    }
}

/// Minimal block-level markdown for briefings: SwiftUI `Text` only renders
/// inline markdown (bold/italic), so render line-by-line and indent bullets.
struct BriefMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
    }

    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.allSatisfy { c in c == "-" || c == "*" || c == "_" } && $0.count >= 3) }
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
                Text(md(String(line.dropFirst(2))))
                    .font(.subheadline).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if line.hasPrefix("#") {
            Text(md(line.drop(while: { $0 == "#" || $0 == " " }).description))
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
        } else {
            Text(md(line))
                .font(.subheadline).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
