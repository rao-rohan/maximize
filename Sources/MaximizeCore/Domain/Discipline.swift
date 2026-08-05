import Foundation

/// Which of the plan's two prescriptions a session belongs to (A17).
///
/// The single structural idea of the lifting build: a day's ask is indexed by
/// discipline, a run is judged against the run ask and a lift against the lift ask, and
/// nothing is ever judged against the other discipline's rubric. Everything else in
/// `docs/LIFTING-SPEC.md` falls out of that.
///
/// ## Closed at two cases, deliberately
///
/// A third discipline is a new answer to "what is this app for", and it should cost an
/// amendment rather than a ticket — the same discipline A12 imposes on the chat subject
/// set, for the same reason. Cycling, swimming and mobility are **not** disciplines
/// here: they are `.other` sessions inside the run slot, which is exactly what they are
/// today. This is not a multi-sport model, and A17 says so in those words.
///
/// ## Why `.run` is the residual rather than a positive claim
///
/// Every workout maps to a discipline, so the mapping has to be total over an
/// `ActivityType` that is an open string wrapper by design (HealthKit gains types every
/// release). `.lift` is the closed, named exception and `.run` takes everything else,
/// because "everything else" is what the run slot already prescribes. A ride is `.run`
/// by slot without being a run — see `ActivityType.isRun`, which is the narrower
/// predicate and is defined in terms of this one so the two cannot disagree.
public enum Discipline: String, Hashable, Sendable, Codable, CaseIterable {
    case run
    case lift
}
