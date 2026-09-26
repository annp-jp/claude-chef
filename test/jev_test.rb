require 'minitest/autorun'
require_relative '../scripts/jev'
require_relative '../scripts/life_netsuper'

class JevTest < Minitest::Test
  def products
    @products ||= LifeNetsuper.decode_products(
      File.binread(File.join(__dir__, 'fixtures', 'life_netsuper', 'search_butakoma.bin'))
    )
  end

  def test_request_offers_only_in_stock_products_plus_none
    options = Jev.build_request(item: '豚こま', products: products).dig('questions', 'product', 'criteria')

    assert_equal 8, options.size # 在庫あり 7 件 + none
    assert_includes options, Jev::NONE
    refute(options.values.any? { |d| d.start_with?('米国産') })
  end

  def test_request_state_carries_item_context
    state = Jev.build_request(item: '豚こま', amount: '300g', dishes: ['生姜焼き'], products: products)['state']

    assert_equal '豚こま', state['買う材料']
    assert_equal '300g', state['必要量']
    assert_equal ['生姜焼き'], state['使う料理']
    assert_includes state['候補'].first, '0000000126896: 北海道産あまに豚こま切れ / 190g / 税込421円'
  end

  def test_request_omits_missing_amount
    refute Jev.build_request(item: '豚こま', products: products)['state'].key?('必要量')
  end

  def test_request_without_candidates_raises
    assert_raises(ArgumentError) { Jev.build_request(item: '豚こま', products: products.select { |p| p['out_of_stock'] }) }
  end

  def answer(choice, probs)
    { 'type' => 'choice', 'choice' => choice, 'probabilities' => probs, 'confidence' => 0.7 }
  end

  def test_decide_auto_when_probability_meets_threshold
    result = Jev.decide(answer('A', 'A' => 0.85, 'B' => 0.15, 'none' => 0.0))

    assert_equal 'auto', result['action']
    assert_equal 'A', result['product_id']
    assert_equal %w[A B none], result['ranked'].map { |r| r['product_id'] }
  end

  def test_decide_ask_when_below_threshold
    assert_equal 'ask', Jev.decide(answer('A', 'A' => 0.6, 'B' => 0.4), threshold: 0.8)['action']
  end

  def test_decide_not_found_on_none
    result = Jev.decide(answer('none', 'A' => 0.1, 'none' => 0.9))

    assert_equal 'not_found', result['action']
    assert_nil result['product_id']
  end
end
