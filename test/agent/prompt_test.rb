# frozen_string_literal: true

require "test_helper"

# The prompt: named blocks in two regions, in one order, and only the dynamic ones may move.
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

  # Una tienda con un bloque cacheado y otro que sigue al estado.
  class WithBlocks < Pinecall::Agent
    state :slots, []
    prompt static: %i[faq], dynamic: %i[availability]

    view template: <<~ERB
      <%= memory(kinds: %w[preference]) { |facts| facts.join(", ") } %>
    ERB
  end

  def setup
    @agent = Clinica.new.seal
  end

  def rendered = Pinecall.render(@agent)

  def test_the_default_layout_is_the_framework_s_four_blocks_in_send_order
    assert_equal %w[identity knowledge tools view], rendered.blocks.map(&:name)
    assert_equal %w[static static static dynamic], rendered.blocks.map(&:region)
  end

  def test_the_static_blocks_joined_are_one_text_the_docstring_the_words_the_knowledge_the_tools
    words = Pinecall::Lang.words_for(Clinica)
    whole = [
      @agent.doc,
      "<rules>\n#{words[:rules]}\n</rules>",
      "<protocols>\n#{words[:protocols]}\n</protocols>",
      "<!-- knowledge: ./knowledge/clinica.md -->",
      "<tools>\n- find_patient: Busca al paciente.\n</tools>"
    ].join("\n\n")

    assert_equal whole, rendered.instructions
  end

  def test_the_identity_block_is_the_docstring_and_the_framework_s_words
    text = rendered[:identity]

    assert_includes text, "Eres la recepción de Clínica Norte."
    assert_includes text, "<rules>"
    assert_includes text, "<protocols>"
    refute_includes text, "find_patient"
  end

  def test_the_knowledge_and_tools_blocks_are_each_one_thing
    assert_equal "<!-- knowledge: ./knowledge/clinica.md -->", rendered[:knowledge]
    assert_includes rendered[:tools], "- find_patient: Busca al paciente."
  end

  def test_the_static_blocks_do_not_move_when_the_state_does
    before = rendered.static.map(&:text)
    @agent.run_tool(:find_patient, name: "Marta")

    assert_equal before, rendered.static.map(&:text)
  end

  def test_the_view_block_is_the_view_and_it_moves
    assert_includes rendered[:view], "Saluda y pide nombre y teléfono."

    @agent.run_tool(:find_patient, name: "Marta")

    assert_includes rendered[:view], "Hablas con Marta."
    refute_includes rendered[:view], "Saluda"
  end

  def test_a_class_configured_with_memory_gets_the_marker_even_if_its_view_never_asks
    assert_includes rendered[:view], "<!-- memory: {} -->"
    assert_includes rendered[:view], %(<!-- retrieved: {"min_score":0.4} -->)
  end

  def test_the_view_reads_what_surrounds_the_call_and_not_only_the_state
    assert_includes Pinecall.render(@agent, resumed: true)[:view], "Se cortó su llamada anterior."
  end

  def test_a_template_is_read_by_a_person_and_the_ragged_edges_come_off_for_the_model
    Pinecall::Agent::Author.with("the test") { @agent.slots = ["martes 10:00", "martes 11:00"] }

    assert_includes rendered[:view], "## Horas libres\n\nmartes 10:00\nmartes 11:00"
    refute_match(/\n{3,}/, rendered[:view])
    assert_equal rendered[:view].strip, rendered[:view]
  end

  def test_the_history_carries_the_summaries_a_collapse_left
    @agent.run_tool(:find_patient, name: "Marta")
    @agent.collapse("La paciente ya está identificada.")

    assert_includes rendered.history, "La paciente ya está identificada."
    assert_includes rendered.history, "<!-- collapsed:"
  end

  def test_a_render_prop_stays_behind_under_the_id_its_marker_carries
    shaped = Class.new(Pinecall::Agent) do
      doc "Un agente con memoria."
      view template: <<~'ERB'
        <%= memory(kinds: %w[preference]) { |facts| "Recuerda: #{facts.join(", ")}" } %>
      ERB
    end
    prompt = Pinecall.render(shaped.new.seal)
    id = JSON.parse(prompt[:view][/<!-- memory: (.*) -->/, 1])["fill"]

    assert_equal "fill-1", id
    assert_equal "Recuerda: le gusta por la mañana", prompt.fills.fill(id, ["le gusta por la mañana"])
  end

  def test_two_renders_never_share_the_registry_one_of_them_wrote
    first = Pinecall.render(@agent)
    second = Pinecall.render(@agent)

    refute_same first.fills, second.fills
  end

  def test_the_page_a_person_reads_names_every_block_and_the_history_between_the_regions
    page = Pinecall.show_prompt(@agent)

    assert_equal ["── identity (static) ──", "── knowledge (static) ──", "── tools (static) ──",
                  "── history ──", "── view (dynamic) ──"],
                 page.lines.map(&:chomp).select { |line| line.start_with?("── ") }
  end

  def test_the_framework_speaks_the_language_the_class_named
    english = Class.new(Pinecall::Agent) do
      doc "A shop."
      language :en
    end

    assert_includes Pinecall.render(english.new.seal)[:identity], "One question per turn"
  end

  # ── the blocks a class declares ───────────────────────────────────────────

  def test_a_class_s_own_blocks_go_after_the_framework_s_and_the_view_goes_last
    assert_equal %w[identity knowledge tools faq availability view],
                 Pinecall.render(WithBlocks.new.seal).blocks.map(&:name)
    assert_equal WithBlocks.layout, WithBlocks.wire_config[:prompt]
  end

  def test_a_declared_block_is_its_template_beside_the_class_under_the_slug
    agent = WithBlocks.new.seal
    Pinecall::Agent::Author.with("the test") { agent.slots = ["martes 10:00"] }
    prompt = Pinecall.render(agent)

    assert_includes prompt[:faq], "¿Aparcamiento?"
    assert_equal "## Horas libres\n\nmartes 10:00", prompt[:availability]
  end

  def test_the_blocks_of_one_prompt_share_one_registry_so_a_fill_id_is_never_used_twice
    prompt = Pinecall.render(WithBlocks.new.seal)

    assert prompt.fills.has?("fill-1")
    refute prompt.fills.has?("fill-2")
  end

  def test_a_static_block_that_reads_the_state_is_refused_by_template_and_field
    refused = assert_raises(Pinecall::StaticBlockReadsState) { Pinecall.render(ReadsState.new.seal) }

    assert_equal "a static block cannot read the state: faq.erb reads slots", refused.message
  end

  def test_a_block_named_like_one_of_the_framework_s_is_refused_at_declaration
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { prompt static: %i[identity] }
    end

    assert_includes refused.message, "identity is one of the framework's own blocks"
  end

  def test_a_block_name_the_wire_would_not_take_is_refused_at_declaration
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { prompt dynamic: %i[Availability] }
    end

    assert_includes refused.message, "Availability"
  end

  def test_a_block_with_no_template_beside_the_class_is_refused_by_path
    PromptTest.const_set(:NoTemplate, Class.new(Pinecall::Agent))
    refused = assert_raises(Pinecall::DeclarationRefused) do
      NoTemplate.class_eval { prompt static: %i[faq] }
    end

    assert_includes refused.message, "faq has no template: write"
    assert_includes refused.message, "views/no-template/faq.erb"
  ensure
    PromptTest.send(:remove_const, :NoTemplate)
  end

  def test_a_block_declared_twice_is_refused_and_a_parent_s_declaration_counts
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(WithBlocks) { prompt dynamic: %i[faq] }
    end

    assert_includes refused.message, "declares the block faq twice"
  end

  def test_a_class_with_no_file_has_nowhere_to_keep_a_block_and_is_told_so
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Class.new(Pinecall::Agent) { prompt static: %i[faq] }
    end

    assert_includes refused.message, "no class file"
  end

  # Un hecho se archiva con la palabra con la que la clase dijo que lo recuerda, así que esas son
  # las únicas que una vista puede pedirle a la memoria por su nombre. Una llamada real archivó
  # `cómo prefiere que le llamen` mientras la vista pedía `preference`: el recuerdo volvió vacío
  # para siempre, con toda la pinta de funcionar (2026-09-10). El marcador se escribe al renderizar,
  # y ahí es donde se rechaza.
  def test_a_memory_kind_the_class_never_said_it_remembers_is_refused_by_name
    refused = assert_raises(Pinecall::DeclarationRefused) do
      Pinecall.render(remembering(%(<%= memory kinds: %w[preference] %>)))
    end

    assert_equal 'memory kinds: "preference" is not one of the words this class remembers ' \
                 "(cómo prefiere que le llamen, alergias)", refused.message
  end

  def test_a_memory_kind_the_class_does_remember_is_written_into_the_marker
    prompt = Pinecall.render(remembering(%(<%= memory kinds: %w[alergias], limit: 3 %>)))

    assert_equal %(<!-- memory: {"kinds":["alergias"],"limit":3} -->), prompt[:view]
  end

  def test_a_class_that_says_nothing_about_what_it_remembers_takes_any_kind
    agent = Class.new(Pinecall::Agent) do
      doc "Agenda que recuerda lo que al modelo le parezca."
      view template: %(<%= memory kinds: %w[preference] %>)
    end.new.seal

    assert_equal %(<!-- memory: {"kinds":["preference"]} -->), Pinecall.render(agent)[:view]
  end

  # Una agenda que dice con qué palabras recuerda, y una vista que le pide algo a la memoria.
  def remembering(template)
    Class.new(Pinecall::Agent) do
      doc "Agenda que dice con qué palabras recuerda."
      memory remember: ["cómo prefiere que le llamen", "alergias"], forget: ["pagos"]
      view template: template
    end.new.seal
  end

  # Un bloque estático que pregunta por el estado: lo que la ley refusa.
  class ReadsState < Pinecall::Agent
    state :slots, []
    prompt static: %i[faq]
  end
end
