import Foundation

/// Why the on-device store did not open, as far as the app can honestly tell.
///
/// ## Why classify at all
///
/// MAX-154 put the store-open error's domain and code into the log, which is the right
/// place for a diagnostic and the wrong place for an athlete. Four reasons is the most
/// this app can distinguish without guessing, and the distinction is worth having for one
/// reason only: **it decides whether trying again is offered.** A control that cannot
/// help is worse than no control — it is a second thing that does not work — so the state
/// that a second attempt cannot clear does not get a button, and says why.
///
/// Every case below is reached from a documented `NSCocoaErrorDomain` code (see
/// `classifying(errorDomain:errorCode:)`); anything else is `unknown`, which is the
/// honest answer and not a fallback dressed up as one.
///
/// **No case names an error, a code or a framework**, here or in the copy derived from
/// it — `FailureCopy`'s rule. These are descriptions of what happened to a person, and
/// the diagnostic stays in the log where the person diagnosing it will actually read it.
public enum StoreOpenFailureReason: Hashable, Sendable, CaseIterable {

    /// The store's files could not be read or written for want of permission — which, for
    /// a container this app owns, is what iOS file protection looks like from inside the
    /// process.
    ///
    /// `MaximizeModelContainer.fileProtection` is `.completeUntilFirstUserAuthentication`,
    /// so the store is unreadable between a restart and the first unlock. A HealthKit
    /// background wake can land in exactly that window — a phone that rebooted overnight
    /// and syncs a Watch workout before anyone has touched it — and if iOS then brings
    /// that same process to the foreground, the athlete opens an app whose store failed
    /// to open an hour ago. That is the one failure here that a second attempt reliably
    /// clears, because by then the phone is unlocked.
    case deviceHadNotBeenUnlocked

    /// The device reported no room to write.
    ///
    /// Trying again is offered because the athlete can act on it between attempts, which
    /// is the whole test for whether a retry is honest.
    case noRoomOnDevice

    /// The store on disk is not the shape this build expects and could not be converted
    /// to it.
    ///
    /// The only failure here that a second identical attempt cannot clear: nothing about
    /// the store or the build changes between them. It is also the one the two record
    /// types added tonight could in principle cause, which is why it is named rather than
    /// left in `unknown` — see `MaximizeMigrationPlan` for why this is believed not to
    /// arise, and `PROJECT_TRACKER.md`'s MAX-169 row for what that belief rests on.
    case shapeThisBuildCannotOpen

    /// Anything else. Trying again is offered: it costs nothing, it cannot make anything
    /// worse, and a transient I/O failure is the likeliest thing hiding in here.
    case unknown

    /// Whether opening again, with nothing else changed, could plausibly work.
    ///
    /// The test each case is held to: is there a world in which the second attempt
    /// succeeds — either because the device's state changed on its own (an unlock), or
    /// because the athlete can change it between the two attempts (freeing space)? Where
    /// the answer is no, no button is offered.
    public var isWorthTryingAgain: Bool {
        switch self {
        case .deviceHadNotBeenUnlocked, .noRoomOnDevice, .unknown:
            return true
        case .shapeThisBuildCannotOpen:
            return false
        }
    }

    /// Classifies a store-open error from the two scalars MAX-154 already treats as
    /// publishable — the domain and the code.
    ///
    /// **Takes scalars, not an `Error`.** The core cannot see SwiftData, and it must not
    /// see the error itself: a Core Data error's `userInfo` can carry
    /// `NSValidationErrorObject`, i.e. stored row values, which is health data (CLAUDE.md).
    /// A domain string and an integer cannot carry a workout. This is the same public/
    /// private split `PersistenceComposition` already logs by, and it is what lets the
    /// classification be decided in the core and tested here rather than in a `catch`
    /// block nothing executes.
    ///
    /// Codes are Foundation's and Core Data's documented constants, spelled out rather
    /// than range-matched — `134100...134199` would silently absorb a future code whose
    /// meaning nobody checked, and absorbing it into `shapeThisBuildCannotOpen` would
    /// withhold a retry that might have worked.
    public static func classifying(errorDomain: String, errorCode: Int) -> StoreOpenFailureReason {
        guard errorDomain == NSCocoaErrorDomain else { return .unknown }

        switch errorCode {
        case CocoaErrorCode.fileReadNoPermission, CocoaErrorCode.fileWriteNoPermission:
            return .deviceHadNotBeenUnlocked
        case CocoaErrorCode.fileWriteOutOfSpace:
            return .noRoomOnDevice
        case CocoaErrorCode.persistentStoreIncompatibleSchema,
            CocoaErrorCode.persistentStoreIncompatibleVersionHash,
            CocoaErrorCode.migration,
            CocoaErrorCode.migrationMissingSourceModel,
            CocoaErrorCode.migrationMissingMappingModel,
            CocoaErrorCode.inferredMappingModel:
            return .shapeThisBuildCannotOpen
        default:
            return .unknown
        }
    }

    /// The documented `NSCocoaErrorDomain` codes this classification rests on.
    ///
    /// Written as integers rather than as `CocoaError.Code` cases because the Core Data
    /// half of this list has no `CocoaError.Code` spelling at all — `NSMigrationError` and
    /// friends are `NSError` codes only — and a list half in one vocabulary and half in
    /// another is a list nobody can check at a glance. Each value is Apple's own constant
    /// and is named after it.
    private enum CocoaErrorCode {
        /// `NSFileReadNoPermissionError`.
        static let fileReadNoPermission = 257
        /// `NSFileWriteNoPermissionError`.
        static let fileWriteNoPermission = 513
        /// `NSFileWriteOutOfSpaceError`.
        static let fileWriteOutOfSpace = 640
        /// `NSPersistentStoreIncompatibleSchemaError`.
        static let persistentStoreIncompatibleSchema = 134_020
        /// `NSPersistentStoreIncompatibleVersionHashError` — the store's model hashes do
        /// not match the running model's, and no migration resolved it.
        static let persistentStoreIncompatibleVersionHash = 134_100
        /// `NSMigrationError`.
        static let migration = 134_110
        /// `NSMigrationMissingSourceModelError`.
        static let migrationMissingSourceModel = 134_130
        /// `NSMigrationMissingMappingModelError`.
        static let migrationMissingMappingModel = 134_140
        /// `NSInferredMappingModelError` — the automatic mapping could not be inferred,
        /// which is precisely the failure `MaximizeMigrationPlan` argues cannot arise from
        /// an additive change.
        static let inferredMappingModel = 134_190
    }
}

/// A store-open failure, with the one fact that changes what is said about it a second
/// time round.
public struct StoreOpenFailure: Hashable, Sendable {

    public let reason: StoreOpenFailureReason

    /// Whether the athlete has already pressed **Try again** at least once for this
    /// failure. The copy acknowledges it rather than repeating itself verbatim, which is
    /// how a screen tells a person their tap did something.
    public let hasAlreadyBeenTriedAgain: Bool

    /// Whether a **Try again** control should be offered.
    ///
    /// Stays true after a failed attempt: a device that has still not been unlocked, or a
    /// disk still full, is not evidence that the *next* attempt fails — and withdrawing
    /// the only control on the screen after one press would leave the athlete with
    /// nothing but a wall of text. The reason is the only thing that removes the button.
    public var permitsTryingAgain: Bool { reason.isWorthTryingAgain }

    public init(reason: StoreOpenFailureReason, hasAlreadyBeenTriedAgain: Bool) {
        self.reason = reason
        self.hasAlreadyBeenTriedAgain = hasAlreadyBeenTriedAgain
    }
}

/// What one attempt to open the store came back with.
public enum StoreOpenOutcome: Hashable, Sendable {
    case opened
    case couldNotOpen(StoreOpenFailureReason)
}

/// Whether the app has a store — the single fact every screen's content depends on
/// (MAX-169).
///
/// ## Why this exists
///
/// Before this type, an unopenable store was not a state the app had; it was the absence
/// of one. `PersistenceComposition.store` was `nil`, every screen independently reported
/// that its own content could not be loaded, and nothing anywhere said the one true thing
/// — that there is no store, so nothing is being saved either. Five screens each claiming
/// a local problem reads as five bugs; it is one fact, and this is the type that holds it.
///
/// ## Why the state machine is in the core
///
/// CLAUDE.md's thin-shell rule, and the specific reason behind it: `App/` is compiled by
/// CI and never executed (tracker R2, R13), and this particular path has never executed
/// anywhere at all — no test and no device has opened a store that refused to open. The
/// transitions below are therefore the only part of this feature anything can check, so
/// they are values with a test rather than branches in a view.
///
/// The app layer's whole remaining job is: call `MaximizeModelContainer.makeOnDisk()`,
/// turn what came back into a `StoreOpenOutcome`, and render what this type says.
public enum StoreAvailability: Hashable, Sendable {

    /// The store opened on this launch's first attempt. The ordinary state.
    case open

    /// The store did not open, and the app is showing that instead of its tabs.
    case couldNotOpen(StoreOpenFailure)

    /// It did not open at first and did on a later attempt.
    ///
    /// **Distinct from `open`, and not a cosmetic distinction.** The ingestion pipeline is
    /// assembled once, from `application(_:didFinishLaunchingWithOptions:)`, against
    /// whatever store existed then — which was none. Reads work from this point; new
    /// workouts are not collected until the app is launched again, and none of them are
    /// lost while it waits (the anchor stays pinned, R9/R12). That is a real difference an
    /// athlete would otherwise discover as "my run never showed up", so the copy for this
    /// case says it.
    case openedAfterTryingAgain

    /// Whether there is a store behind the app's screens.
    public var isUsable: Bool {
        switch self {
        case .open, .openedAfterTryingAgain:
            return true
        case .couldNotOpen:
            return false
        }
    }

    /// The state after the launch's first attempt to open the store.
    public static func afterFirstAttempt(_ outcome: StoreOpenOutcome) -> StoreAvailability {
        switch outcome {
        case .opened:
            return .open
        case let .couldNotOpen(reason):
            return .couldNotOpen(StoreOpenFailure(reason: reason, hasAlreadyBeenTriedAgain: false))
        }
    }

    /// The state after trying again from this one.
    ///
    /// A store that already opened is returned unchanged, and the case is not an oversight:
    /// nothing may re-open a store that is open. `MaximizeStore` holds the container that
    /// opened, screens hold that store, and a second container over the same file is two
    /// SwiftData stacks writing one SQLite database — the very thing
    /// `IngestionComposition` refuses to do. Making the no-op explicit here is what keeps
    /// a caller from having to remember it.
    public func afterTryingAgain(_ outcome: StoreOpenOutcome) -> StoreAvailability {
        switch (self, outcome) {
        case (.open, _), (.openedAfterTryingAgain, _):
            return self
        case (.couldNotOpen, .opened):
            return .openedAfterTryingAgain
        case let (.couldNotOpen, .couldNotOpen(reason)):
            return .couldNotOpen(StoreOpenFailure(reason: reason, hasAlreadyBeenTriedAgain: true))
        }
    }
}

/// The one control the store notice may offer.
///
/// **Two cases, and the absence of a third is the point.** With CloudKit deferred (A8)
/// the on-device store is the athlete's only copy of their history, so no control here
/// deletes, resets, rebuilds or reinstalls anything — a destructive button beside an
/// alarming message is how somebody loses years of training at six in the morning. This
/// enum is `CaseIterable` so that stays checkable: a third case cannot be added without a
/// test failing and a person deciding it is safe.
public enum StoreNoticeAction: Hashable, Sendable, CaseIterable {

    /// Attempt the open again. Reads nothing, writes nothing, and changes nothing on disk
    /// when it fails.
    case tryAgain

    /// Dismiss the notice and show the app. Offered only from
    /// `StoreAvailability.openedAfterTryingAgain`, where the notice's remaining job is to
    /// say what did and did not come back.
    case goToTheApp
}

/// One rendering of the store notice: a heading, a paragraph, an optional second
/// paragraph at secondary weight, and at most one action.
///
/// The same shape as `FirstRunCardCopy`, deliberately: a caller renders a value rather
/// than asking four questions and hoping the answers belong together.
public struct StoreAvailabilityNotice: Hashable, Sendable {

    public let heading: String

    /// What has happened, what it is not, and what it costs. The same paragraph for every
    /// failure reason — the fact does not change with the cause.
    public let body: String

    /// What is specific to this failure, at secondary weight.
    public let detail: String?

    public let action: StoreNoticeAction?

    /// The button's title, present exactly when `action` is.
    public var actionLabel: String? {
        action.map(FailureCopy.actionLabel(for:))
    }
}
