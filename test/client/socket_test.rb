# frozen_string_literal: true

require "test_helper"

# The socket, against a gateway that is really listening: the key at the door, the two
# declarations answered, and one command going up.
#
# It is a real TCP server and a real WebSocket handshake, because the half of a client that is
# worth testing is the half a fake never exercises.
class SocketTest < Minitest::Test
  # The smallest gateway that answers this protocol: it registers an agent, configures it, and
  # keeps every frame it was sent so the test can say what the client did.
  class Gateway
    attr_reader :frames, :authorization

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @frames = Thread::Queue.new
      @sockets = []
      @thread = Thread.new { serve }
    end

    def url = "http://127.0.0.1:#{@server.addr[1]}"

    def stop
      @thread.kill
      @sockets.each { |socket| socket.close rescue nil } # rubocop:disable Style/RescueModifier
      @server.close
    end

    private

    def serve
      loop do
        socket = @server.accept
        @sockets << socket
        Thread.new { talk(socket) }
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def talk(socket)
      driver = WebSocket::Driver.server(Writer.new(socket))
      driver.on(:connect) do
        @authorization = driver.env["HTTP_AUTHORIZATION"]
        driver.start
      end
      driver.on(:message) { |event| took(driver, event.data) }
      loop { driver.parse(socket.readpartial(4096)) }
    rescue EOFError, IOError, Errno::ECONNRESET
      nil
    end

    def took(driver, raw)
      frame = JSON.parse(raw, symbolize_names: true)
      @frames << frame
      case frame[:type]
      when "agent.register"
        write(driver, frame[:agent], "agent.registered", { app: "app_1", routes: frame[:data][:routes] })
      when "agent.configure"
        write(driver, frame[:agent], "agent.configured", { changed: %w[tools] })
      end
    end

    def write(driver, agent, type, data)
      @seq = (@seq || 0) + 1
      driver.text(JSON.generate({ seq: @seq, ts: Time.now.to_f, call: nil, agent:, type:,
                                  ephemeral: false, data: }))
    end

    # websocket-driver writes through whatever answers `write`; a socket answers it already, but
    # the driver also asks for a url on the client side, so the two sides share one shape.
    Writer = Struct.new(:socket) do
      def write(bytes) = socket.write(bytes)
    end
  end

  def setup
    @gateway = Gateway.new
    @client = Pinecall::Client.new(url: @gateway.url, api_key: "pk_test_key")
  end

  def teardown
    @client.close
    @gateway.stop
  end

  def test_it_registers_every_agent_it_holds_the_moment_the_socket_opens
    @client.agent("clinica-norte", routes: [{ channel: "web", number: nil }], tools: [])
    @client.connect

    assert_predicate @client, :connected?
    registered = @gateway.frames.pop(timeout: 5)

    assert_equal "agent.register", registered[:type]
    assert_equal "clinica-norte", registered[:agent]
    assert_match(%r{\Apinecall-ruby/}, registered[:data][:sdk])
  end

  def test_the_key_travels_in_a_header_and_never_in_the_url
    @client.agent("clinica-norte", tools: [])
    @client.connect
    @gateway.frames.pop(timeout: 5)

    assert_equal "Bearer pk_test_key", @gateway.authorization
  end

  def test_the_declaration_follows_the_registration_without_being_asked
    @client.agent("clinica-norte", tools: [], language: "es")
    @client.connect
    @gateway.frames.pop(timeout: 5)
    configured = @gateway.frames.pop(timeout: 5)

    assert_equal "agent.configure", configured[:type]
    assert_equal "es", configured[:data][:config][:language]
  end

  def test_a_command_the_protocol_refuses_never_reaches_the_socket
    agent = @client.agent("clinica-norte", tools: [])
    @client.connect
    @gateway.frames.pop(timeout: 5)

    assert_raises(Pinecall::Protocol::ProtocolError) { agent.command("agent.say", "CA_1", { shout: true }) }
  end

  def test_a_command_goes_up_as_the_wire_carries_it
    agent = @client.agent("clinica-norte", tools: [])
    @client.connect
    2.times { @gateway.frames.pop(timeout: 5) }
    agent.command("agent.say", "CA_1", { text: "Buenas tardes." })
    said = @gateway.frames.pop(timeout: 5)

    assert_equal "agent.say", said[:type]
    assert_equal "CA_1", said[:call]
    assert_equal "Buenas tardes.", said[:data][:text]
  end

  def test_a_command_sent_while_the_socket_is_down_is_refused_and_not_queued
    agent = @client.agent("clinica-norte", tools: [])

    assert_raises(Pinecall::NotConnected) { agent.command("ping", nil, {}) }
  end

  def test_a_client_with_no_url_and_no_key_says_which_two_things_it_needs
    refused = assert_raises(ArgumentError) { Pinecall::Client.new(url: nil, api_key: nil) }

    assert_includes refused.message, "PINECALL_URL"
    assert_includes refused.message, "PINECALL_API_KEY"
  end
end
