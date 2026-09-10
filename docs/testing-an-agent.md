# Testing an agent

Ring 0 is the ring your own suite lives in: no network, no key, no model, no gateway. It is the
one that runs on every commit, in a second, and it is where nearly every mistake is caught.

```ruby
require "minitest/autorun"
require "pinecall"
require "pinecall/testing"
require_relative "../agent"

class ClinicaTest < Minitest::Test
  def setup
    @gateway = Pinecall::Testing::Gateway.new
    @mounted = Pinecall.mount(ClinicaNorte, client: @gateway)
  end

  def test_una_paciente_de_la_ficha_no_tiene_que_decir_su_nombre_otra_vez
    call = @gateway.call_started(from: "+34600123456")

    assert_includes call.prompt, "Hablas con Marta Ruiz"
    assert_equal %w[free_slots], call.tools
  end
end
```

`Pinecall::Testing::Gateway` is a gateway that is not there. It answers the two declarations, keeps
every command the agent sent, and lets the test say what happened next.

## Driving a call

| you write | what happens |
|---|---|
| `gateway.call_started(from:, channel:, id:)` | a call opens, `on_call` runs, the first prompt goes out. Returns the handle |
| `call.tool("free_slots", day: "martes")` | the model calls a tool. Returns the `tool.result` the agent sent back |
| `call.said("el martes me viene bien")` | the caller said something |
| `call.fact("agenda.changed", { slots: [] })` | a fact from the tenant's backend. `from: "participant"` for a browser |
| `call.ended` | the call is over, `on_end` runs |

## Asking what the agent said

| you read | what it is |
|---|---|
| `call.prompt` | the `view` block as the agent last sent it: the last thing the model reads |
| `call.block("knowledge")` | any of the four blocks as the agent last sent it, by name. `nil` until it had something to say |
| `call.tools` | the tools the model may call right now, by name |
| `call.state` | the state as the agent last said it |
| `call.commands` | everything said on this call, in order |
| `call.last("call.log")` | the last command of one type |
| `@mounted.serving(call.id)` | the instance itself, for an assertion about a field |

## What is worth a test

The things a prompt makes true, not the things a method returns:

```ruby
def test_el_telefono_pide_ofrecer_dos_horas_y_la_web_la_lista
  por_telefono = @gateway.call_started(id: "CA_tel", from: "+34600123456", channel: "phone")
  por_telefono.tool("free_slots", day: "martes")

  assert_includes por_telefono.prompt, "Ofrece como máximo dos"
end

def test_una_hora_que_nadie_ofrecio_se_rechaza_en_vez_de_reservarse
  call = @gateway.call_started(from: "+34600123456")
  call.tool("free_slots", day: "martes")

  assert_includes call.tool("propose", chosen: "el domingo")[:error], "no es una de las horas"
end

def test_reservar_es_irreversible_y_por_eso_lleva_una_lectura_en_voz_alta
  spec = @mounted.options[:tools].find { |one| one[:name] == "book" }

  assert_equal "irreversible", spec[:side_effect]
end
```

A tool that raises is not a broken test: the model is waiting for an answer and reads the message
as the tool's own result, so `call.tool(...)` gives you back `{ error: "…" }` and the call carries
on. That is what you assert on.

## Without mounting anything

The prompt is a pure function of the state, so most assertions need no gateway at all:

```ruby
agent = ClinicaNorte.new.seal
agent.start_in(stage: :book, slots: [hueco])

assert_includes Pinecall.render(agent)[:view], "el martes a las diez"
```

`start_in` writes the fields a case names over the ones the class gave itself. `restore` is the
other door and means something stronger: a whole state, so a field it leaves out is cleared.

## The rings above

| ring | what it asks | how |
|---|---|---|
| 1 | does the agent hold its goldens? | `pinecall test` — the Node CLI today |
| 2 | does it hold on a real line? | `pinecall simulate --voice` — the Node CLI today |
| 3 | what does one real call score? | `pinecall eval <call-id>` |
| 4 | what did every call score? | `call.score`, written by the runtime at hang-up |
