# jac/roundtable/tally.jac
# The deterministic core: how votes become a recommendation.
#
# No LLM is involved here, and none can change the result except by casting a
# valid vote. The rule (also re-derived independently, in Python, by
# adv1_contract.check):
#   1. A vote is valid if its choice is one of the request's options and its
#      confidence is within [0, 1]. Invalid votes are not counted.
#   2. Quorum: strictly more than half of the participants cast a valid vote;
#      without one the recommendation is the request's default.
#   3. Most votes wins; equal counts are broken by summed confidence; a
#      remaining tie yields the default.
#   4. A non-default winner that the safety critic flagged as unsafe is
#      replaced by the default. The critic can only move the outcome toward
#      the requester's default, never away from it.
#   5. Otherwise the winner is recommended: "unanimous" if every valid vote
#      agreed, else "plurality".

import from roundtable.spec { Vote }

glob TIE_EPS: float = 1e-9;

obj TallyResult {
    has recommendation: str,
        basis: str,
        valid_votes: int,
        counts: dict[str, int],
        winner: str = "";   # the vote winner before any safety override; "" if none
}

# "" if the ballot is valid, else the reason it is not.
def ballot_problem(choice: str, confidence: float, option_ids: list[str]) -> str {
    if choice not in option_ids {
        return "choice is not one of the request's options";
    }
    # Written as a negated range test so that NaN is rejected too.
    if not (confidence >= 0.0 and confidence <= 1.0) {
        return "confidence is outside [0, 1]";
    }
    return "";
}

# votes maps role -> that role's Vote; valid votes only.
def tally_votes(
    votes: dict[str, Vote], n_participants: int, default_choice: str, blocked: list[str]
) -> TallyResult {
    counts: dict[str, int] = {};
    conf: dict[str, float] = {};
    for role in votes {
        b = votes[role];
        counts[b.choice] = counts.get(b.choice, 0) + 1;
        conf[b.choice] = conf.get(b.choice, 0.0) + b.confidence;
    }
    n_valid = len(votes);

    if n_valid * 2 <= n_participants {
        return TallyResult(
            recommendation=default_choice, basis="no-quorum-default",
            valid_votes=n_valid, counts=counts
        );
    }

    top = max(counts.values());
    tied = [c for c in counts if counts[c] == top];
    best = max([conf[c] for c in tied]);
    leaders = sorted([c for c in tied if abs(conf[c] - best) <= TIE_EPS]);
    if len(leaders) > 1 {
        return TallyResult(
            recommendation=default_choice, basis="tie-default",
            valid_votes=n_valid, counts=counts
        );
    }

    winner = leaders[0];
    if winner != default_choice and winner in blocked {
        return TallyResult(
            recommendation=default_choice, basis="safety-block-default",
            valid_votes=n_valid, counts=counts, winner=winner
        );
    }
    basis = "unanimous" if len(counts) == 1 else "plurality";
    return TallyResult(
        recommendation=winner, basis=basis, valid_votes=n_valid,
        counts=counts, winner=winner
    );
}

def vote(choice: str, confidence: float) -> Vote {
    return Vote(choice=choice, rationale="", confidence=confidence);
}

test "ballots: option membership and confidence range" {
    ids = ["default", "swap"];
    assert ballot_problem("swap", 0.7, ids) == "";
    assert ballot_problem("swap", 0.0, ids) == "";
    assert ballot_problem("swap", 1.0, ids) == "";
    assert ballot_problem("wipe the depot", 0.9, ids) != "";
    assert ballot_problem("swap", 1.5, ids) != "";
    assert ballot_problem("swap", -0.1, ids) != "";
    assert ballot_problem("swap", float("nan"), ids) != "";
}

test "tally: plurality, unanimity, quorum" {
    plurality = tally_votes(
        {"a": vote("swap", 0.7), "b": vote("default", 0.5), "c": vote("swap", 0.8)},
        3, "default", []
    );
    assert plurality.recommendation == "swap" and plurality.basis == "plurality";

    unanimous = tally_votes({"a": vote("swap", 0.7), "b": vote("swap", 0.6)}, 2, "default", []);
    assert unanimous.recommendation == "swap" and unanimous.basis == "unanimous";

    # One vote out of three is not more than half.
    short = tally_votes({"a": vote("swap", 0.9)}, 3, "default", []);
    assert short.recommendation == "default" and short.basis == "no-quorum-default";
    empty = tally_votes({}, 3, "default", []);
    assert empty.recommendation == "default" and empty.basis == "no-quorum-default";
}

test "tally: ties fall to confidence, then to the default" {
    by_confidence = tally_votes(
        {"a": vote("swap", 0.9), "b": vote("swap", 0.6),
         "c": vote("default", 0.4), "d": vote("default", 0.5)},
        4, "default", []
    );
    assert by_confidence.recommendation == "swap" and by_confidence.basis == "plurality";

    dead_heat = tally_votes(
        {"a": vote("swap", 0.5), "b": vote("swap", 0.5),
         "c": vote("default", 0.5), "d": vote("default", 0.5)},
        4, "default", []
    );
    assert dead_heat.recommendation == "default" and dead_heat.basis == "tie-default";
}

test "tally: a safety block only ever moves the outcome to the default" {
    votes = {"a": vote("swap", 0.9), "b": vote("swap", 0.8), "c": vote("default", 0.4)};
    blocked = tally_votes(votes, 3, "default", ["swap"]);
    assert blocked.recommendation == "default" and blocked.basis == "safety-block-default";
    assert blocked.winner == "swap";

    # Blocking the default itself changes nothing, and neither does blocking a loser.
    still_default = tally_votes(
        {"a": vote("default", 0.9), "b": vote("default", 0.8), "c": vote("swap", 0.4)},
        3, "default", ["default"]
    );
    assert still_default.recommendation == "default" and still_default.basis == "plurality";
    loser_blocked = tally_votes(votes, 3, "default", ["other"]);
    assert loser_blocked.recommendation == "swap";
}
