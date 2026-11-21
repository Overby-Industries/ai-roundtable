# jac/roundtable/digest.jac
# Plain-text digests that carry one phase's results into the next phase's
# prompts, plus the clipping used everywhere LLM text enters a result.

import from roundtable.spec { Position, SafetyReview }

def clip(text: str, limit: int) -> str {
    flat = " ".join(text.split());
    if len(flat) <= limit {
        return flat;
    }
    return flat[:limit - 3] + "...";
}

def conf_text(x: float) -> str {
    return f"{x:.2f}";
}

def round_digest(positions: list[Position], round_idx: int) -> str {
    lines: list[str] = [];
    for p in positions {
        if p.round_idx == round_idx {
            lines.append(
                f"- {p.role}: {p.choice} (confidence {conf_text(p.confidence)}). "
                + clip(p.rationale, 400)
            );
        }
    }
    if len(lines) == 0 {
        return f"(no positions were recorded in round {round_idx})";
    }
    return f"Round {round_idx} positions:\n" + "\n".join(lines);
}

def critique_digest(critiques: list[SafetyReview]) -> str {
    if len(critiques) == 0 {
        return "";
    }
    lines: list[str] = ["Safety review:"];
    for c in critiques {
        for issue in c.issues {
            lines.append("- issue: " + clip(issue, 300));
        }
        if len(c.blocks) > 0 {
            lines.append("- judged unsafe to adopt: " + ", ".join(c.blocks));
        }
        for rc in c.cases {
            lines.append(
                f"- case: {clip(rc.scenario, 150)} | risk: {clip(rc.risk, 150)}"
                + f" | mitigation: {clip(rc.mitigation, 150)}"
            );
        }
    }
    return "\n".join(lines);
}

test "clip collapses whitespace and bounds length" {
    assert clip("a   b\n c", 50) == "a b c";
    assert clip("x" * 20, 10) == "xxxxxxx...";
    assert len(clip("y" * 500, 100)) == 100;
}
