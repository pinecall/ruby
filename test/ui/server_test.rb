# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "net/http"

# The console's server: the nonce, the files, and the one place the org key is spent.
class UIServerTest < Minitest::Test
  # The smallest gateway that answers what the console asks: it keeps the authorization header it
  # was given, answers JSON at one door and a stream at another.
  class Gateway
    attr_reader :authorization, :asked

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @asked = []
      @thread = Thread.new { serve }
    end

    def url = "http://127.0.0.1:#{@server.addr[1]}"

    def stop
      @thread.kill
      @server.close
    end

    private

    def serve
      loop do
        socket = @server.accept
        Thread.new { answer(socket) }
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def answer(socket)
      line = socket.gets
      headers = {}
      while (header = socket.gets) && header !~ /\A\r?\n\z/
        name, _, value = header.partition(":")
        headers[name.strip.downcase] = value.strip
      end
      @authorization = headers["authorization"]
      method, target, = line.split
      @asked << [method, target, headers]
      target.start_with?("/v1/live") ? stream(socket) : document(socket, target)
    rescue Errno::EPIPE, IOError
      nil
    ensure
      socket.close unless socket.closed?
    end

    def document(socket, target)
      body = JSON.generate({ door: target })
      socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n" \
                   "content-length: #{body.bytesize}\r\nconnection: close\r\n\r\n#{body}")
    end

    def stream(socket)
      socket.write("HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n")
      socket.write("data: {\"seq\":1}\n\n")
      sleep(0.15)
      socket.write("data: {\"seq\":2}\n\n")
    end
  end

  def setup
    @gateway = Gateway.new
    @files = Dir.mktmpdir("console")
    File.write(File.join(@files, "index.html"), "<html><head><title>pinecall</title></head><body></body></html>")
    Dir.mkdir(File.join(@files, "assets"))
    File.write(File.join(@files, "assets", "index-abc.js"), "console.log('hola')")
    @door = Pinecall::CLI::Env::Pointed.new(url: @gateway.url, api_key: "pk_org_key", source: :environment, notice: nil)
    @served = Pinecall::UI::Server.open(door: @door, files: @files)
  end

  def teardown
    @served.close
    @gateway.stop
    FileUtils.remove_entry(@files)
  end

  def get(path, headers = {})
    Net::HTTP.get_response(URI.join(@served.url, path), headers)
  end

  def test_the_url_it_prints_is_the_loopback_a_free_port_and_a_nonce
    where = URI.parse(@served.url)

    assert_equal "127.0.0.1", where.host
    assert_match(%r{\A/[0-9a-f]{32}/\z}, where.path)
  end

  def test_a_process_that_scans_this_port_without_the_nonce_finds_nothing
    answer = Net::HTTP.get_response(URI.parse("#{URI.parse(@served.url).origin}/v1/agents"))

    assert_equal "404", answer.code
    assert_includes answer.body, "not here"
  end

  def test_a_screen_the_console_routes_itself_gets_the_page_with_the_base_written_in
    answer = get("a/clinica-norte/calls/CA_1")

    assert_equal "200", answer.code
    assert_includes answer["content-type"], "text/html"
    assert_includes answer.body, %(<base href="#{URI.parse(@served.url).path}">)
  end

  def test_a_file_of_the_console_is_that_file_with_its_own_type
    answer = get("assets/index-abc.js")

    assert_equal "console.log('hola')", answer.body
    assert_includes answer["content-type"], "text/javascript"
  end

  # Asked through a raw socket, because a client normalises `..` away before it ever leaves and
  # the whole point is what this server does with one that did not.
  def test_nothing_above_the_console_s_directory_is_ever_read
    where = URI.parse(@served.url)
    socket = TCPSocket.new(where.host, where.port)
    socket.write("GET #{where.path}assets/../../../../etc/passwd HTTP/1.1\r\nhost: x\r\n\r\n")
    answered = socket.read
    socket.close

    refute_includes answered, "root:"
    assert_includes answered, "<html>"
  end

  def test_a_door_is_forwarded_to_the_gateway_with_the_org_key_on_the_header
    answer = get("v1/agents")

    assert_equal "200", answer.code
    assert_equal "Bearer pk_org_key", @gateway.authorization
    assert_equal({ "door" => "/v1/agents" }, JSON.parse(answer.body))
  end

  def test_the_query_a_screen_asked_with_travels_with_it
    get("v1/calls/CA_1/events?after=12")

    assert_equal "/v1/calls/CA_1/events?after=12", @gateway.asked.last[1]
  end

  def test_only_the_headers_the_gateway_needs_cross_and_the_browser_s_own_stop_here
    get("v1/agents", { "accept" => "application/json", "cookie" => "session=secret", "user-agent" => "a browser" })
    sent = @gateway.asked.last[2]

    assert_equal "application/json", sent["accept"]
    assert_nil sent["cookie"]
    # Whatever reaches the gateway as a user agent is this process's own, never the browser's.
    refute_equal "a browser", sent["user-agent"]
  end

  def test_a_log_arrives_as_it_happens_and_is_not_held_until_it_ends
    seen = []
    URI.join(@served.url, "v1/live/CA_1").then do |where|
      Net::HTTP.start(where.host, where.port) do |http|
        http.request(Net::HTTP::Get.new(where, { "accept" => "text/event-stream" })) do |answer|
          assert_includes answer["content-type"], "text/event-stream"
          answer.read_body { |chunk| seen << [Process.clock_gettime(Process::CLOCK_MONOTONIC), chunk] }
        end
      end
    end

    assert_equal 2, seen.size
    assert_operator seen.last.first - seen.first.first, :>, 0.05
    assert_includes seen.map(&:last).join, %("seq":2)
  end

  def test_the_key_is_never_in_anything_the_browser_is_handed
    %w[a/clinica-norte assets/index-abc.js].each do |path|
      refute_includes get(path).body, "pk_org_key"
    end
  end

  def test_after_close_nothing_answers_there_at_all
    @served.close

    assert_raises(SystemCallError, IOError) { get("a/clinica-norte") }
  end
end
