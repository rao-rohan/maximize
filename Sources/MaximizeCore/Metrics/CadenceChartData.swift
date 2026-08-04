import Foundation

/// Chart-ready presentation of one workout's cadence against the plan's target band
/// (FR-1.3) — everything `CadenceBandView` needs to draw the comparison, precomputed
/// here so CI, not a device, verifies it.
///
/// ## Two numbers, read never recomputed
///
/// This mirrors the discipline `HeartRateChartData` established for MAX-042:
/// `averageStepsPerMinute` is `DerivedMetrics.averageCadenceStepsPerMinute` (D2),
/// computed once at ingestion and passed straight through — this initializer never
/// recomputes it from a sample series. `band` is `Plan.cadenceTarget` (D1) for
/// whichever plan version governs the workout's day, or nil when none does. Neither
/// number is ever derived from the other.
///
/// No in/above/below-band verdict is computed or stored anywhere on this type.
/// `CadenceBand.contains(_:)` already answers "was this run in band" — MAX-012 left
/// that verdict deliberately unstored so a single plan version's opinion never gets
/// frozen into a metric — and this type does not call it either. `CadenceBandView`
/// draws the band and the average from the numbers below and lets their relative
/// position speak for itself; FR-1.3 asks for the comparison, not a judgment.
public struct CadenceChartData: Hashable, Sendable {
    /// `DerivedMetrics.averageCadenceStepsPerMinute`, unchanged. Nil means this run
    /// has no step count at all (MAX-010's "absent, not empty") — never a zero, and
    /// never averaged into anything.
    public let averageStepsPerMinute: Double?

    /// The governing plan's `Plan.cadenceTarget`, unchanged, or nil when no plan
    /// governs the workout's day — there is nothing to draw a band against, not a
    /// fallback constant.
    public let band: CadenceBand?

    /// The x-axis a chart should use: wide enough to hold the band (if any) and the
    /// average (if any) without either sitting flush against the frame edge, padded
    /// so a lone value still has a usable domain to plot in.
    public let axisDomain: ClosedRange<Double>

    /// - Parameters:
    ///   - averageStepsPerMinute: `DerivedMetrics.averageCadenceStepsPerMinute` for
    ///     this workout, passed straight through. This initializer never computes it.
    ///   - band: `Plan.cadenceTarget` for the plan governing this workout's day
    ///     (`PlanCalendar.plan(on:)`), or nil if none does.
    public init(averageStepsPerMinute: Double?, band: CadenceBand?) {
        self.averageStepsPerMinute = averageStepsPerMinute
        self.band = band
        self.axisDomain = Self.axisDomain(averageStepsPerMinute: averageStepsPerMinute, band: band)
    }

    private static func axisDomain(averageStepsPerMinute: Double?, band: CadenceBand?) -> ClosedRange<Double> {
        var lower = band?.lowStepsPerMinute
        var upper = band?.highStepsPerMinute
        if let averageStepsPerMinute {
            lower = Swift.min(lower ?? averageStepsPerMinute, averageStepsPerMinute)
            upper = Swift.max(upper ?? averageStepsPerMinute, averageStepsPerMinute)
        }
        guard let lowerBound = lower, let upperBound = upper, lowerBound < upperBound else {
            // Nothing to plot, a single value, or a degenerate (zero-width) band: give
            // the axis a fixed, sane width around whatever center there is rather than
            // a zero- or negative-width range a chart cannot scale against.
            let center = lower ?? upper ?? 0
            return (center - 10)...(center + 10)
        }
        let pad = Swift.max((upperBound - lowerBound) * 0.25, 2)
        return (lowerBound - pad)...(upperBound + pad)
    }
}
