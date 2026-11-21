# jac/roundtable/spec.jac
# Data types for the roundtable engine. No LLM calls and no graph in here.
#
# These are the engine's own types: the request, the roster, and what it keeps
# once an LLM answer has been checked (Position, Vote, SafetyReview). The shapes
# an LLM is asked to return (AgentTake, Critique, Ballot) live in brain.jac, in
# the same module as the `by` functions that return them: byllm 0.6 cannot build
# a response schema for a type imported from another module.

import from datetime { datetime }

def parse_ts(s: str) -> datetime {
    return datetime.fromisoformat(s.replace("Z", "+00:00"));
}

obj OptionSpec {
    has id: str,
        summary: str;
}

# One ADV-1 advisory-request, already validated by adv1_contract.check().
obj AdvRequest {
    has id: str,
        source_id: str,
        topic: str,
        question: str,
        context: dict,
        options: list[OptionSpec],
        default_choice: str,
        issued: datetime,
        decide_by: datetime;

    def option_ids() -> list[str] {
        return [o.id for o in self.options];
    }

    def option_summary(option_id: str) -> str {
        for o in self.options {
            if o.id == option_id {
                return o.summary;
            }
        }
        return "";
    }

    def options_text() -> str {
        return "\n".join([f"- {o.id}: {o.summary}" for o in self.options]);
    }
}

# Explicit str()/dict() conversions: the JSON is already schema-validated, and
# they give jac check concrete types to work with.
def request_from_dict(doc: dict) -> AdvRequest {
    return AdvRequest(
        id=str(doc["id"]),
        source_id=str(doc["source"]["id"]),
        topic=str(doc["topic"]),
        question=str(doc["question"]),
        context=dict(doc.get("context", {})),
        options=[
            OptionSpec(id=str(o["id"]), summary=str(o["summary"])) for o in doc["options"]
        ],
        default_choice=str(doc["defaultChoice"]),
        issued=parse_ts(str(doc["timestamp"])),
        decide_by=parse_ts(str(doc["decideBy"]))
    );
}

# A seat at the table. Roles are configuration, not code: adding one is a new
# entry in the roster file (config/roster.example.json).
obj AgentSpec {
    has role: str,
        brief: str,
        model_name: str,
        temperature: float = 0.2,
        critic: bool = False,
        topics: list[str] = [];

    # An empty `topics` list means the role sits on every topic.
    def covers(topic: str) -> bool {
        return len(self.topics) == 0 or topic in self.topics;
    }
}

# One role's recorded position in one deliberation round, after the engine has
# checked it (the choice is a real option, the confidence is in range).
obj Position {
    has round_idx: int,
        role: str,
        choice: str,
        rationale: str,
        confidence: float,
        risks: list[str];
}

# One role's final vote, after the engine has checked it.
obj Vote {
    has choice: str,
        rationale: str,
        confidence: float;
}

obj RiskRow {
    has scenario: str,
        risk: str,
        mitigation: str;
}

# A safety critic's findings, after the engine has dropped any block that names
# something that is not an option.
obj SafetyReview {
    has issues: list[str],
        blocks: list[str],
        cases: list[RiskRow];
}
