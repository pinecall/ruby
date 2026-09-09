# The view, and the three regions of a prompt

The prompt has three regions, in this order, always:

| region | what is in it | when it changes |
|---|---|---|
| `static` | the class comment · the knowledge marker · the framework's rules and protocols · every tool's name and comment | never during a call |
| `history` | the summaries a `collapse` left where a stretch of the call used to be | when the app collapses |
| `dynamic` | **the view** | on every state change |

The cut between static and dynamic is where the provider's cache is cut. Only the dynamic region
may move between two turns, and only the region whose text actually changed is sent again.

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
<%= memory kinds: %w[preference health] %>
<%= retrieved min_score: 0.4 %>

<% if stage == :identify -%>
Saluda y pide nombre y teléfono. Nada más hasta identificar al paciente.
<% end -%>

<% if identified -%>
Hablas con <%= patient.nombre %>, ya en la ficha: no vuelvas a pedirle el nombre.
<% end -%>

<% if slots.any? -%>
## Horas libres, en orden

<% slots.each do |hueco| -%>
<%= hueco.cuando %> con <%= hueco.doctor %>
<% end -%>

<% if call[:channel] == "phone" -%>
Ofrece como máximo dos de estas horas y pregunta cuál prefiere.
<% end -%>
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

## Markers: the holes the gateway fills

A marker is a placeholder this package writes and never resolves. The gateway reads the line, does
the work, and replaces it with text.

| written | becomes |
|---|---|
| `<%= memory kinds: %w[preference] %>` | `<!-- memory: {"kinds":["preference"]} -->` |
| `<%= retrieved min_score: 0.4 %>` | `<!-- retrieved: {"min_score":0.4} -->` |
| `knowledge "./file.md"` on the class | `<!-- knowledge: ./file.md -->`, in the static region |
| `<%= marker "precio", { sku: 4 } %>` | `<!-- precio: {"sku":4} -->`, for a filler you run |

A class configured with `memory` gets the memory marker even if its view never asks: configuring
memory is expecting the caller to be remembered.

**A render prop** shapes whatever the gateway finds. A block cannot travel inside a marker, so it
stays behind under an id the marker carries:

```erb
<%= memory(kinds: %w[preference]) { |facts| "Recuerda: #{facts.join(", ")}" } %>
```

## Reading the prompt

```bash
pinecall prompt agent.rb
pinecall prompt agent.rb --stage book --resumed
pinecall prompt agent.rb --state 'slots=[{"cuando":"el martes a las diez"}]'
```

No gateway, no key, no network — the whole point of the design is that the prompt is a function
you can call. In a test it is the same function:

```ruby
regions = Pinecall.render(agent, resumed: true)
regions.static     # the cached prefix
regions.dynamic    # what the view said
Pinecall.show_prompt(agent)   # all three, under their headers
```

## Collapsing a long call

```ruby
collapse "La paciente ya está identificada y ha visto las horas del martes."
```

The state is untouched. What collapses is the memory of how it got here, which is what a long call
runs out of room for. The sentence lands in the history region under a `<!-- collapsed: … -->`.
