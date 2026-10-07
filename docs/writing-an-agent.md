# Writing an agent

An agent is one Ruby class. Everything the model can see about it comes from four places: the
comment above the class, what the class declares, the comments above its tools, and the view.

```ruby
require "pinecall"

# Eres la recepción de Clínica Norte. Hablas de usted, con frases cortas.
# Todo lo que dices se lee en voz alta: sin listas, sin markdown.
class ClinicaNorte < Pinecall::Agent
end
```

That comment is the `identity` block of the prompt — the first of the static blocks, which never
change during a call and are what a provider caches. Write it as instructions to a person, not as
documentation.

For a class with no source file to read (one built at runtime, one loaded from a database), say it
out loud instead: `doc "Eres la recepción…"`.

## Config: what the agent *is*

Declared on the class, because it is not something the agent remembers. It never changes during a
call and no view renders it. There is one word left:

```ruby
language :es              # which of the framework's two word-sets the prompt carries
```

**The doors are not here.** A number is bought, pointed at an agent and moved by whoever answers
the telephone, not by whoever deploys: it is a row the org keeps — `pinecall numbers import
<+34…> --agent <slug>`, or the console's Numbers screen. And the web needs no door at all: every
agent can be talked to from a page. A class that still writes `phone "+34…"`, `whatsapp` or
`web true` still loads, and is writing something nobody reads.

### The world's, not the class's

Everything the agent **runs on** is the world's: set per world and per corner, versioned, with who
set it and why, and changed without a deploy — by `pinecall agent set`, the console's Settings
tab, or the verb the table names. Those verbs belong to the Node CLI (`@pinecall/agents`); this
gem's `pinecall` does not have them. A class that still declares one of these fields is refused
when it loads, before a prompt is printed or a gateway is knocked at, with the verb that sets it
now:

```
`voice` is the world's now, not the class's: pinecall agent set --voice <name> — remove it from the class
```

| field | what it is | where it is set |
|---|---|---|
| `voice` | a voice **by name** — the platform resolves it to a vendor and an id | `pinecall agent set --voice` |
| `llm` | `haiku`, `sonnet`, `opus`, or `vendor/model` | `pinecall agent set --llm` |
| `stt` | the ears: `deepgram` (Flux), `soniox`, or `vendor/model` | `pinecall agent set --stt` |
| `greeting` | how the call opens: the words, or what the model reads before finding its own | `pinecall agent set --greeting '…'` · `--reply '…'` |
| `hangup` | whether the model may end the call itself, and when, in your words | `pinecall agent set --hangup '…'` |
| `says` | how a word the voice would misread is said: `DKV` → `de ka uve` | `pinecall lexicon add <word> --say '…'` |
| `hears` | the words the ears must know: names, brands, the doctor's surname | `pinecall lexicon hear <word> …` |
| `memory` | what to remember about a caller across calls, and what never to | `pinecall memory policy --remember '…' --forget '…'` |
| `record` | whether the call is recorded | `pinecall agent set --record on\|off` |
| `knowledge` | what the agent knows by heart: a page of Markdown, read whole on every call | `pinecall agent knowledge edit`, or Settings ▸ Knowledge |
| `docs` | the bases the agent searches per turn, and how many chunks a turn reads | `pinecall docs push`, then `pinecall docs attach <base>` |

Mid-call, `say "..."` and `reply "..."` are still methods of the class, for when something happens
that the caller should hear now; how the call *opens* is the world's.

### What it knows, what it reads, what it remembers

None of the three is in the class any more, and the runtime does the work for all of them:

- **What it knows by heart** — the hours, the prices — is a page of Markdown in the agent's
  settings. The gateway writes it, whole, into the `knowledge` block of the prompt, once per call,
  in the cached prefix. The class sends nothing for that block, so `pinecall prompt` prints it
  empty.
- **What it searches** is a base: a folder of Markdown pushed to the gateway and attached to the
  agent. The platform's `search` tool runs it and the chunks reach the model as a **tool result**.
- **What it remembers** about a contact is the org's memory policy, in its own words; the
  platform's `recall` tool answers from it, the same way, and at hang-up one model call writes what
  this call taught.

**Neither a fact nor a chunk ever reaches the prompt.** Both arrive as a `tool_result`, JSON, in
the history, where a model reads them as information rather than as an instruction — the rule, and
the vendor guidance behind it, is `runtime/docs/security/prompt-injection.md`. What the view may do
with memory is ask it a question: `remembers?("médico habitual")`, and then say a sentence of your
own. The history of a contact, and the right to be forgotten, are `pinecall memory CONTACT` and
`pinecall memory forget CONTACT`.

## State: what it remembers

```ruby
stage :identify, :choose, :book, :done   # declares the stage field and its only values
state :patient, visibility: :pii
state :slots, []                          # every call gets a list of its own
state :proposed
state(:identified) { !patient.nil? }      # derived: read like any field, assigned by nobody
```

**Tools are the only writers.** Assigning a field anywhere else raises `UnauthoredWrite`:

```ruby
agent.patient = row
# => state field patient was assigned outside a tool and outside a lifecycle hook;
#    tools are the only writers of state
```

The author of a write is the tool's own name, and it rides `Fiber[]` rather than a global — so two
calls being served at the same moment never read each other's.

`visibility:` is `:public`, `:tenant` (the default, and the wire's) or `:pii`.

## Tools: what the model may do

```ruby
# Busca al paciente por nombre y teléfono. Pide los dos antes de llamarla.
tool stage: :identify, pii: %i[name phone]
def find_patient(name:, phone:)
  self.patient = Agenda.buscar(name, phone)
  self.stage = :choose if patient
  patient
end
```

`tool` marks the method **defined next** — the same hook Sorbet's `sig` uses — so the comment
stays where a person would write it anyway. That comment is what the model reads to choose the
tool; the signature is the schema it fills.

| option | what it does |
|---|---|
| `stage:` | visible while the state is in one of these stages. Sugar over `when:` |
| `when:` | a question asked of the state, on every change: `-> { slots.any? }` or `->(s) { s.slots.any? }` |
| `confirm:` | the read-back the agent says before running. **This is what makes a tool irreversible on the wire** |
| `preview:` | how many rows of a list result the *model* sees. The state field keeps every row |
| `pii:` | parameters that carry personal data, masked in the log by declaration |
| `timeout:` | how long the platform waits for this method, in seconds |
| `params:` | the type of a parameter when a bare name is not enough |
| `doc:` | the description, for a class with no source to read |

**A tool takes keyword arguments and nothing else.** A model fills a JSON object by name; filling
by position is a thing only a human gets right, so a positional argument is refused at load.

**Types come from `params:`.** A Ruby signature carries none, so a parameter nobody typed is
`string` — which is what a person on the phone says. Anything else says so once:

```ruby
tool params: { day: String, how_many: Integer, slot: { type: "object" } }
def free_slots(day:, how_many: 3, slot: nil)
```

## What is refused, at load

Every one of these raises `DeclarationRefused` when the file is loaded — never in the middle of a
call, and never as a 1008 from a gateway:

| refused | the sentence |
|---|---|
| a tool with no comment above it | `without a docstring no model can choose it` |
| `def book(chosen)` | `a model fills a JSON object by name, so a tool takes keyword arguments` |
| `pii: %i[dni]` on a tool with no `dni:` | `pii names parameters the tool has; unknown: dni` |
| `stage: :pay` where `stage` has no `:pay` | `pay is not one of this agent's stages (identify, book)` |
| `stage:` on a class with no `stage` | `…declares none; add \`stage :identify, :book\`` |
| `state :cart` twice | `declares cart twice` |
| `voice`, `llm`, `stt`, `greeting`, `hangup`, `says`, `hears`, `memory`, `record`, `knowledge`, `docs` | `` `<field>` is the world's now, not the class's: <verb> — remove it from the class``, the verb from the table above |

A view is the one thing read later, at render: a field the class never declared raises there, by
name, the same way an undefined instance variable does in a Rails view.

## The hooks

```ruby
def on_call(call)                  # a call started. Writes here are authored by the hook
  self.patient = Agenda.por_telefono(call.from)
  self.stage = :choose if patient
end

def on_end(call)  = log("resultado", { fase: stage })
def on_event(name, data, meta)     # an outside fact this class declared with `accepts`
def on_memory(ops, call)           # memory was written
```

`on_call` runs before the first render, so the model never reads a state the call was not in.

An outside fact only reaches `on_event` if the class declared the pair:

```ruby
accepts "agenda.changed", from: %i[app]
```

An event declared `from: [:app]` that arrives from a browser is somebody else's event with your
name on it, and the hook never sees it.

## The call

Inside a tool or a hook, `call` is the live call:

```ruby
say "Un momento, que lo miro."          # blocks until the turn lands, or 30 seconds
reply "Dile que ya está reservado."     # the model speaks, guided by words nobody hears
call.send_to("cart", { total: 42 })     # a payload in the browser
call.participant(id).mute
call.invite("+34910000001", kind: :supervisor)
call.transfer("+34910000002")           # blocks until the log says how it went: a Transferred
call.attention("quiere hablar con una persona", wait_s: 60)   # an Attended: who took the line
call.hold                               # and call.unhold
call.dtmf("1#")
call.claim("4821")                      # the page showing 4821 follows this call; call.claimed says so
call.callback("+34600000001", at: "mañana por la tarde", note: "presupuesto")
call.hangup("done")
log "resultado", { referencia: booking[:referencia] }
knowledge.search("horario de verano", k: 3)   # the bases attached to the agent, searched for this call
```

`transfer` and `attention` block the tool that called them until the log answers — `ok: false`
and a sentence when nobody did, or when the call ended first. `knowledge.search` (or
`call.search`) asks the gateway, which searches the bases attached to the agent and logs what it
found; a class that searches says so when it registers, so a world with no base attached is refused
then and not mid-call. A view can ask `call[:claimed]` for the page code this call claimed.

There is no LiveKit here and no escape hatch to it: a need the room cannot express is a new
command with a name.
