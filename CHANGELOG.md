# Changelog

Every change a person using this gem would notice. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); nothing is versioned yet, because a
version number is the human's call.

## [Unreleased]

### Added

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
