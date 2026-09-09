# The console

```bash
pinecall ui                    # every agent this gateway holds
pinecall ui clinica-norte      # straight to one
```

It opens on `127.0.0.1`, on a port the kernel picks, for as long as the command runs, and it opens
in this machine's browser.

| screen | what it reads |
|---|---|
| Agents | which agents this gateway holds — so the front page is a list and not a URL shape |
| Calls · Live | the calls happening now; one watched call: transcript, marks, `STATE`, `ROOM`, `METRICS`, and the supervisor's six verbs |
| Sessions | every finished call; one of them read whole — envelope, latency, consent join, score, then every entry in `seq` |
| Evals | every run this agent's suites scored, the diff between two runs, and what each finished call was sealed with |
| Pipeline | the three providers of a voice turn, the anatomy of a turn as a waterfall, and the overrides an operator may change between two calls |
| Talk | a person reaches the agent from this tab, with this browser's microphone |

## It is the same console, compiled

The console is a React program, and it lives in `pinecall/agents` — one program, built once with
vite, so a screen is written in one place and both packages show the same digits. This gem ships
the **build**, in `console/`, the way a Rails engine ships its assets: a browser reads no
TypeScript, and installing this gem must not mean installing Node.

```bash
rake console:build      # rebuild it from ../agents and vendor it here. Needs pnpm, once
rake console:check      # is what is committed what that source would produce?
```

`console:check` hashes every byte of `../agents/src/cli/ui/console` and compares it with what
`console/BUILT.json` recorded at build time. It runs as part of `rake`, so a console edited next
door and not rebuilt here fails the gate rather than travelling. In a checkout with no `../agents`
it says so and passes — a consumer of the gem has nothing to rebuild.

**Never edit a file under `console/`.** It is the one generated thing in this gem.

## What Ruby owns

Everything around the bundle, and all of it is a containment decision.

- **Loopback only, and the kernel picks the port.** Nothing on the network can reach it, and two
  consoles on one laptop do not fight over a number.
- **Everything answers under a random nonce.** A process on this machine that scans the loopback
  finds a port; without the URL this process printed, it finds `404 not here` and nothing behind it.
- **The org key never reaches the browser.** The page holds no key and sends none: it asks this
  process, and this process signs the request and forwards it to the gateway. `test/ui/` asserts
  the absence — no key and no key's name in anything the browser is handed.
- **Only four headers cross.** `content-type`, `accept`, `last-event-id` and `range`. The cookies,
  the origin and the user agent are the browser's business and stop here.
- **The answer streams.** A log arrives over SSE as it happens, not when it ends: the server writes
  each chunk to the socket as the gateway hands it over. A browser that navigates away breaks the
  pipe and the door behind it is let go with it.
- **The port closes with the command.** There is no console on this machine when this process is
  not running.

It speaks HTTP/1.1 over a plain socket rather than through a web server, and every answer closes
its connection — which is what lets a body end at EOF without a length. On the loopback, for one
person, a connection per request costs nothing and the framing is exact.

## When it will not open

| it says | why |
|---|---|
| `ui needs a browser on this machine and this is an ssh session` | the Talk screen needs a microphone, and a microphone is a browser's on a screen |
| `…and no DISPLAY and no WAYLAND_DISPLAY` | a Linux with nothing to hand a URL to |
| `no key for <url>` | nothing in the environment, in `~/.pinecall/dev` or in `~/.pinecall/credentials` opens that gateway |
| `the console is not in this gem` | a checkout that never ran `rake console:build` |
