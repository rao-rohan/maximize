import Foundation
import MaximizeCore

/// FR-0.2's "persisted anchor", as one small file in Application Support.
///
/// ## Why a file
///
/// MAX-020's SwiftData store does not exist yet, and making the ingestion pipeline wait
/// for it would be the wrong dependency anyway. Of what is available today:
///
/// - **A file** is atomically replaceable, is deleted when the app is, and — with
///   `.completeFileProtectionUntilFirstUserAuthentication` — is readable during a
///   background wake, which is the only situation this store is read in.
/// - **`UserDefaults`** writes back on its own schedule. "The anchor is durable when
///   `save` returns" is the single assumption the whole anchor-last ordering rests on,
///   and `UserDefaults` does not promise it.
/// - **Keychain** is for secrets; an opaque cursor is not one. Worse, Keychain items
///   outlive app deletion, so a reinstall would resume from an anchor pointing past
///   workouts the fresh install never ingested — silent loss, by construction.
/// - **SwiftData, later.** Nothing here prevents it: `WorkoutQueryAnchorStore` is the
///   seam, and moving the anchor into the same transaction as the workout write would be
///   a real improvement (it would make "workout stored" and "anchor advanced" atomic).
///   That belongs with MAX-033, which owns the store.
///
/// ## Durability, honestly
///
/// `Data.write(options: .atomic)` writes a temporary file and renames it, so a reader
/// never sees a half-written anchor. It does not force the write to stable storage, so a
/// power loss in the wrong microsecond can still lose the most recent anchor. That
/// failure lands on the safe side of the pipeline's ordering: an anchor lost is a batch
/// re-delivered, and re-delivery is deduped on `workoutUUID` (FR-0.5). An anchor written
/// *early* would be the unrecoverable direction, and this store never does that — it only
/// ever writes when `AnchoredWorkoutIngester` says the batch is already handled.
///
/// Nothing health-related is stored here. The anchor is an opaque platform cursor with no
/// workout content in it, which is why it can live outside the encrypted store without
/// touching CLAUDE.md's PII rules.
final class FileWorkoutQueryAnchorStore: WorkoutQueryAnchorStore, @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryName: String
    private let fileName: String

    init(
        fileManager: FileManager = .default,
        directoryName: String = "Ingestion",
        fileName: String = "workout-query-anchor.archive"
    ) {
        self.fileManager = fileManager
        self.directoryName = directoryName
        self.fileName = fileName
    }

    func loadAnchor() async throws -> WorkoutQueryAnchor? {
        let url = try anchorFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        // A zero-byte file is a half-completed write, not a stored position. Reporting it
        // as "nothing stored" starts a first-run fetch, which the dedupe absorbs; handing
        // an empty blob to the platform would just fail one step later.
        guard !data.isEmpty else { return nil }
        return WorkoutQueryAnchor(opaqueData: data)
    }

    func saveAnchor(_ anchor: WorkoutQueryAnchor) async throws {
        let url = try anchorFileURL()
        try anchor.opaqueData.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func clearAnchor() async throws {
        let url = try anchorFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Resolved per call rather than in `init` so that a failure to reach the directory is
    /// an error on the operation that needed it, not a construction failure that would
    /// have to be handled in the composition root before the app has a chance to run.
    private func anchorFileURL() throws -> URL {
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(directoryName, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
