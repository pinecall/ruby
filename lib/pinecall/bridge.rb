# frozen_string_literal: true

module Pinecall
  # Mounts an agent class on a client, with one instance per call. The only module that knows
  # both the agent and the socket.
  module Bridge
    # A mounted agent and its live instances.
    class Mounted
      attr_reader :slug, :agent, :options

      def initialize(slug:, agent:, options:, live:)
        @slug = slug
        @agent = agent
        @options = options
        @live = live
      end

      # The instance serving `call_id`, or nil.
      def serving(call_id) = @live[call_id]&.agent
    end

    # One served call: its instance, what was last sent, and a thread running its jobs in order.
    class Live
      attr_reader :agent, :world, :sent, :stops
      attr_accessor :tools_shown

      def initialize(agent, world)
        @agent = agent
        @world = world
        @sent = {}
        @tools_shown = nil
        @stops = {}
        @work = Thread::Queue.new
        @thread = Thread.new { work }
      end

      # Queue a job; jobs run one at a time in order, which keeps `world.cause` accurate.
      def later(&job) = @work << job

      def finish
        @work << :done
        @thread.join(5)
      end

      private

      def work
        while (job = @work.pop)
          break if job == :done

          begin
            job.call
          rescue StandardError => e
            warn("pinecall: #{e.class}: #{e.message}")
          end
        end
      end
    end

    module_function

    # Mount a class on a client; each call gets its own instance. Nothing is sent until `connect`.
    #
    # @param last [Proc] source for `last(contact)`
    # @param opening [Proc] initial state for a call, applied after `on_call` (so the hook cannot
    #   overwrite it) and before the first render
    # @param takes_unclaimed [Boolean] false for a console, which serves only calls it opens
    def mount(klass, client:, slug: nil, last: nil, opening: nil, takes_unclaimed: true)
      name = slug || klass.slug
      live = {}
      # Throwaway instance used only to read the class's declarations.
      probe = klass.new
      options = klass.wire_config(tools: tools_for(probe, live)).merge(takes_unclaimed:)
      agent = client.agent(name, **options)
      agent.on("call.started") { |_data, call| start(klass, live, call, agent, last, opening) }
      agent.on("call.ended") { |_data, call| finish(live, call) }
      Mounted.new(slug: name, agent:, options:, live:)
    end

    # Tool specs with a `run` routed to the instance serving the calling call.
    def tools_for(probe, live)
      probe.tools.map do |spec|
        spec.merge(run: lambda do |arguments, call|
          serving = live[call.id]
          raise ToolFailed, "#{spec[:name]}: this call is no longer being served" if serving.nil?

          serving.agent.run_tool(spec[:name], arguments)
        end)
      end
    end

    # Build the instance and run `on_call` before listening, so the first prompt is sent once
    # rather than once per field.
    def start(klass, live, call, agent, last, opening)
      instance = klass.new.seal
      instance.reads_last_from(last) unless last.nil?
      world = CallWorld.new(id: call.id, contact: call.contact&.dig(:id) || call.from,
                            from: call.from, channel: call.channel) do |type, data|
        call.command(type, data)
      end
      instance.serving(world)
      serving = Live.new(instance, world)
      live[call.id] = serving
      serving.later do
        instance.run_hook(:on_call, world)
        wanted = opening&.call(call)
        instance.start_in(wanted) unless wanted.nil?
        call.set_state(instance.snapshot)
        sync(serving, call)
        listen(serving, call, agent)
      end
    end

    # Re-sync the prompt on every state change.
    def listen(serving, call, agent)
      instance = serving.agent
      serving.stops[:state] = instance.on_change do |change|
        call.set_state(instance.snapshot, [change.field])
        # `state.set` has no cause field on the wire, so log it separately.
        cause = serving.world.cause
        call.log("state.cause", { field: change.field.to_s, kind: "event" }.merge(cause)) unless cause.nil?
        sync(serving, call)
      end
      serving.stops[:log] = instance.on_log { |entry| call.log(entry.name, as_object(entry.data)) }
      serving.stops[:entries] = call.on_any do |event|
        serving.world.take(event.type, event.data, Time.now.to_f)
        received(serving, agent, event.data) if event.type == "event.received"
      end
    end

    # Drop events whose (name, source) the class did not declare: an `:app` event arriving from
    # a browser could be spoofed.
    def received(serving, agent, fact)
      name = fact[:name].to_s
      allowed = agent_class(serving).declared_events[name]
      unless allowed&.include?(fact[:source].to_s)
        return warn("pinecall: #{name} from #{fact[:source]} is not declared by this agent")
      end

      meta = { source: fact[:source], identity: fact[:identity], seq: serving.world.numbered }.compact
      serving.later do
        serving.world.cause = { event: name, event_seq: meta[:seq] }
        serving.agent.run_hook(:on_event, name, fact[:data] || {}, meta)
        serving.agent.notify_heard(name, fact[:data] || {}, meta)
        serving.world.cause = nil
      end
    end

    # Stop rendering and reading entries; the log stays open until `on_end` has run.
    def finish(live, call)
      serving = live.delete(call.id)
      return if serving.nil?

      serving.stops.values_at(:state, :entries).compact.each(&:call)
      serving.later do
        serving.agent.run_hook(:on_end, serving.world)
        serving.stops[:log]&.call
      end
      serving.finish
    end

    # Send only blocks whose text changed since this call's last send: identical re-sends waste
    # the provider's prompt cache. Unsent blocks count as empty.
    def sync(serving, call)
      rendered = Prompt.render(serving.agent, line: { channel: call.channel || "web", from: call.from })
      rendered.blocks.each do |block|
        next if block.text == serving.sent.fetch(block.name, "")

        serving.sent[block.name] = block.text
        call.set_prompt(block.name, block.text)
      end
      visible = serving.agent.visible_tools
      return if visible == serving.tools_shown

      serving.tools_shown = visible
      call.set_tools(visible)
    end

    def agent_class(serving) = serving.agent.class

    # `call.log` data must be an object; wrap scalars under `value`.
    def as_object(data)
      return {} if data.nil?

      data.is_a?(Hash) ? data : { value: data }
    end
  end
end
