# frozen_string_literal: true

require_relative "agent/author"
require_relative "agent/doc"
require_relative "agent/state"
require_relative "agent/spec"
require_relative "agent/tools"
require_relative "agent/config"

module Pinecall
  # The class an application writes its agent as.
  #
  # An agent is an object. Fields are state. Methods are capabilities. Docstrings are prompts. The
  # prompt is `render(state)`. Tools are the only thing that changes state. The log is the truth.
  #
  #     class ClinicaNorte < Pinecall::Agent
  #       language "es"
  #
  #       stage :identify, :book
  #       state :patient
  #
  #       # Busca al paciente por nombre y teléfono.
  #       tool stage: :identify, pii: %i[name phone]
  #       def find_patient(name:, phone:)
  #         self.patient = Agenda.find(name, phone)
  #         self.stage = :book if patient
  #         patient
  #       end
  #     end
  #
  # Nothing here knows the runtime, LiveKit, a model or a microphone. The class speaks commands
  # and reads entries; `Pinecall.mount` is the only place it meets the socket.
  class Agent
    extend Config::Declaring
    extend State::Declaring
    extend Tools::Declaring
    extend Prompt::Declaring
    include State
    include Tools

    # Every agent class written in this process, in the order they were. It is how `pinecall
    # prompt agent.rb` finds the class a file declared without being told its name.
    def self.written = @written ||= []

    def self.inherited(subclass)
      super
      Agent.written << subclass
    end

    def initialize
      @state = {}
      @changes = []
      @change_listeners = []
      @log = []
      @log_listeners = []
      @event_listeners = []
      @seq = 0
      @sealed = false
      @call = nil
      @last_call = nil
      self.class.declared_state.each { |name, default| @state[name] = opening(default) }
    end

    # The call being served right now.
    #
    # It is a method on the base class and not a field, so it never looks like state and never
    # reaches a view; outside a call it says so rather than handing back a nil somebody has to
    # discover three frames later.
    def call
      raise Error, "there is no call here: the bridge hands an agent its call when one starts" if @call.nil?

      @call
    end

    # Whether this instance is serving a call at all.
    def call? = !@call.nil?

    # Say this, word for word, now. Lands as a `turn.agent`.
    def say(text, **options) = call.say(text, **options)

    # Make the model speak now, guided by words the caller never hears.
    def reply(instructions, **options) = call.reply(instructions, **options)

    # Put a named fact in the call's log, for the console and for whatever reads it after.
    def log(name, data = nil)
      entry = LogEntry.new(seq: next_seq, name: name.to_s, data:, at: Time.now.to_f)
      @log << entry
      @log_listeners.each { |listener| listener.call(entry) }
      entry
    end

    # Everything this agent has logged, oldest first.
    def logged = @log.dup

    # Hear every logged fact as it happens; the returned callable stops listening.
    def on_log(&listener)
      @log_listeners << listener
      -> { @log_listeners.delete(listener) }
    end

    # Hear every outside fact this agent was handed, after its hook has had it.
    def on_heard(&listener)
      @event_listeners << listener
      -> { @event_listeners.delete(listener) }
    end

    # What this contact left behind last time. Wired per mount, never a global.
    def last(contact)
      raise Error, "last(contact) needs a store: mount the agent with last: to give it one" if @last_call.nil?

      @last_call.call(contact)
    end

    # ── the hooks. Override them; a write inside one is authored by the hook ──

    # A call started.
    def on_call(call) = nil

    # The call ended.
    def on_end(call) = nil

    # An outside fact this class declared arrived.
    def on_event(name, data, meta) = nil

    # Memory was written, so the tenant can put the ops wherever it keeps them.
    def on_memory(ops, call) = nil

    # ── what the bridge does to it, and nothing else ─────────────────────────

    # Run one hook with everything it writes authored by it, not by nobody.
    def run_hook(hook, *args)
      Author.with("hook:#{hook}") { public_send(hook, *args) }
    end

    # Hand this instance the call it is serving. The bridge does this once, at start.
    def serving(call)
      @call = call
      self
    end

    # Hand this instance the store its `last(contact)` reads.
    def reads_last_from(source)
      @last_call = source
      self
    end

    # Tell the in-process observers about a fact the hook has just been given.
    def notify_heard(name, data, meta)
      @event_listeners.each { |listener| listener.call(name, data, meta) }
    end

    private

    # The value a fresh call starts this field at. A Proc is called, so `state :slots, -> { [] }`
    # and `state :slots, []` both give every call a list of its own instead of one shared list.
    def opening(default)
      return default.call if default.is_a?(Proc)

      case default
      when Array, Hash, String then default.dup
      else default
      end
    end
  end
end
