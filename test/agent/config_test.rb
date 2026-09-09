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
