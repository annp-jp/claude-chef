#!/usr/bin/env ruby
# 仕入れリスト生成。/chef order list / /chef order のバックエンド。
# 確定献立(meal_plans status=applied) の recipe_ids から ingredients を集計し、
# category 別に整形して出力する。
require 'json'
require 'optparse'
require_relative 'chef_db'
require_relative 'config'

CATEGORY_ORDER = %w[肉魚 野菜 調味料 その他].freeze
DEFAULT_CATEGORY = 'その他'
# 買う対象にならないもの（完全一致）。常備品の好みは config の order.pantry_* で持つ。
NEVER_BUY = %w[水 お湯 湯 氷].freeze

HEURISTICS = [
  ['肉魚', /肉|鶏|豚|牛|挽肉|鮭|鯖|鱈|まぐろ|鰤|海老|エビ|イカ|タコ|あさり|貝|魚/],
  ['野菜',
   /菜|キャベツ|玉葱|玉ねぎ|大根|人参|にんじん|じゃがいも|ピーマン|トマト|きゅうり|ナス|なす|もやし|ねぎ|ニンニク|生姜|しょうが|ほうれん草|ブロッコリー|きのこ|椎茸|しめじ|えのき|レタス|白菜/],
  ['調味料', /醤油|味噌|砂糖|塩|酢|みりん|酒|油|だし|出汁|ソース|ケチャップ|マヨネーズ|胡椒|こしょう/]
].freeze

def guess_category(name)
  HEURISTICS.each { |cat, pat| return cat if pat.match?(name) }
  DEFAULT_CATEGORY
end

# recipes: [{ 'name' => 料理名, 'ingredients' => [{name, amount, category}, ...] }, ...]
# 各材料を category 別に集約し、amount と「使用料理(dishes)」を併せて返す。
# dishes は order の商品選択時の判断ヒント（例: 肉団子はスープ用なら味なしを選ぶ 等）。
def aggregate(recipes)
  bucket = Hash.new { |h, k| h[k] = {} }
  recipes.each do |recipe|
    dish = recipe['name'].to_s.strip
    (recipe['ingredients'] || []).each do |ing|
      next unless ing.is_a?(Hash)

      name = ing['name'].to_s.strip
      next if name.empty?

      cat = ing['category'] || guess_category(name)
      entry = (bucket[cat][name] ||= { amounts: [], dishes: [] })
      entry[:amounts] << ing['amount'].to_s
      entry[:dishes] << dish unless dish.empty? || entry[:dishes].include?(dish)
    end
  end
  out = {}
  cats = CATEGORY_ORDER.select { |c| bucket.key?(c) } + bucket.keys.reject { |c| CATEGORY_ORDER.include?(c) }
  cats.each do |cat|
    items = bucket[cat].sort.map do |name, entry|
      amt = entry[:amounts].reject(&:empty?).join(' + ')
      { 'name' => name, 'amount' => amt, 'dishes' => entry[:dishes] }
    end
    out[cat] = items
  end
  out
end

# aggregate の結果に好みを反映する。NEVER_BUY は除外し、常備品には pantry: true、
# item_notes（品目名の部分一致）に当たる品目には note を付ける。
def apply_preferences(cats, pantry_categories:, pantry_items:, item_notes:)
  cats.to_h do |cat, items|
    kept = items.reject { |it| NEVER_BUY.include?(it['name']) }.map do |it|
      it = it.dup
      pantry = pantry_categories.include?(cat) || pantry_items.any? { |p| it['name'].include?(p) }
      it['pantry'] = pantry
      note = item_notes.find { |key, _| it['name'].include?(key) }&.last
      it['note'] = note if note
      it
    end
    [cat, kept]
  end.reject { |_, items| items.empty? }
end

def cmd_build(args)
  ChefDB.init!
  ChefDB.open do |db|
    ws = args[:week_start]
    unless ws
      row = db.execute(
        "SELECT week_start FROM meal_plans WHERE status='applied' " \
        "ORDER BY (week_start >= date('now')) DESC, week_start DESC LIMIT 1"
      ).first
      unless row
        warn JSON.generate({ error: '確定済み献立が見つからない。先に /chef plan apply' })
        exit 1
      end
      ws = row['week_start']
    end
    plan_row = db.execute("SELECT plan_json FROM meal_plans WHERE week_start=? AND status='applied'", [ws]).first
    unless plan_row
      warn JSON.generate({ error: "applied plan for #{ws} not found" })
      exit 1
    end
    plan = JSON.parse(plan_row['plan_json'])
    rids = (plan['days'] || []).flat_map { |d| (d['recipe_ids'] || []).map(&:to_i) }
    recipes = []
    rids.each do |rid|
      r = db.execute('SELECT name, ingredients FROM recipes WHERE id=?', [rid]).first
      next unless r && r['ingredients']

      begin
        ings = JSON.parse(r['ingredients'])
        recipes << { 'name' => r['name'], 'ingredients' => ings } if ings.is_a?(Array)
      rescue JSON::ParserError
        next
      end
    end
    settings = ChefConfig.order_settings
    cats = apply_preferences(
      aggregate(recipes),
      pantry_categories: settings['pantry_categories'],
      pantry_items: settings['pantry_items'],
      item_notes: settings['item_notes']
    )
    puts JSON.pretty_generate({ week_start: ws, categories: cats })
  end
end

def main
  sub = ARGV.shift
  opts = {}
  parser = OptionParser.new
  case sub
  when 'build'
    parser.on('--week-start STR') { |v| opts[:week_start] = v }
    parser.parse!(ARGV)
    cmd_build(opts)
  else
    warn 'usage: shopping.rb build [--week-start YYYY-MM-DD]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
