# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "rest_gateway"

# `pinecall keys`: the org's own key for a vendor sent once and printed back never, the vendors
# read by name, and the gateway's own refusal said as it wrote it.
class CLIKeysTest < Minitest::Test
  # The thing that must never come back out. Every assertion below asks whether it appears
  # anywhere a person, a scrollback or a log would see it.
  THE_ORGS_OWN = "sk-the-clinic-brought-its-own-elevenlabs-key"

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

  # The key arrives the way a script gives it: one line of a stdin that is no terminal.
  def run_cli(*argv, typed: "")
    out = StringIO.new
    err = StringIO.new
    status = Pinecall::CLI.run(argv, out:, err:, input: StringIO.new(typed))
    [status, out.string, err.string]
  end

  def test_add_sends_the_key_in_the_body_once_and_prints_the_vendor_and_nothing_else
    gateway("PUT /v1/provider-keys/elevenlabs" => [204, {}])
    status, out, = run_cli("keys", "add", "elevenlabs", typed: "#{THE_ORGS_OWN}\n")

    assert_equal 0, status
    assert_equal "elevenlabs\n", out
    sent = @gateway.asked.first

    assert_equal "PUT", sent.method
    assert_equal "Bearer pk_org", sent.headers["authorization"]
    assert_equal({ key: THE_ORGS_OWN }, sent.body)
  end

  def test_the_key_is_printed_nowhere_on_the_way_out_or_on_the_way_back
    gateway("PUT /v1/provider-keys/elevenlabs" => [204, {}],
            "GET /v1/provider-keys" => [200, { vendors: %w[elevenlabs] }])
    _, added, added_err = run_cli("keys", "add", "elevenlabs", typed: "#{THE_ORGS_OWN}\n")
    _, listed, listed_err = run_cli("keys", "list")

    refute_includes added + added_err, THE_ORGS_OWN
    refute_includes listed + listed_err, THE_ORGS_OWN
    assert_equal "elevenlabs\n", listed
  end

  def test_add_with_nothing_on_stdin_brings_nothing_and_knocks_at_no_door
    gateway("PUT /v1/provider-keys/elevenlabs" => [204, {}])
    status, _out, err = run_cli("keys", "add", "elevenlabs", typed: "\n")

    assert_equal 2, status
    assert_includes err, "no key was given"
    assert_empty @gateway.asked
  end

  def test_add_says_what_it_takes_when_no_vendor_is_named
    status, _out, err = run_cli("keys", "add", typed: "#{THE_ORGS_OWN}\n")

    assert_equal 2, status
    assert_includes err, "keys add takes the vendor"
  end

  def test_a_vendor_this_build_does_not_run_is_refused_in_the_gateways_own_words
    known = "no vendor named 11labs; this build runs: anthropic, deepgram, elevenlabs, openai, soniox, whatsapp"
    gateway("PUT /v1/provider-keys/11labs" => [400, { detail: known }])
    status, _out, err = run_cli("keys", "add", "11labs", typed: "#{THE_ORGS_OWN}\n")

    assert_equal 1, status
    assert_equal "pinecall: 400: #{known}\n", err
    refute_includes err, THE_ORGS_OWN
  end

  def test_rm_gives_the_vendor_back_to_the_box_and_says_which_one
    gateway("DELETE /v1/provider-keys/elevenlabs" => [204, {}])
    status, out, = run_cli("keys", "rm", "elevenlabs")

    assert_equal 0, status
    assert_equal "elevenlabs\n", out
    assert_equal "DELETE", @gateway.asked.first.method
  end

  def test_rm_of_a_vendor_this_org_never_brought_is_the_gateways_404
    gateway("DELETE /v1/provider-keys/soniox" => [404, { detail: "org clinica has no soniox key" }])
    status, _out, err = run_cli("keys", "rm", "soniox")

    assert_equal 1, status
    assert_equal "pinecall: 404: org clinica has no soniox key\n", err
  end

  def test_list_prints_one_vendor_per_line_and_no_value_beside_it
    gateway("GET /v1/provider-keys" => [200, { vendors: %w[anthropic elevenlabs] }])
    status, out, = run_cli("keys", "list")

    assert_equal 0, status
    assert_equal "anthropic\nelevenlabs\n", out
  end

  def test_list_says_which_keys_run_instead_when_this_org_brought_none
    gateway("GET /v1/provider-keys" => [200, { vendors: [] }])
    status, out, = run_cli("keys", "list")

    assert_equal 0, status
    assert_equal "no provider key brought: every call runs on the keys of the box\n", out
  end

  def test_a_verb_keys_does_not_have_prints_the_usage_and_knocks_at_no_door
    gateway("GET /v1/provider-keys" => [200, { vendors: [] }])
    status, _out, err = run_cli("keys", "drop", "elevenlabs")

    assert_equal 2, status
    assert_includes err, "keys has no verb called drop"
    assert_includes err, "add VENDOR"
    assert_empty @gateway.asked
  end

  def test_with_no_key_every_verb_says_so_before_it_opens_anything
    ENV.delete("PINECALL_API_KEY")
    status, _out, err = run_cli("keys", "list")

    assert_equal 2, status
    assert_includes err, "no key for"
  end
end
