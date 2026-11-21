# jac/roundtable/graph.jac
# The session graph and the walkers that run each phase over it, as laid out
# in docs/roundtable-design.md:
#
#     RoundtableSession --Participates--> Agent   (one edge per seated role)
#
# A walker is spawned on the session, visits every Agent, and records each
# agent's answer on the session. Every LLM answer is checked here before it is
# recorded (the choice must be a real option, the confidence in range); a
# failed call or a rejected answer is noted, never fatal.
#
# Before each call a walker checks the deadline. Past `decideBy` the requester's
# default already applies, so the session marks itself expired and stops.

import json;
import from roundtable.spec { AdvRequest, Position, RiskRow, SafetyReview, Vote }
import from roundtable.brain { Brain }
import from roundtable.clock { Clock }
import from roundtable.digest { clip }
import from roundtable.tally { ballot_problem }

node Agent {
    has role: str,
        brief: str,
        critic: bool,
        brain: Brain;
}

# A session graph is built per run and never attached to `root`: attaching it
# would make Jac persist the request and every answer under .jac/data/, and a
# later run would find this one's sessions there. An advisory run is stateless.
node RoundtableSession {
    has request: AdvRequest,
        positions: list[Position] = [],
        critiques: list[SafetyReview] = [],
        votes: dict[str, Vote] = {},
        abstained: list[dict[str, str]] = [],
        notes: list[str] = [],
        expired: bool = False;
}

edge Participates {}

# Cap on how much of the request context goes into a prompt.
glob CONTEXT_LIMIT: int = 6000;

def context_json(req: AdvRequest) -> str {
    return clip(json.dumps(req.context, sort_keys=True), CONTEXT_LIMIT);
}

def out_of_time(session: RoundtableSession, clock: Clock) -> bool {
    if session.expired {
        return True;
    }
    if clock.now() >= session.request.decide_by {
        session.expired = True;
        return True;
    }
    return False;
}

# Only the exception's class name is recorded: provider error messages can
# echo request details, and none of that belongs in a recommendation.
def failure_reason(e: Exception) -> str {
    return f"LLM call failed ({e.__class__.__name__})";
}

# Round of proposals: every non-critic role takes a position.
walker Deliberate {
    has session: RoundtableSession,
        clock: Clock,
        round_idx: int,
        prior: str;

    can open with RoundtableSession entry {
        visit [-->[?:Agent]];
    }

    can speak with Agent entry {
        if not here.critic and not out_of_time(self.session, self.clock) {
            req = self.session.request;
            try {
                take = here.brain.deliberate(
                    role=here.role, brief=here.brief, topic=req.topic,
                    question=req.question, context_json=context_json(req),
                    options=req.options_text(), prior_round=self.prior
                );
                problem = ballot_problem(take.choice, take.confidence, req.option_ids());
                if problem == "" {
                    self.session.positions.append(Position(
                        round_idx=self.round_idx, role=here.role, choice=take.choice,
                        rationale=take.rationale, confidence=take.confidence,
                        risks=take.risks
                    ));
                } else {
                    self.session.notes.append(
                        f"{here.role}, round {self.round_idx}: position discarded ({problem})"
                    );
                }
            } except Exception as e {
                self.session.notes.append(
                    f"{here.role}, round {self.round_idx}: {failure_reason(e)}"
                );
            }
        }
    }
}

# Safety review, after round one: every critic reviews the positions. A critic
# does not propose; it can only list issues and flag options as unsafe.
walker Review {
    has session: RoundtableSession,
        clock: Clock,
        positions: str;

    can open with RoundtableSession entry {
        visit [-->[?:Agent]];
    }

    can review with Agent entry {
        if here.critic and not out_of_time(self.session, self.clock) {
            req = self.session.request;
            try {
                c = here.brain.critique(
                    role=here.role, brief=here.brief, topic=req.topic,
                    question=req.question, context_json=context_json(req),
                    options=req.options_text(), positions=self.positions
                );
                ids = req.option_ids();
                kept = [b for b in c.blocks if b in ids];
                if len(kept) < len(c.blocks) {
                    self.session.notes.append(
                        f"{here.role}: ignored a block on an id that is not an option"
                    );
                }
                self.session.critiques.append(SafetyReview(
                    issues=c.issues, blocks=kept,
                    cases=[
                        RiskRow(scenario=rc.scenario, risk=rc.risk, mitigation=rc.mitigation)
                        for rc in c.cases
                    ]
                ));
            } except Exception as e {
                self.session.notes.append(f"{here.role}, safety review: {failure_reason(e)}");
            }
        }
    }
}

# Final vote: every seated role, critics included.
walker Cast {
    has session: RoundtableSession,
        clock: Clock,
        discussion: str;

    can open with RoundtableSession entry {
        visit [-->[?:Agent]];
    }

    can vote with Agent entry {
        if not out_of_time(self.session, self.clock) {
            req = self.session.request;
            try {
                b = here.brain.cast_vote(
                    role=here.role, brief=here.brief, topic=req.topic,
                    question=req.question, context_json=context_json(req),
                    options=req.options_text(), discussion=self.discussion
                );
                problem = ballot_problem(b.choice, b.confidence, req.option_ids());
                if problem == "" {
                    self.session.votes[here.role] = Vote(
                        choice=b.choice, rationale=clip(b.rationale, 500),
                        confidence=b.confidence
                    );
                } else {
                    self.session.abstained.append({"role": here.role, "reason": problem});
                }
            } except Exception as e {
                self.session.abstained.append(
                    {"role": here.role, "reason": failure_reason(e)}
                );
            }
        }
    }
}
