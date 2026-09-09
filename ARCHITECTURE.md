# Architecture — `pinecall`, the Ruby package a tenant writes an agent in

What this repository is, file by file, what each piece corresponds to in the TypeScript package it
was brought over from, and where it meets the other two repositories: the wire
(`pinecall/protocol`) and the runtime (`pinecall/runtime`).

**The thesis.** An agent is an object. Fields are state. Methods are capabilities. Docstrings are
prompts. Types are contracts. The prompt is `render(state)`. Tools are the only thing that changes
state. The log is the truth.

---

## 1. Four repositories, one product

| repository | language | what it owns |
|---|---|---|
| `pinecall/protocol` | JSON Schema → Python · TypeScript · **Ruby** | the wire: envelope, events, commands, verbs, metrics, state, the reducer, the goldens |
| `pinecall/runtime` | Python, on livekit-agents | the real time: LiveKit rooms and SIP, STT/LLM/TTS, the gateway's doors, the log, the judges |
| `pinecall/agents` | TypeScript, Node ≥ 24 | the same class, for a team that writes TypeScript, plus the CLI and the console |
| **`pinecall/ruby`** (this one) | Ruby ≥ 3.2 | the same class, for a team that writes Ruby |

The line between this package and the runtime is a **socket**. This package never imports the
runtime, never speaks HTTP to a vendor, never sees audio, and holds no key of its own beyond the
one the person typed.

```
   a tenant's agent.rb                  this package                     pinecall/runtime
   ──────────────────                   ────────────                     ────────────────
   class ClinicaNorte      ──mount()──▶  lib/pinecall/bridge  ──WS──▶    gateway ──▶ LiveKit
     state = state                       lib/pinecall/client  ◀─entries─ worker  ──▶ STT·LLM·TTS
     tool  = verbs                                                       log     ──▶ Postgres
     views/clinica-norte.erb ─render()─▶ prompt.set                       judges
```

## 2. The tree

```
lib/pinecall.rb              the door: what a stranger who types `require "pinecall"` may reach
lib/pinecall/
  version.rb errors.rb       0.0.0 until the human names a number; one error root, five words
  reading.rb                 the state as something you can ask questions of by name — and the one that refuses
  agent.rb                   the base class: config, state, tools, the four hooks, this call
  agent/author.rb            who is writing right now — `Fiber[]`, per call, never a global
  agent/doc.rb               the comment above a class or a method, read back out of the source
  agent/state.rb             the `state` and `stage` macros, the store, snapshot · restore · collapse
  agent/tools.rb             the `tool` macro, the registry, what this state shows
  agent/spec.rb              one tool as the gateway receives it, and what is refused at load
  agent/config.rb            the eleven declarations, and what each becomes on the wire
  view.rb                    the ERB template and what it is rendered in
  lang.rb                    the framework's own words: the rules and the protocols, es · en
  blocks.rb                  the prompt as named blocks in two regions: the layout, `render`, `show`
  call_world.rb              the live call as the class holds it: the room, the turns, six verbs
  bridge.rb                  `mount`: one instance per call, and the sync that sends what changed
  client.rb                  `Pinecall::Client`: one socket, the agents on it, observe · history
  client/connection.rb       the WS: the key at the door, backoff on the way back, a ping
  client/agent.rb            one agent from the app's side: registration, tool calls, listeners
  client/call.rb             one live call as the app holds it, and the book of them
  client/listeners.rb        who is listening for what
  client/observe.rb          reading a log: one page, and the stream after it
  client/endpoints.rb        one base URL, three doors
  cli.rb  cli/env.rb         `pinecall <verb>`, and where the key comes from
  ui.rb                      `pinecall ui`: serve, open, wait, close
  ui/server.rb               the loopback, the nonce, the console's files, and the forwarded doors
  ui/browser.rb              whether this machine has a browser, and how a URL is handed to it
  testing.rb                 a gateway that is not there — what ring 0 mounts against
console/                     the compiled React console, vendored. The one generated thing here
exe/pinecall                 what a gem install puts on the PATH
bin/pinecall                 the bin of a checkout: this source and the sibling protocol repo
sig/                         the public surface as RBS. `rake rbs` is part of the gate
examples/clinica_norte/      a whole agent, its view, and its own ring-0 suite
test/                        mirrors lib/
```

## 3. What came from where: the TypeScript package, line by line

Every line of this table is a decision, not a translation. The right-hand column is what Ruby
gives that TypeScript does not, or what it takes away.

| in `pinecall/agents` (TS) | here (Ruby) | why it is different |
|---|---|---|
| `class X extends Agent { patient = null }` and a `Proxy` on the constructor | `state :patient` | TypeScript must catch an assignment to *any* field, so it needs a Proxy. Ruby declares its state, so the writer the macro generates **is** the recorder. What you cannot do by accident, you cannot do. |
| `CONFIG_FIELDS`: eleven names skipped on every write | config declared on the **class**, state on the **instance** | "config is not state" stops being a rule anybody has to remember and becomes where the words are written. There is no list. |
| `@tool({...})` decorator | `tool ...` above the `def`, caught by `method_added` | Ruby has no decorators; it has the hook Sorbet's `sig` uses. The declaration still reads top to bottom. |
| `docstrings.ts`: the class's own source parsed with **oxc** | `Method#source_location` + the comment block above it | Ruby keeps where every method was defined and the file is still on disk. No parser, no dependency, same two lines. |
| parameter types read out of the TypeScript signature | `Method#parameters` for the names, `params:` for the types | A Ruby signature carries no types. Names are free; anything that is not text says so once. |
| a tool takes positional arguments, mapped by name from the source | a tool takes **keyword arguments only**, refused otherwise | A model fills a JSON object by name. Filling by position is a thing only a human gets right. |
| `AsyncLocalStorage` for the current author | `Fiber[:pinecall_author]` | Ruby 3.2's fiber storage: inherited by the fibers a fiber starts, and per thread. Same guarantee, one line. |
| `zod` parses a command before it leaves | the generated shape table plus `Validate` | The schema already generated the table; walking it is thirty lines that cannot drift from zod or pydantic. |
| `Camel<T>`, `toCamel`, `toSnake` — a whole conversion layer | *nothing* | The wire is snake_case and so is Ruby. The layer does not exist here. |
| a `.tsx` view compiled by a JSX transform | an **ERB template** beside the class, `views/<slug>.erb` | Same idea in each language's own material: the view Rails means. No build step, and `pinecall prompt` reads the file a person edited. |
| `static prompt = { static: ["faq"], dynamic: ["availability"] }` on the class | `prompt static: %i[faq], dynamic: %i[availability]` | The same declaration as a macro. Ruby reads the templates *at the line*, so a block with no file is refused when the class loads, with the path. |
| a tenant block is `views/<name>.tsx`, a default-export function | `views/<slug>/<name>.erb`, under the slug | One directory per agent keeps two agents in one tree from sharing a `faq`. |
| a static block's props are a `Proxy` that throws on any read | a static block is rendered against `StaticReading`, which refuses every question by name | Same law — nothing static reads the state — as an exception at render: `a static block cannot read the state: faq.erb reads slots`. |
| `Blocks = { blocks, fills }`; the layout is `Block[]` in send order | `Blocks = Data.define(:blocks, :history, :fills)`, `Block = Data.define(:name, :region, :text)` | Ruby keeps the history on the same value, because `pinecall prompt` prints it between the regions and a `collapse` is the one thing the app knows about the turns. |
| `Fills` on an `AsyncLocalStorage` | one `Fills` per render, handed to every block's context | A JSX component is a function anybody may call, so the registry has to travel. An ERB template is rendered *in* an object, and that object holds the prompt's one registry — so a fill id is never used by two blocks. |
| `Promise`, one event loop | one reader thread, one thread per call, one per tool call | The socket is never blocked by a hook or a tool. Everything belonging to one call is still serialised, which is what makes `call.cause` mean anything. |
| `WeakMap` internals kept off the instance | plain ivars behind declared readers | Nothing enumerates a Ruby object's fields by accident, so nothing has to be hidden from a snapshot. |
| `test/index.test.ts` pins the exports by name | `sig/pinecall.rbs` and `rake rbs` | Ruby's answer to a `.d.ts`: adding to the surface means editing the signature on purpose. |
| the console is built into `dist/cli/ui/console` by the package that owns its source | the same build, **vendored** into `console/`, with `rake console:check` guarding it | One React program, built once. Ruby ships the bytes the way a Rails engine ships assets; installing the gem must not mean installing Node. |
| `node:http` server, `fetch` proxying, `Readable.fromWeb` | HTTP/1.1 on a `TCPServer`, `Net::HTTP` streaming, one connection per answer | Ruby has no HTTP server in the stdlib, and an SSE proxy has to own the write side. Loopback, one person: `connection: close` makes the framing exact and the file short. |

What did **not** change, because it is the product and not the language: the blocks of the
prompt, their two regions and their order, the markers the gateway fills, `stage` as sugar over
`when`, `confirm` being what makes a tool irreversible, `preview` cutting what the model sees and
not what the state keeps, the registration being memory rather than a database, and the four
rings.

## 4. The class a tenant writes

**Config** is declared on the class and is not state: it never changes during a call, is never
diffed, and no view renders it.

| declared | becomes |
|---|---|
| `phone`, `whatsapp` | a route in `agent.register`, with that number |
| `web` | a route with no number: that is what the widget is |
| `voice` | a **name** the platform resolves to a vendor and an id, never an id |
| `llm` | `"haiku"`/`"sonnet"`/`"opus"` lowered to real ids; `"provider/model"` names both halves |
| `says` | a map written as a map, carried as a list of pronunciations |
| `hears` | the words the ears must know before they hear them |
| `language` | which of `lang.rb`'s two word-sets the `identity` block carries |
| `knowledge` | the `knowledge` block: a `<!-- knowledge: … -->` marker the gateway opens the file into |
| `docs`, `memory` | read by the view and by the runtime |
| `prompt` | the class's own blocks; the whole layout travels as `AgentConfig.prompt` in send order |

**State** is declared with `state`, and the rules are enforced in code:

- **Tools are the only writers.** After `seal`, a write with no author raises `UnauthoredWrite`.
  An author is set by `tool` (its own name), by `run_hook` (`hook:on_call`) or by `restore`.
- **The author rides `Fiber[]`,** never a module-level stack: one process serves many calls at
  once, and two tools running at the same time must not read each other's name.
- **A derived field is state.** `state(:identified) { !patient.nil? }` is exactly what a `when`
  asks about, so it is in every snapshot and nothing may assign it.
- **`call` is a method on the base class,** so it never looks like state and never reaches a view;
  outside a call it says so rather than handing back a nil.

## 5. From a method to a tool the model may call

```
# Reserva la hora que el paciente ya ha confirmado.     ← Doc.for_method reads this
tool stage: :book, confirm: "Le reservo {{proposed.cuando}}. ¿Lo confirmo?"
def book(chosen:)                                       ← method_added catches it here
```

1. `tool` stashes the options; `method_added` fires for the next `def` and declares it.
2. `Spec.lower` turns `stage:` into a `when`, refusing a stage the class never declared.
3. `Spec.build` reads the docstring, the keyword names and `params:`, and builds the wire's
   `ToolSpec` — then checks it against the protocol's own shape, at load.
4. `mount` sends every spec; `sync` sends the **visible** subset on every state change.

What a declaration is refused for, before a model ever sees it (`DeclarationRefused`): no
docstring, a name a model cannot call, a positional argument, `pii:` naming a parameter the tool
does not have, `stage:` on a class that declares no stage, a stage that is not one of its own.

## 6. The prompt: named blocks in two regions, in one order, always

| block | region | what is in it | when it changes |
|---|---|---|---|
| `identity` | static | the class docstring · `<rules>` and `<protocols>` | never during a call |
| `knowledge` | static | the `<!-- knowledge: … -->` marker | never during a call |
| `tools` | static | every tool's name and docstring, visible or not | never during a call |
| the class's own static blocks | static | `views/<slug>/<name>.erb`, rendered against nothing | never during a call |
| *the history* | — | the turns (the runtime's) and the `<!-- collapsed: … -->` summaries a `collapse` left | when the app collapses |
| the class's own dynamic blocks | dynamic | `views/<slug>/<name>.erb`, rendered against the state | on every state change |
| `view` | dynamic | the memory marker, the retrieval marker, and what the view says now | on every state change |

The static blocks are what the provider caches, and it caches them block by block: rewriting
`tools` (a `when:` opened) leaves `identity` and `knowledge` cache hits. That is why the layout is
a list of names and not two strings, and why a block is sent by name and only when its own text
changed. The whole layout travels once, in `agent.configure`, as `AgentConfig.prompt`.

A **marker** is a placeholder this package writes and never resolves — `<!-- memory: {…} -->`,
`<!-- retrieved: {…} -->`, `<!-- knowledge: ./file.md -->`. The gateway reads the line, does the
work, and replaces it. A template that passed a block to `memory` left a **render prop** behind:
the block cannot travel inside a marker, so it stays in that render's `Fills` under an id the
marker carries — one `Fills` for the whole prompt, so two blocks never mint the same id.

`pinecall prompt` prints one section per block, `── identity (static) ──` … `── history ──` …
`── view (dynamic) ──`, in send order. It needs no gateway, no key and no network.

## 7. The call, and what a class may do to it

Everything on `call` was reduced from entries the client already receives; every verb is one
command on the wire. There is no LiveKit in this repository at all.

| the class writes | the command | it lands as |
|---|---|---|
| `say(text)` | `agent.say` | `turn.agent` — the call blocks until it lands, or 30s |
| `reply(instructions)` | `agent.reply` | `turn.agent` |
| `call.send_to(topic, data)` | `room.send` | a payload in a browser |
| `call.participant(id).mute` / `.remove` | `participant.mute` / `.remove` | removing the caller ends the call |
| `call.invite(to)` | `room.invite` | a second SIP leg, or a seat |
| `log(name, data)` | `call.log` | a `custom` entry with a `seq` like anything else |

## 8. The bridge, step by step

`Pinecall.mount(Class, client:, last:, opening:, takes_unclaimed:)`.

1. **At mount** — one **probe** instance is built, read for its tools and its config, and thrown
   away. `client.agent(slug, options)` declares it. Nothing is sent until `connect`.
2. **`call.started`** → a fresh instance, `seal`ed, given its `CallWorld`; `on_call` runs;
   `opening` applies the state a golden asked for — after the hook so it is not overwritten,
   before the first render so the model never reads a state the call was not in.
3. **The opening send** — `state.set`, then `sync`. Only then does the bridge start listening, so
   a hook writing five fields is one prompt and not five.
4. **On every change** — `state.set` with the field that moved; when the write came from an
   outside fact, one `state.cause` line naming it; then `sync`.
5. **`sync`** renders every block and compares each against what **this call** was last sent:
   `prompt.set <name>` only for a block whose text differs (a block never sent counts as empty, so
   an empty one costs nothing), `tools.set` only if the visible list differs. Re-sending identical
   text is a cache miss for nothing.
6. **A tool call** — routed to the instance serving that call, run on a thread of its own; an
   unknown call, an unknown tool and a tool that raised all come back as one `tool.result`
   carrying `error`, because a turn that never gets one waits forever.
7. **An outside fact** — the pair (name, source) is checked against `accepts`. Facts run one at a
   time, in the order they arrived, on that call's own thread.
8. **`call.ended`** → nothing may render for this call any more; `on_end` runs, and the log stays
   open one hook longer so a farewell line still lands.

## 9. `Pinecall::Client` — the socket alone

A second, smaller door for an app with its own way of deciding what to answer: no class, no view,
no CLI. It knows `pinecall-protocol` and `websocket-driver`.

- **Registration is memory, not a database.** `open` runs again on every reconnect. Many sockets
  may hold one agent at once; a call that named no app goes to the newest registration that takes
  unclaimed calls. That is what makes a rolling deploy work.
- **Two commands are awaited** (`agent.register` → `agent.registered`, `agent.configure` →
  `agent.configured`). Everything else is fire and read the log.
- **The declaration goes up on its own thread**, because the answer arrives as an entry and a
  thread waiting for that entry is a thread not reading it. (That was a real deadlock; the socket
  test is what found it.)
- **The key travels as `Authorization: Bearer`**, never in a URL, because a URL ends up in a log.

## 10. The CLI

| verb | what it is | needs a gateway |
|---|---|---|
| `prompt` | the exact prompt a state would produce | **no** |
| `run` | the agent registered and answering: the process you deploy | yes |
| `ui` | the console on 127.0.0.1 for the life of the command | yes |
| `whoami` | which gateway, and where this terminal's key came from | no |

`cli/env.rb` decides where the key comes from, in one order, for every verb:

1. the URL: `PINECALL_URL` → the local gateway's `~/.pinecall/dev` → the single row a login kept →
   `http://localhost:8080`;
2. **if the URL is the local dev gateway, its own dev key** — and an exported `PINECALL_API_KEY`
   is then ignored **out loud**, because that gateway honours its own key and no other;
3. otherwise `PINECALL_API_KEY` → the `credentials` row for that URL → `PINECALL_DEV_KEY`;
4. nothing: the verb says so and exits 2.

It **reads** `~/.pinecall/credentials` and `~/.pinecall/dev` and writes neither — `pinecall login`
belongs to the Node CLI, and one program keeping a key is enough. A file any other account can
read is treated as absent.

`CLI::PLANNED` names the verbs the design has and this package has not written; typing one says
what it will be and exits 0. A verb leaves that table in the commit that writes it.

## 11. The console

`pinecall ui` is the one verb that opens a port, and everything about it is a containment
decision: **127.0.0.1 only**, the kernel picks the port, and everything answers under a random
nonce, so a process that scans the loopback finds a `404` and nothing behind it. **The org key
never reaches the browser**: the page asks this process, this process signs the request and
forwards it, passing only `content-type`, `accept`, `last-event-id` and `range`.

The page itself is not written here. It is the React program in `pinecall/agents`, built once by
vite and **vendored compiled** into `console/` — one program, so a screen is written in one place
and both packages show the same digits. `rake console:build` rebuilds it from the sibling
repository; `rake console:check` hashes that source and fails when what is committed is not what
it would produce; `rake` runs the check. Nothing else in this gem is generated, and no file under
`console/` is ever edited.

`ui/server.rb` speaks HTTP/1.1 on a `TCPServer` rather than through a web server, because a
console reads a live log over SSE and a proxy that streams has to own the write side. Every answer
carries `connection: close`, which lets a body end at EOF with no length and no chunked framing —
on the loopback, for one person, a connection per request costs nothing.

## 12. The four rings, and where each of them runs

| ring | what it asks | where it runs |
|---|---|---|
| 0 | does the class behave? | `minitest`, in the tenant's own repo. No network, no key, no model — `pinecall/testing` is the gateway that is not there |
| 1 | does the agent hold its goldens? | `pinecall test`, in the Node CLI today |
| 2 | does it hold on a real line? | `pinecall simulate --voice`, in the Node CLI today |
| 3 | what does one real call score? | `pinecall eval <call-id>` |
| 4 | what did every call score? | `call.score`, written by the runtime at hang-up |

## 13. The wire

`pinecall-protocol` is generated from JSON Schema in `pinecall/protocol` and committed there;
nothing here runs a generator. This package imports the frames (`Entry`, `Command`, `Event`), the
registries, the validator and the reducer. `Gemfile` names `../protocol/ruby` as a path — a path
today because nothing is published, a version range the day it is.

## 14. Packaging

- **One gem, two bins.** `exe/pinecall` is what a gem install puts on the PATH; `bin/pinecall` is
  the bin of a checkout, and the only place a sibling repository's path is written.
- **`sig/` ships with the gem.** Ruby's type story is RBS, and `rake rbs` is part of the gate.
- **`rake check`** is the console's staleness gate, the tests, the example's own suite, then the
  signatures. Ruby has nothing to compile: the only build step in this repository belongs to the
  console, and it runs in the repository that owns the console's source.
