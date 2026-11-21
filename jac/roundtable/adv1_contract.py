"""ADV-1 contract checks: JSON Schema validation plus the cross-field rules
JSON Schema cannot express.

One implementation shared by tools/validate.py (the CLI), the tests, and the
Jac engine, which runs `check` on its own output as a last gate before
emitting a recommendation.

The recommendation checks also re-derive the outcome of the vote from the
votes the recommendation reports, using the tally rule below. The engine's
Jac tally (jac/roundtable/tally.jac) is a separate implementation of the same
rule, so each one audits the other:

  1. A vote is valid if its choice is one of the request's options and its
     confidence is within [0, 1]. Invalid votes are not counted; the role is
     listed under process.abstained.
  2. Quorum: strictly more than half of the participants cast a valid vote.
     Without one, the recommendation is the request's defaultChoice
     ("no-quorum-default").
  3. The option with the most votes wins; equal counts are broken by the sum
     of the voters' confidences. A remaining tie yields the default
     ("tie-default").
  4. A winner other than the default that the safety critic flagged as unsafe
     is replaced by the default ("safety-block-default"). The critic can only
     move the outcome toward the requester's default, never away from it.
  5. Otherwise the winner is recommended: "unanimous" if every valid vote
     agreed, else "plurality".
"""
import json
from datetime import datetime
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = {
    "advisory-request": ROOT / "schemas" / "advisory-request.schema.json",
    "advisory-recommendation": ROOT / "schemas" / "advisory-recommendation.schema.json",
}
FALLBACK_BASES = ("tie-default", "no-quorum-default", "safety-block-default")
TIE_EPS = 1e-9


def _ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def tally(votes):
    """Per-choice vote counts and confidence sums over {role: {choice, confidence}}."""
    counts, conf = {}, {}
    for v in votes.values():
        c = v["choice"]
        counts[c] = counts.get(c, 0) + 1
        conf[c] = conf.get(c, 0.0) + v["confidence"]
    return counts, conf


def leaders(votes):
    """Choices tied for first place by (count, confidence sum); one entry = clear winner."""
    counts, conf = tally(votes)
    if not counts:
        return []
    top = max(counts.values())
    tied = [c for c in counts if counts[c] == top]
    best = max(conf[c] for c in tied)
    return sorted(c for c in tied if abs(conf[c] - best) <= TIE_EPS)


def _check_recommendation(doc, request):
    problems = []
    proc = doc["process"]
    votes = doc["votes"]
    participants = proc["participants"]
    voted = set(votes)
    abstained = [a["role"] for a in proc.get("abstained", [])]

    if not voted <= set(participants):
        problems.append("votes include roles that are not in process.participants")
    if len(abstained) != len(set(abstained)) or set(abstained) & voted:
        problems.append("a role appears twice across votes and process.abstained")
    if voted | set(abstained) != set(participants):
        problems.append("every participant must appear exactly once in votes or process.abstained")

    basis = proc["basis"]
    rec = doc["recommendation"]
    default = request["defaultChoice"] if request else None

    if basis in FALLBACK_BASES and default is not None and rec != default:
        problems.append(f"basis {basis} requires the recommendation to be the request's defaultChoice")

    quorum = len(votes) * 2 > len(participants)
    if basis == "no-quorum-default":
        if quorum:
            problems.append("basis is no-quorum-default but a quorum voted")
    elif not quorum:
        problems.append(f"basis {basis} needs a quorum of valid votes, which is missing")
    else:
        lead = leaders(votes)
        if basis == "tie-default":
            if len(lead) < 2:
                problems.append("basis is tie-default but the votes have a clear leader")
        elif len(lead) > 1:
            problems.append("the votes are tied, so the basis must be tie-default")
        else:
            winner = lead[0]
            if basis == "safety-block-default":
                if default is not None and winner == default:
                    problems.append("basis is safety-block-default but the vote winner already is the default")
            else:
                unanimous = len({v["choice"] for v in votes.values()}) == 1
                if rec != winner:
                    problems.append("the recommendation is not the vote winner")
                if (basis == "unanimous") != unanimous:
                    problems.append(f"basis {basis} does not match the votes")

    if request is not None:
        ids = {o["id"] for o in request["options"]}
        if doc["requestId"] != request["id"]:
            problems.append("requestId does not match the request")
        if rec not in ids:
            problems.append("recommendation is not one of the request's options")
        for role, vote in votes.items():
            if vote["choice"] not in ids:
                problems.append(f"vote by {role!r} is not one of the request's options")
        if _ts(doc["timestamp"]) < _ts(request["timestamp"]):
            problems.append("recommendation timestamp is earlier than the request's")
        if _ts(doc["timestamp"]) > _ts(request["decideBy"]):
            problems.append("recommendation is later than the request's decideBy")
    return problems


def check(doc, request=None):
    """Return a list of problems (empty means valid).

    `request` (a parsed advisory-request) enables the checks that compare a
    recommendation against the request it answers.
    """
    kind = doc.get("kind")
    if kind not in SCHEMAS:
        return [f"unknown kind {kind!r}"]
    schema = json.loads(SCHEMAS[kind].read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    problems = [f"{'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in validator.iter_errors(doc)]
    if problems:
        return problems
    if kind == "advisory-request":
        ids = {o["id"] for o in doc["options"]}
        if len(ids) != len(doc["options"]):
            problems.append("options: duplicate ids")
        if doc["defaultChoice"] not in ids:
            problems.append("defaultChoice is not one of options[].id")
        if _ts(doc["decideBy"]) <= _ts(doc["timestamp"]):
            problems.append("decideBy must be later than timestamp")
    else:
        problems.extend(_check_recommendation(doc, request))
    return problems
