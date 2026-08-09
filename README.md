# ai-roundtable

**Overby Industries — multi-agent AI deliberation layer, built in Jaseci/Jac.**

This is the **Tier 1 (Deliberative Advisory)** layer described in
[`starlifter-os/docs/ai-advisory-layer-draft.md`](https://github.com/Overby-Industries/starlifter-os/blob/main/docs/ai-advisory-layer-draft.md):
a multi-agent "roundtable" that debates non-urgent fleet decisions
(resource-allocation conflicts, task prioritization, mission replanning) and
proposes a recommendation for human review. It is explicitly **not** part of
any safety-critical or time-critical response path -- see that doc for why
time-critical hazards (incoming debris, containment failure) are handled by
a separate, deterministic Tier 0 policy instead, with no AI or human
approval step in that loop.

## Status: early -- working chat graph, roundtable not yet built

What exists today is a working Jaseci graph migrated from an earlier
personal prototype (`ai-chat-network`): a walker that picks one LLM provider
and holds a single-agent conversation through a small node graph. It's a
correct, verified Jaseci program, and it's a genuinely useful base to build
from -- but it is **not yet** the multi-agent roundtable (multiple agents,
deliberation rounds, critique, voting) that this repo exists to build.

See [`docs/roundtable-design.md`](docs/roundtable-design.md) for the target
architecture and what's left to build.

## What's here

```
jac/
  ai-walkers/          # one walker per LLM provider (groq, anthropic, openai,
                        # together, ollama, huggingface) -- each delegates a
                        # response to that provider via Jac's `by <provider>()`
                        # ability syntax
  human-walkers/        # a human-in-the-loop conversational variant
  multi-chat-node/      # small node/edge graph example (many-to-one topology)
docs/
  roundtable-design.md  # target architecture for the actual roundtable
```

Only the Jaseci/Jac engine came over from the original prototype. Its
Next.js chat UI and websocket relay server did not -- they were a chat
front-end, not part of the fleet decision-support problem this repo solves.

## Relationship to other repos

- **[`starlifter-os`](https://github.com/Overby-Industries/starlifter-os)**
  owns the Tier 0/Tier 1 boundary and the fleet coordinator this layer
  advises. Read that repo's `docs/ai-advisory-layer-draft.md` first --
  it's the reason this repo has the shape it does.
- **[`telemetry-protocol`](https://github.com/Overby-Industries/telemetry-protocol)**
  (OTF-1) is the likely source of the fleet-state context a roundtable
  session would reason over.
- **[`miner-automation`](https://github.com/Overby-Industries/miner-automation)**
  and **[`satnav-swarm`](https://github.com/Overby-Industries/satnav-swarm)**
  are examples of fleets whose non-urgent coordination questions this layer
  is meant to support -- not control.

## Running the existing walkers

Requires [`jaclang`](https://pypi.org/project/jaclang/) and
[`byllm`](https://pypi.org/project/byllm/) (the original prototype used
`mtllm`, which is now deprecated in favor of `byllm` upstream -- this repo
was ported to current jaclang/byllm syntax, not just copied over as-is),
plus an API key for whichever provider you're testing against (set as an
environment variable, e.g. `GROQ_API_KEY` -- never commit a `.env` file to
this repo):

```bash
pip install jaclang byllm
jac check jac/ai-walkers/ai_walker_groq.jac   # type-check, no API key needed
jac run jac/ai-walkers/ai_walker_groq.jac     # actually chat -- needs GROQ_API_KEY
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Jaseci/Jac experience is niche --
if you know it, this is a good repo to help with.

## License

[Apache 2.0](LICENSE).
