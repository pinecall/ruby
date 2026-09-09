# frozen_string_literal: true

module Pinecall
  class Client
    # The socket to the gateway: the key at the door, backoff on the way back, a ping while it is
    # up, and one thread reading it for the life of the process.
    #
    # The key travels as `Authorization: Bearer` on the upgrade, never in the URL, because a URL
    # ends up in an access log. A wrong key is closed with 1008 and no body, so a socket that
    # never opens is retried like any other: the gateway will not say more the second time either.
    #
    # `websocket-driver` is the protocol and nothing else — the same driver ActionCable runs on —
    # so the transport here is a plain TCP or TLS socket and there is no event loop to adopt.
    class Connection
      FIRST_WAIT_S = 0.5
      LONGEST_WAIT_S = 30.0
      GROWS_BY = 2
      PINGS_EVERY_S = 30

      # What the client does with what the socket brings.
      Handlers = Data.define(:on_open, :on_entry, :on_error, :on_heartbeat)

      attr_reader :url

      def initialize(url:, api_key:, handlers:, ping_every: PINGS_EVERY_S, backoff: {})
        @url = Endpoints.apps(url)
        @api_key = api_key
        @handlers = handlers
        @ping_every = ping_every
        @backoff = { first: FIRST_WAIT_S, longest: LONGEST_WAIT_S, grows_by: GROWS_BY }.merge(backoff)
        @lock = Mutex.new
        @open = false
        @closed = false
        @attempt = 0
      end

      # True while the socket is up.
      def open? = @open

      # Open the socket and return once the gateway has answered and `on_open` has run. After
      # that, staying up is this object's problem and not the caller's.
      def start
        @closed = false
        @opened = Thread::Queue.new
        @reader = Thread.new { dial_until_closed }
        @reader.abort_on_exception = false
        answer = @opened.pop(timeout: 30)
        # Nobody waits here again: from the second dial on, a failure is the app's error door's.
        @opened = nil
        raise NotConnected, "the gateway did not answer in 30s: #{@url}" if answer.nil?
        raise answer if answer.is_a?(Exception)

        self
      end

      # One frame up. A command sent while the socket is down is refused, not queued: an app that
      # is told now can decide, and a queue would deliver it into a call that has ended.
      def send_frame(command)
        @lock.synchronize do
          raise NotConnected, "#{command.type}: the gateway is not connected" unless @open

          @driver.text(Protocol.encode(command))
        end
      end

      # Stop, and stay stopped: no reconnect follows a close the app asked for.
      def close
        @closed = true
        @open = false
        @heartbeat&.kill
        @socket&.close
        @reader&.join(1)
        nil
      end

      # websocket-driver writes its bytes through here.
      def write(bytes)
        @socket.write(bytes)
      rescue IOError, SystemCallError => e
        @handlers.on_error.call(e)
      end

      private

      def dial_until_closed
        until @closed
          begin
            dial
          rescue StandardError => e
            fail_the_first_dial(e)
          end
          break if @closed

          sleep(wait_s)
        end
      end

      def dial
        @socket = connect_to(URI.parse(@url))
        @driver = WebSocket::Driver.client(self)
        @driver.set_header("Authorization", "Bearer #{@api_key}")
        @driver.on(:open) { opened }
        @driver.on(:message) { |event| took(event.data) }
        @driver.on(:close) { |event| shut(event) }
        @driver.start
        read_until_closed
      end

      def connect_to(url)
        port = url.port || (url.scheme == "wss" ? 443 : 80)
        socket = TCPSocket.new(url.host, port)
        return socket unless url.scheme == "wss"

        context = OpenSSL::SSL::SSLContext.new
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
        tls = OpenSSL::SSL::SSLSocket.new(socket, context)
        tls.hostname = url.host
        tls.sync_close = true
        tls.connect
        tls
      end

      def read_until_closed
        loop do
          bytes = @socket.readpartial(4096)
          @driver.parse(bytes)
        end
      rescue EOFError, IOError, SystemCallError, OpenSSL::SSL::SSLError
        @open = false
      end

      # The socket is up. Everything that must be true on it goes up before anything else, and
      # only then does whoever called `start` hear that it worked.
      #
      # It happens on a thread of its own because this one is the reader: `agent.register` is
      # answered by an entry, and a thread that is waiting for that entry is a thread that is not
      # reading it. Whoever called `start` is still waiting, so nothing is racing — the socket is
      # simply being read while the declaration goes up and comes back.
      def opened
        @open = true
        @attempt = 0
        @heartbeat = Thread.new { beat }
        Thread.new { declare }
      end

      def declare
        @handlers.on_open.call
        @opened&.push(:open)
      rescue StandardError => e
        # The socket is up and what must be true on it is not. On the first connection whoever
        # called `start` hears it as a raise; on a reconnect nobody is waiting there, and then the
        # app's error door is the only one.
        @opened.nil? || @opened.closed? ? @handlers.on_error.call(e) : @opened.push(e)
      end

      def took(raw)
        @handlers.on_entry.call(Protocol.decode_entry(JSON.parse(raw, symbolize_names: true)))
      rescue StandardError => e
        @handlers.on_error.call(e)
      end

      def shut(event)
        @open = false
        @heartbeat&.kill
        return if @closed

        # The first connection failing is the app's to hear: a wrong key, a host nobody is on.
        # Every close after one that worked is a blip, and a blip is answered with a retry.
        return unless @opened && !@opened.closed? && @attempt.zero?

        @opened.push(NotConnected.new("the gateway refused the socket: closed with #{event.code}"))
      end

      def fail_the_first_dial(error)
        @open = false
        return @handlers.on_error.call(error) unless @opened && !@opened.closed? && @attempt.zero?

        @opened.push(NotConnected.new("#{@url}: #{error.message}"))
      end

      def beat
        loop do
          sleep(@ping_every)
          break unless @open

          @handlers.on_heartbeat.call
        end
      rescue StandardError => e
        @handlers.on_error.call(e)
      end

      # Full jitter: every client that lost the same gateway comes back at a different moment,
      # instead of all of them together on the second it returns.
      def wait_s
        window = [@backoff[:longest], @backoff[:first] * (@backoff[:grows_by]**@attempt)].min
        @attempt += 1
        rand * window
      end
    end
  end
end
