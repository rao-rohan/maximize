import Foundation
import MaximizeCore
import SwiftData

/// Composition root for the on-device store (MAX-020), in the same shape as
/// `IngestionComposition`: assembled once, so every screen that needs to read a
/// workout — starting with this ticket's list and detail view — shares one container
/// and one store rather than each deciding how to open SwiftData for itself.
///
/// **`store` is optional, deliberately.** `MaximizeModelContainer.makeOnDisk()` has
/// never executed anywhere in this pipeline (tracker R2 — no simulator or device in
/// CI), so its first real run is on a phone, and nothing here has watched it succeed.
/// A view that force-unwrapped this would turn "the store failed to open" (disk full,
/// a migration problem) into a crash on launch; carrying the optional through lets a
/// screen show "could not load" instead, the same honest-degrade shape
/// `MaximizeModelContainer` itself uses for file-protection attributes it cannot
/// guarantee.
@MainActor
enum PersistenceComposition {
    static let modelContainer: ModelContainer? = try? MaximizeModelContainer.makeOnDisk()

    /// One store, backing every repository protocol `MaximizeStore` implements
    /// (`WorkoutRepository`, `ScoreRepository`, `PlanRepository`, …). Callers ask for
    /// it as whichever protocol they need; nothing here should ever hand out the
    /// concrete type.
    static let store: MaximizeStore? = modelContainer.map { MaximizeStore(modelContainer: $0) }
}
