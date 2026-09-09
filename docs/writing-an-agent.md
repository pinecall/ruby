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

That comment is the **static region** of the prompt — the part that never changes during a call,
which is the part a provider caches. Write it as instructions to a person, not as documentation.

For a class with no source file to read (one built at runtime, one loaded from a database), say it
out loud instead: `doc "Eres la recepción…"`.

## Config: what the agent *is*

Declared on the class, because it is not something the agent remembers — it is what it was set up
as. It never changes during a call and no view renders it.

```ruby
phone "+34910000000"      # a route in agent.register, with that number
whatsapp "+34910000000"
web true                  # a route with no number: that is what the widget is
voice "carolina"          # a NAME. The platform resolves it to a vendor and an id
llm "haiku"               # or "sonnet", "opus", or "openai/gpt-5.4-mini"
language :es              # which of the framework's two word-sets the prompt carries
says DKV: "de ka uve"     # how a word is said when the voice would read it wrong
hears ["Clínica Norte"]   # what the ears must know before they hear it
knowledge "./knowledge/clinica.md"
memory remember: ["cómo prefiere que le llamen"], forget: ["pagos"]
```

`voice` is a name and never an id. Sending an id is how a call once spent twenty seconds retrying
`voice_id_does_not_exist` while the model apologised.

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
call.hangup("done")
log "resultado", { referencia: booking[:referencia] }
```

There is no LiveKit here and no escape hatch to it: a need the room cannot express is a new
command with a name.
