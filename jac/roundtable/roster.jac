# jac/roundtable/roster.jac
# Who sits at the table. A roster is a JSON file (config/roster.example.json):
# roles, the model behind each, and their briefs are configuration, so adding
# a role or swapping a provider needs no new Jac code. Provider API keys come
# from the environment (for example ANTHROPIC_API_KEY), never from this file.

import json;
import from byllm.lib { Model }
import from roundtable.spec { AgentSpec }
import from roundtable.brain { Brain }

obj AgentSeat {
    has spec: AgentSpec,
        brain: Brain;
}

obj Roster {
    has seats: list[AgentSeat],
        briefer: AgentSeat | None = None,
        rounds: int = 2,
        min_participants: int = 3;
}

def make_brain(spec: AgentSpec) -> Brain {
    return Brain(model=Model(
        model_name=spec.model_name, call_params={"temperature": spec.temperature}
    ));
}

def spec_from_dict(d: dict, defaults: dict) -> AgentSpec {
    for key in ["role", "brief"] {
        if key not in d or not isinstance(d[key], str) or d[key].strip() == "" {
            raise ValueError(f"roster: every agent needs a non-empty '{key}'");
        }
    }
    model_name = str(d.get("model", defaults.get("model", "")));
    if model_name == "" {
        raise ValueError(f"roster: no model for role '{d['role']}' and no default model");
    }
    return AgentSpec(
        role=str(d["role"]),
        brief=str(d["brief"]),
        model_name=model_name,
        temperature=float(str(d.get("temperature", defaults.get("temperature", 0.2)))),
        critic=bool(d.get("critic", False)),
        topics=[str(t) for t in d.get("topics", [])]
    );
}

def roster_from_dict(doc: dict) -> Roster {
    defaults = dict(doc.get("defaults", {}));
    specs = [spec_from_dict(dict(a), defaults) for a in doc.get("agents", [])];
    roles = [s.role for s in specs];
    if len(set(roles)) != len(roles) {
        raise ValueError("roster: role names must be unique");
    }
    briefer: AgentSeat | None = None;
    if "briefer" in doc {
        bspec = spec_from_dict(
            {"role": "Briefer", **dict(doc["briefer"])}, defaults
        );
        briefer = AgentSeat(spec=bspec, brain=make_brain(bspec));
    }
    return Roster(
        seats=[AgentSeat(spec=s, brain=make_brain(s)) for s in specs],
        briefer=briefer,
        rounds=int(doc.get("rounds", 2)),
        min_participants=int(doc.get("min_participants", 3))
    );
}

def load_roster(path: str) -> Roster {
    with open(path, "r", encoding="utf-8") as f {
        return roster_from_dict(dict(json.load(f)));
    }
}
