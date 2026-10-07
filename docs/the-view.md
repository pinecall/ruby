# The view, and the blocks of a prompt

The prompt is a list of named **blocks** in two regions, in this order, always:

| region | when it changes | the blocks |
|---|---|---|
| `static` — before the history, cached by the provider | never during a call | `identity` (the class comment · the framework's rules and protocols · how to write on the call's channel and medium) · `knowledge` (the page the agent knows by heart, written by the gateway from its settings) · `tools` (every tool's name and comment) |
| the history — the turns, the lookups, and the summaries a `collapse` left | the runtime writes it; the app never does | |
| `dynamic` — after the history, replaced every turn | on every state change | `view` — the last thing the model reads |

There are four blocks, the same four for every agent. The cut between the two regions is where the
provider's cache is cut, and the bridge sends each block **by name and only when its own text
changed**: a `when:` that opens a tool rewrites `tools` and nothing else, and the provider reads
`identity` and `knowledge` back from its cache.

**Every word of every block is yours.** Nothing that arrived from outside the conversation is ever
put in one — not a fact memory kept from an earlier call, not a chunk of a document. Those reach
the model as a **tool result**, JSON-encoded, in the history, which is the place both vendors name
for content a model should read as information and not as an instruction. The whole rule, and the
guidance it follows, is `runtime/docs/security/prompt-injection.md`.

## The view is a template, beside the class

It is a view in the sense Rails means: a file of its own, mostly prose with holes in it, rendered
with the state in scope. The object renders itself. `views/<slug>.erb`, beside the file the class
is written in — the convention this package has instead of a setting.

```
examples/clinica_norte/
  agent.rb
  views/clinica-norte.erb
```

```erb
<% if stage == :identify -%>
Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
<% end -%>

<% if identified -%>
Hablas con <%= patient.nombre %>, ya en la ficha: no vuelvas a pedirle el nombre.
<% end -%>

<% if remembers?("médico habitual") -%>
Ofrece primero las horas de su médico habitual.
<% end -%>

<% if proposed && booking.nil? -%>
Ha nombrado <%= proposed.cuando %>. Léesela tal cual y espera un sí antes de reservar.
<% end -%>
```

Every state field is in scope by its own name, derived fields included. So is what surrounds the
call: `resumed`, `call[:channel]`, `call[:from]`.

`-%>` swallows the newline after a tag, which is how a template stays readable and its output
stays tight. Whatever slips through is tidied anyway: no trailing spaces, never more than one
blank line in a row, nothing hanging off either end.

Two helpers sit beside the state, for the two things prose alone does not do:

| in a template | what it is |
|---|---|
| `state` | the whole reading, when the template wants to pass it on rather than ask it something |
| `each_line(items)` | a list, one item per line, the way a person would read it out |

Somewhere else, or inline:

```ruby
view "views/reception.erb"      # relative to the file the class is in
view template: <<~ERB           # small enough to live inside the class
  <% if stage == :identify -%>
  Saluda y pide nombre y teléfono.
  <% end -%>
ERB
```

## What the agent already knows about this caller

`remembers?("médico habitual")` answers whether memory holds something about this caller matching
those words. The runtime supplies the facts; a render nobody gave any — `pinecall prompt`, a ring-0
test that says nothing about it — answers no rather than guessing.

It is a **question**, and that is the whole of what a view does with memory. The fact itself never
appears in the prompt: it reached the model as the result of the platform's `recall` tool, in the
history. What the view adds is the sentence *you* want said when the answer is yes.

```ruby
Pinecall.render(agent, remembered: ["su médico habitual es la doctora Vidal"])[:view]
```

The same is true of the knowledge base. The base attached to the agent, and how to search it, are
the world's settings, not the class's; the platform runs the search itself, at the end of the
caller's turn, through its `search` tool. The view says nothing about it.

What the agent knows by heart, on the other hand, is a page the org wrote in the agent's settings,
so it is its own words and goes where those go: the `knowledge` block, whole, in the cached prefix,
written there by the gateway once per call. The view says nothing about it either.

## Reading the prompt

```bash
pinecall prompt agent.rb
pinecall prompt agent.rb --stage book --resumed
pinecall prompt agent.rb --state 'slots=[{"cuando":"el martes a las diez"}]'
```

No gateway, no key, no network — the whole point of the design is that the prompt is a function
you can call. It prints one section per block, `── identity (static) ──` … `── history ──` …
`── view (dynamic) ──`, so which half is cached is visible at a glance. In a test it is the same
function:

```ruby
prompt = Pinecall.render(agent, resumed: true)
prompt[:view]             # the text of one block, by name
prompt[:knowledge]
prompt.static             # the blocks before the history, in send order
prompt.instructions       # those joined: the one text the provider caches
prompt.blocks             # every block, in send order
Pinecall.show_prompt(agent)   # the page, under its headers
```

## Collapsing a long call

```ruby
collapse "La paciente ya está identificada y ha visto las horas del martes."
```

The state is untouched. What collapses is the memory of how it got here, which is what a long call
runs out of room for. The sentence lands in the history under a `<!-- collapsed: … -->`.
