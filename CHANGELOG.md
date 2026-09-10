# Changelog

Every change a person using this gem would notice. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); nothing is versioned yet, because a
version number is the human's call.

## [Unreleased]

### Added
- **`hangup when: "..."`** on a class: the model may end the call itself, and you say in your own
  words when. The tool is livekit's own `end_call`, hidden while the agent is greeting, and the
  call's log gets `call.ended` with `agent_hung_up`. `hangup` alone is a declaration too, with the
  wording left to livekit. A class that says nothing cannot hang up: only the caller and a
  supervisor end a call. Clínica Norte declares one.
- **`pinecall remember [PATHS]`**, and `client.memory.extraction(slug, cases)` — the goldens
  `memory remember:` is held to, which is the write side and the half that persists. A case is one
  call already held (both speakers, in `said`), the facts memory already holds (`holds`), and what
  must come of the hang-up's one model call: which categories got a fact (`writes`), which never
  did (`never`), which values must not survive in any fact's text (`never_says`), and which held
  facts the call contradicted (`invalidates`) — its mirror included, so a model that supersedes
  whatever it touches is caught too. A case may `plants` sentences somebody tried to get into
  memory, and planting one IS the assertion that admission refuses it. Nothing asks a model whether
  two sentences mean the same thing: a category is your own word, a value is a literal, a
  supersession is an id. The class is mounted in this terminal, because the categories a case may
  name and the tool names admission refuses a fact for are the class's own declaration; the one
  model call per case runs in the gateway on the org's keys. Exits 1 when a case did not hold.
  `test/memory` beside the `agent.rb` by default; Clínica Norte ships three.
- `pinecall memory eval [GOLDEN] [--k N]`, and `client.memory.eval`: the other table's golden.
  A list of `{ "holds", "asks", "expects" }` — what memory holds about a question's contact, what
  the caller said, and the fact or facts that should come back — asked of `recall`, and `recall@k`
  and `nDCG@10` printed, computed by code with no model. No contact of the org is read or written:
  each question's facts go to a scratch contact and are deleted again, which is what makes the
  figures the real ranking. A fact answers when what came back CONTAINS what was expected, folded
  for case, accents and whitespace, because a fact is a sentence a model wrote. Names every
  question memory did not answer whole with what came back instead and exits 1 when anything did.
  Clínica Norte ships one of seven questions, eight or nine facts each.
- `pinecall knowledge eval [GOLDEN] [--base NAME] [--k N]`, and `client.knowledge.eval`: every
  question of a golden asked of the base, and `recall@k` and `nDCG@10` printed — computed by code
  with no model, so two runs answer the same numbers. Names every question it missed with what came
  back instead and exits 1 when anything did, so a base can be held to its golden in CI. Clínica
  Norte ships one. A base listing now names the embedder that wrote its vectors.

- The package itself: `Pinecall::Agent` (config on the class, state on the instance, `tool` above
  the method, the comment as the docstring), the ERB view resolved as `views/<slug>.erb`,
  `Pinecall.mount`, `Pinecall::Client`, and `pinecall/testing` — the gateway that is not there,
  which is what a ring-0 suite mounts against.
- The prompt as four named blocks in two regions: `identity` · `knowledge` · `tools` (static,
  cached), the history, `view` (dynamic). The bridge sends each block by name and only when its
  text changed. `Pinecall.render` returns `Blocks` (`[:name]`, `static`, `dynamic`,
  `instructions`); `pinecall prompt` prints one section per block. In a test,
  `call.block("knowledge")`.
- `pinecall prompt`, `pinecall run` and `pinecall whoami`. `prompt` needs no gateway, no key and
  no network.
- `pinecall-protocol`: Ruby's side of the wire, generated from the same JSON Schema as the Python
  and TypeScript packages, with the log reducer proved against the same golden fixture.
- `sig/`: the public surface as RBS, checked by `rake rbs`.
- `pinecall ui`: the console on 127.0.0.1 — the same compiled React console the TypeScript
  package builds, vendored in `console/` and served from Ruby. Loopback only, a random nonce, and
  the org key never reaching the browser; `v1/*` is forwarded from this process, streaming, so a
  log arrives over SSE as it happens.
- `rake console:build` and `rake console:check`: how the bundle gets here, and how a reader finds
  out that what is here is stale.
- `examples/clinica_norte`: a whole agent, its view, and its own ring-0 suite.
- What the agent knows, reads and remembers, on the wire. `knowledge "./knowledge/clinica.md"`
  is read beside the class, refused at load when the file is not there, and is the `knowledge`
  block whole as well as the `{path, text}` of `agent.configure`; `docs "clinica-norte"` (or
  `docs base:, mode:, k:, min_score:`) names the base and how to search it, and a path or a glob
  is refused with the command that makes a base; `memory remember:, forget:` travels as the
  wire's `MemoryConfig`, checked at load.
- **A lookup is a tool result, never a piece of the prompt.** What memory kept from an earlier
  call and what the knowledge base returned no longer travel through the view: the platform runs
  its own `recall` and `search` tools and their answers reach the model as `tool_result` blocks,
  JSON, in the history — which is where both vendors say content from outside the conversation
  belongs (`runtime/docs/security/prompt-injection.md`). So a view is now the tenant's own prose
  and conditions and nothing else: the `memory`, `retrieved` and `knowledge` template tags are
  gone, and so are the tenant-declared blocks (`prompt static:`/`dynamic:`) and the render props
  that came with them. What a view may still do with memory is ask it a question —
  `remembers?("médico habitual")`, answered by the runtime — and say a sentence of its own about
  the answer. `k` and `min_score` are declared once, on `docs`.
- `pinecall keys add VENDOR` · `rm VENDOR` · `list`: the org brings its own provider key for a
  vendor on its own API key, with no operator in it. The key is read from stdin — typed with
  nothing echoed on a terminal, one piped line off one — and never from a flag, because argv
  is visible in `ps`. `list` answers vendor names alone: no door of the runtime gives a
  provider key back. On the client: `client.provider_keys`.
- `pinecall knowledge push [DIR] --base NAME` · `list` · `drop BASE`, and `pinecall memory
  CONTACT` · `memory forget CONTACT`, on the same key every verb resolves; a refusal is printed
  as the gateway wrote it. On the client: `client.knowledge` and `client.memory_of(contact)`.
- `pinecall prompt` on a file this process already loaded finds its class instead of saying it
  declares none.
