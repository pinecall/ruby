# frozen_string_literal: true

require "test_helper"

# The bridge, against a gateway that is not there: what a mounted agent sends, and when.
class BridgeTest < Minitest::Test
  # Eres la recepción de Clínica Norte.
  class Clinica < Pinecall::Agent
    web true
    llm "haiku"
    language :es

    stage :identify, :book
    state :patient
    state :slots, []
    accepts "agenda.changed", from: %i[app]

    view template: <<~ERB
      <% if stage == :identify -%>
      Pide nombre y teléfono.
      <% end -%>
      <% if patient -%>
      Hablas con <%= patient %>.
      <% end -%>
      <% if slots.any? -%>
      Han cambiado las horas.
      <% end -%>
    ERB

    def on_call(call)
      self.patient = "Marta Ruiz" if call.from == "+34600123456"
      self.stage = :book if patient
    end

    def on_event(name, data, _meta)
      self.slots = data[:slots] if name == "agenda.changed"
    end

    def on_end(_call) = log("goodbye", { patient: })

    # Busca al paciente por su nombre.
    tool stage: :identify
    def find_patient(name:)
      self.patient = name
      self.stage = :book
      { name: }
    end

    # Cuelga.
    tool
    def stop = call.hangup("done")
  end

  def setup
    @gateway = Pinecall::Testing::Gateway.new
    @mounted = Pinecall.mount(Clinica, client: @gateway)
  end

  def test_the_declaration_is_what_the_class_says_about_itself
    assert_equal "clinica", @mounted.slug
    assert_equal [{ channel: "web", number: nil }], @mounted.options[:routes]
    assert_equal({ provider: "anthropic", model: "claude-haiku-4-5-20251001" }, @mounted.options[:llm])
    assert_equal %w[find_patient stop], @mounted.options[:tools].map { |spec| spec[:name] }
    assert_equal [{ name: "agenda.changed", from: %w[app] }], @mounted.options[:events]
  end

  def test_a_call_opens_with_one_whole_prompt_and_not_one_send_per_field
    call = @gateway.call_started(from: "+34600123456")
    opening = call.commands.map(&:type)

    assert_equal 1, opening.count("state.set")
    assert_includes call.instructions, "Eres la recepción de Clínica Norte."
    assert_includes call.prompt, "Hablas con Marta Ruiz."
  end

  def test_the_hook_writes_before_the_first_render_so_the_model_never_reads_a_state_it_was_not_in
    call = @gateway.call_started(from: "+34600123456")

    refute_includes call.prompt, "Pide nombre y teléfono."
    assert_equal "book", call.state[:stage].to_s
  end

  def test_a_tool_the_model_calls_runs_here_and_answers_with_one_result
    call = @gateway.call_started(from: "+34999000111")
    result = call.tool("find_patient", name: "Ana Sanz")

    assert_equal({ name: "Ana Sanz" }, result[:output])
    assert_includes call.prompt, "Hablas con Ana Sanz."
  end

  def test_a_tool_that_refuses_answers_the_model_instead_of_leaving_the_turn_waiting
    call = @gateway.call_started(from: "+34999000111")
    result = call.tool("find_patient")

    assert_includes result[:error], "name"
    assert_nil result[:output]
  end

  def test_a_tool_this_agent_does_not_declare_is_told_so_by_name
    call = @gateway.call_started
    result = call.tool("sing", song: "la traviata")

    assert_includes result[:error], "sing"
  end

  def test_the_cached_prefix_is_sent_once_and_never_again
    call = @gateway.call_started(from: "+34999000111")
    call.tool("find_patient", name: "Ana Sanz")
    static = call.commands.select { |sent| sent.type == "prompt.set" && sent.data[:region] == "static" }

    assert_equal 1, static.size
  end

  def test_a_tool_that_moves_nothing_sends_no_prompt_at_all
    call = @gateway.call_started(from: "+34600123456")
    before = call.commands.count { |sent| sent.type == "prompt.set" }
    call.tool("find_patient", name: "Marta Ruiz")

    assert_equal before, call.commands.count { |sent| sent.type == "prompt.set" }
  end

  def test_the_visible_tools_follow_the_state
    call = @gateway.call_started(from: "+34999000111")

    assert_equal %w[find_patient stop], call.tools

    call.tool("find_patient", name: "Ana Sanz")

    assert_equal %w[stop], call.tools
  end

  def test_a_declared_fact_reaches_the_hook_and_moves_the_prompt
    call = @gateway.call_started(from: "+34600123456")
    call.fact("agenda.changed", { slots: ["martes 10:00"] })

    assert_includes call.prompt, "Han cambiado las horas."
  end

  def test_a_fact_from_somebody_the_class_did_not_declare_never_reaches_the_hook
    call = @gateway.call_started(from: "+34600123456")
    _out, said = capture_subprocess_io do
      call.fact("agenda.changed", { slots: ["martes 10:00"] }, from: "participant")
    end

    refute_includes call.prompt.to_s, "Han cambiado las horas."
    assert_includes said, "agenda.changed from participant" if said && !said.empty?
  end

  def test_a_state_change_caused_by_a_fact_says_so_in_the_log_beside_it
    call = @gateway.call_started(from: "+34600123456")
    call.fact("agenda.changed", { slots: ["martes 10:00"] })
    cause = call.commands.find { |sent| sent.type == "call.log" && sent.data[:name] == "state.cause" }

    assert_equal "slots", cause.data[:data][:field]
    assert_equal "agenda.changed", cause.data[:data][:event]
  end

  def test_a_verb_the_class_calls_on_its_call_is_one_command
    call = @gateway.call_started
    call.tool("stop")

    assert_equal "done", call.last("call.hangup")[:reason]
  end

  def test_the_end_hook_runs_and_the_instance_is_let_go
    call = @gateway.call_started(from: "+34600123456")
    call.ended

    assert_equal "goodbye", call.last("call.log")[:name]
    assert_nil @mounted.serving(call.id)
  end

  def test_two_calls_at_once_never_share_a_state
    first = @gateway.call_started(id: "CA_first", from: "+34999000111")
    second = @gateway.call_started(id: "CA_second", from: "+34600123456")
    first.tool("find_patient", name: "Ana Sanz")

    assert_equal "Ana Sanz", @mounted.serving("CA_first").patient
    assert_equal "Marta Ruiz", @mounted.serving("CA_second").patient
  end
end
