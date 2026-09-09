# frozen_string_literal: true

require_relative "ui/browser"
require_relative "ui/server"

module Pinecall
  # `pinecall ui [agent]`: the console on 127.0.0.1 for the life of the command.
  #
  # The console is the same React program the TypeScript package builds — the same screens, the
  # same stylesheet, the same bundle — served here instead. It is vendored into this gem already
  # compiled, the way a Rails engine ships its assets, because a browser reads no TypeScript and a
  # Ruby shop should not have to install Node to look at its own calls.
  #
  # What Ruby owns is everything around it: the loopback, the nonce, the key that never reaches
  # the page, and the forwarding of `v1/*` to the gateway.
  module UI
    # Where the compiled console lives inside the gem.
    FILES = File.expand_path("../../console", __dir__)

    NOT_VENDORED = "the console is not in this gem: run `rake console:build` in a checkout"

    module_function

    # Serve, open, wait, close. The org key is read once and spent only by the server.
    def run(argv, out: $stdout, err: $stderr, files: FILES, open: nil, env: ENV)
      return usage(out) if argv.first.to_s.start_with?("-")

      pointed = CLI::Env.pointed
      return CLI.no_key(pointed, err) if pointed.api_key.nil?

      why = Browser.headless(env:)
      unless why.nil?
        err.puts("pinecall: ui needs a browser on this machine and #{why}: run it where the screen is")
        return 2
      end
      unless File.directory?(files)
        err.puts(NOT_VENDORED)
        return 2
      end

      serve(argv.first, pointed, files, out:, err:, open:)
    end

    def serve(agent, pointed, files, out:, err:, open:)
      served = Server.open(door: pointed, files:)
      where = agent.nil? ? served.url : served.at("a/#{agent}")
      err.puts("pinecall: #{pointed.notice}") if pointed.notice
      # Which gateway and where the key came from: the one line that answers "why is it talking to
      # that box" before anybody has to grep for an exported name.
      out.puts("gateway: #{pointed.url} · key: #{CLI.said(pointed)}")
      out.puts("#{agent || "console"} · #{where}")
      (open || Browser.method(:open)).call(where)
      wait_for_the_person_to_stop_it
      0
    ensure
      served&.close
    end

    # Ctrl-C, and nothing else. The port closes with the command, which is the whole containment
    # story: there is no console on this machine when this process is not running.
    def wait_for_the_person_to_stop_it
      sleep
    rescue Interrupt
      nil
    end

    def usage(out)
      out.puts(<<~USAGE)
        usage: pinecall ui [agent]

          Opens the console on this gateway, on 127.0.0.1, for as long as the command runs: the
          agents it holds, their calls and logs as they happen, the finished sessions, the evals,
          the pipeline, and a page to talk to an agent with this browser's microphone.

          The key never reaches the browser: this process signs every request the console makes,
          under a URL only it printed. Ctrl-C closes the port with the command.
      USAGE
      2
    end
  end
end
