import SwiftUI

/// App design system — a dark, data-dense health aesthetic with its own
/// identity (not a clone of any existing app). Rings + charts + cards.
enum Theme {
    // Backgrounds
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.08)        // near-black navy
    static let card = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let cardElevated = Color(red: 0.14, green: 0.15, blue: 0.19)

    // Text
    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.62)

    // Accent ramp (recovery/readiness): red → amber → teal → green
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.36)
    static let warn = Color(red: 0.98, green: 0.70, blue: 0.20)
    static let teal = Color(red: 0.20, green: 0.82, blue: 0.78)
    static let good = Color(red: 0.30, green: 0.86, blue: 0.55)
    static let accent = Color(red: 0.40, green: 0.55, blue: 1.0)     // electric blue
    static let violet = Color(red: 0.62, green: 0.45, blue: 0.98)

    /// Colour for a 0–100 score (recovery-style ramp).
    static func scoreColor(_ pct: Double) -> Color {
        switch pct {
        case ..<34: return danger
        case ..<50: return warn
        case ..<67: return teal
        default: return good
        }
    }
}

/// A circular progress ring with a centred value + label. The core visual
/// building block of the dashboard.
struct MetricRing: View {
    let value: Double          // 0...1 fill
    let displayValue: String   // big centre text, e.g. "56" or "7:42"
    let unit: String?          // small text under the value, e.g. "%"
    let label: String          // caption under the ring
    let color: Color
    var size: CGFloat = 110
    var lineWidth: CGFloat = 11

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.cardElevated, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, min(value, 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.6), color]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: value)
                VStack(spacing: 0) {
                    Text(displayValue)
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if let unit {
                        Text(unit).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// A titled card container for grouping content on the dark background.
struct DashCard<Content: View>: View {
    let title: String?
    var systemImage: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.caption).foregroundStyle(Theme.accent)
                    }
                    Text(title.uppercased())
                        .font(.caption).fontWeight(.semibold)
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A small stat shown as a coloured pill (for secondary metrics).
struct StatChip: View {
    let value: String
    let label: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}
