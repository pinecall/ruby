# frozen_string_literal: true

module Pinecall
  class Client
    # A call being served: line details read from the log, and the commands it can send.
    #
    # Commands are not awaited; their effects arrive later as log entries.
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

      def agent_slug = @agent.slug

      # Listen for one event type on this call; the returned lambda unsubscribes.
      def on(type, &listener) = @listeners.on(type, &listener)

      # Listen for every event on this call.
      def on_any(&listener) = @listeners.on_any(&listener)

      # ── commands ───────────────────────────────────────────────────────────

      # Speak `text` verbatim now, as a `turn.agent`.
      def say(text, **options) = command("agent.say", { text: }.merge(options))

      # Make the model speak now, guided by instructions the caller does not hear.
      def reply(instructions, **options) = command("agent.reply", { instructions: }.merge(options))

      # Replace one prompt block by name.
      def set_prompt(name, text) = command("prompt.set", { name: name.to_s, text: })

      # Set the tools currently visible to the model (a subset of the declared ones).
      def set_tools(tools) = command("tools.set", { tools: })

      # Send the full state; answered with `state.changed`.
      def set_state(state, changed = nil)
        @state = state
        wire = { state: }
        wire[:changed] = Array(changed).map(&:to_s) unless changed.nil?
        command("state.set", wire)
      end

      def tool_result(result) = command("tool.result", result)

      # Send an event from the application's backend; the agent must declare `name`.
      def event(name, data) = command("call.event", { name: name.to_s, data: })

      # End the call; `call.ended` follows with reason `agent_hung_up`.
      def hangup(reason = nil) = command("call.hangup", reason.nil? ? {} : { reason: })

      # Append an application entry to the call's log, as a `custom` entry.
      def log(name, data = {}) = command("call.log", { name: name.to_s, data: })

      # Send any call-scoped protocol command.
      def command(type, data) = @agent.command(type, @id, data)

      # ── entries ────────────────────────────────────────────────────────────

      # Apply an event to the call, then notify listeners.
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

    # Live calls by id; a call is dropped once it has ended.
    class CallBook
      def initialize(agent)
        @agent = agent
        @live = {}
        @lock = Mutex.new
      end

      def live = @lock.synchronize { @live.values.dup }

      # Find or create the call for an entry.
      def of(id, at)
        @lock.synchronize { @live[id] ||= Call.new(id, @agent, at) }
      end

      # Drop an ended call; `call.ended` listeners have already run.
      def forget(call)
        @lock.synchronize { @live.delete(call.id) } if call.status == "ended"
      end
    end
  end
end
