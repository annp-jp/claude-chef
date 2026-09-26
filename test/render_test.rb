require 'minitest/autorun'
require 'json'
require_relative '../scripts/playwright/render'

class RenderTest < Minitest::Test
  def test_embeds_args_into_template
    path = render('search', '["豚こま","牛乳"]')
    source = ROOT.join(path).read(encoding: 'UTF-8')

    assert_equal '.playwright-mcp/search.js', path
    assert_includes source, 'const words = ["豚こま","牛乳"];'
    refute_includes source, PLACEHOLDER
  end

  def test_add_items_template
    source = ROOT.join(render('add_items', '[["0000000126896",2]]')).read(encoding: 'UTF-8')

    assert_includes source, 'const items = [["0000000126896",2]];'
  end

  def test_rejects_unknown_template_and_empty_args
    assert_raises(ArgumentError) { render('nope', '["x"]') }
    assert_raises(ArgumentError) { render('search', '[]') }
    assert_raises(ArgumentError) { render('search', '{"a":1}') }
  end
end
