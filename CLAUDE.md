# pinecall (Ruby) — working agreement

The application's side of Pinecall, in Ruby: a class whose declared fields are the state, whose
`tool` methods are the model's verbs, whose comments are the prompt, and whose ERB view is the
part of that prompt which changes. Reply to the human in Spanish; code, comments and commit
messages in English.

**Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing anything.** §3 is the table that says
what each piece corresponds to in the TypeScript package and why it is different here — a change
that ignores it is a change that makes the two drift. How to build an agent is `docs/`.

## Workflow

```bash
rake              # what CI runs: the tests, the example's own suite, then the signatures
rake test
rake examples     # the ring-0 suite a customer writes, run the way they run it
rake rbs

bin/pinecall prompt examples/clinica_norte/agent.rb --stage book
bin/pinecall run examples/clinica_norte/agent.rb
```

`bin/pinecall` is the bin of a checkout: it adds `lib/` and the sibling `../protocol/ruby/lib`.
`exe/pinecall` is what a gem install puts on the PATH and must never mention a sibling.

## Structure

`lib/pinecall/agent*` is the class, `lib/pinecall/client*` is the socket, `bridge.rb` is the only
place the two know about each other, and `view.rb` + `regions.rb` are the prompt. Nothing in
`lib/pinecall/agent/` may know what a websocket is.

## Docs are part of the change

A change lands with the page that describes it, in the same commit.

| you changed | you edit |
|---|---|
| a module, an entity, the correspondence with the TypeScript package | `ARCHITECTURE.md` |
| a CLI verb or a flag | `README.md` and `docs/the-cli.md` |
| anything a person writing an agent types | the `docs/` page for it |
| a rule that is refused at load | `docs/writing-an-agent.md`, with the sentence the refusal says |
| anything a user would notice | `CHANGELOG.md`, under Unreleased |

Before renaming anything public: `grep -rn "<old name>" lib test examples docs *.md sig`.

When a doc and the code disagree, the code is what happened and the doc is the bug.

## Rules the tests enforce

- **Tools are the only writers of state.** A write with no author raises `UnauthoredWrite`. The
  author rides `Fiber[]`, never a module-level variable: one process serves many calls at once.
- **A declaration is refused at load, never at the first call.** No docstring, a positional
  argument, a stage the class never declared, `pii:` naming a parameter that is not there.
- **Only the region whose text changed is sent again.** The static prefix goes up once per call.
- **The three regions keep their order.** static · history · dynamic. The cut is where the cache is.
- **Nothing here imports LiveKit, a model vendor, or the runtime.** Commands out, entries in.
- **The wire is never hand-written.** Every shape comes from `pinecall-protocol`, which is
  generated. A field this package needs is a schema change in `pinecall/protocol` first.

## What a review comes back to

- One definition per thing. Before writing a constant or a helper, `grep -rn` for it.
- No dead code and nothing "for later". A symbol with no user outside its own file and its own
  test is deleted by the card that notices it.
- No module-level mutable state. Per call, per mount, or on the fiber.
- Every file opens with a line saying what it is. 400 lines is the ceiling, 150 the norm.
- Tests read as sentences: `test_a_write_outside_a_tool_is_refused_by_name`.

## Traps — each one cost an afternoon

- **`method_added` fires for every method**, including the ones this package defines itself. The
  guard is `@pending_tool` being nil; do not add a second mechanism beside it.
- **A thread that waits for an entry must not be the thread that reads them.** `agent.register` is
  answered by an entry, so the declaration goes up on its own thread. That was a real deadlock and
  `test/client/socket_test.rb` is what found it.
- **`memory` means two things** in a template if you let it. The tag writes the marker; what the
  agent already knows about the caller reads as `remembered`.
- **A state default that is a literal `[]`** is duplicated per instance on purpose. If you change
  `opening`, check that two calls never share one list.
- **zsh `noclobber`**: `cat > file` refuses to overwrite and leaves the old file in place. `>|`.

## Commits

`Bernardo Castro <me@bernardocastro.dev>`. No `Co-Authored-By`, no generated-with trailers.
Versions and tags are the human's call — never pick a number, never tag.
