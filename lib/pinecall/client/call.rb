# frozen_string_literal: true

module Pinecall
  class Client
    # One call the app is serving: what is known about the line, and every command it can send.
    #
    # Everything readable here was read off the log — the client never invents a field the wire
    # does not carry — and every method is one command, sent and not awaited: the gateway answers
    # with the events the command lands as, and those arrive as entries like everything else.
    class Call
      attr_reader :id, :today
      attr_accessor :status, :channel, :from, :to, :contact, :state

      def initialize(id, agent, opened_at)
        @id = id
        @agent = agent
        @today = Time.at(opened_at).strftime("%Y-%m-%d")
        @status = "ringing"
        @channel = nil
        @from = nil
        @to = nil
        @contact = nil
        @state = {}
        @listeners = Listeners.new { |error| agent.on_error(error) }
      end

      # The agent serving this call.
      def agent_slug = @agent.slug

      # Listen for one event type on this call alone. The returned callable stops listening.
      def on(type, &listener) = @listeners.on(type, &listener)

      # Listen for every event on this call.
      def on_any(&listener) = @listeners.on_any(&listener)

      # ── the commands ───────────────────────────────────────────────────────

      # Say this, verbatim, now. Lands as `turn.agent`.
      def say(text, **options) = command("agent.say", { text: }.merge(options))

      # Make the model speak now, guided by an instruction the caller never hears.
      def reply(instructions, **options) = command("agent.reply", { instructions: }.merge(options))

      # Rewrite one block of the prompt, whole, by name: one of the agent's declared blocks, or
      # one of the framework's four.
      def set_prompt(name, text) = command("prompt.set", { name: name.to_s, text: })

      # The tools the model may see now: the subset of the declaration this state allows.
      def set_tools(tools) = command("tools.set", { tools: })

      # The app's state changed and this is all of it. Lands as `state.changed`.
      def set_state(state, changed = nil)
        @state = state
        wire = { state: }
        wire[:changed] = Array(changed).map(&:to_s) unless changed.nil?
        command("state.set", wire)
      end

      # What came back from running a tool here, against the `call_id` the model gave.
      def tool_result(result) = command("tool.result", result)

      # A fact from the tenant's backend. The agent must have declared the name, or this is refused.
      def event(name, data) = command("call.event", { name: name.to_s, data: })

      # End the call from the app's side. `call.ended` follows with reason agent_hung_up.
      def hangup(reason = nil) = command("call.hangup", reason.nil? ? {} : { reason: })

      # Write a line of the app's own into the call's log. Lands as `custom`, with a seq like any.
      def log(name, data = {}) = command("call.log", { name: name.to_s, data: })

      # Anything else the protocol declares about a call, for an app ahead of this library.
      def command(type, data) = @agent.command(type, @id, data)

      # ── what the log teaches it ────────────────────────────────────────────

      # Fold one event into what the call knows, then hand it to this call's listeners.
      def take(event)
        learn(event)
        @listeners.emit(event, self)
      end

      private

      def learn(event)
        case event.type
        when "call.ringing" then the_line(event.data, "ringing")
        when "call.dialing" then the_line(event.data, "dialing")
        when "call.started" then the_line(event.data, "active")
        when "call.ended" then @status = "ended"
        when "state.changed" then @state = event.data[:state].dup
        end
      end

      def the_line(line, status)
        @status = status
        @channel = line[:channel]
        @from = line[:from]
        @to = line[:to]
        @contact = line[:caller]
      end
    end

    # Every call this agent is serving right now, by id. A call is forgotten when its log ends.
    class CallBook
      def initialize(agent)
        @agent = agent
        @live = {}
        @lock = Mutex.new
      end

      # The calls in progress, in the order they opened.
      def live = @lock.synchronize { @live.values.dup }

      # The call this entry belongs to, opened on the first entry that named it.
      def of(id, at)
        @lock.synchronize { @live[id] ||= Call.new(id, @agent, at) }
      end

      # Forget a call whose log has ended. Listeners for `call.ended` have already run.
      def forget(call)
        @lock.synchronize { @live.delete(call.id) } if call.status == "ended"
      end
    end
  end
end
