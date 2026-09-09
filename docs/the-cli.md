# The CLI

```
pinecall <verb>

  prompt [file]   the exact prompt this agent would produce   (no gateway)
  run [file]      the agent registered and answering
  ui [agent]      the console on 127.0.0.1: calls, sessions, evals, and a page to talk
  whoami          which gateway, and where this key came from
  version
```

`file` is `agent.rb` in the current directory when nobody says otherwise, as every example has it.

## prompt

The one verb that needs no gateway, no key and no network. It loads the class, puts it in the
state the flags describe, and prints the three regions.

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
