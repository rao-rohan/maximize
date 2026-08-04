import SwiftUI
import MaximizeCore

extension Color {

    /// The color for an **already-decided** score band.
    ///
    /// Note what this function cannot do: there is no `Color.scoreBand(for: 84)` and
    /// there must never be one. PRD D1 makes the effective threshold versioned plan
    /// data, so only the scorer — reading the plan version in effect on the workout's
    /// date — is entitled to turn a number into a band. A design system that accepted
    /// an `Int` would be quietly re-deciding that, against whatever threshold happened
    /// to be compiled in, and historical scores would change color the first time the
    /// plan did. Band in, color out. That is the whole contract.
    ///
    /// FR-4.3 confines these three saturated colors to **the calendar (D4/FR-3.2) and
    /// the verdict header (FR-1.1)**. They are not a general-purpose status palette;
    /// using them anywhere else dilutes the one signal the product exists to give.
    static func scoreBand(_ band: ScoreBand) -> Color {
        switch band {
        case .effective:
            return .scoreEffective
        case .marginal:
            return .scoreMarginal
        case .ineffective:
            return .scoreIneffective
        }
    }
}

// A calendar day with no band — a planned rest day, a day auto-converted from missed
// under the weekly budget (D9/A6), or a day outside the plan — is not a fourth band
// and deliberately has no entry here. Those are *day states*, decided by the tallies
// layer, and they render as `Color.surfaceInset`: present, but carrying no verdict.
