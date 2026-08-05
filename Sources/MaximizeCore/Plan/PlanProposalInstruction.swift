import Foundation

/// The text put in front of the model for one plan-drafting call (CHAT-FIRST-SPEC.md
/// §4.7, §4.9).
///
/// ## The four-way split, and what each part is
///
/// `ScoringInstruction` splits two ways and `ChatInstruction` three; this splits four,
/// and the extra seam is the one §4.9 argues for:
///
/// - `task` is what the model is asked to *do*. Identical for every first attempt in the
///   app, and it holds no health data at all, so it can be sent as a cacheable system
///   block.
/// - `schema` is the shape and vocabulary of a plan — `PlanProposal.schemaDescription`,
///   generated from the core enums. Also stable, and also free of health data.
/// - `factSheet` is the athlete's training, rendered by `ContextBuilder`, and it is the
///   only part that carries PII.
/// - `turns` is the conversation in which they described the plan they want.
///
/// Keeping the schema out of the fact sheet is the point. `WorkoutContext.Audience` is a
/// **health-data minimisation switch** and must stay one: `Audience` selects what health
/// data leaves the device, `task` selects what the model is asked to do, and a third
/// audience whose only difference was "also knows what a plan looks like" would conflate
/// them. The schema travels next to `task` because that is what it is.
///
/// ## This type does not assemble context (D3)
///
/// `factSheet` must be `ContextBuilder`'s output **verbatim**. Nothing in this file reads
/// a `Workout`, a `Plan` or a `Score`; it takes a string it did not write and a
/// conversation it did not have. `task` and `schema`, by contrast, are *not* the caller's
/// to supply — there is no initialiser that accepts them. Prompt text living in a
/// transport is how two callers end up asking for subtly different things, and MAX-100's
/// client is required to be decision-free.
public struct PlanProposalInstruction: Hashable, Sendable {

    /// What the model is asked to do. No health data, no plan data, no numbers — the same
    /// contract `ScoringInstruction.task` and `ChatInstruction.task` carry.
    public let task: String

    /// `PlanProposal.schemaDescription`. Stable, and free of health data.
    public let schema: String

    /// The athlete's training, rendered by the one context builder and passed through
    /// unchanged. The only part of this type that carries PII.
    public let factSheet: String

    /// The conversation so far, oldest first — the turns in which the athlete described
    /// the plan they want.
    public let turns: [ChatTurn]

    /// - Parameters:
    ///   - factSheet: `PromptContext.factSheet()`, verbatim.
    ///   - turns: the transcript, oldest first. Must open with a user turn: the Messages
    ///     API requires it, and a conversation that opens with the assistant is nonsense
    ///     to replay. Rejected here, in the core and under test, rather than discovered as
    ///     a 400 from a live server.
    ///   - previousFailure: the rejection that this call is a retry of, if it is one.
    ///     §4.5 allows exactly one — *one, not a loop*, because a loop burning the owner's
    ///     tokens against a model that keeps proposing a 400 bpm cap is the failure mode
    ///     to design against. **How many retries to make is MAX-101's policy; what to say
    ///     when making one is prompt text, so it lives here.**
    ///
    /// - Throws: `DomainError` when the pieces could not be a valid request.
    public init(
        factSheet: String,
        turns: [ChatTurn],
        retryingAfter previousFailure: PlanProposalError? = nil
    ) throws {
        try Validate.nonEmpty(factSheet, "PlanProposalInstruction.factSheet")
        guard let first = turns.first else {
            throw DomainError.empty(field: "PlanProposalInstruction.turns")
        }
        guard first.speaker == .user else {
            throw DomainError.inconsistent(
                reason: "PlanProposalInstruction.turns must begin with a user turn; the athlete "
                    + "describes the plan before there is anything to draft from."
            )
        }

        if let previousFailure {
            self.task = """
                \(PlanProposalInstruction.taskDescription)

                Your previous reply was rejected: \(previousFailure.description)

                Send a corrected proposal in the same shape. Do not explain the \
                correction and do not apologise — reply with the JSON object only.
                """
        } else {
            self.task = PlanProposalInstruction.taskDescription
        }
        self.schema = PlanProposal.schemaDescription
        self.factSheet = factSheet
        self.turns = turns
    }

    /// Whether this instruction is the one retry §4.5 permits.
    ///
    /// Exposed so a caller can tell the two calls apart without comparing prompt strings —
    /// and so a transport can decline to cache a `task` block that will be sent once.
    public var isRetry: Bool { task != PlanProposalInstruction.taskDescription }

    /// The stable half of the prompt. Contains no data about any athlete.
    ///
    /// It says what a proposal *is* — reviewable, editable, not yet saved — because a
    /// model that believes it is writing the plan directly hedges, and a model that knows
    /// the athlete gets a prefilled form does not have to.
    public static let taskDescription = """
        You are drafting a training plan for one athlete, from the conversation you have \
        just had with them.

        You are given their recent training as a fact sheet — the plan in effect, if there \
        is one, how they have actually been executing it, and the window that covers — and \
        the conversation in which they described what they want. Take what they are asking \
        for from the conversation and what is true about them today from the fact sheet. \
        Where the two disagree, the conversation wins: they are telling you to change \
        something.

        What you send back is a proposal, not a saved plan. The athlete sees it, every \
        field stays editable, and they choose the date it starts. So propose the plan you \
        would actually recommend rather than hedging.

        - Change only what the conversation asks you to change. If they already have a \
        plan, carry every field they did not mention through unchanged. An unrequested \
        edit is shown to them as a change they did not ask for, and it costs you their \
        trust in the ones they did.
        - Prescribe the whole week, every time: all seven weekdays, rest days included.
        - Do not invent facts about the athlete. Where the conversation is silent — how \
        many days a week they can run, how far their long run goes — take the answer from \
        their current plan and their recent training.
        - Do not restate or argue with a score the app has already given a run. Those are \
        settled.
        """
}
