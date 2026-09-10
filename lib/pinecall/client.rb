# frozen_string_literal: true

require "cgi"
require "net/http"
require "openssl"
require "socket"
require "uri"
require "websocket/driver"

require_relative "client/endpoints"
require_relative "client/listeners"
require_relative "client/connection"
require_relative "client/call"
require_relative "client/agent"
require_relative "client/observe"
require_relative "client/rest"
require_relative "client/knowledge"
require_relative "client/contact_memory"
require_relative "client/memory"
require_relative "client/provider_keys"

module Pinecall
  # One application's connection to Pinecall: one socket, the agents on it, a door to any log the
  # key can read, and the org's knowledge bases and contact memories over the same key.
  #
  # This is the smaller of the two doors. It knows the protocol and a websocket and nothing else —
  # no agent class, no view, no CLI — and it is what an application with its own way of deciding
  # what to answer wants. `Pinecall::Agent` is built on it, not beside it.
  #
  #     pc = Pinecall::Client.new                 # PINECALL_URL and PINECALL_API_KEY
  #     agent = pc.agent("clinica-norte", routes: [{ channel: "web", number: nil }], tools: [])
  #     agent.on("turn.user") { |data, call| call.say("Le he oído: #{data[:text]}") }
  #     pc.connect
  #
  # `PINECALL_URL` and `PINECALL_API_KEY` are the two things it needs and it will not guess
  # either: a client pointed at a host nobody named fails later, somewhere the app cannot read.
  class Client
    # Who is registering, in the wire's own field. The gateway logs it and a console shows it.
    def sdk = "pinecall-ruby/#{VERSION}"

    attr_reader :url, :api_key

    def initialize(url: ENV.fetch("PINECALL_URL", nil), api_key: ENV.fetch("PINECALL_API_KEY", nil),
                   ping_every: Connection::PINGS_EVERY_S, backoff: {})
      if url.nil? || api_key.nil?
        raise ArgumentError, "PINECALL_URL and PINECALL_API_KEY: one of them is not set"
      end

      @url = url
      @api_key = api_key
      @agents = {}
      @errors = []
      @listeners = Listeners.new { |error| on_error(error) }
      @connection = Connection.new(
        url:, api_key:, ping_every:, backoff:,
        handlers: Connection::Handlers.new(
          on_open: -> { @agents.each_value(&:open) },
          on_entry: ->(entry) { took(entry) },
          on_error: ->(error) { on_error(error) },
          on_heartbeat: -> { @agents.each_value { |agent| guarded { agent.ping } } }
        )
      )
    end

    # Declare an agent this app speaks for. Nothing is sent until `connect`.
    def agent(slug, **options)
      @agents[slug] = Agent.new(slug, options, self)
    end

    # The agents this client holds, by slug.
    def agents = @agents.dup

    # Open the socket, claim every agent's slug and doors, and send every declaration.
    def connect
      @connection.start
      self
    end

    # Close the socket and stay closed. Every agent's slug is free the moment it shuts.
    def close = @connection.close

    # True while the socket is up.
    def connected? = @connection.open?

    # Listen for one event type across every agent on this client.
    def on(type, &listener) = @listeners.on(type, &listener)

    # Listen for every event across every agent.
    def on_any(&listener) = @listeners.on_any(&listener)

    # Hear what the client could not hand to anybody: a bad frame, a tool that raised, a lost
    # socket. With nobody listening, it goes to stderr rather than nowhere.
    def on_errors(&listener)
      @errors << listener
      -> { @errors.delete(listener) }
    end

    # A log as it happens, folded by the protocol's reducer. `{ call: "CA_1" }` or `{ agent: … }`.
    def observe(target, **options, &block) = Observe.observe(target, url: @url, api_key: @api_key, **options, &block)

    # A log as it stands, as one page, and what it folds to.
    def history(target, **options) = Observe.history(target, url: @url, api_key: @api_key, **options)

    # The org's knowledge bases: push one from a folder, list them, drop one.
    def knowledge = Knowledge.new(url: @url, api_key: @api_key)

    # What is remembered about one contact, and the right to be forgotten.
    def memory_of(contact) = ContactMemory.new(contact, url: @url, api_key: @api_key)

    # The golden recall is held to; it names no contact, because every question brings its own.
    def memory = Memory.new(url: @url, api_key: @api_key)

    # The provider keys this org brought of its own: added, taken back, and read back by name.
    def provider_keys = ProviderKeys.new(url: @url, api_key: @api_key)

    # ── what the agents send through ─────────────────────────────────────────

    # One command frame up the socket, checked against its schema before it leaves.
    def send_command(type:, agent:, call:, data:, id: nil)
      @connection.send_frame(Protocol.command(type:, agent:, call:, data:, id:))
    end

    # One event an agent has finished with, for the listeners registered across every agent.
    def seen(event, call) = @listeners.emit(event, call)

    # Something failed where nobody was waiting.
    def on_error(error)
      return warn("pinecall: #{error.class}: #{error.message}") if @errors.empty?

      @errors.each { |listener| listener.call(error) }
    end

    private

    def took(entry)
      agent = @agents[entry.agent]
      # An entry for an agent this client never declared: the socket is shared, the app is not.
      return if agent.nil?

      guarded { agent.take(entry) }
    end

    def guarded
      yield
    rescue StandardError => e
      on_error(e)
    end
  end
end
