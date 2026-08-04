import Foundation

/// A position in the health store's change history, as an opaque blob.
///
/// The core never looks inside this. On the device it is an archived `HKQueryAnchor`
/// (`NSSecureCoding`), but nothing here knows or cares — `MaximizeCore` must not import
/// HealthKit (CLAUDE.md), and more usefully, "the anchor is opaque" is exactly the
/// property that lets the anchor-advancement rules be tested without a health store.
///
/// Equatable so the ingester can tell "the fetch moved us forward" from "the fetch
/// returned the same position again", which is its loop-termination guard.
public struct WorkoutQueryAnchor: Hashable, Sendable {
    /// The archived platform anchor. Meaningless to every type in this module except as
    /// a value to hand back to the fetcher unchanged.
    public let opaqueData: Data

    public init(opaqueData: Data) {
        self.opaqueData = opaqueData
    }
}

/// Durable storage for the anchor, across launches and across the app being killed
/// between background wakes.
///
/// This protocol is the whole of FR-0.2's "persisted anchor". It is deliberately tiny
/// and free of any storage vocabulary: MAX-020's SwiftData store does not exist yet,
/// and when it does, the ingester should not have to change to adopt it.
///
/// ## What implementations owe the caller
///
/// - `save` must be **durable on return**. The ingester treats a returned `save` as the
///   point after which the batch will never be delivered again, so an implementation
///   that buffers in memory and flushes later converts a crash into permanent silent
///   data loss. Write through.
/// - `load` returning `nil` means "nothing has ever been stored", and the ingester
///   reads that as a first run. Throwing means "something is stored but could not be
///   read", which the ingester treats as a first run *as well* — see
///   `AnchoredWorkoutIngester` for why failing open is the only safe direction here.
public protocol WorkoutQueryAnchorStore: Sendable {
    /// The last durably recorded position, or `nil` if there has never been one.
    func loadAnchor() async throws -> WorkoutQueryAnchor?

    /// Records a new position. Must not return until the value would survive a crash.
    func saveAnchor(_ anchor: WorkoutQueryAnchor) async throws

    /// Forgets the stored position, so the next fetch starts from scratch. Used only on
    /// the recovery path for an anchor the platform refuses to accept.
    func clearAnchor() async throws
}
