# pinecall

Build voice agents as Ruby classes. Declared fields are the agent's state, `tool` methods are
what the model can call, the comment above each tool is its description, and an ERB view renders
the part of the prompt that changes during the call.

```ruby
require "pinecall"

# Eres la recepción de Clínica Norte. Hablas de usted, con frases cortas.
class ClinicaNorte < Pinecall::Agent
  language :es

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

`views/clinica-norte.erb` renders the prompt from that state:

```erb
<% if stage == :identify -%>
Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
<% end -%>

<% if remembers?("médico habitual") -%>
Ofrece primero las horas de su médico habitual.
<% end -%>

<% if slots.any? -%>
## Horas libres, en orden

<% slots.each do |hueco| -%>
<%= hueco.cuando %> con <%= hueco.doctor %>
<% end -%>
<% end -%>
```

The prompt has four named blocks: `identity`, `knowledge` and `tools` are static and cached
before the history; `view` comes after it and is replaced every turn. A block is re-sent only when
its text changes.

Memory and knowledge-base results never enter the prompt. The platform runs `recall` and `search`
and returns their results to the model as tool results, so retrieved text is treated as data, not
instructions. A view can ask `remembers?("médico habitual")` and write its own sentence about the
answer.

## Five minutes

```bash
gem install pinecall
pinecall prompt agent.rb              # the exact prompt this state would produce. No gateway.
pinecall prompt agent.rb --stage book
pinecall run agent.rb                 # registered and answering: the process you deploy
pinecall knowledge push               # knowledge/docs, as a base named after the agent
pinecall memory +34600123456          # what is remembered about a contact; `forget` to forget
pinecall memory eval                  # the golden: does recall bring the right facts back?
pinecall keys add elevenlabs          # this org's own key for a vendor, read off stdin
pinecall ui                           # the console on 127.0.0.1: calls, sessions, evals, talk
```

`pinecall prompt` needs no gateway, key or network: the prompt is a function of the state.

## The console

`pinecall ui` serves the console on 127.0.0.1 while the command runs: live calls and logs,
finished sessions, eval runs, and a page to talk to an agent with the browser's microphone. It is
the same compiled React console the TypeScript package builds, vendored into the gem, so no Node
is needed. It listens on a random port under a random path prefix, and the org key never reaches
the browser: this process signs and forwards each request.

## Architecture

This gem is the application side. It never talks to a model vendor or handles audio: it sends
commands and reads log entries over one WebSocket, in the runtime's own wire (`lib/pinecall/wire/`),
held to the runtime's golden call log. Tools are the only code that may change state.

| you want | you use |
|---|---|
| the class, the view, the CLI | `Pinecall::Agent`, `Pinecall.mount` |
| the socket alone, your own way of deciding what to answer | `Pinecall::Client` |
| a suite with no network, no key and no model | `pinecall/testing` |

```ruby
pc = Pinecall::Client.new(url: "https://cloud.pinecall.io", api_key: ENV.fetch("PINECALL_KEY"))
agent = pc.agent("clinica-norte", tools: [])
agent.on("turn.user") { |data, call| call.say("Le he oído: #{data[:text]}") }
pc.connect
```

## Testing it

Agent tests run with no network, key, model or gateway:

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
| tutorial: an agent with knowledge and memory, from an empty directory | [docs/tutorial.md](docs/tutorial.md) |
| every file, entity and rule | [ARCHITECTURE.md](ARCHITECTURE.md) |
| how to write an agent, step by step | [docs/writing-an-agent.md](docs/writing-an-agent.md) |
| the view, and the blocks of a prompt | [docs/the-view.md](docs/the-view.md) |
| how to test one | [docs/testing-an-agent.md](docs/testing-an-agent.md) |
| the CLI, verb by verb | [docs/the-cli.md](docs/the-cli.md) |
| the console, and how it is vendored | [docs/the-console.md](docs/the-console.md) |
| a complete example agent | [examples/clinica_norte](examples/clinica_norte) |
| the wire itself | `lib/pinecall/wire/`, the runtime's shapes this gem speaks |

## Requirements

Ruby 3.2+. The only runtime dependency is `websocket-driver` (the driver ActionCable uses).

## License

[Apache-2.0](LICENSE), including its patent grant. No CLA.
