# The CLI

```
pinecall <verb>

  prompt [file]                 the exact prompt this agent would produce   (no gateway)
  run [file]                    the agent registered and answering
  ui [agent]                    the console on 127.0.0.1: calls, sessions, evals, and a page to talk
  whoami                        which gateway, and where this key came from
  knowledge push|list|drop|eval a folder of Markdown as a base the agent retrieves from,
                                and a golden that says how well it answers
  memory [forget] CONTACT       what is remembered about a contact, and forgetting it
  memory eval [GOLDEN]          a golden that says whether recall brings the right facts back
  keys add|rm|list VENDOR       the provider keys this org brought of its own
  version
```

`file` is `agent.rb` in the current directory when nobody says otherwise, as every example has it.

## prompt

The one verb that needs no gateway, no key and no network. It loads the class, puts it in the
state the flags describe, and prints every block of the prompt under its own header —
`── identity (static) ──`, `── history ──`, `── view (dynamic) ──` — in the order it is sent.

```bash
pinecall prompt
pinecall prompt examples/clinica_norte/agent.rb --stage book
pinecall prompt --state 'patient={"nombre":"Marta Ruiz"}' --resumed
```

| flag | what it does |
|---|---|
| `--stage <name>` | opens in that stage |
| `--state <field>=<json>` | sets one field. JSON when it parses as JSON, the word itself when not |
| `--resumed` | renders as a call that is being picked up again |

## run

The agent registered and answering: **the process you deploy**. It binds no port and serves no
page. Ctrl-C closes the socket, and every agent's slug is free the moment it shuts.

```bash
pinecall run examples/clinica_norte/agent.rb
# clinica-norte is answering on http://localhost:8080 (3 routes)
```

## ui

The console, served on the loopback for as long as the command runs, and opened in this machine's
browser. It is [the compiled React console](the-console.md) the TypeScript package builds.

```bash
pinecall ui                    # every agent this gateway holds
pinecall ui clinica-norte      # straight to one
```

Three things it will not do: run where there is no browser (over ssh, or a Linux with no display,
it says so and exits 2), open a port on anything but `127.0.0.1`, or let the org key reach the
page. Ctrl-C closes the port with the command.

## knowledge

The base an agent's `docs` names is a folder of Markdown, pushed whole under that name. The
gateway cuts it by heading, embeds it, and from then on the platform's `search` tool answers from
it — at the end of the caller's turn, as a tool result the model reads in the history.

```bash
pinecall knowledge push                                   # knowledge/docs beside agent.rb, as its `docs` base
pinecall knowledge push ./knowledge/docs --base clinica-norte
# clinica-norte · 2 files · 14 chunks · 312 ms
pinecall knowledge list
# clinica-norte · 14 chunks · pushed 2026-09-10 10:26
pinecall knowledge drop clinica-norte

pinecall knowledge eval                                   # knowledge/golden.json beside agent.rb
# clinica-norte · pplx-embed-context-v1-0.6b · 7 questions · recall@4 1.00 · nDCG@10 0.89 · 918 ms
```

| | |
|---|---|
| `push [DIR] [--base NAME]` | every `*.md` under DIR, recursively, each as its path relative to DIR and its text. The base is **replaced**: a file not in the folder is gone from it |
| defaults | DIR is `knowledge/docs` beside the `agent.rb` here; NAME is what that agent's `docs` says, or its slug |
| `list` | every base this org has pushed: name, chunks, when |
| `drop BASE` | the base is gone; an agent still naming it retrieves nothing until the next push |
| `eval [GOLDEN] [--base NAME] [--k N]` | every question of a golden asked of the base, and `recall@k` and `nDCG@10` — computed by code with no model, so two runs answer the same numbers. Prints every question it missed with what came back instead, and **exits 1** when anything did, so a base can be held to its golden in CI. GOLDEN is `knowledge/golden.json` beside the `agent.rb` here: a JSON list of `{ "asks", "expects" }`, where `expects` is the heading path the answer should carry. A golden is fixed and the index is the variable |

A refusal is printed as the gateway wrote it — `pinecall: 503: this gateway keeps no knowledge:
it runs on a dev key` — and the verb exits 1.

## memory

```bash
pinecall memory +34600123456
# - Prefiere que le llamen Marta  (preference · since 2026-09-01)
# - Alérgica a la penicilina  (health · since 2026-07-31 · until 2026-09-01)
pinecall memory forget +34600123456
# forget everything about +34600123456? [y/N] y
# +34600123456: 2 facts forgotten
```

The history is current facts first; a fact a later call superseded keeps its dates and is dimmed
on a terminal. `forget` is the right to be forgotten: it asks once when stdin is a terminal and
not at all from a pipe, and it is the one verb that removes rows.

```bash
pinecall memory eval                        # memory/golden.json beside agent.rb
pinecall memory eval --k 1                  # the best fact alone: is the right one first?
pinecall memory eval test/recall.json
# memory · pplx-embed-context-v1-0.6b · 7 questions · recall@6 1.00 · nDCG@10 0.78 · 12107 ms
```

| the line | what it takes |
|---|---|
| `eval [GOLDEN] [--k N]` | every question of a golden asked of `recall`, and `recall@k` and `nDCG@10` — computed by code with no model, so two runs answer the same numbers. GOLDEN is `memory/golden.json` beside the `agent.rb` here: a JSON list of `{ "holds", "asks", "expects" }`, where `holds` is what memory holds about that question's contact and `expects` is the fact or facts that should come back. No contact of yours is read or written — each question's facts go to a scratch contact and are deleted again. Prints every question memory did not answer whole with what came back instead, and **exits 1** when anything did |

A fact answers when what came back CONTAINS what was expected, folded for case, accents and
whitespace: a fact is a sentence a model wrote, and a golden names the substance and not the
wording. `docs/testing-an-agent.md` has the whole of it.

## keys

The provider keys this org brought of its own. A key added here is the org's own account with
that vendor, and every call of this org runs on it from the next one; every vendor nobody
brought runs on the box's own key. No operator is involved: the org's own API key is what opens
these doors, and there is no way to name another org at them.

```bash
pinecall keys add elevenlabs
# elevenlabs key:            (typed, and echoed nowhere)
# elevenlabs
echo "$ELEVEN_API_KEY" | pinecall keys add elevenlabs
pinecall keys list
# anthropic
# elevenlabs
pinecall keys rm elevenlabs
# elevenlabs
```

| | |
|---|---|
| `add VENDOR` | the key is read from **stdin** and never from a flag: `ps` shows every argument to every user on the box, and a key pasted as an argument is a key in the shell history. On a terminal it is typed with nothing echoed; off one it is one piped line. On success it prints the vendor and nothing else |
| `rm VENDOR` | that vendor goes back to the box's own key. A vendor this org never brought is the gateway's `404`, as it wrote it |
| `list` | the vendors this org brought, by name — **never a key**, not a value, not a prefix, not a fingerprint. No door of the runtime answers with a provider key, so a key that was lost was lost at the vendor and the fix is to add it again |

A vendor this build does not run is refused with the list of the ones it does:
`pinecall: 400: no vendor named 11labs; this build runs: anthropic, deepgram, elevenlabs,
openai, soniox, whatsapp`.

## whoami

Which gateway this terminal is pointed at, and **where its key came from** — never the key itself.

```bash
pinecall whoami
# gateway: http://localhost:8080
# key: ~/.pinecall/dev — the local gateway's own
```

## Where the key comes from

One order, for every verb:

1. the URL: `PINECALL_URL` → the local gateway's `~/.pinecall/dev` → the single row a login kept →
   `http://localhost:8080`;
2. **if that URL is the local dev gateway, its own dev key** — and an exported `PINECALL_API_KEY`
   is ignored, *out loud*. That gateway honours its own key and no other, and a bare `403` with no
   sentence in it cost this project an afternoon twice;
3. otherwise `PINECALL_API_KEY` → the `credentials` row for that URL → `PINECALL_DEV_KEY`;
4. nothing at all: the verb says so and exits 2.

`env | grep PINECALL` is still the first thing to run when a door refuses you and will not say why.

This CLI **reads** `~/.pinecall/credentials` and `~/.pinecall/dev` and writes neither: `pinecall
login` belongs to the Node CLI, and one program keeping a key on a machine is enough. A file any
other account on the box can read is treated as absent.

## Planned

Typing one of these says what it will be and exits 0. A verb leaves that table in the commit that
writes it.

| verb | what it will be |
|---|---|
| `chat` | the same agent in this terminal, and a written caller against it |
| `test` | ring 1: the goldens, through the agent in this process, scored by the gateway |
| `eval` | ring 3: one real call re-evaluated by the runtime's code checks |
| `login` | the key typed once — today it is the Node CLI's, and this one reads what it kept |
