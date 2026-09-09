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
