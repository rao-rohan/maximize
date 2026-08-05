import Foundation

/// The formatters shared by every fact-sheet renderer in `Context/` (CHAT-FIRST-SPEC.md
/// §3.2, PRD-AMENDMENTS.md A12 rule 3).
///
/// `WorkoutFactSheet` was, until MAX-094, the only renderer, and it formatted its own
/// numbers. MAX-095 adds a second — a roll-up over many runs — and the two must not be
/// free to spell the same measurement two ways: `+4.2%` against `4.2 %` is a divergence
/// at the exact boundary D3 exists to close, even though both still live inside "one
/// context module" (D3/A12 §3.2: *"the two fact sheets must render the same measurement
/// identically... enforced mechanically or this claim rots"*). So every renderer calls
/// through here instead of formatting its own numbers, and there is exactly one place a
/// rounding or wording decision can be made — and one place `FactSheetFormattingAgreementTests`
/// can check it was made the same way twice.
///
/// ## Locale pinned to nil, always
///
/// A fact sheet is machine-facing text, not UI: it is read by Claude, not rendered on a
/// screen. `String(format:)` with a `nil` locale forces the POSIX ("C") locale — a point
/// decimal separator, ASCII digits — regardless of the device's region settings.
/// Without that pin, the same stored run would render a different prompt for an athlete
/// whose phone is set to a comma-decimal locale than for one set to a point-decimal
/// locale: what Claude is told about a run would change depending on where the athlete
/// is standing. That is D3's determinism guarantee failing quietly at a boundary nothing
/// else checks, so every formatter here pins locale rather than trusting a caller to.
enum FactSheetFormatting {
    static func number(_ value: Double) -> String {
        String(format: "%.0f", locale: nil, value)
    }

    static func bpm(_ value: Double?) -> String {
        guard let value else { return "not applicable — this workout has no heart-rate data" }
        return "\(number(value)) bpm"
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "not recorded (indoor runs may report none)" }
        return "\(String(format: "%.2f", locale: nil, meters / 1000)) km"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }

    static func pace(_ secondsPerKilometer: Double) -> String {
        let total = Int(secondsPerKilometer.rounded())
        return "\(total / 60):\(String(format: "%02d", locale: nil, total % 60))"
    }

    static func percent(_ fraction: Double) -> String {
        "\(String(format: "%.0f", locale: nil, fraction * 100))%"
    }

    static func signedPercent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: nil, fraction * 100))%"
    }
}
