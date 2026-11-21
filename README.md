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

## Status: early -- the roundtable engine runs, verified against scripted models only

The roundtable engine in [`jac/roundtable/`](jac/roundtable/) takes a
non-urgent fleet question as an ADV-1 advisory request, seats a roster of
agents, runs rounds of proposals, a safety review and a vote, and returns an
ADV-1 recommendation for a human to approve. See
[`docs/adv1.md`](docs/adv1.md) for how it decides and what it guarantees.

**It has not been run against a live LLM provider.** Its tests run the whole
engine (graph, walkers, tally, report) against byllm's scripted `mockllm`
model. The prompts in [`brain.jac`](jac/roundtable/brain.jac) and the roles in
[`config/roster.example.json`](config/roster.example.json) are first drafts
that need real review before anyone relies on them.

The original single-agent chat walkers, migrated from an earlier personal
prototype (`ai-chat-network`), are still here and unchanged.
[`docs/roundtable-design.md`](docs/roundtable-design.md) is the design the
engine follows, and notes where it deliberately differs.

## What's here

```
jac/
  roundtable/          # the engine: graph + walkers (graph.jac), vote rule
                        # (tally.jac), LLM prompts (brain.jac), roster loader,
                        # report builder, and adv1_contract.py (see below)
  roundtable_cli.jac   # command line: jac run jac/roundtable_cli.jac ...
  ai-walkers/          # one walker per LLM provider (groq, anthropic, openai,
                        # together, ollama, huggingface) -- each delegates a
                        # response to that provider via Jac's `by <provider>()`
                        # ability syntax
  human-walkers/        # a human-in-the-loop conversational variant
  multi-chat-node/      # small node/edge graph example (many-to-one topology)
schemas/                # ADV-1 advisory-request / advisory-recommendation
examples/               # a request and the recommendation that answers it
config/                 # example roster: roles, briefs, models
tools/validate.py       # validates ADV-1 files and audits a recommendation
tests/                  # schema tests + end-to-end engine tests
docs/
  adv1.md               # how the engine decides; guarantees and limits
  roundtable-design.md  # target architecture, and where the engine differs
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

## Running the roundtable

```bash
pip install -r jac/requirements.txt
export PYTHONPATH=jac     # PowerShell: $env:PYTHONPATH = "jac" -- lets jac check/test resolve `roundtable.*`

# Who would be seated and how many model calls it would make. No model is called.
# (--now replays the example request, which is stamped 2026-11-21T12:00Z.)
jac run jac/roundtable_cli.jac --request examples/dock-contention-request.json \
    --roster config/roster.example.json --now 2026-11-21T12:00:00Z --dry-run

# For real: needs a provider key for the models named in the roster
# (the example uses Anthropic, so ANTHROPIC_API_KEY). Never commit keys.
jac run jac/roundtable_cli.jac --request REQUEST.json \
    --roster config/roster.example.json --out recommendation.json
```

The recommendation is ADV-1 JSON on stdout (and in `--out`). Exit code 0 means
one was produced -- it can still be a fallback to the request's default, which
is flagged on stderr and in `process.basis`; 2 means none was produced
(request not deliberable, out of time); 64/65 are usage and input errors.

```bash
python tools/validate.py                          # schemas, examples, cross-field rules
jac check jac/roundtable                          # type check the engine...
jac check jac/roundtable_cli.jac                  # ...and the CLI (separately: jac check mistakes
                                                  # one Roster type for two if given both at once)
jac test jac/roundtable/tally.jac                 # native tests of the vote rule
python -m pytest                                  # end to end against scripted models
```

## Fleet integration (ADV-1)

Requests are produced by [`outpost-core`](https://github.com/Overby-Industries/outpost-core)
today (docking contention) and are checked here against the same schema. A
request always carries a `defaultChoice` that stands if no human approves in
time, and a recommendation is schema-locked to `requiresHumanApproval: true`,
so the fleet is never blocked on, or bound by, the roundtable.
[`design-studies`](https://github.com/Overby-Industries/design-studies) runs the
two together end to end.

## Known limits

- Never run against a live provider (see Status). Provider failures are
  contained -- a failed call is a missing vote, not a crash -- but real
  models may behave in ways the scripted ones do not.
- byllm 0.6 cannot build a response schema for a return type imported from
  another module, so the LLM-facing types live in `brain.jac` beside the
  methods that return them. If you move them, every call will fail and the
  engine will degrade to "no quorum" -- the tests catch this.
- Sessions are in-memory and stateless by design: the graph is never attached
  to Jac's `root`, so no request or answer is written to disk. (Jac still
  creates `.jac/data/<script>.db` holding only its empty root node; `.jac/` is
  git-ignored.) Attaching a session to `root` would persist it there.
- Sequential, in-process, one session per run. No `jac serve` wiring yet.
