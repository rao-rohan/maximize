import Foundation

/// `Plan` as stored (PRD §8 `plan`, D1).
///
/// ## Two columns and a blob
///
/// The whole plan is one JSON payload, because the weekly template, the long-run arc
/// and the rubric are deep trees that nothing filters on — `PlanCalendar` loads every
/// version and resolves in memory. `versionNumber` and `effectiveFromISO8601` are
/// lifted out as columns because they are what a load *orders by*.
///
/// `effectiveFrom` is stored in `CalendarDay`'s own `YYYY-MM-DD` wire format, which
/// sorts lexicographically in exactly the order it sorts chronologically — zero-padded,
/// fixed-width, most-significant-first. So a plain string sort is a correct
/// chronological sort, with no date parsing and no time zone anywhere near it. That is
/// the property `CalendarDay` exists to protect (a run at 23:40 must not drift into the
/// next day), and it survives being written to disk intact.
///
/// ## The columns are checked against the payload
///
/// Lifting two fields out duplicates them, and duplicated data can disagree. `toDomain`
/// therefore verifies both against the decoded plan and refuses a record where they
/// differ. A mismatch would mean a plan sorted into one position while governing a
/// different range of days — which is D1's reproducibility guarantee failing silently,
/// the single worst way for this record to be wrong.
public struct StoredPlan: Hashable, Sendable {
    public var versionNumber: Int

    /// `CalendarDay`'s `YYYY-MM-DD` form. See the note above on why this is a string.
    public var effectiveFromISO8601: String

    /// A JSON-encoded `Plan`.
    public var payloadJSON: Data

    public init(versionNumber: Int, effectiveFromISO8601: String, payloadJSON: Data) {
        self.versionNumber = versionNumber
        self.effectiveFromISO8601 = effectiveFromISO8601
        self.payloadJSON = payloadJSON
    }

    public init(_ plan: Plan) throws {
        let payloadJSON = try PersistencePayload.encode(plan, field: "StoredPlan.payloadJSON")
        self.init(
            versionNumber: plan.version.number,
            effectiveFromISO8601: plan.effectiveFrom.description,
            payloadJSON: payloadJSON
        )
    }

    public func toDomain() throws -> Plan {
        let plan = try PersistencePayload.decode(
            Plan.self,
            from: payloadJSON,
            field: "StoredPlan.payloadJSON"
        )
        guard plan.version.number == versionNumber else {
            throw DomainError.inconsistent(
                reason: "StoredPlan.versionNumber (\(versionNumber)) disagrees with the stored "
                    + "plan's version (\(plan.version.number))"
            )
        }
        guard plan.effectiveFrom.description == effectiveFromISO8601 else {
            throw DomainError.inconsistent(
                reason: "StoredPlan.effectiveFromISO8601 (\(effectiveFromISO8601)) disagrees with "
                    + "the stored plan's effectiveFrom (\(plan.effectiveFrom))"
            )
        }
        return plan
    }
}

/// `RestDayOverride` as stored (PRD §8 `rest_day_override`, D9/A6).
///
/// Keyed by the day, in the same sortable `YYYY-MM-DD` form as `StoredPlan`.
public struct StoredRestDayOverride: Hashable, Sendable {
    public var dayISO8601: String
    public var convertedFromMissed: Bool
    public var createdAt: Date

    public init(dayISO8601: String, convertedFromMissed: Bool, createdAt: Date) {
        self.dayISO8601 = dayISO8601
        self.convertedFromMissed = convertedFromMissed
        self.createdAt = createdAt
    }

    public init(_ override: RestDayOverride) {
        self.init(
            dayISO8601: override.date.description,
            convertedFromMissed: override.convertedFromMissed,
            createdAt: override.createdAt
        )
    }

    public func toDomain() throws -> RestDayOverride {
        RestDayOverride(
            date: try CalendarDay(iso8601: dayISO8601),
            convertedFromMissed: convertedFromMissed,
            createdAt: createdAt
        )
    }
}

/// `ChatThread` as stored (PRD §8 `chat_thread`, D6, A11).
///
/// The PRD specifies the messages as `json: [{role, content, ts}]`, and that is what is
/// stored: one blob per thread. Threads are read whole — a conversation is replayed
/// from the top as model context (D3) and rendered from the top as bubbles — so there
/// is no per-message query to normalize for.
///
/// D6 is why this record syncs like the rest: the conversation about a run is part of
/// the longitudinal record and must survive a reinstall.
///
/// ## The subject is columnar, not a blob (MAX-093)
///
/// `ChatSubject`'s own `Codable` conformance already names its wire keys after the
/// columns this type was always going to need — `kind`, `workoutID`, `from`, `through`
/// (see that type's doc comment) — so this is that split, not a new encoding invented
/// for storage. The columns exist because `threadSummaries()` and
/// `mostRecentThread(for:)` have to *query* by subject (which workout, which frozen
/// range) and a subject folded into an opaque JSON blob is not something a predicate can
/// see into.
///
/// - `subjectKindRawValue` — `ChatSubjectKind.rawValue`, always present.
/// - `workoutUUID` — meaningful only when the kind is `.workout`; carries a fixed
///   sentinel otherwise (see `Self.noWorkoutSentinel`) rather than becoming optional, so
///   the column keeps the same shape it had before this ticket.
/// - `scopeFromISO8601` / `scopeThroughISO8601` — `CalendarDay`'s `YYYY-MM-DD` form,
///   meaningful only when the kind is `.training`. Optional, and default-less: exactly
///   `DerivedMetricsRecord.distanceSplitsJSON`'s precedent for "a column that only some
///   rows use."
///
/// ## Why no migration is needed
///
/// Every column MAX-093 adds is either non-optional with a default (`subjectKindRawValue`,
/// `lastActivityAt`) or optional with none (`scopeFromISO8601`, `scopeThroughISO8601`) —
/// the same two shapes `DerivedMetricsRecord.distanceSplitsComputed` and
/// `.distanceSplitsJSON` already used for exactly this reason (see that type's doc
/// comment). SwiftData's lightweight migration adds a nullable or defaulted attribute to
/// an existing table without rewriting a row: a `ChatThreadRecord` written before this
/// build has `subjectKindRawValue` read back as `"workout"` (correct — A11: "every
/// existing thread has a workout subject") and both scope columns read back as `nil`
/// (correct — a workout thread has no scope to carry). No `MigrationStage` is required
/// and `MaximizeSchemaV1`'s version number does not move, for the reason
/// `distanceSplitsComputed`'s doc comment already gives: this schema has never been
/// promoted to CloudKit production (mirroring is off, A8), so the additive-only
/// immutability rule that would otherwise demand a version bump has not started
/// applying.
///
/// ## `lastActivityAt` and its sentinel
///
/// A genuine column now, rather than the derivation MAX-092 shipped — but the
/// derivation is not thrown away, because a pre-MAX-093 row has no value for it and
/// SwiftData will hand back the column's default. `Date.distantPast` is that default
/// (matching `createdAt`'s own precedent immediately below), and `toDomain()` treats it
/// as "unset" and falls back to exactly the rule MAX-092 used: the last message's
/// timestamp, or `createdAt` for a thread nobody has spoken in. A record written by this
/// build always supplies a real value, so the sentinel is only ever read on a thread
/// that predates this column — which is precisely the "no migration" claim, restated as
/// behaviour rather than asserted.
///
/// ## `createdAt` is storage metadata (MAX-048)
///
/// `createdAt` exists so the store can break a tie deterministically when CloudKit
/// mirroring produces two `ChatThreadRecord`s for one workout: the schema cannot carry a
/// unique constraint (see `MaximizeSchemaV1`'s CloudKit notes), so
/// `MaximizeStore.workoutThreadRecords(for:)` needs the same kind of explicit ordering
/// `workoutRecords(for:)` already has via `StoredWorkout.ingestedAt`. That job is
/// unchanged and untouched by this ticket.
///
/// ## `firstUserMessageContent` / `lastVisibleMessageContent` — a summary's own columns
/// (MAX-188)
///
/// `ChatThreadSummary`'s own doc comment states the rule it exists to enforce: a list of
/// threads must not be built by decoding every stored transcript to draw rows that show
/// none of it. `MaximizeStore.threadSummaries()` did exactly that, because
/// `messagesJSON` was the only place the two strings a summary needs — the opening
/// question and the last visible turn — lived. These two columns are that data lifted
/// out, the same move `subjectKindRawValue` already made for the subject at MAX-093.
///
/// They store **raw content, not a formatted title or preview.** `ChatThreadTitle` and
/// `ChatThreadPreview` still do the collapsing and truncation, at read time, from
/// whichever source handed them a string — a decoded `ChatMessage.content` or this
/// column's value are interchangeable inputs to the same pure functions. That is
/// deliberate: it means a future change to how a title or preview is formatted needs no
/// backfill, because nothing formatted is ever what gets stored.
///
/// `summaryFieldsComputed` is the flag that tells a fast, columns-only read (a row this
/// build wrote) apart from a row that predates these columns and must still be read
/// through a full decode this one time — see that property's own doc for why `nil` alone
/// cannot make that distinction. No schema version bump: both new `String?` columns are
/// optional and default-less, and `summaryFieldsComputed` is `Bool` with a `false`
/// default — the same additive shape `distanceSplitsComputed`/`distanceSplitsJSON`
/// already established, so a pre-MAX-188 row reads back with the two strings `nil` and
/// the flag `false`, and nothing is rewritten.
public struct StoredChatThread: Hashable, Sendable {
    public var threadUUID: UUID

    public var subjectKindRawValue: String

    /// Meaningful only when `subjectKindRawValue == ChatSubjectKind.workout.rawValue`.
    /// Carries `Self.noWorkoutSentinel` for a training thread rather than becoming
    /// optional — see the type-level doc for why.
    public var workoutUUID: UUID

    /// `CalendarDay`'s `YYYY-MM-DD` form. Meaningful only for a training subject; `nil`
    /// for a workout subject, including every row written before this column existed.
    public var scopeFromISO8601: String?

    /// See `scopeFromISO8601`.
    public var scopeThroughISO8601: String?

    /// A JSON-encoded `[ChatMessage]`.
    public var messagesJSON: Data

    /// Duplicate-resolution tiebreak (MAX-048). See the type-level doc above.
    public var createdAt: Date

    /// What the thread list sorts on and "which thread opens" resolves by (§2.2, §2.3).
    /// `Date.distantPast` marks a row written before this column existed; see the
    /// type-level doc for the fallback `toDomain()` applies in that case.
    public var lastActivityAt: Date

    /// The raw content of `ChatThread.firstUserMessage`, denormalised (MAX-188). Nil for
    /// a thread nobody has asked anything in yet, and for every row written before this
    /// column existed — see `summaryFieldsComputed`, which is what tells the two apart.
    ///
    /// Titles a training subject (`ChatThreadTitle.training(scope:firstUserMessage:)`
    /// still does the collapsing and truncation — this column stores the same raw string
    /// `thread.firstUserMessage?.content` always was, not a pre-formatted title, so a
    /// change to the title rule needs no backfill).
    public var firstUserMessageContent: String?

    /// The raw content of `ChatThread.lastVisibleMessage`, denormalised (MAX-188). Nil
    /// for a thread with no visible turns yet, and for every row written before this
    /// column existed — see `summaryFieldsComputed`.
    ///
    /// Previews the row (`ChatThreadPreview.line(for:)` does the collapsing and
    /// truncation at read time), for the same "store the raw string, format on read"
    /// reason `firstUserMessageContent` does.
    public var lastVisibleMessageContent: String?

    /// Whether `firstUserMessageContent` and `lastVisibleMessageContent` were set by a
    /// write that knew about them (MAX-188), as opposed to defaulting to `nil` because
    /// the row predates this column and there is nothing to backfill it with.
    ///
    /// The distinction matters because `nil` is also the correct value for a thread that
    /// genuinely has no first user message or no visible turns yet — an empty column
    /// alone cannot tell "legacy row" apart from "empty thread". This flag is what does:
    /// `false` on every row written before this ticket (CloudKit's default-required rule,
    /// same shape as `DerivedMetricsRecord.distanceSplitsComputed`), `true` on every row
    /// `init(_ thread:createdAt:)` below writes, forever after. `MaximizeStore
    /// .threadSummaries()` reads this to decide whether it may build a summary from these
    /// two columns alone, or must fall back to a full decode for that one row.
    public var summaryFieldsComputed: Bool

    /// A fixed, deterministic stand-in for "no workout" — not a fresh `UUID()` on every
    /// construction, which would make two `StoredChatThread` values built from the same
    /// training thread compare unequal for a reason that has nothing to do with their
    /// content.
    public static let noWorkoutSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")
        ?? UUID()

    /// The sentinel `lastActivityAt` reads back as on a row written before this column
    /// existed. See the type-level doc.
    public static let unsetLastActivityAt = Date.distantPast

    /// - Parameters:
    ///   - firstUserMessageContent, lastVisibleMessageContent, summaryFieldsComputed:
    ///     default to "not computed" (MAX-188) — the shape a row written before these
    ///     columns existed reads back as. A caller building a genuinely fresh record
    ///     always goes through `init(_ thread:createdAt:)` below, which sets all three
    ///     explicitly; this memberwise form defaulting to the legacy shape is what lets
    ///     `StoredRecordRoundTripTests` construct a pre-MAX-188 payload by simply not
    ///     mentioning them, the same way it already does for `lastActivityAt`.
    public init(
        threadUUID: UUID,
        subjectKindRawValue: String,
        workoutUUID: UUID,
        scopeFromISO8601: String?,
        scopeThroughISO8601: String?,
        messagesJSON: Data,
        createdAt: Date,
        lastActivityAt: Date,
        firstUserMessageContent: String? = nil,
        lastVisibleMessageContent: String? = nil,
        summaryFieldsComputed: Bool = false
    ) {
        self.threadUUID = threadUUID
        self.subjectKindRawValue = subjectKindRawValue
        self.workoutUUID = workoutUUID
        self.scopeFromISO8601 = scopeFromISO8601
        self.scopeThroughISO8601 = scopeThroughISO8601
        self.messagesJSON = messagesJSON
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.firstUserMessageContent = firstUserMessageContent
        self.lastVisibleMessageContent = lastVisibleMessageContent
        self.summaryFieldsComputed = summaryFieldsComputed
    }

    /// - Parameter createdAt: Not derived from `thread`. The caller (`MaximizeStore`)
    ///   decides this: the existing record's `createdAt` on an update, or the current
    ///   time on first insert.
    public init(_ thread: ChatThread, createdAt: Date) throws {
        let messagesJSON = try PersistencePayload.encode(
            thread.messages,
            field: "StoredChatThread.messagesJSON"
        )
        let firstUserMessageContent = thread.firstUserMessage?.content
        let lastVisibleMessageContent = thread.lastVisibleMessage?.content
        switch thread.subject {
        case let .workout(workoutUUID):
            self.init(
                threadUUID: thread.id,
                subjectKindRawValue: ChatSubjectKind.workout.rawValue,
                workoutUUID: workoutUUID,
                scopeFromISO8601: nil,
                scopeThroughISO8601: nil,
                messagesJSON: messagesJSON,
                createdAt: createdAt,
                lastActivityAt: thread.lastActivityAt,
                firstUserMessageContent: firstUserMessageContent,
                lastVisibleMessageContent: lastVisibleMessageContent,
                summaryFieldsComputed: true
            )
        case let .training(scope):
            self.init(
                threadUUID: thread.id,
                subjectKindRawValue: ChatSubjectKind.training.rawValue,
                workoutUUID: Self.noWorkoutSentinel,
                scopeFromISO8601: scope.from.description,
                scopeThroughISO8601: scope.through.description,
                messagesJSON: messagesJSON,
                createdAt: createdAt,
                lastActivityAt: thread.lastActivityAt,
                firstUserMessageContent: firstUserMessageContent,
                lastVisibleMessageContent: lastVisibleMessageContent,
                summaryFieldsComputed: true
            )
        }
    }

    /// `ChatSubject`, decoded from the columnar fields alone (MAX-188) — no
    /// `messagesJSON` in reach. `toDomain()` below is built on this rather than
    /// duplicating the switch, and it is also what `MaximizeStore.threadSummaries()`'s
    /// fast path calls: a summary needs a subject and never needs the transcript that
    /// would otherwise be decoded to get one.
    public static func subject(
        kindRawValue: String,
        workoutUUID: UUID,
        scopeFromISO8601: String?,
        scopeThroughISO8601: String?
    ) throws -> ChatSubject {
        guard let kind = ChatSubjectKind(rawValue: kindRawValue) else {
            throw DomainError.malformed(
                field: "StoredChatThread.subjectKindRawValue",
                value: kindRawValue
            )
        }
        switch kind {
        case .workout:
            return .workout(workoutUUID)
        case .training:
            guard let scopeFromISO8601, let scopeThroughISO8601 else {
                throw DomainError.inconsistent(
                    reason: "StoredChatThread has a training subjectKind but is missing its scope columns"
                )
            }
            return .training(try TrainingScope(
                from: try CalendarDay(iso8601: scopeFromISO8601),
                through: try CalendarDay(iso8601: scopeThroughISO8601)
            ))
        }
    }

    public func toDomain() throws -> ChatThread {
        let subject = try Self.subject(
            kindRawValue: subjectKindRawValue,
            workoutUUID: workoutUUID,
            scopeFromISO8601: scopeFromISO8601,
            scopeThroughISO8601: scopeThroughISO8601
        )
        let messages = try PersistencePayload.decode(
            [ChatMessage].self,
            from: messagesJSON,
            field: "StoredChatThread.messagesJSON"
        )
        let resolvedLastActivityAt = lastActivityAt == Self.unsetLastActivityAt
            ? (messages.last?.timestamp ?? createdAt)
            : lastActivityAt
        return try ChatThread(
            id: threadUUID,
            subject: subject,
            messages: messages,
            lastActivityAt: resolvedLastActivityAt
        )
    }
}

/// `AppSettings` as stored (PRD §8 `settings`).
///
/// There is exactly one settings record. It carries no identifier of its own: the
/// repository reads whichever row exists and writes back to it, creating one on first
/// use. A singleton row is a shape SwiftData has no direct support for, so
/// `SettingsRepository` owns the "there is only one" rule.
///
/// Note this record is a CloudKit-mirrored singleton, which means two devices editing
/// settings resolve last-writer-wins per field. That is the right outcome for
/// preferences and would be the wrong outcome for a ledger — which is why nothing else
/// in this schema is shaped like it.
public struct StoredAppSettings: Hashable, Sendable {
    public var restDayBudgetDaysPerWeek: Int
    public var distanceUnitRawValue: String
    public var appearanceRawValue: String
    public var reducesTransparency: Bool
    public var increasesContrast: Bool
    public var reducesMotion: Bool

    public init(
        restDayBudgetDaysPerWeek: Int,
        distanceUnitRawValue: String,
        appearanceRawValue: String,
        reducesTransparency: Bool,
        increasesContrast: Bool,
        reducesMotion: Bool
    ) {
        self.restDayBudgetDaysPerWeek = restDayBudgetDaysPerWeek
        self.distanceUnitRawValue = distanceUnitRawValue
        self.appearanceRawValue = appearanceRawValue
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        self.reducesMotion = reducesMotion
    }

    public init(_ settings: AppSettings) {
        self.init(
            restDayBudgetDaysPerWeek: settings.restDayBudget.daysPerWeek,
            distanceUnitRawValue: settings.distanceUnit.rawValue,
            appearanceRawValue: settings.appearance.rawValue,
            reducesTransparency: settings.reducesTransparency,
            increasesContrast: settings.increasesContrast,
            reducesMotion: settings.reducesMotion
        )
    }

    public func toDomain() throws -> AppSettings {
        guard let distanceUnit = DistanceUnit(rawValue: distanceUnitRawValue) else {
            throw DomainError.malformed(
                field: "StoredAppSettings.distanceUnitRawValue",
                value: distanceUnitRawValue
            )
        }
        guard let appearance = AppearancePreference(rawValue: appearanceRawValue) else {
            throw DomainError.malformed(
                field: "StoredAppSettings.appearanceRawValue",
                value: appearanceRawValue
            )
        }
        return AppSettings(
            restDayBudget: try RestDayBudget(daysPerWeek: restDayBudgetDaysPerWeek),
            distanceUnit: distanceUnit,
            appearance: appearance,
            reducesTransparency: reducesTransparency,
            increasesContrast: increasesContrast,
            reducesMotion: reducesMotion
        )
    }
}
