# frozen_string_literal: true

require "securerandom"

module Pinecall
  module UI
    # Local server for `pinecall ui`: serves the console files and proxies the gateway's `v1/*`.
    #
    # Security: binds loopback only, on a kernel-chosen port; everything lives under a random
    # nonce path (anything else is 404); the API key is only added to outgoing proxy requests and
    # never reaches the browser.
    #
    # Plain-socket HTTP/1.1 so SSE can stream straight through. Every response closes its
    # connection, so bodies can end at EOF without a length.
    class Server
      LOOPBACK = "127.0.0.1"
      NONCE_BYTES = 16

      # Paths under the nonce with this prefix are proxied; everything else is a console file or route.
      DOORS = "v1/"

      # Request headers forwarded to the gateway; cookies, origin etc. are dropped.
      FORWARDED = %w[content-type accept last-event-id range].freeze

      # Response headers relayed back, so recordings can be seeked with range requests.
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

      def self.open(door:, files:)
        new(door:, files:).tap(&:listen)
      end

      def initialize(door:, files:)
        @door = door
        @files = File.expand_path(files)
        @nonce = SecureRandom.hex(NONCE_BYTES)
        @open = []
      end

      # Bind and serve on a background thread until `close`.
      def listen
        @server = TCPServer.new(LOOPBACK, 0)
        @url = "http://#{LOOPBACK}:#{@server.addr[1]}/#{@nonce}/"
        @thread = Thread.new { accept_until_closed }
        self
      end

      # URL for a console route.
      def at(path) = "#{@url}#{path.to_s.delete_prefix("/")}"

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

      # The only place the API key is used. Streams the response through, for SSE.
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
        # The browser left mid-stream: the normal end of an SSE stream.
        nil
      rescue StandardError => e
        write_head(socket, 502, { "content-type" => "text/plain; charset=utf-8" })
        socket.write("the gateway did not answer: #{e.message}\n")
      end

      # Serve a console file, or `index.html` for client-side routes. Paths outside `@files` are
      # never read.
      def file(socket, path)
        found = File.expand_path(File.join(@files, path))
        return page(socket) unless found.start_with?("#{@files}#{File::SEPARATOR}") && File.file?(found)

        body = File.binread(found)
        write_head(socket, 200, { "content-type" => TYPES.fetch(File.extname(found), "application/octet-stream"),
                                  "content-length" => body.bytesize.to_s })
        socket.write(body)
      end

      # Re-read per request so a rebuilt console is picked up. `<base>` makes asset paths resolve
      # from the nonce root at any route depth.
      def page(socket)
        body = File.read(File.join(@files, "index.html"))
                   .sub("<head>", %(<head><base href="/#{@nonce}/">))
        write_head(socket, 200, { "content-type" => TYPES[".html"], "cache-control" => "no-store",
                                  "content-length" => body.bytesize.to_s })
        socket.write(body)
      end

      # Always `connection: close`, so length-less bodies end at EOF and no chunked framing is needed.
      def write_head(socket, status, headers)
        lines = ["HTTP/1.1 #{status} #{REASONS.fetch(status, "OK")}", "connection: close"]
        headers.each { |name, value| lines << "#{name}: #{value}" }
        socket.write("#{lines.join("\r\n")}\r\n\r\n")
      end

      REASONS = { 200 => "OK", 206 => "Partial Content", 404 => "Not Found", 405 => "Method Not Allowed",
                  500 => "Internal Server Error", 502 => "Bad Gateway" }.freeze

      # A parsed request. Bodies are read whole by `content-length`; the console never streams uploads.
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
