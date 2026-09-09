# frozen_string_literal: true

require "securerandom"

module Pinecall
  module UI
    # The local server behind `pinecall ui`: the console's files and the gateway's doors, under one
    # nonce on 127.0.0.1.
    #
    # Everything about it is a containment decision. Loopback only, so nothing on the network can
    # reach it. The kernel picks the port, so two consoles on one laptop do not fight over a
    # number. Everything answers under a random path, so a process that scans the loopback finds a
    # 404 and nothing behind it. And the org key is a field of this object, written into exactly
    # one place: the authorization header of a request THIS process makes. The browser holds none.
    #
    # It speaks HTTP/1.1 over a plain socket rather than through a web server, for one reason: the
    # console reads a live log over SSE, and a proxy that streams has to own the write side. Every
    # answer closes its connection, which is what lets a body end at EOF without a length — on the
    # loopback, for one person, a connection per request costs nothing and the framing is exact.
    class Server
      LOOPBACK = "127.0.0.1"
      NONCE_BYTES = 16

      # The gateway's doors, as the console asks for them relative to its base. Everything else
      # under the nonce is a file of the console, or a screen the console routes itself.
      DOORS = "v1/"

      # The headers a browser's request carries that the gateway needs to see. Everything else —
      # the cookies, the origin, the user agent — is the browser's business and stops here.
      FORWARDED = %w[content-type accept last-event-id range].freeze

      # A recording is served in byte ranges so a player can seek; those three are the range's own
      # and travel back with it.
      RELAYED = %w[content-range accept-ranges content-length].freeze

      TYPES = {
        ".html" => "text/html; charset=utf-8",
        ".js" => "text/javascript; charset=utf-8",
        ".css" => "text/css; charset=utf-8",
        ".json" => "application/json",
        ".map" => "application/json",
        ".svg" => "image/svg+xml",
        ".png" => "image/png",
        ".ico" => "image/x-icon",
        ".woff2" => "font/woff2"
      }.freeze

      attr_reader :url

      # Bind the loopback on a free port and serve the console in `files` for this door.
      def self.open(door:, files:)
        new(door:, files:).tap(&:listen)
      end

      def initialize(door:, files:)
        @door = door
        @files = File.expand_path(files)
        @nonce = SecureRandom.hex(NONCE_BYTES)
        @open = []
      end

      # Bind, and answer from a thread of its own until `close`.
      def listen
        @server = TCPServer.new(LOOPBACK, 0)
        @url = "http://#{LOOPBACK}:#{@server.addr[1]}/#{@nonce}/"
        @thread = Thread.new { accept_until_closed }
        self
      end

      # Where one screen of the console is, by the path the console routes.
      def at(path) = "#{@url}#{path.to_s.delete_prefix("/")}"

      # Close every socket and the port. After this, nothing answers at `url`.
      def close
        @closed = true
        @server&.close
        @open.each { |socket| socket.close unless socket.closed? }
        @thread&.join(1)
        nil
      end

      private

      def accept_until_closed
        loop do
          socket = @server.accept
          @open << socket
          Thread.new { serve(socket) }
        end
      rescue IOError, Errno::EBADF, Errno::EINVAL
        nil
      end

      def serve(socket)
        asked = Request.read(socket)
        answer(socket, asked) unless asked.nil?
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      ensure
        socket.close unless socket.closed?
        @open.delete(socket)
      end

      def answer(socket, asked)
        under = "/#{@nonce}/"
        return refuse(socket) unless asked.path.start_with?(under)

        path = asked.path.delete_prefix(under)
        return forward(socket, asked, "/#{path}#{asked.query}") if path.start_with?(DOORS)

        file(socket, path)
      end

      def refuse(socket)
        write_head(socket, 404, { "content-type" => "text/plain; charset=utf-8" })
        socket.write("not here\n")
      end

      # The one place the key is spent. The answer streams back as it arrives, which is what a log
      # over SSE needs; a browser that navigates away breaks the pipe and the door behind it is
      # let go with it.
      def forward(socket, asked, path)
        where = URI.join(@door.url, path)
        request = Net::HTTP.const_get(asked.method.capitalize).new(where)
        request["authorization"] = "Bearer #{@door.api_key}"
        FORWARDED.each { |name| request[name] = asked.headers[name] if asked.headers[name] }
        request.body = asked.body unless asked.body.nil?
        relay(socket, where, request)
      rescue NameError
        write_head(socket, 405, { "content-type" => "text/plain; charset=utf-8" })
        socket.write("#{asked.method} is not a verb this console forwards\n")
      end

      def relay(socket, where, request)
        http = Net::HTTP.new(where.host, where.port)
        http.use_ssl = where.scheme == "https"
        http.read_timeout = nil
        http.start do |open|
          open.request(request) do |answered|
            head = { "content-type" => answered["content-type"] || "application/octet-stream",
                     "cache-control" => "no-store" }
            RELAYED.each { |name| head[name] = answered[name] if answered[name] }
            write_head(socket, answered.code.to_i, head)
            answered.read_body { |chunk| socket.write(chunk) }
          end
        end
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        # The browser left mid-stream. It is the one way a stream is expected to end.
        nil
      rescue StandardError => e
        write_head(socket, 502, { "content-type" => "text/plain; charset=utf-8" })
        socket.write("the gateway did not answer: #{e.message}\n")
      end

      # A path that names a file of the console is that file; every other path is a screen the
      # console routes itself, so it gets the page. Nothing above the console's directory is read.
      def file(socket, path)
        found = File.expand_path(File.join(@files, path))
        return page(socket) unless found.start_with?("#{@files}#{File::SEPARATOR}") && File.file?(found)

        body = File.binread(found)
        write_head(socket, 200, { "content-type" => TYPES.fetch(File.extname(found), "application/octet-stream"),
                                  "content-length" => body.bytesize.to_s })
        socket.write(body)
      end

      # Read on every request and not once: a console rebuilt while `ui` runs names new assets in
      # a new page. The page is served for every screen the console routes itself, at any depth,
      # so its assets are addressed from the base and not from wherever the address bar stands.
      def page(socket)
        body = File.read(File.join(@files, "index.html"))
                   .sub("<head>", %(<head><base href="/#{@nonce}/">))
        write_head(socket, 200, { "content-type" => TYPES[".html"], "cache-control" => "no-store",
                                  "content-length" => body.bytesize.to_s })
        socket.write(body)
      end

      # Every answer says `connection: close`, so a body with no length ends at EOF and a stream
      # needs no chunked framing of its own.
      def write_head(socket, status, headers)
        lines = ["HTTP/1.1 #{status} #{REASONS.fetch(status, "OK")}", "connection: close"]
        headers.each { |name, value| lines << "#{name}: #{value}" }
        socket.write("#{lines.join("\r\n")}\r\n\r\n")
      end

      REASONS = { 200 => "OK", 206 => "Partial Content", 404 => "Not Found", 405 => "Method Not Allowed",
                  500 => "Internal Server Error", 502 => "Bad Gateway" }.freeze

      # One request off the socket: the line, the headers, and the body when it says it has one.
      # A console sends one JSON document at a time, never a stream, so a body is read whole.
      Request = Data.define(:method, :path, :query, :headers, :body) do
        def self.read(socket)
          line = socket.gets
          return nil if line.nil?

          method, target, = line.split
          return nil if method.nil? || target.nil?

          headers = {}
          while (header = socket.gets) && header != "\r\n" && header != "\n"
            name, _, value = header.partition(":")
            headers[name.strip.downcase] = value.strip
          end
          path, _, query = target.partition("?")
          body = read_body(socket, headers)
          new(method: method.upcase, path:, query: query.empty? ? "" : "?#{query}", headers:, body:)
        end

        def self.read_body(socket, headers)
          length = headers["content-length"].to_i
          length.positive? ? socket.read(length) : nil
        end
      end
    end
  end
end
