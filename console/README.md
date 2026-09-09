# The console, compiled

This directory is **generated**. It is the same React program `pinecall/agents` builds with vite —
the same screens, the same stylesheet, the same bundle — vendored here already compiled, the way a
Rails engine ships its assets: a browser reads no TypeScript, and a Ruby shop should not have to
install Node to look at its own calls.

```bash
rake console:build      # rebuilds it from ../agents and copies it here
rake console:check      # says whether what is here is what that source would produce
```

`rake console:build` needs the `pinecall/agents` repository checked out beside this one, with its
dependencies installed (`pnpm install`). Nothing else in this gem needs Node, ever.

What Ruby owns is everything around the bundle: `lib/pinecall/ui/server.rb` binds the loopback,
picks a nonce, serves these files under it, and forwards `v1/*` to the gateway with the org key on
the header. The key never reaches the page.
