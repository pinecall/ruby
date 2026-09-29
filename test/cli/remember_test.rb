# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "rest_gateway"

class CLIRememberTest < Minitest::Test
  Remember = Pinecall::CLI::Remember

  A_CASE = {
    said: [["caller", "Soy alérgica a la penicilina"], ["agent", "Anotado."]],
    expect: { writes: ["alergias"] }
  }.freeze

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

  def in_a_directory
    Dir.mktmpdir("pinecall-cases") { |dir| yield dir }
  end

  def a_file(dir, name, content)
    path = File.join(dir, name)
    File.write(path, JSON.generate(content))
    path
  end

  # ── arguments ────────────────────────────────────────────────────────────────

  def test_the_flags_are_read_in_any_order_and_the_rest_are_paths
    paths, named, grep = Remember.parse(["--grep", "alergia", "test/memory", "--agent", "clara.rb"])

    assert_equal [File.expand_path("test/memory")], paths
    assert_equal "clara.rb", named
    assert_equal "alergia", grep
  end

  def test_with_no_flags_every_word_is_a_path
    paths, named, grep = Remember.parse(["uno.json", "dos.json"])

    assert_equal 2, paths.length
    assert_nil named
    assert_nil grep
  end

  # ── loading cases ────────────────────────────────────────────────────────────

  def test_a_file_holding_one_case_is_called_after_its_own_basename
    in_a_directory do |dir|
      file = a_file(dir, "la-alergia.json", A_CASE)

      assert_equal ["la-alergia"], Remember.cases_of(file).map { |one| one[:name] }
    end
  end

  def test_a_file_holding_several_cases_numbers_the_ones_that_named_nothing
    in_a_directory do |dir|
      file = a_file(dir, "dos.json", [A_CASE, A_CASE.merge(name: "la tarde")])

      assert_equal ["dos #1", "la tarde"], Remember.cases_of(file).map { |one| one[:name] }
    end
  end

  def test_a_directory_is_read_whole_and_in_the_order_a_person_reads_it
    in_a_directory do |dir|
      a_file(dir, "b.json", A_CASE)
      a_file(dir, "a.json", A_CASE)

      assert_equal %w[a b], Remember.cases_in([dir], nil, nil, err: StringIO.new).map { |one| one[:name] }
    end
  end

  def test_a_grep_that_matches_nothing_says_so_and_runs_none
    in_a_directory do |dir|
      a_file(dir, "la-alergia.json", A_CASE)
      err = StringIO.new

      assert_nil Remember.cases_in([dir], nil, "la tarde", err:)
      assert_includes err.string, "--grep la tarde"
    end
  end

  def test_a_directory_with_no_goldens_names_where_it_looked
    in_a_directory do |dir|
      err = StringIO.new

      assert_nil Remember.cases_in([dir], nil, nil, err:)
      assert_includes err.string, dir
    end
  end

  def test_a_case_file_that_is_not_json_is_a_refusal_and_not_a_backtrace
    in_a_directory do |dir|
      File.write(File.join(dir, "roto.json"), "{ nope")
      err = StringIO.new

      assert_nil Remember.cases_in([dir], nil, nil, err:)
      assert_includes err.string, "is not JSON"
    end
  end

  # ── the report ───────────────────────────────────────────────────────────────

  def a_run(results)
    { agent: "clinica-norte", model: "anthropic/claude-haiku-4-5", cases: results.length,
      held: results.count { |one| one[:held] }, took_ms: 3672.4, results: }
  end

  def test_a_run_that_held_is_one_line_and_a_tick_per_case
    lines = Remember.lines_of(a_run([{ name: "la alergia", held: true }]))

    assert_equal "clinica-norte · anthropic/claude-haiku-4-5 · 1 case · 1 held · 3672 ms", lines.first
    assert_equal "  #{Remember::HELD} la alergia", lines.last
  end

  def test_a_case_that_did_not_hold_carries_its_evidence_under_it
    run = a_run([{ name: "la tarjeta", held: false, wrote: ["add · alergias · Alérgica"],
                   refused: ["add · pagos · La Visa"],
                   broke: [{ check: "never_says", detail: "'4242' is in a fact memory would have kept" }] }])
    lines = Remember.lines_of(run)

    assert_includes lines[1], "#{Remember::BROKEN} la tarjeta"
    assert_includes lines[2], "never_says"
    assert_includes lines[3], "kept      add · alergias · Alérgica"
    assert_includes lines[4], "refused   add · pagos · La Visa"
  end

  def test_the_checks_line_up_in_a_column_so_two_failures_read_as_a_table
    run = a_run([{ name: "dos", held: false,
                   broke: [{ check: "writes", detail: "nothing under 'alergias'" },
                           { check: "invalidates", detail: "'Prefiere la tarde' still holds" }] }])
    lines = Remember.lines_of(run)

    assert_equal lines[2].index("nothing under"), lines[3].index("'Prefiere la tarde'")
  end

  # ── gateway ──────────────────────────────────────────────────────────────────

  def test_the_cases_go_to_the_agents_own_extraction_door
    @gateway = RestGateway.new(
      "POST /v1/agents/clinica-norte/memory/extraction" => [200, a_run([{ name: "la alergia", held: true }])]
    )
    client = Pinecall::Client.new(url: @gateway.url, api_key: "pk_org")

    answer = client.memory.extraction("clinica-norte", [A_CASE.merge(name: "la alergia")])

    assert_equal 1, answer[:held]
    assert_equal [["caller", "Soy alérgica a la penicilina"], ["agent", "Anotado."]],
                 @gateway.asked.first.body[:cases].first[:said]
  end

  def test_a_transcript_line_of_one_thing_is_refused_before_a_model_is_paid_for
    client = Pinecall::Client.new(url: "http://127.0.0.1:1", api_key: "pk_org")

    refusal = assert_raises(Pinecall::Wire::WireError) do
      client.memory.extraction("clinica-norte", [{ name: "media línea", said: [["caller"]] }])
    end

    assert_includes refusal.message, "said[0]"
  end
end
