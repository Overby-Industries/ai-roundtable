# jac/roundtable/report.jac
# Assembles the ADV-1 advisory-recommendation. Everything that states or
# justifies the decision (the lead sentence, the basis, the approval line) is
# built here from the tally, not written by a model, so the prose a human reads
# can never contradict the vote. A model's briefing is appended after it.

import from datetime { datetime }
import from roundtable.spec { AdvRequest, Position, SafetyReview, Vote }
import from roundtable.tally { TallyResult }
import from roundtable.digest { clip }
import from roundtable.clock { fmt_ts }

glob MAX_RISKS: int = 8;
glob MAX_ACTIONS: int = 5;
glob MAX_NOTES: int = 20;

def dedupe(items: list[str], limit: int) -> list[str] {
    kept: list[str] = [];
    for item in items {
        if item != "" and item not in kept {
            kept.append(item);
        }
        if len(kept) == limit {
            break;
        }
    }
    return kept;
}

def lead_sentence(
    req: AdvRequest, result: TallyResult, votes: dict[str, Vote], n_participants: int
) -> str {
    rec = result.recommendation;
    what = clip(req.option_summary(rec), 160);
    if result.basis == "unanimous" {
        return f"All {result.valid_votes} voting roles favour '{rec}' ({what}).";
    }
    if result.basis == "plurality" {
        n_for = result.counts.get(rec, 0);
        dissent = [
            f"{role} voted '{votes[role].choice}'" for role in votes
            if votes[role].choice != rec
        ];
        return (
            f"{n_for} of {result.valid_votes} voting roles favour '{rec}' ({what}); "
            + "; ".join(dissent) + "."
        );
    }
    if result.basis == "tie-default" {
        return (
            f"The vote was tied for first place, so there is no consensus; "
            + f"the request's default '{rec}' ({what}) is recommended."
        );
    }
    if result.basis == "no-quorum-default" {
        return (
            f"Only {result.valid_votes} of {n_participants} roles cast a valid vote "
            + f"(more than half are required); the request's default '{rec}' ({what}) stands."
        );
    }
    return (
        f"'{result.winner}' won the vote but was flagged unsafe by the safety review; "
        + f"the request's default '{rec}' ({what}) is recommended."
    );
}

def approval_line(req: AdvRequest, rec: str) -> str {
    by = fmt_ts(req.decide_by);
    if rec == req.default_choice {
        return f"No change recommended: the default '{rec}' stands unless a human overrides it before {by}.";
    }
    return f"A human must approve '{rec}' before {by}; otherwise the default '{req.default_choice}' stands.";
}

# Safety issues, plus the risks the supporters of the recommended option listed.
def gather_risks(positions: list[Position], critiques: list[SafetyReview], rec: str) -> list[str] {
    out: list[str] = [];
    for c in critiques {
        for issue in c.issues {
            out.append(clip(issue, 300));
        }
    }
    latest: dict[str, Position] = {};
    for p in positions {
        latest[p.role] = p;   # later rounds overwrite earlier ones
    }
    for role in latest {
        if latest[role].choice == rec {
            for r in latest[role].risks {
                out.append(clip(r, 300));
            }
        }
    }
    return dedupe(out, MAX_RISKS);
}

def gather_actions(req: AdvRequest, rec: str, critiques: list[SafetyReview]) -> list[str] {
    out: list[str] = [approval_line(req, rec)];
    for c in critiques {
        for rc in c.cases {
            out.append(clip(f"{rc.scenario}: {rc.mitigation}", 300));
        }
    }
    return dedupe(out, MAX_ACTIONS);
}

def votes_json(votes: dict[str, Vote]) -> dict {
    out: dict = {};
    for role in votes {
        b = votes[role];
        out[role] = {"choice": b.choice, "rationale": b.rationale, "confidence": b.confidence};
    }
    return out;
}

def build_recommendation(
    req: AdvRequest,
    result: TallyResult,
    votes: dict[str, Vote],
    positions: list[Position],
    critiques: list[SafetyReview],
    abstained: list[dict[str, str]],
    notes: list[str],
    participants: list[str],
    rounds: int,
    briefing: str,
    now: datetime
) -> dict {
    rec = result.recommendation;
    summary = lead_sentence(req, result, votes, len(participants));
    if briefing != "" {
        summary = clip(summary + " " + briefing, 1500);
    }
    process: dict = {
        "basis": result.basis,
        "rounds": rounds,
        "participants": participants
    };
    if len(abstained) > 0 {
        process["abstained"] = abstained;
    }
    if len(notes) > 0 {
        process["notes"] = notes[:MAX_NOTES];
    }
    return {
        "version": "ADV-1",
        "kind": "advisory-recommendation",
        "timestamp": fmt_ts(now),
        "requestId": req.id,
        "recommendation": rec,
        "summary": summary,
        "risks": gather_risks(positions, critiques, rec),
        "nextActions": gather_actions(req, rec, critiques),
        "votes": votes_json(votes),
        "process": process,
        "requiresHumanApproval": True
    };
}
