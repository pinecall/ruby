# Changelog

Every change a person using this gem would notice. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); nothing is versioned yet, because a
version number is the human's call.

## [Unreleased]

### Fixed
- **A voice call whose vendor fails over no longer stops the agent.** The runtime writes
  `vendor.switched` when a stage's fallback switches vendor, and the gem did not know the type: the
  socket raised `unknown event type` mid-call. `vendor.switched` and `spend.unusual` are in the
  wire now, both left to `call.on` and `client.on_any`.

### Changed
- **Breaking: no CLI, no console, no executable.** The verbs are the one `pinecall` CLI's (npm),
  the same for a Ruby project as for a TypeScript one, in the same layout
  (`agents/<slug>/agent.rb`): for `prompt`, `chat`, `test` and `start` it runs `Pinecall::Serve`.
  `exe/pinecall`, `bin/pinecall`, the vendored console and `pinecall ui`, `run`, `whoami`,
  `knowledge`, `memory`, `remember` and `keys` are gone, and so are `Client#knowledge`,
  `#memory_of`, `#memory` and `#provider_keys`: those doors are the CLI's verbs.
- **Breaking: `Pinecall::Client.new` reads nothing from the environment.** It takes `url:`,
  `api_key:` and `env:` (`"production"` names production for a person's key); the serve entry
  reads `PINECALL_KEY`, and no other key variable is read anywhere.
- **Breaking: a call opens in the state its `call.started` carries.** `Pinecall.mount` takes no
  `opening:`: the state a golden, a persona or a chat's `?state=` asked for rides the call, and the
  bridge applies it after `on_call` and before the first render. `Testing::Gateway#call_started`
  takes `state:`.
- **No `pinecall-protocol` dependency.** The gem keeps the runtime's wire it speaks in
  `lib/pinecall/wire/` (`Pinecall::Wire`: the shapes, the validator, the codec, the reducer), held
  to the runtime's golden call log; `Pinecall::Protocol` is `Pinecall::Wire` and `ProtocolError` is
  `WireError`.
- **Breaking: the class is code, the world is environment.** A class declares the contract — its
  `language`, `state` and `stage`, its `tool`s, `accepts`, its view — and nothing it runs on.
  `voice`, `llm`, `stt`, `greeting`, `hangup`, `says`, `hears`, `memory`, `record`, `knowledge`
  and `docs` in a class body now raise `DeclarationRefused` when the class loads, before a prompt
  is printed or a gateway is knocked at, naming the verb that sets each instead:
  `` `voice` is the world's now, not the class's: pinecall agent set --voice <name> — remove it
  from the class``. What to run instead, per world, with the Node CLI or the console's Settings:
  `pinecall agent set --voice | --llm | --stt | --greeting '…' (or --reply '…') | --hangup '…' |
  --record on|off`, `pinecall lexicon add <word> --say '…'` and `pinecall lexicon hear <word>`,
  `pinecall memory policy --remember '…' --forget '…'`, `pinecall agent knowledge edit` for what
  the agent knows by heart, and `pinecall docs attach <base>` for the base it searches. None of
  them travels on `agent.configure` any more, and the `knowledge` block is the gateway's to fill:
  the class sends nothing for it, so `pinecall prompt` prints it empty.
- **A class declares no doors.** `phone`, `whatsapp` and `web` still load and are read by nobody:
  `agent.register` carries no routes from the class, and nothing counts them. A
  number is pointed at an agent with `pinecall numbers import <+34…> --agent <slug>`, and every
  agent can be talked to from a page.

### Added
- **`Pinecall::Serve`, the entry the one `pinecall` CLI starts a Ruby agent with**:
  `start --file --slug [--console] [--events] [--prod]` holds the agents (its door from
  `PINECALL_URL`, `PINECALL_KEY`, `PINECALL_ENV` alone; the wire entry by entry on stdout with
  `--events`; leaves draining on a signal or the end of its stdin) and `prompt --file --slug
  [--state field=json]… [--show-machine]` prints a prompt. `Pinecall.serve(klass, url:, api_key:,
  env:)` holds one inside your own Ruby process. The client gains `drain`, `on_entries`,
  `on_stopped` and the `pinecall-env` header, registers its machine as `host`, and answers a
  console's ask with `a Ruby agent draws no panel`. `docs/production.md` says how a server runs it.
- **A call handed over mid-conversation is served.** On `call.attached` (another process drained
  or died) the agent opens in the state the gateway kept, with no `on_call`; one this process
  already serves sends its whole prompt again. A call knows the code it claimed (`call.claimed`)
  and the eval run that opened it. `Testing::Gateway#call_attached(state:)`.
- **`examples/clinica_norte` is the TypeScript example's agent, in Ruby**, in the one CLI's layout
  (`agents/clinica-norte/`, `docs/clinica-norte/`, `test/clinica-norte/`): the same agenda —
  specialties, slots booked by id, a day resolved to a date — the same documents, the same three
  extraction cases and the same eleven goldens. `rake ring1` runs them through the CLI.
- A stage restored from JSON — a golden's, `call.started.state` — is the declared stage it names.
- **The whole call.** `call.transfer(to, mode:)` and `call.attention(reason, wait_s:)` block until
  the log answers (a `Transferred`, an `Attended`); `call.hold`, `unhold`, `dtmf(digits)`,
  `claim(code)` (then `call.claimed`) and `callback(number, at:, note:)` are one command each.
  `knowledge.search(query, k:)` — or `call.search` — searches the bases attached to the agent
  through the gateway, and a class that searches registers `uses_knowledge`. The view is rendered
  again on the caller's turn, on a claim and on recall, and reads `call[:claimed]`. The call ending
  answers every verb still waiting. `Testing::Gateway#finds` and `#searched` for ring 0.
- The wire reads `call.started`'s `worker`, which the runtime writes on every spoken call: until
  now a Ruby app refused a phone call's first entry.
- The wire reads `call.started`'s `state`, the state a call opens in when its opener asked for
  one, and `agent.register` may carry `answers_dev`. Nothing sends or reads either yet.
- **`pinecall remember [PATHS]`**, and `client.memory.extraction(slug, cases)` — the goldens
  the memory policy is held to, which is the write side and the half that persists. A case is one
  call already held (both speakers, in `said`), the facts memory already holds (`holds`), and what
  must come of the hang-up's one model call: which categories got a fact (`writes`), which never
  did (`never`), which values must not survive in any fact's text (`never_says`), and which held
  facts the call contradicted (`invalidates`) — its mirror included, so a model that supersedes
  whatever it touches is caught too. A case may `plants` sentences somebody tried to get into
  memory, and planting one IS the assertion that admission refuses it. Nothing asks a model whether
  two sentences mean the same thing: a category is your own word, a value is a literal, a
  supersession is an id. The class is mounted in this terminal, because the tool names admission
  refuses a fact for are the class's own declaration; the one
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
- `pinecall-protocol`: Ruby's side of the wire, generated from the same JSON Schema as the Python
  and TypeScript packages, with the log reducer proved against the same golden fixture.
- `sig/`: the public surface as RBS, checked by `rake rbs`.
- `examples/clinica_norte`: a whole agent, its view, and its own ring-0 suite.
- **A lookup is a tool result, never a piece of the prompt.** What memory kept from an earlier
  call and what the knowledge base returned no longer travel through the view: the platform runs
  its own `recall` and `search` tools and their answers reach the model as `tool_result` blocks,
  JSON, in the history — which is where both vendors say content from outside the conversation
  belongs (`runtime/docs/security/prompt-injection.md`). So a view is now the tenant's own prose
  and conditions and nothing else: the `memory`, `retrieved` and `knowledge` template tags are
  gone, and so are the tenant-declared blocks (`prompt static:`/`dynamic:`) and the render props
  that came with them. What a view may still do with memory is ask it a question —
  `remembers?("médico habitual")`, answered by the runtime — and say a sentence of its own about
  the answer.
