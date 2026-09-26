# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# CLI verbs, and gateway/key resolution order.
class CLITest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("pinecall-home")
    @kept = ENV.to_h.slice("PINECALL_HOME", "PINECALL_URL", "PINECALL_API_KEY", "PINECALL_DEV_KEY")
    %w[PINECALL_URL PINECALL_API_KEY PINECALL_DEV_KEY].each { |name| ENV.delete(name) }
    ENV["PINECALL_HOME"] = @home
  end

  def teardown
    %w[PINECALL_HOME PINECALL_URL PINECALL_API_KEY PINECALL_DEV_KEY].each { |name| ENV.delete(name) }
    ENV.update(@kept)
    FileUtils.remove_entry(@home)
  end

  def write(name, table, mode: 0o600)
    path = File.join(@home, name)
    File.write(path, JSON.generate(table))
    File.chmod(mode, path)
    path
  end

  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Pinecall::CLI.run(argv, out:, err:)
    [status, out.string, err.string]
  end

  def test_with_nothing_anywhere_it_points_at_the_local_gateway_and_says_it_has_no_key
    pointed = Pinecall::CLI::Env.pointed

    assert_equal Pinecall::CLI::Env::LOCAL, pointed.url
    assert_nil pointed.api_key
    assert_equal 2, run_cli("whoami").first
  end

  def test_the_url_the_person_exported_wins_over_everything
    ENV["PINECALL_URL"] = "https://box.pinecall.io"
    ENV["PINECALL_API_KEY"] = "pk_exported"

    assert_equal "https://box.pinecall.io", Pinecall::CLI::Env.pointed.url
    assert_equal :environment, Pinecall::CLI::Env.pointed.source
  end

  def test_a_local_gateway_on_a_dev_key_honours_its_own_key_and_says_the_exported_one_is_ignored
    write("dev", { "url" => "http://localhost:8080", "key" => "pk_dev" })
    ENV["PINECALL_API_KEY"] = "pk_exported"
    pointed = Pinecall::CLI::Env.pointed

    assert_equal "pk_dev", pointed.api_key
    assert_equal :dev_file, pointed.source
    assert_includes pointed.notice, "ignored"
  end

  def test_the_one_gateway_a_login_kept_is_used_when_there_is_exactly_one
    write("credentials", { "gateways" => { "https://box.pinecall.io" => { "api_key" => "pk_kept" } } })
    pointed = Pinecall::CLI::Env.pointed

    assert_equal "https://box.pinecall.io", pointed.url
    assert_equal "pk_kept", pointed.api_key
  end

  def test_two_gateways_is_a_choice_and_the_choice_is_the_person_s
    write("credentials", { "gateways" => { "https://one.io" => { "api_key" => "a" },
                                           "https://two.io" => { "api_key" => "b" } } })

    assert_equal Pinecall::CLI::Env::LOCAL, Pinecall::CLI::Env.pointed.url
  end

  def test_a_key_file_anybody_on_the_box_could_read_is_treated_as_absent
    write("dev", { "url" => "http://localhost:8080", "key" => "pk_dev" }, mode: 0o644)

    assert_nil Pinecall::CLI::Env.pointed.api_key
  end

  def test_whoami_says_where_the_key_came_from_and_never_the_key
    ENV["PINECALL_URL"] = "https://box.pinecall.io"
    ENV["PINECALL_API_KEY"] = "pk_secret_value"
    status, out, = run_cli("whoami")

    assert_equal 0, status
    assert_includes out, "PINECALL_API_KEY"
    refute_includes out, "pk_secret_value"
  end

  def test_prompt_needs_no_gateway_and_no_key_at_all
    status, out, = run_cli("prompt", "examples/clinica_norte/agent.rb", "--stage", "identify")

    assert_equal 0, status
    assert_includes out, "── identity (static) ──"
    assert_includes out, "Saluda y pide nombre y teléfono."
  end

  def test_a_file_that_declares_no_agent_says_so_and_exits_two
    status, _out, err = run_cli("prompt", "lib/pinecall/version.rb")

    assert_equal 2, status
    assert_includes err, "declares no Pinecall::Agent"
  end

  def test_a_file_that_does_not_load_says_why_instead_of_a_backtrace
    broken = File.join(@home, "roto.rb")
    File.write(broken, "class Roto < Pinecall::Agent\n")
    status, _out, err = run_cli("prompt", broken)

    assert_equal 2, status
    assert_includes err, "did not load"
  end

  def test_a_verb_the_design_names_and_this_package_has_not_written_says_what_it_will_be
    status, out, = run_cli("test")

    assert_equal 0, status
    assert_includes out, "ring 1"
  end

  def test_the_console_says_what_it_is_before_it_opens_a_port
    status, out, = run_cli("ui", "--help")

    assert_equal 2, status
    assert_includes out, "127.0.0.1"
    assert_includes out, "The key never reaches the browser"
  end

  def test_the_console_refuses_to_open_without_a_key_rather_than_serving_nothing
    status, _out, err = run_cli("ui")

    assert_equal 2, status
    assert_includes err, "no key for"
  end

  def test_a_verb_nobody_has_is_an_error_and_the_usage
    status, _out, err = run_cli("dance")

    assert_equal 2, status
    assert_includes err, "no verb called dance"
  end
end
