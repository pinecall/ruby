# The view, and the blocks of a prompt

The prompt is a list of named **blocks** in two regions, in this order, always:

| region | when it changes | the framework's blocks |
|---|---|---|
| `static` — before the history, cached by the provider | never during a call | `identity` (the class comment · the framework's rules and protocols) · `knowledge` (the marker) · `tools` (every tool's name and comment) |
| the history — the turns, and the summaries a `collapse` left | the runtime writes it; the app never does | |
| `dynamic` — after the history, replaced every turn | on every state change | `view` — the last thing the model reads |

The cut between the two regions is where the provider's cache is cut. A static block may not
read the state (it is refused at render if it tries); a dynamic block is rendered against it on
every change. The bridge sends each block **by name and only when its own text changed**: a
`when:` that opens a tool rewrites `tools` and nothing else, and the provider reads `identity`
and `knowledge` back from its cache.

## The view is a template, beside the class

It is a view in the sense Rails means: a file of its own, mostly prose with holes in it, rendered
with the state in scope. `views/<slug>.erb`, beside the file the class is written in — the
convention this package has instead of a setting.

```
examples/clinica_norte/
  agent.rb
  views/clinica-norte.erb
```

```erb
## Lo que recordamos de este paciente
<%= memory kinds: %w[preference health] %>

## De la base de conocimiento
<%= retrieved k: 4, min_score: 0.5 %>

<% if stage == :identify -%>
Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
<% end -%>

<% if identified -%>
Hablas con <%= patient.nombre %>, ya en la ficha: no vuelvas a pedirle el nombre.
<% end -%>

<% if proposed && booking.nil? -%>
Ha nombrado <%= proposed.cuando %>. Léesela tal cual y espera un sí antes de reservar.
<% end -%>
```

Every state field is in scope by its own name, derived fields included. So is what surrounds the
call: `resumed`, `call[:channel]`, `call[:from]`, and `remembered.has?("médico habitual")`.

`-%>` swallows the newline after a tag, which is how a template stays readable and its output
stays tight. Whatever slips through is tidied anyway: no trailing spaces, never more than one
blank line in a row, nothing hanging off either end.

Somewhere else, or inline:

```ruby
view "views/reception.erb"      # relative to the file the class is in
view template: <<~ERB           # small enough to live inside the class
  <% if stage == :identify -%>
  Saluda y pide nombre y teléfono.
  <% end -%>
ERB
```

## Blocks of your own

A class adds blocks with `prompt`, by region. Each one is a template of its own,
`views/<slug>/<name>.erb`, beside the class:

```ruby
prompt static: %i[faq], dynamic: %i[availability]
```

```
examples/clinica_norte/
  agent.rb
  views/clinica-norte.erb                 the view
  views/clinica-norte/availability.erb    a dynamic block: the free slots, sent when they change
```

```erb
<%# views/clinica-norte/availability.erb %>
<% if slots.any? -%>
## Horas libres, en orden

<% slots.each do |hueco| -%>
<%= hueco.cuando %> con <%= hueco.doctor %>
<% end -%>
<% end -%>
```

The send order is the framework's static blocks, then yours in the order you declared them,
then the history, then your dynamic blocks, and `view` last: the view is always the last thing
the model reads. A name must match `^[a-z][a-z0-9_]*$`, cannot be one of the framework's four,
and its template must exist — all three are refused when the class loads, with the path.

A **static** block is prose the provider caches: a FAQ, a price list, the house style. It is
rendered against nothing, so a template that asks the state a question is refused at render,
naming the template and the field:

```
a static block cannot read the state: faq.erb reads slots
```

`prompt` reads `slug`, so a class that names its own slug does so above that line.

## Markers: the holes the gateway fills

A marker is a placeholder this package writes and never resolves. The gateway reads the line, does
the work, and replaces it with text.

| written | becomes | filled with |
|---|---|---|
| `<%= memory kinds: %w[preference], limit: 6 %>` | `<!-- memory: {"kinds":["preference"],"limit":6} -->` | the contact's facts, one `- ` line each, after the caller's turn and before the model reads |
| `<%= retrieved k: 4, min_score: 0.5 %>` | `<!-- retrieved: {"k":4,"min_score":0.5} -->` | the chunks of the base `docs` names, `### path › heading` then the text |
| `knowledge "./file.md"` on the class | `<!-- knowledge: ./file.md -->`, the whole `knowledge` block | the file's text, once per call, so the cached prefix never moves |
| `<%= marker "precio", { sku: 4 } %>` | `<!-- precio: {"sku":4} -->` | whatever a filler you run puts there |

The payload is the keywords as you typed them, as JSON, and the runtime reads them by those
names: `kinds`, `limit` (memory), `k`, `min_score` (retrieved). Write the heading the model reads
above the marker, in the template — the fill is the facts or the chunks and nothing else. A
marker never delays a reply: the runtime gives both fills one budget, and past it the turn goes
on with the marker empty and an `error` entry in the log saying which was skipped.

A class configured with `memory` gets the memory marker even if its view never asks: configuring
memory is expecting the caller to be remembered.

**A render prop** shapes whatever the gateway finds. A block cannot travel inside a marker, so it
stays behind under an id the marker carries — one registry per prompt, so an id is never used by
two blocks:

```erb
<%= memory(kinds: %w[preference]) { |facts| "Recuerda: #{facts.join(", ")}" } %>
```

The id travels as `fill` in the payload. This release the runtime renders the facts in its own
shape and does not call the block back; it stays behind for the release that does.

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
prompt[:availability]
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
