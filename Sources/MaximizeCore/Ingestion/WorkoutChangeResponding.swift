/// "Something told us new workouts may exist."
///
/// This is the boundary between the platform and the decisions. The HealthKit adapter
/// in the app layer knows how to be woken; it does not know what being woken *means*,
/// how long the response may take, or when the platform is allowed to consider the
/// delivery handled. All of that lives behind this protocol, in
/// `WorkoutObservationCoordinator`, where a fake can drive it without a Health store —
/// see CLAUDE.md, "thin shell, fat core".
///
/// Nothing here is HealthKit-shaped on purpose. The signal is "workouts may have
/// changed" and the response is "tell the caller when we are done", which is a claim
/// about background wakes in general, not about `HKObserverQuery` in particular.
public protocol WorkoutChangeResponding: Sendable {
    /// Responds to a report that the health store may contain workouts we have not
    /// ingested.
    ///
    /// - Parameters:
    ///   - observationError: an error the observation mechanism reported alongside the
    ///     wake, if any. Passed through rather than handled at the call site because
    ///     "what does an errored wake mean" is a decision, and decisions belong on
    ///     this side of the boundary.
    ///   - acknowledge: the platform's completion handler. Implementations **must**
    ///     invoke it exactly once, on every path including failure — see
    ///     `BackgroundDeliveryAcknowledgement` for what happens if they do not.
    func workoutsMayHaveChanged(
        observationError: Error?,
        acknowledge: @escaping @Sendable () -> Void
    ) async
}

extension WorkoutChangeResponding {
    /// Convenience for callers with no error to report.
    public func workoutsMayHaveChanged(
        acknowledge: @escaping @Sendable () -> Void
    ) async {
        await workoutsMayHaveChanged(observationError: nil, acknowledge: acknowledge)
    }
}
