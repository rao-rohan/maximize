import Foundation

extension WorkoutContext {
    /// Where one session sits in the athlete's training week — **chat only** (MAX-182,
    /// PRD-AMENDMENTS.md A29).
    ///
    /// ## The question this exists to make answerable
    ///
    /// A workout thread's fact sheet knew that day's prescription in detail and nothing at
    /// all about the days either side of it, so *"was this run consistent with my week"*,
    /// *"should I back off Thursday"* and *"is this my third hard day running"* were
    /// unanswerable in the one conversation a person would naturally ask them in — standing
    /// on the run they had just done. This is the smallest record that orients the session
    /// in its week.
    ///
    /// ## Fixed size, by construction — the constraint MAX-184's audit imposed
    ///
    /// **Nothing here grows with how much the athlete trained.** An earlier draft of this
    /// ticket carried one line per sibling session; the audit rejected that shape and it was
    /// right to. Per-session lines are `TrainingContext` arriving by a side door: they
    /// reintroduce an unbounded term into a prompt that already carries a full split series,
    /// and they send a second copy of the athlete's recent movement record on a call that
    /// was about one run. So this type carries **aggregates and configuration only** — every
    /// field below is O(1), or seven lines of the athlete's own plan, whichever the block is
    /// looking at. A week with three sessions and a week with fourteen render the same
    /// number of lines.
    ///
    /// What that costs is real and worth stating: the model can say *"you were 2 of 3 on the
    /// plan this week"* and cannot say *"your Thursday run was 9.2 km"*. The second is a
    /// question for that Thursday's own conversation, and the fact sheet says so.
    ///
    /// ## What is deliberately absent, and why each one
    ///
    /// - **No sibling session lines**, per above — and with them go every per-session
    ///   figure: no other session's distance, duration, activity type, classification,
    ///   heart rate, drift or score. `TrainingContext.Session` carries all of those,
    ///   including drift, and that is the deliberate difference between the two types: a
    ///   training thread's whole job is reading a trend across sessions, and orientation is
    ///   not.
    /// - **No heart-rate curve, no splits, no route.** `WorkoutContext` and
    ///   `TrainingContext` each give the reasoning at their own scale; it only gets stronger
    ///   for sessions that are not even the subject of the conversation.
    /// - **No score rationales.** The prose the scorer wrote about a *neighbouring* run adds
    ///   nothing to where this one sits, and it invites the model to argue with a stored
    ///   verdict (D8).
    /// - **No streak.** Two reasons, either sufficient. `Tallies.currentStreak` walks
    ///   backwards *out* of the interval it was computed over, so it is not measured over
    ///   the seven days this block names — and the block's first sentence promises that
    ///   every figure in it is. It is also, over a window this short, a *truncated* streak:
    ///   `TalliesCalculator` documents the walk as stopping at `from`, which makes the
    ///   number a lower bound with no way to tell a reader that it is one.
    /// - **No acute:chronic load ratio, yet.** A29 sanctions the field and this type does
    ///   not carry it — see A29's "What is sanctioned but not built" for why that is a
    ///   sequencing decision rather than a judgement about the figure.
    ///
    /// ## Why the week, and which week
    ///
    /// **The Monday-first training week containing the session's own calendar day**,
    /// resolved through `CalendarDay.startOfTrainingWeek()` — civil-date arithmetic through
    /// `Calendar`, never a count of 86,400-second blocks, which is the defect
    /// `MuscleFatigue` already had to have corrected for it. The athlete's time zone enters
    /// exactly once, where it always does: `Workout.calendarDay(in:)`.
    ///
    /// Three alternatives, and why each loses:
    ///
    /// - **A trailing seven days ending at the session.** It straddles two template weeks,
    ///   so an effective-sessions figure over it corresponds to nothing the plan asks and
    ///   nothing any screen shows. `TalliesCalculator` also ranks a missed day against the
    ///   other misses *in its week* (C1) and cannot widen what it is handed, so a window
    ///   that does not start on a Monday misjudges its own edges.
    /// - **The plan's arc week.** Not an alternative at all: `PlanCalendar.arcWeek` anchors
    ///   arc weeks to the Monday on or before the plan's effective date, so the arc week
    ///   *is* this week. They agree by construction, which is why the arc week can be quoted
    ///   here without resolving a second notion of "what week is it".
    /// - **The week containing today.** The conversation is about the session, not about
    ///   now. A run ninety days back must get its own week, or the same thread answers
    ///   differently next month — the freezing argument of §3.4, arriving free for a workout
    ///   subject because a session's calendar day never moves.
    ///
    /// ## The scorer is not shown this, and that is not a detail
    ///
    /// `Audience.scoring` never carries a surrounding week. The scorer's job under D1 is to
    /// judge one workout against the plan version in effect on its date, and D8 then stores
    /// that verdict forever. Feeding it "the athlete has trained twice this week" would make
    /// an immutable score depend on data outside the workout being scored — two identical
    /// runs would score differently because of what happened on the days around them, and
    /// nothing on screen would say so. `WorkoutContextBuilder` drops this for any audience
    /// but `.chat`, and `WorkoutFactSheet` renders the section only for `.chat`; the two
    /// gates are the same belt and braces MAX-068 put around the pace breakdown.
    ///
    /// ## No arithmetic here (A12 rule 4, §3.6(a))
    ///
    /// Every aggregate is `TalliesCalculator`'s own value for exactly these seven days, read
    /// verbatim — the same function the dashboard's tiles read. Every plan ask is a
    /// `PlanCalendar` lookup. This type derives one number, `sessionCount`, and it measures
    /// the prompt rather than the athlete.
    public struct SurroundingWeek: Hashable, Sendable {

        /// One day of the week, and what the plan asked of it.
        ///
        /// **The plan's asks are configuration, not measurement** — §3.3 item 1 draws
        /// exactly that line, and it is why seven of these lines are a different kind of
        /// thing from seven session lines. They carry no health data at all, they are
        /// always seven regardless of how much the athlete trained, and without them the
        /// block is a pile of figures with nothing to compare them against: "should I back
        /// off Thursday" is a question about Thursday's *ask*, and the fact sheet around
        /// this block carries only the subject day's.
        public struct Day: Hashable, Sendable, Identifiable {
            public var id: CalendarDay { date }

            public let date: CalendarDay

            /// The plan's entry for the day, resolved per day through `PlanCalendar` rather
            /// than read off one plan's weekly template — so a week straddling a revision
            /// (D1) shows each day the ask that actually governed it, with no coverage
            /// caveat needed.
            ///
            /// Nil where no plan version governs the day: a real state, kept distinct from
            /// "the plan asked for rest".
            public let planDay: PlanDay?

            init(date: CalendarDay, planDay: PlanDay?) {
                self.date = date
                self.planDay = planDay
            }
        }

        /// The Monday the week starts on.
        public let from: CalendarDay

        /// The Sunday it ends on.
        public let through: CalendarDay

        /// The athlete's current civil day — an input, never a clock read (MAX-110), the
        /// same one `TalliesCalculator` was given.
        ///
        /// Carried so the renderer can say that a week reaching past today is not over.
        /// Without it, a Thursday ask with nothing against it reads identically whether
        /// Thursday has been and gone or has not arrived, and only one of those is a session
        /// the athlete skipped.
        public let today: CalendarDay

        /// The plan version governing the **last** day of the week, or nil when none does.
        ///
        /// The last day rather than the first, matching `TrainingContext.plan` and
        /// `TalliesCalculator.resolveCurrentWeek` — which resolves the arc week from
        /// `through` for the same reason. Read only for the arc week's prescribed long run;
        /// every day's own ask comes from that day's `PlanDay`.
        public let plan: Plan?

        /// `TalliesCalculator.compute`'s value for exactly `from...through`, verbatim.
        public let tallies: Tallies

        /// The seven days, Monday first.
        public let days: [Day]

        /// How many workouts are recorded in the week, including the one this context
        /// describes.
        ///
        /// The one number this type derives, and it measures the prompt rather than the
        /// athlete: it is what tells "the app holds one session for this week" apart from
        /// "the app holds nine", which no other figure here says. Distinct from
        /// `Tallies.workoutDays`, which counts *days* with at least one workout — a Tuesday
        /// holding a run and a lift is one day and two sessions, and both are worth a
        /// reader.
        public let sessionCount: Int

        /// - Throws: when the days handed in are not the seven Monday-first days the tallies
        ///   were computed over. The block's opening sentence promises that every figure in
        ///   it is measured over exactly these days, and this is that promise as a check
        ///   rather than a comment — a caller that computed tallies over a month and
        ///   rendered them under a week's heading would be §3.6(b)'s disagreement, printed
        ///   as a fact.
        init(
            from: CalendarDay,
            through: CalendarDay,
            today: CalendarDay,
            plan: Plan?,
            tallies: Tallies,
            days: [Day],
            sessionCount: Int
        ) throws {
            guard from.weekday == .monday else {
                throw DomainError.inconsistent(
                    reason: "WorkoutContext.SurroundingWeek: the week must start on a Monday, "
                        + "not \(from) (\(from.weekday))"
                )
            }
            guard try from.days(until: through) == 6 else {
                throw DomainError.inconsistent(
                    reason: "WorkoutContext.SurroundingWeek: \(from) through \(through) is not "
                        + "seven days"
                )
            }
            guard tallies.from == from, tallies.through == through else {
                throw DomainError.inconsistent(
                    reason: "WorkoutContext.SurroundingWeek: the tallies cover "
                        + "\(tallies.from)…\(tallies.through), not the week \(from)…\(through) "
                        + "this block states"
                )
            }
            guard days.map(\.date) == (try CalendarDay.days(from: from, through: through)) else {
                throw DomainError.inconsistent(
                    reason: "WorkoutContext.SurroundingWeek: the days supplied are not every day "
                        + "of \(from)…\(through), ascending"
                )
            }
            self.from = from
            self.through = through
            self.today = today
            self.plan = plan
            self.tallies = tallies
            self.days = days
            self.sessionCount = sessionCount
        }

        /// Whether the only session recorded in the week is the one this context describes.
        ///
        /// A stated fact rather than a figure left to be read as a blank (MAX-175). Worded
        /// by the renderer as a claim about the record and not about the athlete: what this
        /// app holds for a week and what a person did in it are different claims, and only
        /// the first is one it can make.
        public var holdsNoOtherSession: Bool {
            sessionCount <= 1
        }

        /// Whether the week runs past the day the athlete is standing in.
        public var reachesBeyondToday: Bool {
            through > today
        }

        /// The 1-based arc week this week is, or nil when no plan governs its last day.
        ///
        /// Read off `tallies`, which got it from `PlanCalendar.arcWeek(for:under:)` — the
        /// one interpretation of "what week is it", shared with the plan screen and with the
        /// calendar resolution the scorer uses.
        public var arcWeekIndex: Int? {
            tallies.currentWeek.arcWeekIndex
        }

        /// The long run the plan prescribes for `arcWeekIndex`, in metres.
        ///
        /// A lookup in `LongRunArc`, not a calculation: nil when the arc has run out, which
        /// `PlanCalendar` documents as an expected state meaning the plan wants a new
        /// version (D1).
        public var arcWeekLongRunMeters: Double? {
            guard let plan, let week = arcWeekIndex else { return nil }
            return plan.longRunArc.distanceMeters(forWeek: week)
        }
    }
}
