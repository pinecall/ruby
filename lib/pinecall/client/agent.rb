# frozen_string_literal: true

module Pinecall
  class Client
    # One agent an app speaks for: what it declares, what it does with a tool call, who listens.
    #
    # The declaration is sent again on every reconnect, because the gateway's registry is memory:
    # it knows which sockets are open right now and nothing else. Many sockets may hold one agent
    # at once and a call nobody claimed takes the newest of those that take unclaimed calls, so a
    # rolling deploy's new process serves from the moment it registers and never waits for the old
    # one to let go — and a console holding the same agent is never handed a call it did not open.
    #
    # This is `Client::Agent`, the handle: the thing that holds a socket, a slug and a book of
    # calls. `Pinecall::Agent` is the other one — the class a person writes. They meet in Bridge.
    class Agent
      ANSWERS_WITHIN_S = 10

      attr_reader :slug, :calls, :config, :app

      def initialize(slug, options, client)
        @slug = slug
        @client = client
        @routes = options[:routes] || []
        @takes_unclaimed = options.fetch(:takes_unclaimed, true)
        @tools = {}
        @waiting = []
        @config = options.reject { |key, _| %i[routes tools takes_unclaimed].include?(key) }
        @app = nil
        declare(options[:tools] || [])
        @calls = CallBook.new(self)
        @listeners = Listeners.new { |error| on_error(error) }
      end

      # Listen for one event type across every call of this agent.
      def on(type, &listener) = @listeners.on(type, &listener)

      # Listen for every event of this agent.
      def on_any(&listener) = @listeners.on_any(&listener)

      # Replace the tools and the code behind them. The next `configure` carries the declaration.
      #
      # A tool is `{ **spec, run: ->(arguments, call) { … } }`: the contract the model sees, and
      # the function this process runs when the model calls it.
      def declare(tools)
        @tools = tools.to_h { |tool| [tool[:name].to_s, tool] }
        @config = @config.merge(tools: tools.map { |tool| tool.reject { |key, _| key == :run } })
      end

      # Change what the agent is. Only the fields sent change; live calls keep their session.
      def configure(changes = {})
        @config = @config.merge(changes)
        ask("agent.configure", lands_as: "agent.configured", data: { config: @config })
      end

      # Claim the slug and its doors, then send the declaration. Runs again on every reconnect.
      def open
        registered = ask("agent.register", lands_as: "agent.registered", data: {
                           routes: @routes, sdk: @client.sdk, takes_unclaimed: @takes_unclaimed
                         })
        # A reconnect mints a new socket and so a new id: the one kept is always this socket's own.
        @app = registered[:app]
        configure
        self
      end

      # ── the socket's side ──────────────────────────────────────────────────

      # One entry of this agent's, folded into the call it belongs to and handed to the listeners.
      def take(entry)
        event = Protocol.event_of(entry)
        call = entry.call.nil? ? nil : @calls.of(entry.call, entry.ts)
        settle(event)
        call&.take(event)
        @listeners.emit(event, call)
        @client.seen(event, call)
        return if call.nil?

        run_tool(event, call) if event.type == "tool.call"
        @calls.forget(call)
      end

      # One command out, on this agent's behalf.
      def command(type, call, data)
        @client.send_command(type:, agent: @slug, call:, data:, id: "#{@slug}:#{type}")
      end

      # A listener of this agent's raised, where nobody was waiting for the answer.
      def on_error(error) = @client.on_error(error)

      # Prove the socket is alive. `ping` is agent-scoped like every command, and lands as `pong`.
      def ping = command("ping", nil, {})

      private

      # The model called a tool; the code is here, not in the platform. Whatever it answers — a
      # value, a refusal, nothing at all — becomes one `tool.result` against the model's own
      # call_id, because a turn that never gets one waits forever.
      #
      # It runs on a thread of its own so that a tool which takes a second does not stop this
      # process reading the socket: the same call may be receiving transcripts while it runs.
      def run_tool(event, call)
        call_id, name, arguments = event.data.values_at(:call_id, :name, :arguments)
        tool = @tools[name.to_s]
        return call.tool_result({ call_id:, name:, error: "this app declares no tool called #{name}" }) if tool.nil?

        Thread.new do
          started = now
          begin
            output = tool[:run].call(arguments || {}, call)
            call.tool_result({ call_id:, name:, output:, duration_s: now - started })
          rescue StandardError => e
            # A refusal is the tool's answer, not an unhandled failure: the model is waiting for
            # it and reads it as `error`, and the log keeps the same tool.result for a person.
            call.tool_result({ call_id:, name:, error: e.message, duration_s: now - started })
          end
        end
      end

      # A command is answered by the event it lands as, or by an `error` naming the id we sent.
      # Only the two declarations are awaited: everything else on this wire is fire and read the log.
      def ask(type, lands_as:, data:)
        id = "#{@slug}:#{type}"
        answer = Thread::Queue.new
        @waiting << { type: lands_as, id:, answer: }
        @client.send_command(type:, agent: @slug, call: nil, data:, id:)
        settled = answer.pop(timeout: ANSWERS_WITHIN_S)
        raise NotConnected, "#{type}: the gateway did not answer in #{ANSWERS_WITHIN_S}s" if settled.nil?
        raise settled if settled.is_a?(Exception)

        settled
      ensure
        @waiting.reject! { |one| one[:answer].equal?(answer) }
      end

      def settle(event)
        @waiting.dup.each do |waiting|
          if event.type == waiting[:type]
            waiting[:answer].push(event.data)
          elsif event.type == "error" && event.data[:id] == waiting[:id]
            waiting[:answer].push(Refused.new(event.data))
          end
        end
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
