# frozen_string_literal: true

require "test_helper"

# The prompt: three regions, in one order, and only the last of them may move during a call.
class PromptTest < Minitest::Test
  # Eres la recepción de Clínica Norte.
  # Todo lo que dices se lee en voz alta.
  class Clinica < Pinecall::Agent
    language :es
    knowledge "./knowledge/clinica.md"
    memory remember: ["cómo prefiere que le llamen"]

    stage :identify, :book
    state :patient
    state :slots, []

    view template: <<~ERB
      <%= retrieved min_score: 0.4 %>

      <% if stage == :identify -%>
      Saluda y pide nombre y teléfono.
      <% end -%>
      <% if patient -%>
      Hablas con <%= patient %>.
      <% end -%>

      <% if slots.any? -%>
      ## Horas libres

      <% slots.each do |slot| -%>
      <%= slot %>
      <% end -%>
      <% end -%>

      <% if resumed -%>
      Se cortó su llamada anterior.
      <% end -%>
    ERB

    # Busca al paciente.
    tool stage: :identify
    def find_patient(name:)
      self.patient = name
      self.stage = :book
    end
  end

  def setup
    @agent = Clinica.new.seal
  end

  def regions = Pinecall.render(@agent)

  def test_the_static_region_is_the_docstring_the_knowledge_the_words_and_the_tools
    text = regions.static

    assert_includes text, "Eres la recepción de Clínica Norte."
    assert_includes text, "<!-- knowledge: ./knowledge/clinica.md -->"
    assert_includes text, "<rules>"
    assert_includes text, "- find_patient: Busca al paciente."
  end

  def test_the_static_region_does_not_move_when_the_state_does
    before = regions.static
    @agent.run_tool(:find_patient, name: "Marta")

    assert_equal before, regions.static
  end

  def test_the_dynamic_region_is_the_view_and_it_moves
    assert_includes regions.dynamic, "Saluda y pide nombre y teléfono."

    @agent.run_tool(:find_patient, name: "Marta")

    assert_includes regions.dynamic, "Hablas con Marta."
    refute_includes regions.dynamic, "Saluda"
  end

  def test_a_class_configured_with_memory_gets_the_marker_even_if_its_view_never_asks
    assert_includes regions.dynamic, "<!-- memory: {} -->"
    assert_includes regions.dynamic, %(<!-- retrieved: {"min_score":0.4} -->)
  end

  def test_the_view_reads_what_surrounds_the_call_and_not_only_the_state
    assert_includes Pinecall.render(@agent, resumed: true).dynamic, "Se cortó su llamada anterior."
  end

  def test_a_template_is_read_by_a_person_and_the_ragged_edges_come_off_for_the_model
    Pinecall::Agent::Author.with("the test") { @agent.slots = ["martes 10:00", "martes 11:00"] }

    assert_includes regions.dynamic, "## Horas libres\n\nmartes 10:00\nmartes 11:00"
    refute_match(/\n{3,}/, regions.dynamic)
    assert_equal regions.dynamic.strip, regions.dynamic
  end

  def test_the_history_region_carries_the_summaries_a_collapse_left
    @agent.run_tool(:find_patient, name: "Marta")
    @agent.collapse("La paciente ya está identificada.")

    assert_includes regions.history, "La paciente ya está identificada."
    assert_includes regions.history, "<!-- collapsed:"
  end

  def test_a_render_prop_stays_behind_under_the_id_its_marker_carries
    shaped = Class.new(Pinecall::Agent) do
      doc "Un agente con memoria."
      view template: <<~'ERB'
        <%= memory(kinds: %w[preference]) { |facts| "Recuerda: #{facts.join(", ")}" } %>
      ERB
    end
    rendered = Pinecall.render(shaped.new.seal)
    id = JSON.parse(rendered.dynamic[/<!-- memory: (.*) -->/, 1])["fill"]

    assert_equal "fill-1", id
    assert_equal "Recuerda: le gusta por la mañana", rendered.fills.fill(id, ["le gusta por la mañana"])
  end

  def test_two_renders_never_share_the_registry_one_of_them_wrote
    first = Pinecall.render(@agent)
    second = Pinecall.render(@agent)

    refute_same first.fills, second.fills
  end

  def test_the_page_a_person_reads_names_its_three_regions_in_order
    page = Pinecall.show_prompt(@agent)

    assert_equal ["── static ──", "── history ──", "── dynamic ──"],
                 page.lines.map(&:chomp).select { |line| line.start_with?("── ") }
  end

  def test_the_framework_speaks_the_language_the_class_named
    english = Class.new(Pinecall::Agent) do
      doc "A shop."
      language :en
    end

    assert_includes Pinecall.render(english.new.seal).static, "One question per turn"
  end
end
