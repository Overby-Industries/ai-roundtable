# jac/roundtable/engine.jac
# Runs one roundtable session over an ADV-1 advisory-request and returns an
# ADV-1 advisory-recommendation, or says why it did not.
#
#   plan_session  admission: is the request valid and deliberable, and who sits?
#   run_session   rounds of proposals -> safety review -> vote -> tally -> briefing
#
# The requester's `defaultChoice` is the fallback for everything that can go
# wrong: no quorum, a tie, a safety block. A session that cannot finish in time
# produces no recommendation at all (status "expired"), because by then the
# default already applies. The output is checked against the ADV-1 contract
# before it is returned.

import from roundtable.adv1_contract { check }
import from roundtable.clock { Clock }
import from roundtable.digest { clip, critique_digest, round_digest }
import from roundtable.graph { Agent, Cast, Deliberate, Participates, RoundtableSession, Review }
import from roundtable.report { build_recommendation }
import from roundtable.roster { AgentSeat, Roster }
import from roundtable.spec { request_from_dict }
import from roundtable.tally { tally_votes }

glob MAX_ROUNDS: int = 5;

obj RunConfig {
    has rounds: int = 2,
        min_participants: int = 3,
        min_deliberation_s: int = 600,
        participant_roles: list[str] = [];   # empty: seat the roles that cover the topic
}

obj Plan {
    has ok: bool,
        reasons: list[str],
        seats: list[AgentSeat] = [],
        rounds: int = 0,
        llm_calls: int = 0;
}

# status: "recommended", "declined" (not admitted; nothing was asked of any
# model), "expired" (ran out of time mid-session), or "failed" (the engine's
# own output broke the contract; a bug, reported rather than emitted).
obj Outcome {
    has status: str,
        reasons: list[str] = [],
        recommendation: dict | None = None,
        plan: Plan | None = None;
}

def contract_problems(doc: dict, request_doc: dict | None) -> list[str] {
    return [str(p) for p in check(doc, request_doc)];
}

def plan_session(request_doc: dict, roster: Roster, cfg: RunConfig, clock: Clock) -> Plan {
    problems = contract_problems(request_doc, None);
    if len(problems) > 0 {
        return Plan(
            ok=False,
            reasons=["not a valid ADV-1 advisory-request: " + p for p in problems]
        );
    }
    req = request_from_dict(request_doc);

    seconds_left = int((req.decide_by - clock.now()).total_seconds());
    if seconds_left < cfg.min_deliberation_s {
        return Plan(ok=False, reasons=[
            f"decideBy is {seconds_left} s away; at least {cfg.min_deliberation_s} s are "
            + "needed to deliberate, so the request's default stands"
        ]);
    }
    if cfg.rounds < 1 or cfg.rounds > MAX_ROUNDS {
        return Plan(ok=False, reasons=[f"rounds must be between 1 and {MAX_ROUNDS}"]);
    }

    seats: list[AgentSeat] = [];
    if len(cfg.participant_roles) > 0 {
        known = [s.spec.role for s in roster.seats];
        unknown = [r for r in cfg.participant_roles if r not in known];
        if len(unknown) > 0 {
            return Plan(ok=False, reasons=["unknown roles requested: " + ", ".join(unknown)]);
        }
        seats = [s for s in roster.seats if s.spec.role in cfg.participant_roles];
    } else {
        seats = [s for s in roster.seats if s.spec.covers(req.topic)];
    }

    reasons: list[str] = [];
    n_critics = len([s for s in seats if s.spec.critic]);
    n_proposers = len(seats) - n_critics;
    if len(seats) < cfg.min_participants {
        reasons.append(
            f"only {len(seats)} roles are seated for topic '{req.topic}'; "
            + f"at least {cfg.min_participants} are required"
        );
    }
    if n_critics == 0 {
        reasons.append("no safety critic is seated; a recommendation needs a safety review");
    }
    if n_proposers == 0 {
        reasons.append("no proposing role is seated");
    }
    if len(reasons) > 0 {
        return Plan(ok=False, reasons=reasons);
    }

    calls = n_proposers * cfg.rounds + n_critics + len(seats);
    if roster.briefer is not None {
        calls += 1;
    }
    return Plan(ok=True, reasons=[], seats=seats, rounds=cfg.rounds, llm_calls=calls);
}

def run_session(request_doc: dict, roster: Roster, cfg: RunConfig, clock: Clock) -> Outcome {
    plan = plan_session(request_doc, roster, cfg, clock);
    if not plan.ok {
        return Outcome(status="declined", reasons=plan.reasons, plan=plan);
    }
    req = request_from_dict(request_doc);

    session = RoundtableSession(request=req);
    for seat in plan.seats {
        session +>:Participates:+> Agent(
            role=seat.spec.role, brief=seat.spec.brief,
            critic=seat.spec.critic, brain=seat.brain
        );
    }

    # Rounds of proposals. The safety review happens once, after round one, and
    # its findings go into every later round and into the vote.
    rounds_done = 0;
    prior = "";
    r = 1;
    while r <= plan.rounds and not session.expired {
        session spawn Deliberate(session=session, clock=clock, round_idx=r, prior=prior);
        if r == 1 and not session.expired {
            session spawn Review(
                session=session, clock=clock, positions=round_digest(session.positions, 1)
            );
        }
        if not session.expired {
            rounds_done = r;
        }
        prior = round_digest(session.positions, r);
        review = critique_digest(session.critiques);
        if review != "" {
            prior = prior + "\n" + review;
        }
        r += 1;
    }
    if session.expired {
        return Outcome(
            status="expired", plan=plan,
            reasons=["decideBy passed during deliberation; the request's default already applies"]
        );
    }

    session spawn Cast(session=session, clock=clock, discussion=prior);
    if session.expired {
        return Outcome(
            status="expired", plan=plan,
            reasons=["decideBy passed during the vote; the request's default already applies"]
        );
    }

    blocked: list[str] = [];
    for c in session.critiques {
        blocked += c.blocks;
    }
    result = tally_votes(
        session.votes, len(plan.seats), req.default_choice, blocked
    );

    briefing = "";
    briefer = roster.briefer;
    if briefer is not None {
        try {
            briefing = clip(briefer.brain.write_briefing(
                topic=req.topic, question=req.question, options=req.options_text(),
                decision=f"recommended option '{result.recommendation}' "
                    + f"(basis: {result.basis}; {result.valid_votes} valid votes)",
                discussion=prior
            ), 600);
        } except Exception as e {
            session.notes.append(
                f"briefing unavailable ({e.__class__.__name__}); the deterministic summary stands alone"
            );
        }
    }

    now = clock.now();
    if now > req.decide_by {
        return Outcome(
            status="expired", plan=plan,
            reasons=["decideBy passed before the recommendation was ready; the default already applies"]
        );
    }
    rec = build_recommendation(
        req, result, session.votes, session.positions, session.critiques,
        session.abstained, session.notes, [s.spec.role for s in plan.seats],
        rounds_done, briefing, now
    );
    problems = contract_problems(rec, request_doc);
    if len(problems) > 0 {
        return Outcome(
            status="failed", plan=plan,
            reasons=["engine output violates the ADV-1 contract: " + p for p in problems]
        );
    }
    return Outcome(status="recommended", recommendation=rec, plan=plan);
}
