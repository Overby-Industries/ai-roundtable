# jac/roundtable_cli.jac
# Command line for one roundtable session.
#
#   jac run jac/roundtable_cli.jac --request REQUEST.json --roster ROSTER.json \
#       [--out RECOMMENDATION.json] [--roles "Role A,Role B"] [--rounds N] \
#       [--min-deliberation SECONDS] [--now 2026-11-21T12:00:00Z] [--dry-run]
#
# The recommendation (ADV-1 JSON) goes to stdout, and to --out if given.
# Messages go to stderr. --dry-run validates the request, seats the roster and
# prints the plan, including how many LLM calls the session would make,
# without calling any model. --now replays a request against a fixed clock.
#
# Exit codes: 0 a recommendation was produced (it may still be a fallback to the
# request's default; see "process.basis" and the warning on stderr),
# 2 no recommendation (declined, expired or failed; the default stands),
# 64 bad usage, 65 unreadable or invalid input file.

import json;
import os;
import sys;
import from roundtable.clock { Clock }
import from roundtable.engine { Outcome, Plan, RunConfig, plan_session, run_session }
import from roundtable.roster { Roster, load_roster }
import from roundtable.spec { parse_ts }

def eprint(msg: str) -> None {
    os.write(2, (msg + "\n").encode("utf-8"));
}

def parse_args(argv: list[str]) -> dict[str, str] {
    opts: dict[str, str] = {};
    i = 0;
    while i < len(argv) {
        a = argv[i];
        if a == "--dry-run" {
            opts["dry-run"] = "1";
        } elif a.startswith("--") and i + 1 < len(argv) {
            opts[a[2:]] = argv[i + 1];
            i += 1;
        } else {
            raise ValueError(f"unexpected argument: {a}");
        }
        i += 1;
    }
    return opts;
}

def load_json(path: str) -> dict {
    with open(path, "r", encoding="utf-8") as f {
        return dict(json.load(f));
    }
}

def plan_json(plan: Plan) -> dict {
    return {
        "ok": plan.ok,
        "reasons": plan.reasons,
        "participants": [s.spec.role for s in plan.seats],
        "rounds": plan.rounds,
        "llm_calls": plan.llm_calls
    };
}

def main(argv: list[str]) -> int {
    try {
        opts = parse_args(argv);
    } except ValueError as e {
        eprint(str(e));
        return 64;
    }
    if "request" not in opts or "roster" not in opts {
        eprint("usage: jac run jac/roundtable_cli.jac --request FILE --roster FILE [--out FILE] [--roles A,B] [--rounds N] [--min-deliberation S] [--now TS] [--dry-run]");
        return 64;
    }
    try {
        request_doc = load_json(opts["request"]);
        roster = load_roster(opts["roster"]);
    } except Exception as e {
        eprint(f"cannot read input: {e.__class__.__name__}: {e}");
        return 65;
    }

    cfg = RunConfig(rounds=roster.rounds, min_participants=roster.min_participants);
    try {
        if "rounds" in opts {
            cfg.rounds = int(opts["rounds"]);
        }
        if "min-deliberation" in opts {
            cfg.min_deliberation_s = int(opts["min-deliberation"]);
        }
    } except ValueError {
        eprint("--rounds and --min-deliberation take whole numbers");
        return 64;
    }
    if "roles" in opts {
        cfg.participant_roles = [r.strip() for r in opts["roles"].split(",") if r.strip() != ""];
    }
    clock = Clock();
    if "now" in opts {
        clock = Clock(fixed=parse_ts(opts["now"]));
    }

    if "dry-run" in opts {
        plan = plan_session(request_doc, roster, cfg, clock);
        print(json.dumps(plan_json(plan), indent=2));
        return 0 if plan.ok else 2;
    }

    outcome = run_session(request_doc, roster, cfg, clock);
    rec = outcome.recommendation;
    if rec is None {
        eprint(f"no recommendation ({outcome.status}); the request's default stands.");
        for reason in outcome.reasons {
            eprint("  - " + reason);
        }
        return 2;
    }
    text = json.dumps(rec, indent=2);
    if "out" in opts {
        with open(opts["out"], "w", encoding="utf-8") as f {
            f.write(text + "\n");
        }
    }
    print(text);
    basis = rec["process"]["basis"];
    if basis in ["tie-default", "no-quorum-default", "safety-block-default"] {
        eprint(f"warning: this is a fallback to the request's default ({basis}); see process in the output.");
    }
    return 0;
}

with entry:__main__ {
    sys.exit(main(sys.argv[1:]));
}
