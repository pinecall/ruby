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
  # A connection to the Pinecall gateway: one socket, its agents, log reads, and the org's
  # knowledge bases and contact memory. `Pinecall::Agent` is built on top of it.
  #
  #     pc = Pinecall::Client.new                 # PINECALL_URL and PINECALL_API_KEY
  #     agent = pc.agent("clinica-norte", routes: [{ channel: "web", number: nil }], tools: [])
  #     agent.on("turn.user") { |data, call| call.say("Le he oído: #{data[:text]}") }
  #     pc.connect
  #
  # `PINECALL_URL` and `PINECALL_API_KEY` are required; there are no defaults.
  class Client
    # The `sdk` field sent on register.
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

    # Declare an agent. Nothing is sent until `connect`.
    def agent(slug, **options)
      @agents[slug] = Agent.new(slug, options, self)
    end

    # Declared agents by slug.
    def agents = @agents.dup

    # Open the socket and register every agent.
    def connect
      @connection.start
      self
    end

    # Close the socket without reconnecting; agents are unregistered.
    def close = @connection.close

    # True while the socket is up.
    def connected? = @connection.open?

    # Listen for one event type across all agents.
    def on(type, &listener) = @listeners.on(type, &listener)

    # Listen for every event across all agents.
    def on_any(&listener) = @listeners.on_any(&listener)

    # Listen for unhandled errors (bad frames, raising tools, socket loss). Without a listener
    # they go to stderr. Returns a lambda that unsubscribes.
    def on_errors(&listener)
      @errors << listener
      -> { @errors.delete(listener) }
    end

    # Stream a log, reduced by the wire's reducer. `target` is `{ call: "CA_1" }` or `{ agent: … }`.
    def observe(target, **options, &block) = Observe.observe(target, url: @url, api_key: @api_key, **options, &block)

    # Fetch one page of a log and its reduced state.
    def history(target, **options) = Observe.history(target, url: @url, api_key: @api_key, **options)

    # The org's knowledge bases.
    def knowledge = Knowledge.new(url: @url, api_key: @api_key)

    # Memory about one contact, including erasure.
    def memory_of(contact) = ContactMemory.new(contact, url: @url, api_key: @api_key)

    # The org's memory recall golden.
    def memory = Memory.new(url: @url, api_key: @api_key)

    # The org's own provider (BYOK) keys.
    def provider_keys = ProviderKeys.new(url: @url, api_key: @api_key)

    # Search the agent's knowledge bases on behalf of a call this client serves; the gateway runs
    # the search and logs it. Returns the chunks as the gateway answered them.
    def search(call, query, k: nil)
      input = k.nil? ? { query: } : { query:, k: }
      answer = Rest.post(Endpoints.lookup(@url, call), { tool: "search", input: }, api_key: @api_key)
      answer.dig(:output, :chunks) || []
    end

    # ── used by agents ───────────────────────────────────────────────────────

    # Send one command, validated against its schema.
    def send_command(type:, agent:, call:, data:, id: nil)
      @connection.send_frame(Wire.command(type:, agent:, call:, data:, id:))
    end

    # Forward an event to client-wide listeners.
    def seen(event, call) = @listeners.emit(event, call)

    def on_error(error)
      return warn("pinecall: #{error.class}: #{error.message}") if @errors.empty?

      @errors.each { |listener| listener.call(error) }
    end

    private

    def took(entry)
      agent = @agents[entry.agent]
      # The socket may carry entries for agents this client did not declare.
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
