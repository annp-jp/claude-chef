require 'minitest/autorun'
require_relative '../scripts/life_netsuper'

class LifeNetsuperTest < Minitest::Test
  FIXTURES = File.join(__dir__, 'fixtures', 'life_netsuper')

  def fixture(name)
    File.binread(File.join(FIXTURES, name))
  end

  def test_search_returns_all_products_with_stock_flags
    products = LifeNetsuper.decode_products(fixture('search_butakoma.bin'))

    assert_equal 9, products.size
    assert_equal %w[米国産豚肉こま切れ] * 2, products.select { |p| p['out_of_stock'] }.map { |p| p['name'] }
  end

  def test_search_product_fields
    first = LifeNetsuper.decode_products(fixture('search_butakoma.bin')).first

    assert_equal '0000000126896', first['product_id']
    assert_equal '北海道産あまに豚こま切れ', first['name']
    assert_equal '190g', first['size']
    assert_equal 390, first['price']
    assert_equal 421, first['price_with_tax']
    assert_equal 179, first['price_per_100g']
    assert_equal ['おすすめ'], first['badges']
  end

  def test_gram_sale_range_matches_product_page
    gram = LifeNetsuper.decode_products(fixture('product_detail.bin')).first['gram_sale']

    assert_equal [190, 161, 218], gram.values_at('estimated_grams', 'min_grams', 'max_grams')
    assert_equal [340, 288, 390], gram.values_at('estimated_price', 'min_price', 'max_price')
    assert_equal [367, 311, 421], gram.values_at('estimated_price_with_tax', 'min_price_with_tax', 'max_price_with_tax')
  end

  def test_non_gram_product_has_no_size_or_gram_sale
    frozen = LifeNetsuper.decode_products(fixture('search_butakoma.bin')).find { |p| p['name'].start_with?('【冷凍】') }

    assert_nil frozen['size']
    assert_nil frozen['gram_sale']
    assert_equal 1058, frozen['price_with_tax']
  end

  def test_add_to_cart_request_from_search
    req = LifeNetsuper.decode_add_request(fixture('add_to_cart_request.bin'))

    assert_equal({ 'product_id' => '0000000126896', 'new_item' => true, 'source' => 'search', 'keyword' => '豚こま' }, req)
  end

  def test_add_to_cart_request_increment
    req = LifeNetsuper.decode_add_request(fixture('add_to_cart_increment_request.bin'))

    assert_equal '0000000126896', req['product_id']
    refute req['new_item']
    assert_equal 'increment_amount', req['source']
  end

  def test_past_product_ids_from_image_urls
    raw = 'x' + 'https://stailer.imgix.net/life_only_images/0000005638952_ab.JPG' * 2 +
          'https://stailer.imgix.net/life_only_images/00201268900000.jpg' +
          'https://stailer.imgix.net/life_only_images/0000006906564_cd.jpg'

    assert_equal({ '0000005638952' => 2, '0000006906564' => 1 }, LifeNetsuper.past_product_ids(raw))
  end

  def test_grpc_status_from_trailer
    assert_equal 0, LifeNetsuper.grpc_status(fixture('add_to_cart_response.bin'))
    assert_nil LifeNetsuper.grpc_status(fixture('product_detail.bin').byteslice(0, 5 + 1))
  end
end
