# frozen_string_literal: true

require "test_helper"

# The three declarations that name something outside the class — a file, a base, a policy — and
# what each becomes in `agent.configure`. Each is refused at load, with the path or the field.
class ConfigTest < Minitest::Test
  # Un agente que sabe, responde y recuerda.
  class Clinica < Pinecall::Agent
    knowledge "./knowledge/clinica.md"
    docs "clinica-norte"
    memory remember: ["alergias", :preferencias], forget: ["pagos"]
  end

  def test_knowledge_travels_as_the_path_written_and_the_text_of_the_file_beside_the_class
    sent = Clinica.wire_config[:knowledge]

    assert_equal "./knowledge/clinica.md", sent[:path]
    assert_includes sent[:text], "# Clínica Norte"
    assert_equal File.expand_path("knowledge/clinica.md", __dir__), Clinica.knowledge_file
  end

  def test_a_knowledge_file_that_is_not_there_is_refused_at_load_with_the_path
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { knowledge "./knowledge/nadie.md" }
    end

    assert_includes refused.message, "knowledge names a file beside the class"
    assert_includes refused.message, "knowledge/nadie.md"
  end

  def test_docs_by_name_is_the_base_and_nothing_else
    assert_equal({ base: "clinica-norte" }, Clinica.wire_config[:docs])
  end

  def test_docs_with_keywords_carries_mode_k_and_min_score_as_the_wire_names_them
    shop = Class.new(Pinecall::Agent) { docs base: "tienda", mode: :retrieved, k: 4, min_score: 0.5 }

    assert_equal({ base: "tienda", mode: "retrieved", k: 4, min_score: 0.5 }, shop.wire_config[:docs])
  end

  def test_a_glob_or_a_path_is_not_a_base_and_the_refusal_says_the_command_that_makes_one
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { docs "./knowledge/docs/**/*.md" }
    end

    assert_equal "docs name the base they were pushed to: " \
                 "run `pinecall knowledge push ./knowledge/docs --base agent`", refused.message
  end

  def test_a_docs_field_the_wire_does_not_have_is_refused_by_name
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { docs base: "tienda", top: 3 }
    end

    assert_includes refused.message, "DocsConfig has no field called top"
  end

  def test_memory_carries_remember_and_forget_as_words
    assert_equal({ remember: %w[alergias preferencias], forget: ["pagos"] }, Clinica.wire_config[:memory])
  end

  def test_a_memory_policy_the_wire_does_not_have_is_refused_by_name
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { memory keep: ["todo"] }
    end

    assert_includes refused.message, "MemoryConfig has no field called keep"
  end

  def test_a_class_that_declares_none_of_the_three_sends_none_of_them
    sent = Class.new(Pinecall::Agent).wire_config

    refute sent.key?(:knowledge)
    refute sent.key?(:docs)
    refute sent.key?(:memory)
  end

  def test_the_whole_configuration_is_what_the_wire_declares
    Pinecall::Protocol::Validate.call!("AgentConfig", Clinica.wire_config(tools: []), where: "configure")
  end

  def test_a_subclass_reads_its_parent_s_file_and_may_name_its_own_base
    child = Class.new(Clinica) { docs "clinica-sur" }

    assert_equal Clinica.knowledge_file, child.knowledge_file
    assert_equal "clinica-sur", child.wire_config[:docs][:base]
    assert_equal "clinica-norte", Clinica.docs[:base]
  end
end

# `greeting`: how the agent opens a call. Exactly one of the two verbs the wire already has —
# the words themselves, or what the model reads before it finds its own.
class GreetingDeclarationTest < Minitest::Test
  def test_a_class_that_says_nothing_opens_with_nothing
    klass = Class.new(Pinecall::Agent) { def self.name = "Muda" }

    refute_includes klass.wire_config(tools: []), :greeting
  end

  def test_the_bare_string_form_is_the_words_said_as_written
    klass = Class.new(Pinecall::Agent) do
      def self.name = "Saluda"
      greeting "Clínica Norte, buenos días."
    end

    assert_equal({ say: "Clínica Norte, buenos días." }, klass.wire_config(tools: [])[:greeting])
  end

  def test_an_improvised_opening_travels_as_the_instruction_the_caller_never_hears
    said = "saluda, di que eres la recepción y pregunta en qué puedes ayudar"
    klass = Class.new(Pinecall::Agent) do
      def self.name = "Improvisa"
      greeting reply: said
    end

    assert_equal({ reply: said }, klass.wire_config(tools: [])[:greeting])
  end

  def test_a_notice_nobody_may_talk_over_carries_the_flag
    klass = Class.new(Pinecall::Agent) do
      def self.name = "Aviso"
      greeting say: "Esta llamada será grabada.", allow_interruptions: false
    end

    said = klass.wire_config(tools: [])[:greeting]
    assert_equal({ say: "Esta llamada será grabada.", allow_interruptions: false }, said)
  end

  def test_both_verbs_at_once_is_a_class_that_has_not_decided
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) do
        def self.name = "LasDos"
        greeting say: "Buenos días.", reply: "saluda"
      end
    end

    assert_includes refused.message, "Both were declared — pick one."
  end

  def test_neither_verb_is_refused_with_the_same_sentence
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) do
        def self.name = "Ninguna"
        greeting allow_interruptions: false
      end
    end

    assert_includes refused.message, "Neither was — pick one."
  end
end

# `hangup`: whether the model may end the call itself. The tool is livekit's own; declaring this is
# what puts it in front of the model, and a class that says nothing cannot hang up at all.
class HangupDeclarationTest < Minitest::Test
  def test_a_class_that_says_nothing_declares_no_hangup
    klass = Class.new(Pinecall::Agent) { def self.name = "Muda" }

    refute_includes klass.wire_config(tools: []), :hangup
  end

  def test_the_tenants_own_words_travel_as_they_were_written
    said = "cuando el paciente se despide"
    klass = Class.new(Pinecall::Agent) do
      def self.name = "Cuelga"
      hangup when: said
    end

    assert_equal({ when: said }, klass.wire_config(tools: [])[:hangup])
  end

  def test_hangup_with_no_words_is_still_a_declaration
    klass = Class.new(Pinecall::Agent) do
      def self.name = "Escueta"
      hangup
    end

    assert_equal({ when: "" }, klass.wire_config(tools: [])[:hangup])
  end
end
