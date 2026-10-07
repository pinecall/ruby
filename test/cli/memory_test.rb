# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../client/rest_gateway"

class CLIMemoryTest < Minitest::Test
  # A TTY stdin with scripted input.
  class Terminal < StringIO
    def tty? = true
  end

  def setup
    @kept = ENV.to_h.slice("PINECALL_HOME", "PINECALL_URL", "PINECALL_API_KEY")
    ENV["PINECALL_HOME"] = Dir.mktmpdir("pinecall-home")
    ENV["PINECALL_API_KEY"] = "pk_org"
  end

  def teardown
    @gateway&.stop
    FileUtils.remove_entry(ENV.fetch("PINECALL_HOME"))
    %w[PINECALL_HOME PINECALL_URL PINECALL_API_KEY].each { |name| ENV.delete(name) }
    ENV.update(@kept)
  end

  def gateway(answers)
    @gateway = RestGateway.new(answers)
    ENV["PINECALL_URL"] = @gateway.url
    @gateway
  end

  def run_cli(*argv, input: StringIO.new)
    out = StringIO.new
    err = StringIO.new
    status = Pinecall::CLI.run(argv, out:, err:, input:)
    [status, out.string, err.string]
  end

  FACTS = [
    { id: "f2", text: "Prefiere que le llamen Marta", category: "preference", valid_from: 1_757_500_000.0,
      invalidated_at: nil },
    { id: "f1", text: "Alérgica a la penicilina", category: "health", valid_from: 1_754_000_000.0,
      invalidated_at: 1_757_500_000.0 }
  ].freeze

  def test_the_history_is_printed_current_first_and_a_superseded_fact_says_until_when
    gateway("GET /v1/contacts/%2B34600123456/memory" => [200, { facts: FACTS }])
    status, out, = run_cli("memory", "+34600123456")

    assert_equal 0, status
    assert_equal ["- Prefiere que le llamen Marta  (preference · since 2025-09-10)",
                  "- Alérgica a la penicilina  (health · since 2025-07-31 · until 2025-09-10)"], out.lines.map(&:chomp)
  end

  def test_a_contact_nobody_remembers_is_said_so
    gateway("GET /v1/contacts/nadie/memory" => [200, { facts: [] }])
    _status, out, = run_cli("memory", "nadie")

    assert_equal "nothing is remembered about nadie\n", out
  end

  def test_forget_from_a_pipe_deletes_without_asking
    gateway("DELETE /v1/contacts/ana/memory" => [200, { forgotten: 3 }])
    status, out, = run_cli("memory", "forget", "ana")

    assert_equal 0, status
    assert_equal "ana: 3 facts forgotten\n", out
  end

  def test_forget_on_a_terminal_asks_once_and_a_no_sends_nothing
    gateway("DELETE /v1/contacts/ana/memory" => [200, { forgotten: 3 }])
    status, out, = run_cli("memory", "forget", "ana", input: Terminal.new("n\n"))

    assert_equal 0, status
    assert_includes out, "forget everything about ana? [y/N]"
    assert_includes out, "kept"
    assert_empty @gateway.asked
  end

  def test_forget_on_a_terminal_goes_ahead_on_a_yes
    gateway("DELETE /v1/contacts/ana/memory" => [200, { forgotten: 1 }])
    _status, out, = run_cli("memory", "forget", "ana", input: Terminal.new("y\n"))

    assert_includes out, "ana: 1 facts forgotten"
  end

  def test_the_gateway_s_refusal_is_printed_as_it_wrote_it
    gateway("GET /v1/contacts/x/memory" => [404, { detail: "no contact called x" }])
    status, _out, err = run_cli("memory", "x")

    assert_equal 1, status
    assert_equal "pinecall: 404: no contact called x\n", err
  end

  A_QUESTION = {
    holds: ["Prefiere mañanas", "Alérgica a la penicilina"],
    asks: "¿le va bien el martes?",
    expects: ["Prefiere mañanas"]
  }.freeze

  def test_eval_sends_the_whole_golden_to_the_one_door_and_prints_the_two_figures
    gateway("POST /v1/contacts/memory/eval" => [200, {
              model: "BAAI/bge-m3", questions: 1, k: 6,
              recall_at_k: 1.0, ndcg_at_10: 1.0, took_ms: 612.4, misses: []
            }])
    status, out, = run_cli("memory", "eval", a_golden, "--k", "6")

    assert_equal 0, status
    assert_equal "memory · BAAI/bge-m3 · 1 questions · recall@6 1.00 · nDCG@10 1.00 · 612 ms\n", out
    assert_equal({ questions: [A_QUESTION], k: 6 }, @gateway.asked.first.body)
  end

  def test_eval_names_every_fact_a_question_wanted_and_did_not_get_and_exits_one
    gateway("POST /v1/contacts/memory/eval" => [200, {
              model: "m", questions: 1, k: 1, recall_at_k: 0.0, ndcg_at_10: 0.0, took_ms: 12.0,
              misses: [{ asks: "¿le va bien el martes?", missing: ["Prefiere mañanas"],
                         found: ["Alérgica a la penicilina"] }]
            }])
    status, out, = run_cli("memory", "eval", a_golden, "--k", "1")

    assert_equal 1, status
    assert_includes out, "missed: ¿le va bien el martes? → wanted Prefiere mañanas, " \
                         "got Alérgica a la penicilina"
  end

  def test_eval_says_where_it_looked_when_there_is_no_golden_there
    status, _, err = run_cli("memory", "eval", "/nope/golden.json")

    assert_equal 2, status
    assert_includes err, "there is no /nope/golden.json"
  end

  def a_golden
    path = File.join(Dir.mktmpdir("pinecall-golden"), "golden.json")
    File.write(path, JSON.generate([A_QUESTION]))
    path
  end
end
