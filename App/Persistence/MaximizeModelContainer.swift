import Foundation
import MaximizeCore
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// ## File protection
///
/// The store holds workouts, heart-rate curves and GPS tracks. CLAUDE.md treats all of
/// it as PII and says to rely on iOS file protection, so the class is chosen here rather
/// than inherited by accident.
///
/// **`.completeUntilFirstUserAuthentication`, deliberately, and not `.complete`.**
///
/// The strongest class, `.complete`, makes a file unreadable whenever the device is
/// locked. That is wrong for this app specifically, and the reason is the same one
/// MAX-030 flagged for the anchor file: HealthKit wakes the app in the background to
/// deliver a new workout, and that wake can land while the phone is locked in a pocket
/// immediately after a run — which is the *normal* case for this product, not an edge
/// case. With `.complete`, the write would fail, the sink would throw, and the anchor
/// would stay pinned; nothing would be lost (the ingester is built for exactly that),
/// but zero-touch capture would stall until the athlete next unlocked the phone, and
/// the product's whole claim is that they never have to think about it.
///
/// `.completeUntilFirstUserAuthentication` keeps the store encrypted at rest before the
/// device has been unlocked once since boot, and readable thereafter — including while
/// locked. That is the same trade `FileWorkoutQueryAnchorStore` already makes, and
/// keeping the two consistent matters: a pipeline where the anchor is readable during a
/// wake but the workout store is not would fail in a way that looks like a HealthKit
/// bug.
///
/// It is also iOS's default class for app files. It is set explicitly anyway, because a
/// default is a thing that can change out from under a decision, and this one is
/// load-bearing enough to write down.
///
/// **Not verified by CI.** No line in this file has ever executed — there is no
/// simulator or device in this pipeline (tracker R2). See the PR for what a human should
/// check.
enum MaximizeModelContainer {
    /// Where the store lives. Application Support rather than Documents: this is app
    /// state, not user-visible content, and it should not appear in Files.
    static let storeDirectoryName = "Store"
    static let storeFileName = "Maximize.store"

    /// The protection class applied to the store and its sidecar files.
    static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// The on-disk container the app runs against.
    ///
    /// - Parameter cloudKitDatabase: `.none` today. MAX-021 owns turning mirroring on,
    ///   which also needs the iCloud capability and a container identifier in
    ///   `project.yml`. The *schema* is already built to CloudKit's restrictions — no
    ///   unique constraints, no relationships, defaults on every non-optional property —
    ///   so that ticket should be configuration rather than a redesign.
    static func makeOnDisk(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
    ) throws -> ModelContainer {
        let url = try prepareStoreURL()
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: MaximizeSchemaV1.self),
            url: url,
            cloudKitDatabase: cloudKitDatabase
        )
        let container = try ModelContainer(
            for: Schema(versionedSchema: MaximizeSchemaV1.self),
            migrationPlan: MaximizeMigrationPlan.self,
            configurations: configuration
        )
        // Applied after creation as well as before: SQLite's write-ahead log and shared
        // memory files are created by the store, not by us, and they hold the same data
        // as the store itself. Protecting only the main file would leave recent writes —
        // the most recent run — in a less protected sidecar.
        applyFileProtection(around: url)
        return container
    }

    /// An in-memory container, for previews and for anything that wants a store without
    /// touching the athlete's real history.
    static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: MaximizeSchemaV1.self),
            migrationPlan: MaximizeMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static func prepareStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(storeDirectoryName, isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: fileProtection]
        )
        return directory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    /// Sets the protection class on the store and the two sidecar files SQLite keeps
    /// beside it.
    ///
    /// Failures are swallowed on purpose. A file that does not exist yet is the normal
    /// case on first launch, and refusing to start the app because a protection
    /// attribute could not be set on a not-yet-created write-ahead log would trade a
    /// working app for no app. The directory attribute set in `prepareStoreURL` is the
    /// belt to this pair of braces.
    private static func applyFileProtection(around storeURL: URL) {
        let fileManager = FileManager.default
        let paths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm",
        ]
        for path in paths where fileManager.fileExists(atPath: path) {
            try? fileManager.setAttributes([.protectionKey: fileProtection], ofItemAtPath: path)
        }
    }
}
