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

## The index has a golden of its own

The rings test the agent. None of them tests the **index**, and they cannot: a ring watches a
conversation, so it only ever sees the passage retrieval handed over. Whether a better one existed
and was missed is a question no conversation can answer, because the model never saw the one it
missed.

That is what a knowledge golden is for. One file beside the documents it asks about — a question,
and the chunk that should answer it:

```json
[
  { "asks": "¿cuánto tengo que pagar de copago?",
    "expects": "seguros-y-autorizaciones.md › Seguros, autorizaciones y facturación › Copagos" },
  { "asks": "¿tengo que ir en ayunas para el análisis?",
    "expects": "preparacion-de-pruebas.md › Preparación de las pruebas › Analíticas" }
]
```

`expects` is the heading path a chunk carries, which is what you can read off your own documents:
naming a file alone accepts any chunk of it, naming a heading accepts that section and what is
under it. Fifty to a hundred questions per base is the size that stops being noise.

```bash
pinecall knowledge eval                        # knowledge/golden.json beside agent.rb
pinecall knowledge eval --k 4                  # as many chunks as the class asks for
pinecall knowledge eval golden.json --base clinica-norte
```

```
clinica-norte · pplx-embed-context-v1-0.6b · 7 questions · recall@4 1.00 · nDCG@10 0.89 · 918 ms
```

| figure | means |
|---|---|
| `recall@k` | the share of questions whose chunk came back at all. **The one that matters**: a chunk the model never sees cannot be used, whatever its rank |
| `nDCG@10` | how high it ranked, discounted logarithmically. Two indexes that both find a passage are not equal if one puts it first and the other seventh, because `k` cuts |
| the model named | the embedder that wrote the vectors. Two scores are comparable only under one model |

Every question it missed is printed with what came back instead, and the verb **exits 1** when
anything did — so a base belongs in CI beside `rake test`. Both figures are computed by code, with
no model in the loop, so two runs over one base answer the same numbers.

A golden is fixed and the index is the variable. **A question is never softened so a change can
pass.** What you change instead is the documents, the chunking, `k`, `min_score`, or the embedder.

`client.knowledge.eval(base, questions, k:)` is the same thing from Ruby, when a rake task suits
you better than a shell line.

## Memory has one too, and it is the other table

`recall` makes the same promise over the other table — the facts this caller taught earlier calls,
the best six of them in front of the model — and it is just as invisible to a ring, for the same
reason. Whether a better fact existed and was missed is something no conversation can answer.

What differs from the index is the question. Nobody can name "the fact that should have won" for a
contact the way they can name a heading in a file they wrote, because a contact's facts are
whatever their earlier calls taught. So a memory question **brings its own facts**:

```json
[
  { "holds": ["Prefiere mañanas", "Paciente de la doctora Vidal desde 2024", "Alérgica a la penicilina"],
    "asks": "¿le va bien el martes?",
    "expects": ["Prefiere mañanas"] }
]
```

| field | means |
|---|---|
| `holds` | every fact memory holds about this question's contact, in the words a fact is written in |
| `asks` | what the caller just said, in their own words — this is the query `recall` is given |
| `expects` | the fact or facts that should come back |

**No contact of yours is read or written.** Each question's facts go to a scratch contact of your
org, `recall` runs, and they are deleted again before the next question — which is also what makes
the figures the real ranking: the same two index scans, the same fusion, the same embedder a call
uses, rather than an arithmetic in a test.

**A fact answers when what came back CONTAINS what you expected**, folded for case, accents and
whitespace. A fact is a sentence a model wrote and you know the substance, not the wording: so
`"Prefiere mañanas"` is answered by *"Prefiere mañanas, nunca después de comer"*, and an expected
`"Alérgica a la penicilina"` is not answered by *"Alérgica"*, which says less than you asked for.

```bash
pinecall memory eval                  # memory/golden.json beside agent.rb
pinecall memory eval --k 1            # the best fact alone: is the right one first?
```

```
memory · pplx-embed-context-v1-0.6b · 7 questions · recall@6 1.00 · nDCG@10 0.78 · 12107 ms
```

The two figures are the index's two, generalised once: a question may expect several facts, so
`recall@k` is the share of the facts you asked for that came back and `nDCG@10` is normalised by
the best places they could have taken.

**Write questions whose contact holds more facts than a turn asks for.** A turn takes six; a
contact with four gets all four back whatever the ranking did, and `recall@6 1.00` then says
nothing at all. Clínica Norte's golden holds eight or nine per question for that reason, and the
way to make recall bite is a smaller `k`:

```
$ pinecall memory eval --k 1
memory · pplx-embed-context-v1-0.6b · 7 questions · recall@1 0.57 · nDCG@10 0.57 · 11568 ms
  missed: me han mandado una resonancia, ¿me la puedo hacer? → wanted Le pusieron un marcapasos en 2023, got Prefiere que le llamen don Julián
  missed: me han pedido una radiografía de la espalda → wanted Está embarazada de cinco meses, got Su médico habitual es el doctor Ferrán
  missed: llamadme mañana a las nueve para confirmar → wanted Trabaja de noche, Prefiere que le escriban por WhatsApp, got Prefiere que le llamen Aixa
```

Every question memory did not answer whole is printed with what came back instead, and the verb
**exits 1** when anything did. A golden is fixed and the ranking is the variable here too: what you
change is the words a fact is written in — `memory remember:` is that vocabulary — the embedder,
or `k`.

`client.memory.eval(questions, k:)` is the same thing from Ruby.

## Is there a score for retrieval on a call?

No, and the reason is worth knowing rather than working around.

`call.score` carries the panel's verdicts, and the one that touches retrieval is `grounded`: it
checks that every price, hour, date and name the agent stated appears in the evidence it was given —
and since a lookup arrives as a tool result, that evidence **is** the chunks. So the rate of `held`
over calls carrying a `docs.sources` entry is the precision of retrieval on real traffic, for free.

What no live call can score is whether the index missed a **better** passage, because there is no
truth to compare against outside a golden. The judge says the answer was grounded in what it was
given; the golden says what it was given was the best there was.

What a call does carry, per turn, is the fact of it: `docs.sources` with the query, every chunk and
its score, and `took_ms`; `memory.ops` with the facts recalled; `metrics.eou` with what the lookup
cost the caller in silence. The runtime's `docs/retrieval/spec.md` is the contract for all of it.

