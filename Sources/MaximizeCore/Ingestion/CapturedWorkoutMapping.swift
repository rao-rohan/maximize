import Foundation

extension ActivityType {
    /// The core activity type for what a capture source reported.
    ///
    /// One rule, and it is here rather than in the HealthKit adapter because it is the
    /// only part of the mapping that is a *judgement* rather than a lookup: an indoor run
    /// is a treadmill run. FR-0.6 makes that distinction first-class — a treadmill run has
    /// no route by nature, not by failure — and getting it wrong is invisible until a
    /// detail view shows an empty map where it should show none at all.
    ///
    /// - Parameters:
    ///   - activityName: the source's activity, already reduced to this module's
    ///     vocabulary by the adapter. Unrecognised names pass through unchanged, because
    ///     `ActivityType` is deliberately open.
    ///   - isIndoor: whether the source flagged the workout as indoor.
    public static func captured(activityName: String, isIndoor: Bool) -> ActivityType {
        let trimmed = activityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .other }

        let reported = ActivityType(rawValue: trimmed)
        if isIndoor, reported == .running { return .treadmillRunning }
        return reported
    }
}

extension WorkoutSource {
    /// The core source for a capture device's product identifier.
    ///
    /// Provenance only — nothing is scored differently because of it — so an unrecognised
    /// device degrades to `.unknown` rather than being treated as an error.
    ///
    /// - Parameter productType: the source's hardware identifier, e.g. `Watch6,1` or
    ///   `iPhone14,2`. Absent when the source did not report one.
    public static func captured(productType: String?) -> WorkoutSource {
        guard let productType, !productType.isEmpty else { return .unknown }

        if productType.hasPrefix("Watch") { return .appleWatch }
        if productType.hasPrefix("iPhone") { return .iPhone }
        return .unknown
    }
}
