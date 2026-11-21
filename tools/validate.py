#!/usr/bin/env python3
"""Validate ADV-1 advisory packets against schemas/, plus the cross-field
rules JSON Schema cannot express:

  * a request's defaultChoice is one of its options
  * decideBy is later than timestamp
  * a recommendation's choice (and every vote) is one of the request's
    options, when the matching request is available

Usage: python tools/validate.py [FILE ...] [--request REQUEST.json]
With no files, validates everything in examples/.
"""
import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = {
    "advisory-request": ROOT / "schemas" / "advisory-request.schema.json",
    "advisory-recommendation": ROOT / "schemas" / "advisory-recommendation.schema.json",
}


def _ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def check(doc, request=None):
    """Return a list of problems (empty means valid)."""
    kind = doc.get("kind")
    if kind not in SCHEMAS:
        return [f"unknown kind {kind!r}"]
    schema = json.loads(SCHEMAS[kind].read_text(encoding="utf-8"))
    v = jsonschema.Draft202012Validator(schema)
    problems = [f"{'/'.join(map(str, e.path)) or '<root>'}: {e.message}" for e in v.iter_errors(doc)]
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
    elif request is not None:
        ids = {o["id"] for o in request["options"]}
        if doc["requestId"] != request["id"]:
            problems.append("requestId does not match the request")
        if doc["recommendation"] not in ids:
            problems.append("recommendation is not one of the request's options")
        for role, vote in doc["votes"].items():
            if vote["choice"] not in ids:
                problems.append(f"vote by {role!r} is not one of the request's options")
    return problems


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--request")
    args = ap.parse_args(argv)
    request = json.loads(Path(args.request).read_text(encoding="utf-8")) if args.request else None
    files = [Path(f) for f in args.files] or sorted((ROOT / "examples").glob("*.json"))
    bad = 0
    for f in files:
        doc = json.loads(f.read_text(encoding="utf-8"))
        req = request
        if req is None and doc.get("kind") == "advisory-recommendation":
            sibling = f.with_name(f.name.replace("recommendation", "request"))
            if sibling.exists():
                req = json.loads(sibling.read_text(encoding="utf-8"))
        problems = check(doc, req)
        print(("FAIL " if problems else "OK   ") + str(f))
        for p in problems:
            print("  " + p)
        bad += bool(problems)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
