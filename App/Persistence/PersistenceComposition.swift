import Foundation
import MaximizeCore
import OSLog
import SwiftData

/// Logger for opening the on-device store.
///
/// At file scope and its own category, mirroring `ingestionLog`. **No health data goes
/// through it**, and the one call site below is careful about how: see the note there.
private let persistenceLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Maximize",
    category: "persistence"
)

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
    /// **MAX-154 replaced a `try?` here.** The optional was right and stays; what was
    /// wrong was that the *reason* went nowhere. This is the single most consequential
    /// failure in the app — every screen degrades to "could not be loaded", ingestion
    /// falls back to the anchor-pinning sink, and nothing is written anywhere — and
    /// until this ticket the only trace of it was those symptoms. There is no way to
    /// tell a disk-full from a schema problem by looking at a phone, and R2 means
    /// nobody can attach a debugger to a background launch to find out.
    ///
    /// The two-field split is `IngestionComposition`'s rule, applied for the same
    /// reason: `domain` and `code` are a bounded pair of scalars the system chose, so
    /// they are `.public` and survive into a sysdiagnose, which is where someone
    /// diagnosing this will actually read them. The `Error` itself is arbitrary — a
    /// Core Data error's `userInfo` can carry `NSValidationErrorObject`, i.e. stored row
    /// values, which is health data in a log and forbidden without qualification — so it
    /// is `.private`, still visible in full to a debugger attached in Xcode.
    static let modelContainer: ModelContainer? = { () -> ModelContainer? in
        do {
            return try MaximizeModelContainer.makeOnDisk()
        } catch {
            let nsError = error as NSError
            persistenceLog.error(
                "The on-device store could not be opened (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)). Every screen will report that it could not load, and nothing will be written until it opens."
            )
            persistenceLog.error("Underlying error: \(String(describing: error), privacy: .private)")
            return nil
        }
    }()

    /// One store, backing every repository protocol `MaximizeStore` implements
    /// (`WorkoutRepository`, `ScoreRepository`, `PlanRepository`, …). Callers ask for
    /// it as whichever protocol they need; nothing here should ever hand out the
    /// concrete type.
    static let store: MaximizeStore? = modelContainer.map { MaximizeStore(modelContainer: $0) }
}
