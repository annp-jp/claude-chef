#!/usr/bin/env ruby
# TypeSafe の Jev で「買い物リストの項目にどの商品を入れるか」を判定する。/chef order のバックエンド。
# 候補一覧は scripts/life_netsuper.rb products の出力をそのまま受け取る。
# API キーは環境変数 TYPESAFE_API_KEY か、config の 1Password 参照から op read で取得する（表示・保存しない）。
require 'json'
require 'net/http'
require 'open3'
require 'optparse'
require 'uri'
require_relative 'config'

module Jev
  ENDPOINT = URI('https://api.typesafe.ai/v1/systemone')
  MODEL = 'jev-latest'
  NONE = 'none'
  DEFAULT_THRESHOLD = 0.8

  module_function

  def describe(product)
    parts = [product['name']]
    parts << product['size'] if product['size']
    parts << "税込#{product['price_with_tax']}円" if product['price_with_tax']
    parts << "100gあたり#{product['price_per_100g']}円(税抜)" if product['price_per_100g']
    parts << '冷凍' if product['name'].to_s.include?('冷凍')
    parts << "バッジ:#{product['badges'].join('/')}" if product['badges']&.any?
    parts.join(' / ')
  end

  def candidates(products)
    products.reject { |p| p['out_of_stock'] }.uniq { |p| p['product_id'] }
  end

  def build_request(item:, products:, amount: nil, dishes: [])
    options = candidates(products).to_h { |p| [p['product_id'], describe(p)] }
    raise ArgumentError, 'no in-stock candidates' if options.empty?

    state = {
      '買う材料' => item,
      '必要量' => amount,
      '使う料理' => dishes,
      '候補' => options.map { |id, desc| "#{id}: #{desc}" }
    }.compact
    {
      'model' => MODEL,
      'state' => state,
      'questions' => {
        'product' => {
          'type' => 'choice',
          'instructions' => '家庭の献立の材料としてネットスーパーのカートに入れる商品を1つ選ぶ。' \
                            '材料そのものであること、必要量に近い容量であること、料理に合うことを重視する。' \
                            '味付き・加工品・別の食材は材料と違うなら選ばない。',
          'criteria' => options.merge(NONE => '候補のどれも、この材料として適切ではない')
        }
      }
    }
  end

  def decide(answer, threshold: DEFAULT_THRESHOLD)
    probs = answer.fetch('probabilities')
    choice = answer.fetch('choice')
    ranked = probs.sort_by { |_, p| -p }.map { |id, p| { 'product_id' => id, 'probability' => p.round(3) } }
    action =
      if choice == NONE then 'not_found'
      elsif probs.fetch(choice) >= threshold then 'auto'
      else 'ask'
      end
    {
      'action' => action,
      'product_id' => choice == NONE ? nil : choice,
      'probability' => probs.fetch(choice).round(3),
      'confidence' => answer['confidence']&.round(3),
      'ranked' => ranked
    }
  end

  def api_key
    return ENV['TYPESAFE_API_KEY'] if ENV['TYPESAFE_API_KEY'] && !ENV['TYPESAFE_API_KEY'].empty?

    ref = ChefConfig.typesafe_op_ref or
      raise 'TypeSafe の API キーが未設定（TYPESAFE_API_KEY か config/chef.local.yml の typesafe.op_ref）'
    out, status = Open3.capture2('op', 'read', ref)
    raise "op read に失敗（typesafe.op_ref の形式 op://<vault>/<item>/<field> と 1Password のサインインを確認）" unless status.success?

    out.strip
  end

  def call(request)
    http = Net::HTTP.new(ENDPOINT.host, ENDPOINT.port)
    http.use_ssl = true
    http.read_timeout = 20
    req = Net::HTTP::Post.new(ENDPOINT)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(request)
    res = http.request(req)
    raise "Jev API error #{res.code}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
end

if $PROGRAM_NAME == __FILE__
  # LANG 未設定のシェルでも日本語の引数を UTF-8 として扱う
  ARGV.map! { |a| a.dup.force_encoding(Encoding::UTF_8) }
  opts = { dishes: [], threshold: Jev::DEFAULT_THRESHOLD }
  parser = OptionParser.new do |o|
    o.banner = 'usage: jev.rb choose --item NAME --products FILE [--amount AMT] [--dish NAME]... [--threshold P] [--dry-run]'
    o.on('--item NAME') { |v| opts[:item] = v }
    o.on('--amount AMT') { |v| opts[:amount] = v }
    o.on('--dish NAME') { |v| opts[:dishes] << v }
    o.on('--products FILE', 'life_netsuper.rb products の出力 JSON') { |v| opts[:products] = v }
    o.on('--threshold P', Float) { |v| opts[:threshold] = v }
    o.on('--dry-run', '送信せずリクエストだけ表示') { opts[:dry_run] = true }
  end
  cmd = ARGV.shift
  parser.parse!(ARGV)
  unless cmd == 'choose' && opts[:item] && opts[:products]
    warn parser.banner
    exit 1
  end

  products = JSON.parse(File.read(opts[:products], encoding: 'UTF-8'))['products']
  request = Jev.build_request(item: opts[:item], amount: opts[:amount], dishes: opts[:dishes], products: products)
  if opts[:dry_run]
    puts JSON.pretty_generate(request)
    exit
  end

  response = Jev.call(request)
  result = Jev.decide(response.dig('answers', 'product'), threshold: opts[:threshold])
  puts JSON.pretty_generate(result.merge('item' => opts[:item], 'model' => response['model'], 'usage' => response['usage']))
end
