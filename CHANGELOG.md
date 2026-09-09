# Changelog

Every change a person using this gem would notice. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); nothing is versioned yet, because a
version number is the human's call.

## [Unreleased]

### Added

- The package itself: `Pinecall::Agent` (config on the class, state on the instance, `tool` above
  the method, the comment as the docstring), the ERB view resolved as `views/<slug>.erb`, the
  three prompt regions, `Pinecall.mount`, `Pinecall::Client`, and `pinecall/testing` — the gateway
  that is not there, which is what a ring-0 suite mounts against.
- `pinecall prompt`, `pinecall run` and `pinecall whoami`. `prompt` needs no gateway, no key and
  no network.
- `pinecall-protocol`: Ruby's side of the wire, generated from the same JSON Schema as the Python
  and TypeScript packages, with the log reducer proved against the same golden fixture.
- `sig/`: the public surface as RBS, checked by `rake rbs`.
- `examples/clinica_norte`: a whole agent, its view, and its own ring-0 suite.
