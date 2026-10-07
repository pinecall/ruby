# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "test_helper"
require_relative "client/fake_gateway"

# The entry the one CLI starts a Ruby agent with: the wire on stdout, its door from the environment,
# a drained leave, and a prompt that needs nothing.
class ServeTest < Minitest::Test
  AGENT = File.expand_path("../examples/clinica_norte/agent.rb", __dir__)
  SLUG = "clinica-norte"

  def setup
    @gateway = FakeGateway.new
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown = @gateway.stop

  def env(**more) = { "PINECALL_URL" => @gateway.url, "PINECALL_KEY" => "pk_test" }.merge(more)

  # `start` on a thread, its stdin a pipe the test holds and its signals a queue the test pushes.
  def started(*flags, environment: env)
    reading, @writing = IO.pipe
    @signals = Thread::Queue.new
    Thread.new do
      Pinecall::Serve.main(["start", "--file", AGENT, "--slug", SLUG, *flags], out: @out, err: @err, env: environment,
                                                                              input: reading, signals: @signals)
    end
  end

  def until_registered
    refute_nil @gateway.next_frame("agent.configure")
    sleep(0.05)
  end

  def test_the_first_line_is_the_registration_with_the_app_it_was_given
    running = started("--events")
    until_registered
    @signals.push(:signalled)

    assert_equal 0, running.value
    first = JSON.parse(@out.string.lines.first, symbolize_names: true)
    assert_equal({ type: "agent.registered", agent: SLUG, call: nil }, first.slice(:type, :agent, :call))
    assert_equal "app_1", first[:data][:app]
  end

  def test_a_signal_drains_before_the_socket_closes
    running = started
    until_registered
    @signals.push(:signalled)

    assert_equal 0, running.value
    refute_nil @gateway.next_frame("agent.drain")
    assert_includes @err.string, "draining · no live calls"
  end

  def test_the_end_of_its_stdin_drains_it_too
    running = started
    until_registered
    @writing.close

    assert_equal 0, running.value
    refute_nil @gateway.next_frame("agent.drain")
  end

  def test_a_consoles_process_takes_no_unclaimed_call_and_prod_names_production
    running = started("--console", "--prod")
    registered = @gateway.next_frame("agent.register")
    until_registered
    @signals.push(:signalled)
    running.value

    assert_equal false, registered[:data][:takes_unclaimed]
    assert_equal "production", @gateway.world
  end

  def test_nothing_in_the_environment_is_a_sentence_and_exit_two
    code = Pinecall::Serve.main(["start", "--file", AGENT, "--slug", SLUG], out: @out, err: @err, env: {})

    assert_equal 2, code
    assert_includes @err.string, "PINECALL_URL and PINECALL_KEY"
  end

  def test_a_gateway_that_is_not_there_is_a_sentence_and_exit_two
    code = Pinecall::Serve.main(["start", "--file", AGENT, "--slug", SLUG], out: @out, err: @err,
                                                                            env: env("PINECALL_URL" => "http://127.0.0.1:1"))

    assert_equal 2, code
    assert_includes @err.string, "127.0.0.1:1"
  end

  def test_a_prompt_needs_no_gateway_and_opens_in_the_state_its_pairs_name
    code = Pinecall::Serve.main(["prompt", "--file", AGENT, "--slug", SLUG, "--state", 'stage="book"', "--show-machine"],
                                out: @out, err: @err, env: {})

    assert_equal 0, code
    assert_includes @out.string, "── tools ── stage: book"
  end

  def test_a_file_with_no_agent_and_a_verb_nobody_wrote_are_refused
    assert_equal 2, Pinecall::Serve.main(["prompt", "--file", "nowhere.rb", "--slug", SLUG], out: @out, err: @err)
    assert_includes @err.string, "no agent at"
    assert_equal 2, Pinecall::Serve.main(["fly"], out: @out, err: @err)
  end

  def test_a_class_whose_own_slug_is_another_is_refused
    Dir.mktmpdir do |folder|
      file = File.join(folder, "agent.rb")
      File.write(file, "# Otra.\nclass OtraServida < Pinecall::Agent\n  slug \"otra\"\nend\n")

      assert_equal 2, Pinecall::Serve.main(["prompt", "--file", file, "--slug", "una"], out: @out, err: @err)
      assert_includes @err.string, "says its slug is otra, and it is served as una"
    end
  end
end
