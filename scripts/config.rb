#!/usr/bin/env ruby
# ローカル設定（config/chef.local.yml）の読み込み。
# 環境別の値（calendar_id / ライフの1Password参照）を集約する。
# 実値・参照は git に乗せない（.local.yml は .gitignore 済み）。
require 'yaml'
require 'json'
require 'pathname'

module ChefConfig
  ROOT = Pathname.new(__dir__).parent
  PATH = Pathname.new(ENV['CHEF_CONFIG'] || ROOT.join('config', 'chef.local.yml'))

  module_function

  # 設定全体を Hash で返す。ファイルが無ければ空 Hash。
  def load
    return {} unless PATH.exist?

    YAML.safe_load(PATH.read) || {}
  rescue Psych::SyntaxError => e
    warn "config parse error: #{e.message}"
    {}
  end

  # GoogleカレンダーのID。未設定なら nil（呼び出し側で primary 扱い）。
  def calendar_id
    load['calendar_id']
  end

  # ライフの 1Password item 参照（op://vault/item-id）。未設定なら nil。
  def life_op_item
    (load['life_netsuper'] || {})['op_item']
  end

  # TypeSafe（Jev）の API キーの 1Password 参照（op://vault/item/field）。未設定なら nil。
  def typesafe_op_ref
    (load['typesafe'] || {})['op_ref']
  end

  # /chef order の商品選びの設定（selection_rules は優先順の文章リスト）
  def order_settings
    order = load['order'] || {}
    {
      'minimum_order_yen' => order['minimum_order_yen'],
      'selection_rules' => Array(order['selection_rules'])
    }
  end
end

if __FILE__ == $PROGRAM_NAME
  sub = ARGV.shift
  case sub
  when 'show'
    cfg = ChefConfig.load
    cfg = cfg.dup
    # 参照値はそのまま出すが、構造の確認用
    puts JSON.pretty_generate(cfg)
  when 'calendar-id'
    id = ChefConfig.calendar_id
    if id
      puts id
    else
      warn 'calendar_id 未設定（config/chef.local.yml）'
      exit 1
    end
  when 'life-op-item'
    item = ChefConfig.life_op_item
    if item
      puts item
    else
      warn 'life_netsuper.op_item 未設定（config/chef.local.yml）'
      exit 1
    end
  when 'order'
    settings = ChefConfig.order_settings
    if settings['selection_rules'].empty?
      warn 'order.selection_rules 未設定（config/chef.local.yml。.example 参照）'
      exit 1
    end
    puts JSON.pretty_generate(settings)
  else
    warn 'usage: config.rb {show|calendar-id|life-op-item|order}'
    exit 1
  end
end
