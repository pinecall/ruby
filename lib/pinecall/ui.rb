# frozen_string_literal: true

require_relative "ui/browser"
require_relative "ui/server"

module Pinecall
  # `pinecall ui [agent]`: serve the console on 127.0.0.1 while the command runs.
  #
  # The console bundle is vendored pre-built so Ruby users need no Node. This side provides the
  # loopback server, the URL nonce, and `v1/*` forwarding signed with a key the page never sees.
  module UI
    FILES = File.expand_path("../../console", __dir__)

    NOT_VENDORED = "the console is not in this gem: run `rake console:build` in a checkout"

    module_function

    # Serve, open the browser, and block until Ctrl-C. Only the server uses the key.
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
      out.puts("gateway: #{pointed.url} · key: #{CLI.said(pointed)}")
      out.puts("#{agent || "console"} · #{where}")
      (open || Browser.method(:open)).call(where)
      wait_for_the_person_to_stop_it
      0
    ensure
      served&.close
    end

    # The port closes with the command, so no console outlives it.
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
