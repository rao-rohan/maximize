import Foundation

/// What the model is asked to return, before anything has been checked (§10.3, §10.5).
///
/// A *proposal*, not a score. The distinction is the point of the type: `Score` is the
/// permanent, immutable record (D8), and nothing may become one without passing the
/// validation in `WorkoutScorer`. Parsing into a deliberately weak shape — a bare `Int`
/// rather than a `ScoreValue` — is what makes rejection possible: a `137` has to be
/// representable long enough to be refused with a specific reason, and a type that
/// could not hold it would collapse "the model is out of range" into "the JSON did not
/// decode".
///
/// ## Why the band identifier is not requested
///
/// The rubric selects the band deterministically before the model is called, so asking
/// the model to name one would invite it to disagree about a fact that is not its to
/// have an opinion on — and would add a failure mode (echoed the wrong identifier) with
/// nothing to buy. The model is asked for the two things the rubric genuinely cannot
/// produce: where inside the permitted range this run lands, and one line of prose
/// saying why.
public struct ScoreProposal: Hashable, Sendable, Codable {
    /// 0...100, as an `Int` so an out-of-range answer survives parsing and is rejected
    /// on its merits.
    public let score: Int

    /// One line for the verdict header (FR-1.1).
    public let rationale: String

    public init(score: Int, rationale: String) {
        self.score = score
        self.rationale = rationale
    }

    /// The response shape, worded for the prompt.
    ///
    /// It lives beside the type it describes so the instruction and the decoder cannot
    /// drift apart — a prompt that asks for a key the decoder does not read fails at
    /// runtime, in production, on a real workout.
    public static let responseFormatDescription = """
        {"score": <integer>, "rationale": "<one sentence>"}
        """

    /// Decodes the model's reply.
    ///
    /// Tolerant about *formatting*, strict about *content*. A leading code fence is
    /// stripped, because a fenced JSON object is the same object and refusing it would
    /// burn a retry on punctuation. Prose wrapped around the JSON is **not** salvaged
    /// by hunting for the first `{`: a model that explained itself instead of answering
    /// did not follow the contract, and quietly digging the object out of the
    /// commentary hides that from the retry logic and from anyone reading the logs.
    public static func parse(_ raw: String) throws -> ScoreProposal {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst() // ``` or ```json
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard text.hasPrefix("{"), text.hasSuffix("}") else {
            throw ScoringError.malformedResponse(
                reason: "expected a single JSON object matching \(responseFormatDescription)"
            )
        }
        guard let data = text.data(using: .utf8) else {
            throw ScoringError.malformedResponse(reason: "response was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(ScoreProposal.self, from: data)
        } catch {
            throw ScoringError.malformedResponse(
                reason: "could not decode \(responseFormatDescription) — \(error)"
            )
        }
    }
}

/// The rules a rationale must satisfy to reach the verdict header (FR-1.1).
///
/// `Score` already refuses an empty or multi-line rationale, and that stays the floor —
/// nothing stored can violate it. This adds the rules that belong at the *model
/// boundary* rather than in the record: a length bound, and a refusal of the control
/// characters a generated string can carry invisibly.
///
/// ## On the length bound and D1
///
/// `maximumCharacters` is not a plan threshold and does not belong in the plan record.
/// D1 versions the numbers that define *training* — the HR cap, the cadence band, the
/// score cuts — because changing one must not silently rewrite history. This is a
/// layout invariant: it describes how much text fits on one line of a header at large
/// accessibility sizes, it is the same for every plan version, and changing it
/// re-renders a header rather than re-scoring a run.
public enum RationaleContract {
    /// One line in the verdict header, at the largest accessibility text sizes the app
    /// must survive. Exposed so a view can lay out against it rather than restate it.
    public static let maximumCharacters = 140

    /// The rules, in the wording the model is given. Kept next to the code that
    /// enforces them so the instruction and the check cannot disagree.
    public static let instructionText = """
        - One sentence, on a single line. No line breaks, no markdown, no bullet points.
        - At most \(maximumCharacters) characters.
        - Say what the athlete did and why it earned this score, in plain language, \
        citing the numbers that decided it.
        - It is a verdict on the execution, not advice for next time.
        """

    /// - Returns: the rationale, trimmed of surrounding whitespace.
    /// - Throws: `ScoringError.rationaleRejected` when it cannot be a header line.
    public static func validated(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ScoringError.rationaleRejected(reason: "it was empty")
        }
        guard !trimmed.contains(where: { $0.isNewline }) else {
            throw ScoringError.rationaleRejected(
                reason: "it spans more than one line, and the verdict header is one line"
            )
        }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ScoringError.rationaleRejected(reason: "it contains control characters")
        }
        guard trimmed.count <= maximumCharacters else {
            throw ScoringError.rationaleRejected(
                reason: "it is \(trimmed.count) characters, over the \(maximumCharacters)-character "
                    + "limit for a single header line"
            )
        }
        return trimmed
    }
}
