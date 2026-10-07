# frozen_string_literal: true

require "test_helper"

# Class config, what `agent.configure` sends, and refusal of world settings at load.
class ConfigTest < Minitest::Test
  # Un agente que sólo dice su contrato.
  class Clinica < Pinecall::Agent
    phone "+34910000000"
    web true
  end

  def test_the_declaration_is_the_contract_and_nothing_of_the_environment
    sent = Clinica.wire_config(tools: [])

    assert_equal %i[prompt tools], sent.keys
  end

  def test_a_class_that_names_its_language_is_refused_with_the_verb_that_sets_it
    error = assert_raises(Pinecall::DeclarationRefused) { Class.new(Pinecall::Agent) { language :es } }

    assert_equal "`language` is the world's now, not the class's: pinecall agent set --language <tag> — remove it from the class",
                 error.message
  end

  def test_the_doors_are_accepted_and_read_by_nobody
    assert_equal "+34910000000", Clinica.phone
    refute Clinica.wire_config(tools: []).key?(:routes)
    refute Clinica.respond_to?(:routes)
  end

  def test_the_whole_configuration_is_what_the_wire_declares
    Pinecall::Wire::Validate.call!("AgentConfig", Clinica.wire_config(tools: []), where: "configure")
  end

  def test_a_field_of_the_world_s_is_refused_at_load_with_the_verb_that_sets_it
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { voice "carolina" }
    end

    assert_equal "`voice` is the world's now, not the class's: pinecall agent set --voice <name> " \
                 "— remove it from the class", refused.message
  end

  def test_every_field_of_the_world_s_is_refused_whatever_it_was_written_with
    written = {
      voice: ["carolina"], llm: ["haiku"], stt: ["deepgram"], language: [:es], greeting: ["Buenos días."],
      hangup: [], says: [{ DKV: "de ka uve" }], hears: [["Clínica Norte"]], record: [true],
      knowledge: ["./knowledge/clinica.md"], docs: ["clinica-norte"], memory: [{ remember: ["alergias"] }]
    }

    assert_equal Pinecall::Agent::Config::THE_WORLDS.keys.sort, written.keys.sort
    written.each do |field, args|
      refused = assert_raises(Pinecall::DeclarationRefused) do
        Class.new(Pinecall::Agent) do
          args.last.is_a?(Hash) ? public_send(field, **args.last) : public_send(field, *args)
        end
      end

      assert_equal Pinecall::Agent::Config.moved_to_the_world(field), refused.message
      assert_includes refused.message, Pinecall::Agent::Config::THE_WORLDS[field]
    end
  end

  def test_the_refusal_names_the_verb_even_for_the_form_the_class_used_to_take
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { greeting reply: "saluda" }
    end

    assert_includes refused.message, "pinecall agent set --greeting '…' (or --reply '…')"
  end
end
