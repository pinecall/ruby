# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "rest_gateway"

# `pinecall knowledge`: a folder becomes a base, by name, through the org's key.
class CLIKnowledgeTest < Minitest::Test
  EXAMPLE = File.expand_path("../../examples/clinica_norte", __dir__)

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

  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Pinecall::CLI.run(argv, out:, err:, input: StringIO.new)
    [status, out.string, err.string]
  end

  def test_push_sends_every_markdown_file_under_the_folder_as_the_base_named_and_says_what_it_became
    gateway("PUT /v1/knowledge/clinica-norte" => [200, { base: "clinica-norte", chunks: 7, took_ms: 312.4 }])
    status, out, = run_cli("knowledge", "push", "#{EXAMPLE}/knowledge/docs", "--base", "clinica-norte")

    assert_equal 0, status
    assert_equal "clinica-norte · 2 files · 7 chunks · 312 ms\n", out
    sent = @gateway.asked.first

    assert_equal "Bearer pk_org", sent.headers["authorization"]
    assert_equal %w[pruebas.md seguros.md], sent.body[:files].map { |file| file[:path] }
    assert_includes sent.body[:files].first[:text], "# Preparación de pruebas"
  end

  def test_push_with_nothing_said_reads_the_base_and_the_folder_off_the_agent_here
    gateway("PUT /v1/knowledge/clinica-norte" => [200, { base: "clinica-norte", chunks: 7, took_ms: 10 }])
    status, out, = Dir.chdir(EXAMPLE) { run_cli("knowledge", "push") }

    assert_equal 0, status
    assert_includes out, "clinica-norte · 2 files"
  end

  def test_push_with_no_agent_here_and_no_base_says_what_it_takes
    status, _out, err = Dir.chdir(ENV.fetch("PINECALL_HOME")) { run_cli("knowledge", "push") }

    assert_equal 2, status
    assert_includes err, "there is no"
    assert_includes err, "takes DIR and --base NAME"
  end

  def test_a_folder_with_no_markdown_in_it_is_refused_before_anything_is_sent
    status, _out, err = run_cli("knowledge", "push", ENV.fetch("PINECALL_HOME"), "--base", "vacia")

    assert_equal 2, status
    assert_includes err, "no *.md under"
  end

  def test_the_gateway_s_refusal_is_printed_as_it_wrote_it
    gateway("PUT /v1/knowledge/x" => [503, { detail: "this gateway keeps no knowledge: it runs on a dev key" }])
    status, _out, err = run_cli("knowledge", "push", "#{EXAMPLE}/knowledge/docs", "--base", "x")

    assert_equal 1, status
    assert_equal "pinecall: 503: this gateway keeps no knowledge: it runs on a dev key\n", err
  end

  def test_list_prints_one_line_per_base
    gateway("GET /v1/knowledge" => [200, { bases: [{ base: "clinica-norte", chunks: 7, model: "BAAI/bge-m3", pushed_at: 1_757_500_000.0 }] }])
    status, out, = run_cli("knowledge", "list")

    assert_equal 0, status
    assert_equal "clinica-norte · 7 chunks · pushed 2025-09-10 10:26\n", out
  end

  def test_drop_sends_the_delete_and_says_so
    gateway("DELETE /v1/knowledge/clinica-norte" => [200, {}])
    status, out, = run_cli("knowledge", "drop", "clinica-norte")

    assert_equal 0, status
    assert_equal "clinica-norte dropped\n", out
    assert_equal "DELETE", @gateway.asked.first.method
  end

  def test_with_no_key_every_verb_says_so_before_it_opens_anything
    ENV.delete("PINECALL_API_KEY")
    status, _out, err = run_cli("knowledge", "list")

    assert_equal 2, status
    assert_includes err, "no key for"
  end
  # A golden is the only thing that says the index missed a BETTER passage: the judge that runs on
  # every call can only weigh what the model was given. runtime/docs/retrieval/spec.md.
  def test_eval_prints_the_two_figures_and_the_embedder_that_wrote_the_vectors
    gateway("POST /v1/knowledge/clinica/eval" => [200, {
              base: "clinica", model: "BAAI/bge-m3", questions: 1, k: 4,
              recall_at_k: 1.0, ndcg_at_10: 1.0, took_ms: 90.4, misses: []
            }])
    status, out, = run_cli("knowledge", "eval", a_golden, "--base", "clinica")

    assert_equal 0, status
    assert_equal "clinica · BAAI/bge-m3 · 1 questions · recall@4 1.00 · nDCG@10 1.00 · 90 ms\n", out
  end

  def test_eval_names_every_question_it_missed_and_exits_one
    gateway("POST /v1/knowledge/clinica/eval" => [200, {
              base: "clinica", model: "m", questions: 1, k: 4,
              recall_at_k: 0.0, ndcg_at_10: 0.0, took_ms: 12.0,
              misses: [{ asks: "¿cuánto cuesta?", expects: "tarifas.md",
                         found: ["horarios.md › Horario"] }]
            }])
    status, out, = run_cli("knowledge", "eval", a_golden, "--base", "clinica")

    assert_equal 1, status
    assert_includes out, "missed: ¿cuánto cuesta? → wanted tarifas.md, got horarios.md › Horario"
  end

  def test_eval_says_where_it_looked_when_there_is_no_golden_there
    status, _, err = run_cli("knowledge", "eval", "/nope/golden.json", "--base", "clinica")

    assert_equal 2, status
    assert_includes err, "there is no /nope/golden.json"
  end

  # One question, on disk, as a person writes it beside their own documents.
  def a_golden
    path = File.join(Dir.mktmpdir("pinecall-golden"), "golden.json")
    File.write(path, JSON.generate([{ asks: "¿cuánto cuesta?", expects: "tarifas.md" }]))
    path
  end

end
