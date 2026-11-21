#!/usr/bin/env python3
"""Validate ADV-1 advisory packets against schemas/, plus the cross-field
rules JSON Schema cannot express (see jac/roundtable/adv1_contract.py for the
full list and the vote-tally rule a recommendation is audited against).

Usage: python tools/validate.py [FILE ...] [--request REQUEST.json]
With no files, validates everything in examples/. A recommendation is checked
against its request: --request, else the sibling file with "recommendation"
replaced by "request" in its name.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "jac"))
from roundtable.adv1_contract import SCHEMAS, check  # noqa: E402,F401  (check is re-exported)


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
