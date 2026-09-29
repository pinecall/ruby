# frozen_string_literal: true

require "test_helper"

# A value checked against a named shape: what the runtime writes reads, what it never writes does not.
class ValidateTest < Minitest::Test
  def test_an_optional_field_the_runtime_wrote_as_null_reads_as_absent
    turn = { text: "hola", speech_id: "sp_1", item_id: "it_1", metrics: {}, language: nil }
    assert_equal turn, Pinecall::Wire::Validate.call!("UserTurnEnded", turn, where: "turn.user")
  end

  def test_a_tool_that_answered_nothing_is_a_result_with_no_output
    result = { call_id: "tc_1", name: "find_patient", output: nil }
    assert_equal result, Pinecall::Wire::Validate.call!("ToolResult", result, where: "tool.result")
  end

  def test_a_required_field_still_has_to_be_there
    error = assert_raises(Pinecall::Wire::WireError) do
      Pinecall::Wire::Validate.call!("ToolResult", { name: "find_patient" }, where: "tool.result")
    end
    assert_match "requires it", error.message
  end
end
