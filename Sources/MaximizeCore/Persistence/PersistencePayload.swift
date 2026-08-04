import Foundation

/// JSON encoding for the parts of a record that are stored as an opaque blob.
///
/// Two kinds of value take this path, for two different reasons:
///
/// - **The heart-rate series and the route (D7).** These are whole curves, read whole
///   by every consumer. A row per sample would be thousands of records per run to
///   serve a query nobody intends to make.
/// - **Nested plan and session structure.** The weekly template, the long-run arc and
///   the rubric are deep trees that nothing filters or sorts on. Flattening them into
///   columns would be a large hand-written mapping bought for no query.
///
/// Anything a screen actually filters, sorts or groups by stays a real column — see
/// `StoredWorkout.start`, `StoredPlan.effectiveFromISO8601` and friends.
///
/// ## Why the configuration is spelled out
///
/// These bytes outlive the process that wrote them. Both settings below are already
/// `JSONEncoder`'s defaults, and they are written down anyway because a future edit
/// that changed either one would silently fail to read every record already on disk:
///
/// - `.deferredToDate` stores a `Date` as its `timeIntervalSinceReferenceDate`, which
///   is exactly lossless — a round-tripped `Date` compares equal, which `.iso8601`
///   (whole seconds) would not.
/// - `.sortedKeys` makes the bytes a deterministic function of the value. That keeps
///   the round-trip tests stable, and it means an unchanged value re-encodes to
///   identical bytes — so CloudKit sees no change to mirror.
enum PersistencePayload {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    static func encode<Value: Encodable>(_ value: Value, field: String) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            // The underlying error is discarded deliberately: `EncodingError` embeds the
            // offending value's debug description, and for a heart-rate series or a route
            // that is health data (CLAUDE.md). The field name says everything a reader
            // needs and carries nothing a reader should not have.
            throw DomainError.malformed(field: field, value: "<unencodable>")
        }
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        field: String
    ) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DomainError {
            // A domain invariant rejected the decoded value — that is a more precise
            // answer than "malformed", and it carries no payload content, so it is
            // passed through rather than flattened.
            throw error
        } catch {
            throw DomainError.malformed(field: field, value: "<undecodable>")
        }
    }
}
