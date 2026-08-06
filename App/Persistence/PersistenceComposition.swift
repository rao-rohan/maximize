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

/// One attempt at opening the store, and everything that follows from it.
///
/// Bundled rather than kept as three independent values because they must not be able to
/// disagree: a non-nil `store` alongside a `.couldNotOpen` availability would put the app
/// behind a failure screen with a perfectly good store sitting behind it.
///
/// At file scope, outside `PersistenceComposition`, so that `openStore(from:)` below is
/// plain non-isolated code — the store is opened from a static property's initialiser, and
/// a main-actor-isolated function is the one thing that cannot be called from there.
private struct StoreOpenAttempt {
    let container: ModelContainer?
    let store: MaximizeStore?
    let availability: StoreAvailability
}

/// Opens the store once and reports what happened.
///
/// - Parameter previous: the availability being retried from, or nil for the launch's
///   first attempt. The core decides which state follows; this function only says which
///   of the two questions it is asking.
private func openStore(from previous: StoreAvailability?) -> StoreOpenAttempt {
    func resolve(_ outcome: StoreOpenOutcome) -> StoreAvailability {
        guard let previous else { return .afterFirstAttempt(outcome) }
        return previous.afterTryingAgain(outcome)
    }

    do {
        let container = try MaximizeModelContainer.makeOnDisk()
        return StoreOpenAttempt(
            container: container,
            store: MaximizeStore(modelContainer: container),
            availability: resolve(.opened)
        )
    } catch {
        let nsError = error as NSError
        let reason = StoreOpenFailureReason.classifying(
            errorDomain: nsError.domain,
            errorCode: nsError.code
        )

        // The split between what is published and what is not is `IngestionComposition`'s
        // rule, applied for the same reason: `domain`, `code`, and now the reason derived
        // from the two, are a bounded set of scalars the system chose, so they are
        // `.public` and survive into a sysdiagnose — which is where someone diagnosing
        // this will actually read them. The `Error` itself is arbitrary: a Core Data
        // error's `userInfo` can carry `NSValidationErrorObject`, i.e. stored row values,
        // which is health data in a log and forbidden without qualification (CLAUDE.md).
        // So it stays `.private`, still visible in full to a debugger attached in Xcode.
        persistenceLog.error(
            "The on-device store could not be opened (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public), read as \(String(describing: reason), privacy: .public)). The app is showing its store notice instead of its tabs, and nothing will be written until it opens."
        )
        persistenceLog.error("Underlying error: \(String(describing: error), privacy: .private)")

        return StoreOpenAttempt(
            container: nil,
            store: nil,
            availability: resolve(.couldNotOpen(reason))
        )
    }
}

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
///
/// **MAX-154 replaced a `try?` here.** The optional was right and stays; what was wrong
/// was that the *reason* went nowhere. This is the single most consequential failure in
/// the app — every screen degrades to "could not be loaded", ingestion falls back to the
/// anchor-pinning sink, and nothing is written anywhere — and until that ticket the only
/// trace of it was those symptoms. There is no way to tell a disk-full from a schema
/// problem by looking at a phone, and R2 means nobody can attach a debugger to a
/// background launch to find out.
///
/// **MAX-169 gave the failure a state, a sentence and a second chance.** `availability`
/// is the one fact the app root branches on, and `tryOpeningAgain()` is the only thing in
/// the app that may attempt the open twice. Every decision either of them expresses — what
/// the athlete is told, whether trying again is offered at all, what a successful retry
/// does and does not restore — lives in `MaximizeCore.StoreAvailability`, where it is
/// tested. What is left here is calling SwiftData and reporting what came back.
@MainActor
enum PersistenceComposition {

    /// The launch's first attempt, made once and lazily — the same semantics as the
    /// `static let` this replaces, so nothing about *when* the store is first opened has
    /// changed.
    private static let firstAttempt = openStore(from: nil)

    /// A later attempt, once the athlete has pressed **Try again**. Nil until then.
    private static var laterAttempt: StoreOpenAttempt?

    private static var current: StoreOpenAttempt { laterAttempt ?? firstAttempt }

    static var modelContainer: ModelContainer? { current.container }

    /// One store, backing every repository protocol `MaximizeStore` implements
    /// (`WorkoutRepository`, `ScoreRepository`, `PlanRepository`, …). Callers ask for
    /// it as whichever protocol they need; nothing here should ever hand out the
    /// concrete type.
    ///
    /// **Read this where it is used, not at init, if the reader outlives the app's first
    /// screen.** A retry can turn this from nil into a store, and anything that captured
    /// the nil at construction keeps it for the life of the process. Screens are built
    /// only after the notice is dismissed, so they cannot capture it early;
    /// `SettingsModel.shared` is constructed by the app root before the athlete has
    /// pressed anything, and resolves this lazily for exactly that reason.
    static var store: MaximizeStore? { current.store }

    /// What the app can honestly say about whether it has a store. The app root branches
    /// on this and on nothing else.
    static var availability: StoreAvailability { current.availability }

    /// Attempts the open again, for the one screen that offers it.
    ///
    /// A no-op when the store is already open, and that guard is not housekeeping: a
    /// second `ModelContainer` over the same SQLite file is two SwiftData stacks writing
    /// one store, the arrangement `IngestionComposition` refuses for the background wake.
    /// `StoreAvailability.afterTryingAgain(_:)` states the same rule in the core, where it
    /// is tested; this is the half that must not build the container.
    ///
    /// Synchronous and on the main actor, like the launch-time open it repeats. An
    /// inferred migration over a long history can take a moment, so this can hold a frame
    /// — the same cost the launch path already pays every time, and moving it off the
    /// actor everything below it is isolated to would buy a spinner at the price of a
    /// second concurrency story for the store.
    @discardableResult
    static func tryOpeningAgain() -> StoreAvailability {
        guard case .couldNotOpen = current.availability else { return current.availability }
        let attempt = openStore(from: current.availability)
        laterAttempt = attempt
        return attempt.availability
    }
}
