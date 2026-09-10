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
- The prompt as named blocks in two regions: `identity` · `knowledge` · `tools` (static, cached),
  the history, `view` (dynamic). `prompt static: %i[faq], dynamic: %i[availability]` adds a
  class's own, one template each at `views/<slug>/<name>.erb`; the bridge sends each block by
  name and only when its text changed, and a static block that reads the state is refused at
  render. `Pinecall.render` returns `Blocks` (`[:name]`, `static`, `dynamic`, `instructions`);
  `pinecall prompt` prints one section per block. In a test, `call.block("availability")`.
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
  now sends the file whole (`{path, text}`) and is refused at load when the file is not beside
  the class; `docs "clinica-norte"` (or `docs base:, mode:, k:, min_score:`) names the base the
  `retrieved` marker searches, and a path or a glob is refused with the command that makes a
  base; `memory remember:, forget:` travels as the wire's `MemoryConfig`, checked at load.
- The marker payloads pinned: `memory kinds:, limit:` and `retrieved k:, min_score:`, snake_case
  as typed. The example's view puts each under its heading, and asks for memory with a bare
  `<%= memory %>`: a fact is filed under the word the class remembers it by, so a `kinds` naming
  any other word is refused as the marker is written — `memory kinds: "preference" is not one of
  the words this class remembers (cómo prefiere que le llamen, alergias, su médico habitual)` —
  where before it matched nothing for ever while the recall looked like it worked.
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
