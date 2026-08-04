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

/// `ChatThread` as stored (PRD §8 `chat_thread`, D6).
///
/// The PRD specifies the messages as `json: [{role, content, ts}]`, and that is what is
/// stored: one blob per thread. Threads are read whole — a conversation is replayed
/// from the top as model context (D3) and rendered from the top as bubbles — so there
/// is no per-message query to normalize for.
///
/// D6 is why this record syncs like the rest: the conversation about a run is part of
/// the longitudinal record and must survive a reinstall.
public struct StoredChatThread: Hashable, Sendable {
    public var threadUUID: UUID
    public var workoutUUID: UUID

    /// A JSON-encoded `[ChatMessage]`.
    public var messagesJSON: Data

    public init(threadUUID: UUID, workoutUUID: UUID, messagesJSON: Data) {
        self.threadUUID = threadUUID
        self.workoutUUID = workoutUUID
        self.messagesJSON = messagesJSON
    }

    public init(_ thread: ChatThread) throws {
        let messagesJSON = try PersistencePayload.encode(
            thread.messages,
            field: "StoredChatThread.messagesJSON"
        )
        self.init(
            threadUUID: thread.id,
            workoutUUID: thread.workoutID,
            messagesJSON: messagesJSON
        )
    }

    public func toDomain() throws -> ChatThread {
        try ChatThread(
            id: threadUUID,
            workoutID: workoutUUID,
            messages: try PersistencePayload.decode(
                [ChatMessage].self,
                from: messagesJSON,
                field: "StoredChatThread.messagesJSON"
            )
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
