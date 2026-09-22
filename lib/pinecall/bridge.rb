# frozen_string_literal: true

module Pinecall
  # The bridge: an agent class mounted on a client, one live instance per call.
  #
  # This is the only place the class and the socket know about each other. The class never learns
  # what a websocket is; the client never learns what a tool is.
  module Bridge
    # A mounted agent: what it registered as, and the instance serving each call right now.
    class Mounted
      attr_reader :slug, :agent, :options

      def initialize(slug:, agent:, options:, live:)
        @slug = slug
        @agent = agent
        @options = options
        @live = live
      end

      # The instance serving one call, while the call lasts.
      def serving(call_id) = @live[call_id]&.agent
    end

    # One call being served: the instance, its call, what was last sent — every block by name,
    # and the tools — and the one thread that runs this call's hooks in the order they arrived.
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

      # Do this next, after everything already queued for this call and before anything after it.
      # One at a time and in the order they arrived: that is what makes `call.cause` mean anything.
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

    # Mount a class on a client. It registers once, and from then on every call gets its own
    # instance, its own state and its own rendered prompt. Nothing is sent until `connect`.
    #
    # @param last [Proc] where every instance reads `last(contact)` from. Per mount, never global.
    # @param opening [Proc] the state a case opens a call in, applied after `on_call` and before
    #   the first render — the only moment it can be: earlier and the hook writes over it, later
    #   and the model reads a state the call was never in.
    # @param takes_unclaimed [Boolean] false for a console: it serves the call it opens itself.
    def mount(klass, client:, slug: nil, last: nil, opening: nil, takes_unclaimed: true)
      name = slug || klass.slug
      live = {}
      # One instance to read the class with: its tools and everything it declares about itself are
      # read off the same probe, which is then thrown away. Every call gets an instance of its own.
      probe = klass.new
      # No doors: a number is a row the org keeps and points at an agent, and every agent can be
      # talked to from a page. A class that still says `phone` is saying something nobody reads.
      options = klass.wire_config(tools: tools_for(probe, live)).merge(takes_unclaimed:)
      agent = client.agent(name, **options)
      agent.on("call.started") { |_data, call| start(klass, live, call, agent, last, opening) }
      agent.on("call.ended") { |_data, call| finish(live, call) }
      Mounted.new(slug: name, agent:, options:, live:)
    end

    # Every tool the class declares, each carrying the code that runs it, routed to the instance
    # that owns the call the model called it in.
    def tools_for(probe, live)
      probe.tools.map do |spec|
        spec.merge(run: lambda do |arguments, call|
          serving = live[call.id]
          raise ToolFailed, "#{spec[:name]}: this call is no longer being served" if serving.nil?

          serving.agent.run_tool(spec[:name], arguments)
        end)
      end
    end

    # A call started: build the instance, let `on_call` write into it, send the whole prompt once,
    # and only then start listening — so the opening send is one prompt and not one per field.
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

    # From here on the prompt follows the state, one send per field that actually moved.
    def listen(serving, call, agent)
      instance = serving.agent
      serving.stops[:state] = instance.on_change do |change|
        call.set_state(instance.snapshot, [change.field])
        # `state.set` carries no cause on the wire, so the reason a field moved goes in the log
        # next to it: one line naming the event, the field, and the fact's place in this call.
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

    # One outside fact. The pair (name, source) is checked against what the class declared: an
    # event declared `from: [:app]` that arrives from a browser is somebody else's event with our
    # name on it, and the hook never sees it.
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

    # The call is over: nothing may render a prompt for it any more, and nothing may fold another
    # entry into it. The log stays open one hook longer, because a farewell line — what the call
    # was worth, what to remember — is exactly what `on_end` is for, and it is written after.
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

    # The one rule this file exists for: render, compare with what THIS call was last sent, and
    # send only the blocks whose text is different. Re-sending identical text is a cache miss for
    # nothing, and the cache is most of what a voice turn costs. A block never sent counts as
    # empty, so an empty one costs no command until it has something to say.
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

    # `call.log` carries an object; a tool that logged a number still deserves a line, so a value
    # that is not an object travels under `value` rather than being dropped at the door.
    def as_object(data)
      return {} if data.nil?

      data.is_a?(Hash) ? data : { value: data }
    end
  end
end
