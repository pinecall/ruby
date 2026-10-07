# frozen_string_literal: true

require_relative "serve/loading"
require_relative "serve/held"

module Pinecall
  # The entry the one `pinecall` CLI starts a Ruby agent with: `start` holds the agents and serves
  # their calls, `prompt` prints a prompt. The CLI runs it as
  # `ruby -r pinecall -e 'exit Pinecall::Serve.main(ARGV)' -- start --file … --slug …`.
  #
  # It reads its door from `PINECALL_URL`, `PINECALL_KEY` and `PINECALL_ENV` alone, and leaves on
  # SIGINT, SIGTERM or the end of its stdin, draining first; a second signal leaves now.
  module Serve
    USAGE = <<~USAGE
      usage: serve start --file <agent.rb> --slug <slug> [--file … --slug …] [--console] [--events] [--prod]
             serve prompt --file <agent.rb> --slug <slug> [--state field=json]… [--channel name] [--show-machine]
    USAGE

    NO_DOOR = "serve start reads PINECALL_URL and PINECALL_KEY from its environment, and one was not set"

    WORLDS = %w[sandbox production].freeze

    module_function

    # Run one verb and answer its exit status: 2 when it cannot run at all, with the sentence on `err`.
    def main(argv, out: $stdout, err: $stderr, env: ENV, input: $stdin, signals: nil)
      verb, *rest = argv
      case verb
      when "start" then start(Loading.parse(rest), out:, err:, env:, input:, signals:)
      when "prompt" then prompt(Loading.parse(rest), out:)
      else err.puts(USAGE) || 2
      end
    rescue CannotServe, NotConnected => e
      err.puts(e.message)
      2
    end

    # Hold every agent named until asked to leave; 0 once they drained.
    def start(flags, out:, err:, env:, input:, signals:)
      client = client_from(env, prod: flags.prod)
      classes = flags.served.map { |served| [served, Loading.load_served(served)] }
      said(client, out:, err:, events: flags.events)
      mounted = classes.map do |served, klass|
        Pinecall.mount(klass, client:, slug: served.slug, takes_unclaimed: !flags.console)
      end
      held = Held.new(client, mounted)
      asked = signals || trapped
      client.on_stopped { |why| err.puts(why) || asked.push(:stopped) }
      client.connect
      err.puts("#{mounted.map(&:slug).join(", ")} answering on #{client.url}") if flags.events
      Thread.new { ended(input, asked) }
      leave(held, asked, err)
    end

    # Load the class, open it in the state the pairs name, and print its prompt. No gateway, no key.
    def prompt(flags, out:)
      klass = Loading.load_served(flags.served.first)
      instance = klass.new.seal
      instance.start_in(flags.state) unless flags.state.empty?
      out.puts(Pinecall.show_prompt(instance, line: { channel: flags.channel }))
      out.puts("\n#{machine(instance)}") if flags.show_machine
      0
    end

    # The tools the class declares, marking the ones this state shows, under the stage.
    def machine(instance)
      shown = instance.visible_tools.map { |spec| spec[:name] }
      stage = instance.respond_to?(:stage) ? " stage: #{instance.stage}" : ""
      header = "#{Prompt.header_for("tools")}#{stage}"
      return "#{header}\n\n  this agent declares no tools" if instance.tools.empty?

      lines = instance.tools.map { |spec| "  #{shown.include?(spec[:name]) ? "●" : "○"} #{spec[:name]}" }
      [header, "", *lines].join("\n")
    end

    # Where the calls went, and what became of the tools running: one line on stderr.
    def drain_line(drained)
      return "draining · no live calls" if drained.handed + drained.parked + drained.tools == 0

      parts = ["draining"]
      parts << "#{plural(drained.handed, "live call")} handed over" if drained.handed.positive?
      parts << "#{plural(drained.parked, "live call")} kept for the next process" if drained.parked.positive?
      parts << "#{plural(drained.finished, "tool")} finished" if drained.finished.positive?
      parts << "#{plural(drained.tools - drained.finished, "tool")} cut" if drained.tools > drained.finished
      parts.join(" · ")
    end

    def plural(count, noun) = "#{count} #{noun}#{count == 1 ? "" : "s"}"

    def client_from(env, prod:)
      url, key = env["PINECALL_URL"], env["PINECALL_KEY"]
      raise CannotServe, NO_DOOR if url.to_s.empty? || key.to_s.empty?

      world = prod ? "production" : env["PINECALL_ENV"]
      world = nil if world.to_s.empty?
      raise CannotServe, "PINECALL_ENV is sandbox or production, not #{world}" unless world.nil? || WORLDS.include?(world)

      Client.new(url:, api_key: key, env: world)
    end

    # Listening starts before connect, so `agent.registered` is the first line of a pipe.
    def said(client, out:, err:, events:)
      client.on_entries do |entry|
        if events
          out.puts(JSON.generate({ type: entry.type, agent: entry.agent, call: entry.call, data: entry.data }))
        elsif entry.type == "agent.registered"
          out.puts("#{entry.agent}  · answering as #{entry.data[:app]}")
        end
      end
      client.on_errors { |error| err.puts("#{error.class}: #{error.message}") }
    end

    # A trap only pushes: the main thread does the leaving, as a trap may not take a lock.
    def trapped
      asked = Thread::Queue.new
      %w[INT TERM].each { |signal| Signal.trap(signal) { asked.push(:signalled) } }
      asked
    end

    # The process that started this one is gone when its end of the pipe closes.
    def ended(input, asked)
      input.read
    rescue IOError, SystemCallError
      nil
    ensure
      asked.push(:ended)
    end

    # The first reason drains (unless the org already stopped it); a second one closes at once.
    def leave(held, asked, err)
      if asked.pop == :stopped
        held.close
        return 0
      end
      outcome = Thread::Queue.new
      Thread.new { outcome.push(held.stop) }
      Thread.new { asked.pop && outcome.push(:again) }
      drained = outcome.pop
      drained == :again ? held.close : err.puts(drain_line(drained))
      0
    end
  end
end
