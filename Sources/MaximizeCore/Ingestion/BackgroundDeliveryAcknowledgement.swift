import Foundation

/// A one-shot acknowledgement that a background wake was handled.
///
/// HealthKit hands every observer-query update a completion handler and requires it
/// to be called. Apple's documentation for `HKObserverQueryCompletionHandler` is
/// unusually blunt about the consequence of not calling it:
///
/// > If you do not call this block, HealthKit continues to attempt to launch your app
/// > using a back off algorithm. If your app fails to respond three times, HealthKit
/// > assumes that your app cannot receive data, and stops sending you background
/// > updates.
///
/// That failure is permanent-until-relaunch and completely silent — no crash, no
/// error, just a zero-touch pipeline that stops capturing (PRD §13, tracker R5). It is
/// the worst outcome available on this code path, so the "must be called" half of the
/// contract is encoded in a type rather than left to the reader of a control-flow
/// graph.
///
/// The other half — *at most once* — matters because the handler is a C-style block
/// with no reentrancy guarantee of its own. Calling it twice is not a documented
/// error, but it is a lie about how many deliveries were handled, and this type makes
/// the second call a no-op instead of a question.
///
/// Thread-safe: the wake path spans an `await`, and HealthKit invokes update handlers
/// on an anonymous background queue, so the acknowledgement can be reached from more
/// than one thread even though the intended flow reaches it from exactly one.
public final class BackgroundDeliveryAcknowledgement: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingHandler: (@Sendable () -> Void)?

    /// - Parameter handler: the platform's completion handler. In production this is
    ///   HealthKit's `HKObserverQueryCompletionHandler`; in tests it is a closure that
    ///   records that the acknowledgement happened.
    public init(_ handler: @escaping @Sendable () -> Void) {
        self.pendingHandler = handler
    }

    /// Whether the underlying handler has already run.
    public var hasAcknowledged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingHandler == nil
    }

    /// Runs the underlying handler if it has not run yet.
    ///
    /// - Returns: `true` if this call is the one that ran the handler, `false` if it
    ///   had already been acknowledged. Callers are free to ignore the result; it
    ///   exists so tests can distinguish "acknowledged twice" from "acknowledged once".
    @discardableResult
    public func acknowledge() -> Bool {
        lock.lock()
        let handler = pendingHandler
        pendingHandler = nil
        lock.unlock()

        // Called outside the lock: the handler is platform code of unknown duration,
        // and holding a lock across it would be a deadlock waiting for a reentrant
        // caller.
        handler?()
        return handler != nil
    }
}
