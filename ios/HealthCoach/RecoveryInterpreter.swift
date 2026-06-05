import Foundation
import SwiftUI

/// Rule-based interpretation of WHOOP recovery into a short, actionable text.
/// Thresholds: recovery red <33, yellow 33–66, green >66.
struct RecoveryInterpretation {
    let headline: String          // e.g. "Recovery 56% (medium)"
    let detail: String            // metric breakdown
    let recommendation: String    // what to do today
    let mainLimit: String?        // biggest limiter, if any
    let color: Color

    static func make(recovery: RecoveryDay?, sleepMinutes: Double?) -> RecoveryInterpretation? {
        guard let r = recovery, let score = r.recoveryScore else { return nil }

        let band: String
        let color: Color
        switch score {
        case ..<33: band = "niedrig"; color = Theme.danger
        case ..<67: band = "medium"; color = Theme.warn
        default: band = "hoch"; color = Theme.good
        }

        // Per-metric notes
        var parts: [String] = []
        var limits: [(String, Double)] = []   // (label, severity 0..1)

        if let hrv = r.avgHrvSdnnMs {
            let note = hrv >= 80 ? "gut" : (hrv >= 50 ? "ok" : "niedrig")
            parts.append("HRV \(Int(hrv)) ms (\(note))")
            if hrv < 50 { limits.append(("niedrige HRV", 0.7)) }
        }
        if let rhr = r.restingHeartRateBpm {
            let note = rhr <= 55 ? "exzellent" : (rhr <= 65 ? "gut" : "erhöht")
            parts.append("Ruhepuls \(Int(rhr)) bpm (\(note))")
            if rhr > 65 { limits.append(("erhöhter Ruhepuls", 0.6)) }
        }
        if let sm = sleepMinutes {
            let h = Int(sm) / 60, m = Int(sm) % 60
            let note = sm >= 420 ? "gut" : (sm >= 360 ? "knapp" : "Defizit")
            parts.append("Schlaf \(h):\(String(format: "%02d", m)) h (\(note))")
            if sm < 390 { limits.append(("Schlafmangel", (390 - sm) / 390)) }
        }

        // Recommendation by band
        let rec: String
        switch score {
        case ..<33: rec = "Heute Deload oder Ruhe. Falls Training: nur leicht, RPE-Cap 6–7."
        case ..<67: rec = "Training durchführbar, RPE-Cap bei 8 statt 9."
        default: rec = "Volle Belastung möglich — heute kannst du Vollgas geben."
        }

        let main = limits.max { $0.1 < $1.1 }?.0

        return RecoveryInterpretation(
            headline: "Recovery \(Int(score))% (\(band))",
            detail: parts.joined(separator: ", "),
            recommendation: rec,
            mainLimit: main,
            color: color
        )
    }
}
