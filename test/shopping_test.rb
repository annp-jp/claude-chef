require 'minitest/autorun'
require_relative '../scripts/shopping'

class ShoppingTest < Minitest::Test
  def cats
    {
      '肉魚' => [{ 'name' => 'ツナ油漬缶', 'amount' => '1缶', 'dishes' => [] }, { 'name' => '豚肉', 'amount' => '', 'dishes' => [] }],
      '野菜' => [{ 'name' => 'たけのこ', 'amount' => '', 'dishes' => [] }, { 'name' => 'にんにくの薄切り', 'amount' => '', 'dishes' => [] }],
      '調味料' => [{ 'name' => '味噌', 'amount' => '', 'dishes' => [] }],
      'その他' => [{ 'name' => '水', 'amount' => '2カップ', 'dishes' => [] }]
    }
  end

  def apply(**opts)
    apply_preferences(cats, pantry_categories: %w[調味料], pantry_items: [], item_notes: {}, **opts)
  end

  def item(result, name)
    result.values.flatten.find { |i| i['name'] == name }
  end

  def test_never_buy_items_are_dropped_and_empty_category_removed
    result = apply

    assert_nil item(result, '水')
    refute result.key?('その他')
  end

  def test_pantry_category_marks_every_item
    assert item(apply, '味噌')['pantry']
    refute item(apply, '豚肉')['pantry']
  end

  def test_pantry_items_match_by_substring
    result = apply(pantry_items: %w[ツナ にんにく])

    assert item(result, 'ツナ油漬缶')['pantry']
    assert item(result, 'にんにくの薄切り')['pantry']
    refute item(result, 'たけのこ')['pantry']
  end

  def test_item_notes_attach_by_substring
    result = apply(item_notes: { 'たけのこ' => '水煮を選ぶ' })

    assert_equal '水煮を選ぶ', item(result, 'たけのこ')['note']
    refute item(result, '豚肉').key?('note')
  end

  def test_original_items_are_not_mutated
    original = cats
    apply_preferences(original, pantry_categories: %w[調味料], pantry_items: [], item_notes: {})

    refute original['調味料'].first.key?('pantry')
  end
end
