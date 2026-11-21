import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import validate  # noqa: E402

REQ = json.loads((ROOT / "examples/dock-contention-request.json").read_text())
REC = json.loads((ROOT / "examples/dock-contention-recommendation.json").read_text())


def test_examples_valid():
    assert validate.check(REQ) == []
    assert validate.check(REC, REQ) == []


def test_default_choice_must_be_an_option():
    bad = copy.deepcopy(REQ)
    bad["defaultChoice"] = "nope"
    assert any("defaultChoice" in p for p in validate.check(bad))


def test_urgent_requests_rejected():
    bad = copy.deepcopy(REQ)
    bad["urgency"] = "immediate"
    assert validate.check(bad)


def test_decide_by_must_follow_timestamp():
    bad = copy.deepcopy(REQ)
    bad["decideBy"] = bad["timestamp"]
    assert any("decideBy" in p for p in validate.check(bad))


def test_recommendation_must_match_request_options():
    bad = copy.deepcopy(REC)
    bad["recommendation"] = "other"
    assert any("recommendation" in p for p in validate.check(bad, REQ))
    bad = copy.deepcopy(REC)
    bad["votes"]["Safety Officer"]["choice"] = "other"
    assert any("vote" in p for p in validate.check(bad, REQ))


def test_recommendation_can_never_be_binding():
    bad = copy.deepcopy(REC)
    bad["requiresHumanApproval"] = False
    assert validate.check(bad, REQ)
