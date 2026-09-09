# frozen_string_literal: true

require "test_helper"

# The markers a template writes and never resolves: the runtime reads the line, so the payload's
# keys are the runtime's and are pinned here, snake_case, exactly as the tag was called.
class ViewTest < Minitest::Test
  def rendered(template)
    Pinecall::View.inline(template).render(Pinecall::Reading.new({}))
  end

  def test_the_memory_tag_writes_kinds_and_limit_as_the_runtime_reads_them
    assert_equal %(<!-- memory: {"kinds":["preference","health"],"limit":6} -->),
                 rendered("<%= memory kinds: %w[preference health], limit: 6 %>").text
  end

  def test_the_retrieved_tag_writes_k_and_min_score_in_snake_case
    assert_equal %(<!-- retrieved: {"k":4,"min_score":0.02} -->),
                 rendered("<%= retrieved k: 4, min_score: 0.02 %>").text
  end

  def test_the_knowledge_tag_writes_the_bare_path
    assert_equal "<!-- knowledge: ./knowledge/clinica.md -->", rendered(%(<%= knowledge "./knowledge/clinica.md" %>)).text
  end

  def test_a_tag_with_nothing_to_say_writes_an_empty_payload
    assert_equal "<!-- memory: {} -->", rendered("<%= memory %>").text
    assert_equal "<!-- retrieved: {} -->", rendered("<%= retrieved k: nil %>").text
  end

  def test_a_render_prop_rides_as_fill_beside_the_other_keys_and_stays_behind
    render = rendered(%(<%= memory(kinds: %w[preference]) { |facts| facts.size } %>))

    assert_equal %(<!-- memory: {"kinds":["preference"],"fill":"fill-1"} -->), render.text
    assert_equal "2", render.fills.fill("fill-1", %w[a b])
  end

  def test_a_marker_of_the_tenant_s_own_takes_any_name_and_any_payload
    assert_equal %(<!-- precio: {"sku":4} -->), rendered(%(<%= marker "precio", { sku: 4 } %>)).text
  end
end
