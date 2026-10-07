# frozen_string_literal: true

require "test_helper"
require_relative "fake_gateway"

# One agent from the app's side, on a real socket: it leaves by draining, and a console's ask is answered.
class AgentTest < Minitest::Test
  def setup
    @gateway = FakeGateway.new
    @client = Pinecall::Client.new(url: @gateway.url, api_key: "pk_test", env: "production")
    @client.on_errors { |_error| nil }
    @client.agent("clinica-norte", tools: [])
    @client.connect
  end

  def teardown
    @client.close
    @gateway.stop
  end

  def test_a_drain_asks_the_gateway_and_says_where_the_calls_went
    drained = @client.drain(tools_s: 0.1)

    refute_nil @gateway.next_frame("agent.drain")
    assert_equal [0, 0, 0, 0], [drained.handed, drained.parked, drained.tools, drained.finished]
  end

  def test_a_consoles_ask_is_answered_that_a_ruby_agent_draws_no_panel
    @gateway.send_entry("clinica-norte", "dev.request", { id: "dev_1", verb: "view.render", data: {} })

    answer = @gateway.next_frame("dev.answer")
    assert_equal({ id: "dev_1", refused: { status: 404, detail: "a Ruby agent draws no panel" } }, answer[:data])
  end

  def test_the_socket_says_which_world_it_acts_in_and_where_it_runs
    registered = @gateway.next_frame("agent.register")

    assert_equal "production", @gateway.world
    assert_equal Socket.gethostname, registered[:data][:host]
  end

  def test_every_entry_reaches_on_entries_as_the_gateway_wrote_it
    seen = Thread::Queue.new
    @client.on_entries { |entry| seen << entry }
    @gateway.send_entry("tienda-sur", "agent.configured", { changed: %w[tools] })

    entry = seen.pop(timeout: 5)
    assert_equal ["agent.configured", "tienda-sur", { changed: %w[tools] }], [entry.type, entry.agent, entry.data]
  end

  def test_a_vendor_that_switches_mid_call_is_read_and_the_socket_keeps_answering
    errors = Thread::Queue.new
    @client.on_errors { |error| errors << error }
    @gateway.send_entry("clinica-norte", "vendor.switched", { stage: "tts", vendor: "elevenlabs", model: "eleven_flash_v2_5",
                                                              available: false, serving: "cartesia", serving_model: "sonic-2" }, call: "CA_1")
    @gateway.send_entry("clinica-norte", "dev.request", { id: "dev_2", verb: "view.render", data: {} })

    refute_nil @gateway.next_frame("dev.answer")
    assert_nil errors.pop(timeout: 0.2)
  end

  def test_a_stop_from_the_org_is_said_once_and_the_socket_closes_for_good
    why = Thread::Queue.new
    @client.on_stopped { |said| why << said }
    @gateway.send_entry("", "error", { code: "stopped", message: "stopped by Lucía" })

    assert_equal "stopped by Lucía", why.pop(timeout: 5)
    refute @client.connected?
  end
end
