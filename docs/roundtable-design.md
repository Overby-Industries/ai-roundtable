# Roundtable Design — Target Architecture

This describes where this repo is headed, not what's built yet. See
[`README.md`](../README.md) for what actually runs today (a single-agent
multi-provider chat graph, migrated from an earlier prototype).

The design below is distilled from exploratory design work done before this
repo existed (an AI-assisted scaffolding session for the earlier prototype).
That source material was a full chat-assistant scaffold -- FastAPI server,
GraphQL, a Discord bot, community "awards/badges" gamification. None of that
is relevant here and none of it is being carried over. What's worth keeping
is the underlying graph shape and deliberation flow, re-themed for fleet
decision support instead of a chat assistant.

## Graph model

```
node Agent {
    role: str            // e.g. "Logistics Officer", "Safety Officer"
    provider: str         // which LLM backend this agent calls
    model: str
    system_prompt: str    // persona / role framing
    temperature: float
}

node RoundtableSession {
    id: str
    question: str
    context: str
    topic: str
    round_idx: int
    transcripts: list      // per-round agent output
    proposals: list        // consolidated, deduplicated proposals
    votes: dict            // role -> {choice_id, rationale, confidence}
    participants: list     // refs to Agent
    summary: str
}

edge participates {}       // RoundtableSession -> Agent
```

Agents are graph nodes, not hardcoded personas -- the same node type is
configured differently per role. Adding a role is a config change, not new
`.jac` code.

## Deliberation flow

1. **`start_session`** -- spawns (or reuses) the configured `Agent` nodes,
   creates a `RoundtableSession`, links participants via `participates`.
   Supports an optional `participant_roles` subset so a session doesn't have
   to involve every agent (e.g. a routing question doesn't need a resource
   economist).
2. **`roundtable_deliberate`** (repeated per round) -- calls
   `agent_deliberate` for every participant. Each agent gets the question,
   context, and a digest of the *previous* round's transcripts, and returns
   structured JSON: `{proposal, rationale, risks, confidence, references}`.
   Proposals are then consolidated (grouped by similarity) into a
   deduplicated `sess.proposals` list.
3. **`critique_phase`** (after round 1 only) -- a dedicated critic role
   (the earlier prototype called it "Test Engineer"; for fleet use this
   should be a **Safety Officer** role) reviews the consolidated proposals
   for edge cases and failure modes, returning
   `{issues, test_matrix: [{case, risk, mitigation}]}`. This is deliberately
   a distinct role from the proposers, not a self-critique step.
4. **`vote_round`** -- every participant votes on the final proposal set,
   returning `{choice_id, rationale, confidence}`.
5. **Summary** -- a closing pass produces the human-facing briefing:
   `{exec_summary, decision, risks, next_actions, comm_plan}`. (The
   prototype's version also produced "awards" for a community-recognition
   feature -- that's chat-app-specific and dropped here.)

## Fleet-appropriate roles (replacing the prototype's civic/community set)

The prototype's default roles (drawn from a general-purpose civic assistant)
don't map to fleet decisions. A starting role set for Tier 1 fleet
deliberation -- **not finalized, needs real review before use**:

- **Logistics Officer** -- task/resource sequencing across pods.
- **Safety Officer** -- the critique-phase role; explicitly tasked with
  finding failure modes in other agents' proposals, not proposing itself.
- **Resource Economist** -- tradeoffs between competing resource claims
  (e.g. which site gets a refinery pod next).
- **Navigation/Comms Officer** -- feasibility given light-delay and current
  fleet positions.

This list is a starting point for the "what agent roles make sense" open
question in
[`starlifter-os/docs/ai-advisory-layer-draft.md`](https://github.com/Overby-Industries/starlifter-os/blob/main/docs/ai-advisory-layer-draft.md#not-decided-yet),
not a final answer.

## What's explicitly out of scope here

- **Tier 0 (time-critical hazard response).** This entire roundtable
  pattern is Tier 1 only -- deliberative, minutes-to-hours decisions. It
  never sits in the path of a time-critical physical threat (incoming
  debris, containment failure). See `ai-advisory-layer-draft.md` for why
  that split exists and why Tier 0 is deliberately *not* an AI decision at
  all, fast or slow.
- **Any pod-local safety/fault response.** This layer runs at the
  coordinator/ground tier, never on a pod, per the same design doc.
- The prototype's web/API/Discord-bot wrapper layer, and its
  community-gamification features (contributors, badges, awards). Neither
  is relevant to fleet decision support.

## Status: built, and where it differs from the design above

The engine in `jac/roundtable/` implements the graph model, rounds, the
critique phase, the vote and the summary. It has been exercised only against
scripted models, not a live provider. See [`adv1.md`](adv1.md) for how it
behaves. Where it deliberately departs from the sketch above:

- **Agents choose among the request's options; they do not invent proposals.**
  The ADV-1 request enumerates the options, so there is no consolidation or
  de-duplication step, and nothing an agent writes can become an action the
  requester did not list.
- **The vote is decided by a deterministic tally, not by a model.** Quorum,
  a confidence tie-break, and a fallback to the request's default are fixed
  rules (`tally.jac`), re-derived independently by `adv1_contract.py`.
- **The Safety Officer can block, but only toward the default.** A flagged
  winner is replaced by the requester's default; the critic cannot push the
  outcome to any other option.
- **The summary is partly deterministic.** Its first sentence is built from
  the tally; a model's prose follows it.
- **A session is a detached, per-run graph.** It is not attached to Jac's
  `root`, so no request or answer is persisted between runs.
- **Roles live in a roster file** (`config/roster.example.json`), as designed,
  with an optional `topics` list per role to pick who sits on which question.

Still open: running against live providers and tuning the prompts, a reviewed
role set (the roles in the example roster are placeholders), serving the engine
(`jac serve`), and a path for a human approval to flow back to the requester.
