#!/usr/bin/env ruby
# 買い物リスト生成。/chef buy のバックエンド。
# 確定献立(meal_plans status=applied) の recipe_ids から ingredients を集計し、
# category 別に整形して出力する。
require 'json'
require 'optparse'
require_relative 'chef_db'

CATEGORY_ORDER = %w[肉魚 野菜 調味料 その他].freeze
DEFAULT_CATEGORY = 'その他'

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

def aggregate(ingredients_lists)
  bucket = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = [] } }
  ingredients_lists.each do |ings|
    ings.each do |ing|
      next unless ing.is_a?(Hash)

      name = ing['name'].to_s.strip
      next if name.empty?

      cat = ing['category'] || guess_category(name)
      amount = ing['amount'].to_s
      bucket[cat][name] << amount
    end
  end
  out = {}
  cats = CATEGORY_ORDER.select { |c| bucket.key?(c) } + bucket.keys.reject { |c| CATEGORY_ORDER.include?(c) }
  cats.each do |cat|
    items = bucket[cat].sort.map do |name, amounts|
      amt = amounts.reject(&:empty?).join(' + ')
      { 'name' => name, 'amount' => amt }
    end
    out[cat] = items
  end
  out
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
    ingredients_lists = []
    rids.each do |rid|
      r = db.execute('SELECT ingredients FROM recipes WHERE id=?', [rid]).first
      next unless r && r['ingredients']

      begin
        ings = JSON.parse(r['ingredients'])
        ingredients_lists << ings if ings.is_a?(Array)
      rescue JSON::ParserError
        next
      end
    end
    puts JSON.pretty_generate({ week_start: ws, categories: aggregate(ingredients_lists) })
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
