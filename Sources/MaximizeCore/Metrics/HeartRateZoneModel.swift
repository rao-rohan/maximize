import Foundation

/// Where one heart-rate zone ends and the next begins (§9, "time in each zone relative
/// to the plan's **cap-anchored** zones").
///
/// The boundaries are values, not literals in the splitting code, for the D1 reason:
/// a zone edge written into a function is a threshold that cannot be versioned, and a
/// historical zone split would silently re-interpret itself the day someone edited it.
/// `HeartRateZone` carries the label; this carries the numbers.
///
/// **Known gap, stated plainly:** `Plan` (MAX-010) carries an HR cap but no zone
/// boundaries, so the boundaries cannot yet be read from the plan record the way the
/// cap and the cadence band are. `capAnchored(heartRateCapBPM:)` derives them from the
/// plan's cap, which is what §9 asks for ("cap-anchored") and keeps the cap as the
/// single versioned knob — but the *ratios* below are a modelling choice living in
/// code. The honest fix is a `zoneBoundaries` field on a future plan version, at which
/// point this type is constructed from that data instead. Every caller already takes
/// the model as a parameter, so that change is additive.
public struct HeartRateZoneModel: Hashable, Sendable, Codable {
    /// **Inclusive** upper bounds in bpm for zones 1…4, strictly ascending. Zone 5 is
    /// unbounded above, so there are one fewer bounds than zones.
    ///
    /// Inclusive-upper matters at the cap: with the cap-anchored ratios below, zone 2's
    /// upper bound *is* the cap, so a beat exactly at the cap counts as zone 2 (easy) —
    /// the same reading as time-above-cap, which counts only HR strictly greater than
    /// the cap (§9). Two metrics disagreeing about the boundary case is exactly the
    /// kind of quiet inconsistency D2 exists to prevent.
    public let upperBoundsBPM: [Double]

    static var boundaryCount: Int { HeartRateZone.allCases.count - 1 }

    public init(upperBoundsBPM: [Double]) throws {
        guard upperBoundsBPM.count == HeartRateZoneModel.boundaryCount else {
            throw DomainError.inconsistent(
                reason: "HeartRateZoneModel.upperBoundsBPM needs exactly "
                    + "\(HeartRateZoneModel.boundaryCount) bounds for "
                    + "\(HeartRateZone.allCases.count) zones, got \(upperBoundsBPM.count)"
            )
        }
        for bound in upperBoundsBPM {
            try Validate.positive(bound, "HeartRateZoneModel.upperBoundsBPM")
        }
        for index in 1..<upperBoundsBPM.count where upperBoundsBPM[index] <= upperBoundsBPM[index - 1] {
            throw DomainError.outOfOrder(field: "HeartRateZoneModel.upperBoundsBPM", index: index)
        }
        self.upperBoundsBPM = upperBoundsBPM
    }

    /// Multipliers on the plan's HR cap giving the inclusive upper bound of zones 1…4.
    ///
    /// The cap is the ceiling of easy running (FR-1.2), which places it at the top of
    /// the aerobic zone — hence exactly `1.0` for zone 2. Below that, a recovery zone at
    /// 90% of the cap; above it, work that is by definition no longer easy: tempo to
    /// ~8% over the cap, threshold to ~16% over, and anything beyond is zone 5.
    public static let capAnchoredMultipliers: [Double] = [0.90, 1.00, 1.08, 1.16]

    /// The zones implied by a plan's cap. With a 150 bpm cap: ≤135, ≤150, ≤162, ≤174,
    /// then above.
    public static func capAnchored(heartRateCapBPM: Double) throws -> HeartRateZoneModel {
        try HeartRateZoneModel(
            upperBoundsBPM: capAnchoredMultipliers.map { $0 * heartRateCapBPM }
        )
    }

    /// The zone a single instantaneous heart rate falls in. Total: every bpm has a zone.
    public func zone(for beatsPerMinute: Double) -> HeartRateZone {
        for (index, bound) in upperBoundsBPM.enumerated() where beatsPerMinute <= bound {
            if let zone = HeartRateZone(rawValue: index + 1) {
                return zone
            }
        }
        return .five
    }

    private enum CodingKeys: String, CodingKey {
        case upperBoundsBPM
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(upperBoundsBPM: container.decode([Double].self, forKey: .upperBoundsBPM))
    }
}
