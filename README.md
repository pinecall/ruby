# pinecall

Write a voice agent as a Ruby class. Its declared fields are the state, its `tool` methods are the
verbs the model may call, the comment above each one is what the model reads, and an ERB view is
the part of the prompt that changes while the call is happening.

```ruby
require "pinecall"

# Eres la recepción de Clínica Norte. Hablas de usted, con frases cortas.
class ClinicaNorte < Pinecall::Agent
  phone "+34910000000"
  voice "carolina"
  llm   "haiku"

  stage :identify, :book
  state :patient, visibility: :pii
  state :slots, []

  # Busca al paciente por nombre y teléfono. Pide los dos antes de llamarla.
  tool stage: :identify, pii: %i[name phone]
  def find_patient(name:, phone:)
    self.patient = Agenda.buscar(name, phone)
    self.stage = :book if patient
    patient
  end

  # Horas libres de un día.
  tool stage: :book, preview: 2
  def free_slots(day:)
    self.slots = Agenda.libres(day)
  end
end
```

`views/clinica-norte.erb`, beside it, is the prompt as a function of that state:

```erb
<%= memory kinds: %w[preference] %>

<% if stage == :identify -%>
Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
<% end -%>

<% if slots.any? -%>
## Horas libres, en orden

<% slots.each do |hueco| -%>
<%= hueco.cuando %> con <%= hueco.doctor %>
<% end -%>
<% end -%>
```

The prompt is a list of named blocks in two regions: static ones before the history, cached by
the provider — `identity`, `knowledge`, `tools` — and dynamic ones after it, replaced every turn —
the `view`. A class adds its own with `prompt static: %i[faq], dynamic: %i[availability]`, one
template each under `views/<slug>/`, and each block goes up by name only when its text changed.

## Five minutes

```bash
gem install pinecall
pinecall prompt agent.rb              # the exact prompt this state would produce. No gateway.
pinecall prompt agent.rb --stage book
pinecall run agent.rb                 # registered and answering: the process you deploy
pinecall ui                           # the console on 127.0.0.1: calls, sessions, evals, talk
```

`pinecall prompt` needs no gateway, no key and no network, which is why it is the verb to run
first: the whole point of the design is that the prompt is a function you can call.

## The console

`pinecall ui` opens the console on 127.0.0.1 for as long as the command runs: the agents this
gateway holds, their calls and logs as they happen, the finished sessions read whole, the eval
runs, the pipeline of a voice turn, and a page to talk to an agent with this browser's microphone.

It is **the same React console the TypeScript package builds** — the same screens, the same
bundle — vendored into this gem already compiled, the way a Rails engine ships its assets. A
browser reads no TypeScript, and a Ruby shop should not have to install Node to look at its own
calls.

What Ruby owns is everything around it, and all of it is a containment decision: the loopback and
a port the kernel picks, a random nonce that every path answers under (a process that scans the
loopback finds a 404), and **the org key, which never reaches the browser** — the page asks this
process, this process signs the request and forwards it. Ctrl-C closes the port with the command.

## What it is

An agent is an object. Fields are state. Methods are capabilities. Docstrings are prompts. The
prompt is `render(state)`. Tools are the only thing that changes state. The log is the truth.

This package is the application's side of that. It never imports the runtime, never talks to a
model vendor, never sees audio: it sends **commands** and reads **entries** over one socket, both
of them shapes generated from `pinecall/protocol`'s JSON Schema — the same schema the Python
runtime and the TypeScript package are generated from.

Two doors out:

| you want | you use |
|---|---|
| the class, the view, the CLI | `Pinecall::Agent`, `Pinecall.mount` |
| the socket alone, your own way of deciding what to answer | `Pinecall::Client` |
| a suite with no network, no key and no model | `pinecall/testing` |

```ruby
pc = Pinecall::Client.new                # PINECALL_URL and PINECALL_API_KEY
agent = pc.agent("clinica-norte", routes: [{ channel: "web", number: nil }], tools: [])
agent.on("turn.user") { |data, call| call.say("Le he oído: #{data[:text]}") }
pc.connect
```

## Testing it

Ring 0 is the ring your own suite lives in: no network, no key, no model, no gateway.

```ruby
require "pinecall/testing"

gateway = Pinecall::Testing::Gateway.new
Pinecall.mount(ClinicaNorte, client: gateway)

call = gateway.call_started(from: "+34600123456")
call.tool("free_slots", day: "martes")

assert_includes call.prompt, "el martes a las diez"
assert_equal %w[propose], call.tools
```

## Where the rest is

| what | where |
|---|---|
| the map: every file, every entity, every rule | [ARCHITECTURE.md](ARCHITECTURE.md) |
| how to write an agent, step by step | [docs/writing-an-agent.md](docs/writing-an-agent.md) |
| the view, and the blocks of a prompt | [docs/the-view.md](docs/the-view.md) |
| how to test one | [docs/testing-an-agent.md](docs/testing-an-agent.md) |
| the CLI, verb by verb | [docs/the-cli.md](docs/the-cli.md) |
| the console, and how it is vendored | [docs/the-console.md](docs/the-console.md) |
| a whole agent, written the way a customer writes one | [examples/clinica_norte](examples/clinica_norte) |
| the wire itself | `pinecall-protocol`, generated in the `pinecall/protocol` repository |

## Requirements

Ruby 3.2 or newer. It uses fiber storage (`Fiber[]`), `Data.define` and endless methods, and it
depends on `websocket-driver` — the protocol driver ActionCable runs on — and nothing else.

## License

[Apache-2.0](LICENSE). Use it, change it, run it in production, sell what you build with it —
commercially or not, on your own box or somebody else's. The licence carries an explicit patent
grant, which is why it is the one this stack uses (LiveKit's is the same). There is no NOTICE
file, so nothing has to be reproduced downstream beyond the licence itself, and there is no CLA:
a patch is yours and stays under the same terms.
