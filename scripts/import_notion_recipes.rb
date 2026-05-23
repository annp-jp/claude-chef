#!/usr/bin/env ruby
# Notion「料理レパートリー」からのワンショット取り込み用スクリプト。
require 'json'
require_relative 'chef_db'

# カテゴリ推定辞書
CAT_MAP = {
  '肉魚' => %w[
    ひき肉 ひきにく 豚肉 豚バラ 鶏肉 鶏むね肉 鶏胸肉 とりささみ ささみ 牛豚 牛肉 魚 シーフード冷凍 シーフード たらこ 明太子 コンビーフ 肉団子 うずら 豚なす
  ],
  '野菜' => %w[
    大葉 なす ナス 長ネギ ネギ ねぎ にんにく ニンニク 白菜 きくらげ ほうれん草 きゅうり わかめ キャベツ にんじん ピーマン たけのこ もやし葉物野菜 もやし 葉物野菜 きのこ チンゲンサイ 生姜
  ],
  '調味料' => %w[
    バター マーマレードジャム ぽん酢 ポン酢 塩昆布 うめぼし 梅干し 白だし 味噌 オイスター 酒 醤油 お酢 ごま油 ジェノべソース 和風出汁
  ]
}.freeze

def categorize(name)
  n = name.strip
  CAT_MAP.each { |cat, list| return cat if list.any? { |w| n.include?(w) } }
  # 主食・麺・冷食類はその他
  'その他'
end

def parse_ingredients(raw)
  return [] if raw.nil? || raw.strip.empty?
  # カンマ（全角半角）・読点で分割
  raw.split(/[,、]/).map(&:strip).reject(&:empty?).map do |n|
    { 'name' => n, 'amount' => '', 'category' => categorize(n) }
  end
end

TYPE_MAP = { 'メイン' => ['主菜'], 'サブ' => ['副菜'], '汁物' => ['汁物'] }.freeze

# 取り込みデータ（手で組み立て）
RECIPES = [
  { name: 'たらこスパゲッティ', type: 'メイン', ingredients: 'たらこか明太子,大葉,バター',
    note: '日水レシピ参考（マヨ・醤油は入れず、白だし大さじ1/麺500g）',
    url: 'https://www.notion.so/2b554ba013c280639a7bdde7316fc4da', cook: 20 },
  { name: '味噌茄子麻婆', type: 'メイン', ingredients: 'なす,長ネギ,ひき肉',
    note: '味噌・オイスター・酒・ニンニク・和風出汁の味',
    url: 'https://www.notion.so/2cd54ba013c280fe87d8d91455ec736a', cook: 25 },
  { name: '八宝菜丼', type: 'メイン', ingredients: '白菜,うずら,きくらげ,シーフード冷凍,豚肉',
    note: 'ウェイパー・酒大さじ2・塩・生姜。本当は豚バラがいい',
    url: 'https://www.notion.so/2ca54ba013c28020b08bc80df4a88264', cook: 25 },
  { name: '鶏胸肉を焼いてマーマレードソース', type: 'メイン', ingredients: '鶏むね肉,マーマレードジャム',
    note: '鶏肉400gぐらいあった方がいい',
    url: 'https://www.notion.so/2cb54ba013c280fbafdbf654acf02e44', cook: 20 },
  { name: '味噌汁', type: '汁物', ingredients: '何らかの具',
    note: '', url: 'https://www.notion.so/2b554ba013c2800ab7dbc9baf84197b0', cook: 10 },
  { name: '焼き魚', type: 'メイン', ingredients: '魚（何か）',
    note: '', url: 'https://www.notion.so/2b554ba013c28081994cf485eb4b6341', cook: 15 },
  { name: 'きゅうりの酢の物', type: 'サブ', ingredients: 'きゅうり,わかめ',
    note: '', url: 'https://www.notion.so/2b554ba013c2806d838ee44a788a0dc6', cook: 10 },
  { name: 'じょうや鍋', type: 'メイン', ingredients: 'ほうれん草,豚バラ,豆腐,ぽん酢',
    note: 'ぽん酢で食べる常夜鍋', url: 'https://www.notion.so/2b554ba013c2802ba5adcfb7aeee3943', cook: 20 },
  { name: '冷凍餃子', type: 'メイン', ingredients: '冷凍餃子',
    note: '時短', url: 'https://www.notion.so/2b554ba013c28048973fd72d942316ea', cook: 10 },
  { name: '焼きうどん', type: 'メイン', ingredients: 'うどん,キャベツ,豚肉,にんじん',
    note: '', url: 'https://www.notion.so/2b554ba013c28089844cf19db2bca5a9', cook: 15 },
  { name: '塩焼きそば', type: 'メイン', ingredients: '焼きそば,キャベツ,豚肉,にんじん',
    note: '', url: 'https://www.notion.so/2b554ba013c2808da802f5bb2e558f3c', cook: 15 },
  { name: 'ズボラハンバーグ', type: 'メイン', ingredients: 'ひき肉',
    note: '牛豚合挽をそのまま焼くだけ', url: 'https://www.notion.so/2d154ba013c28095bd77e76635f24e4c', cook: 15 },
  { name: '白菜とササミのサラダ', type: 'サブ', ingredients: '白菜,とりささみ,塩昆布,うめぼし',
    note: 'タレ: お酢・醤油・ごま油・白だし各大さじ1', url: 'https://www.notion.so/2d154ba013c2804a812bf0242eefefcc', cook: 15 },
  { name: 'すまし汁', type: '汁物', ingredients: 'なんらかの具',
    note: '', url: 'https://www.notion.so/2b554ba013c28018a4b1edb60777eb0b', cook: 10 },
  { name: '冷凍ハンバーグ', type: 'メイン', ingredients: '冷凍ハンバーグ',
    note: '時短', url: 'https://www.notion.so/2b554ba013c280f4b0badfc71c8bde15', cook: 10 },
  { name: '天ぷらうどん', type: 'メイン', ingredients: 'うどん,惣菜天ぷら',
    note: '時短', url: 'https://www.notion.so/2fe54ba013c2808ea9b0e6e891ea7b78', cook: 10 },
  { name: '青椒肉絲', type: 'メイン', ingredients: 'たけのこ,豚肉,ピーマン,にんじん',
    note: '', url: 'https://www.notion.so/2b554ba013c280d5b208fbdb43fa7533', cook: 25 },
  { name: '辛くない麻婆豆腐', type: 'メイン', ingredients: '豆腐,ねぎ,にんにく,ひきにく',
    note: '辛さなし（子供OK）', url: 'https://www.notion.so/2b554ba013c2801dacd7d15ddaba5959', cook: 20 },
  { name: 'コンビーフチャーハン', type: 'メイン', ingredients: 'コンビーフ,ネギ,キャベツ',
    note: '', url: 'https://www.notion.so/2b554ba013c28024a53ef1e7d4935a47', cook: 15 },
  { name: '味噌豚なす炒め', type: 'メイン', ingredients: '豚肉,ナス,味噌',
    note: '味噌・酒・ナス', url: 'https://www.notion.so/2b554ba013c2802cb522e5ff4be9b428', cook: 20 },
  { name: '冷奴（ごま梅白だし）', type: 'サブ', ingredients: 'ひややっこ',
    note: 'ごま・梅・白だしで', url: 'https://www.notion.so/2b554ba013c280d3b189fd2292cde2e6', cook: 5 },
  { name: 'チンゲンサイ・豚肉・マヨいため', type: 'メイン', ingredients: 'チンゲンサイ,豚肉',
    note: 'マヨ炒め', url: 'https://www.notion.so/2b554ba013c280d3b4d0ca0dcd08feec', cook: 15 },
  { name: 'タンメン袋麺', type: 'メイン', ingredients: 'タンメン,豚肉,もやし,葉物野菜',
    note: '袋麺アレンジ', url: 'https://www.notion.so/2b554ba013c28081b9b3fffa618ce804', cook: 15 },
  { name: '肉団子スープ', type: '汁物', ingredients: '肉団子,長ネギ',
    note: '', url: 'https://www.notion.so/2b554ba013c28038b0c5de6857fd87c9', cook: 15 },
  { name: 'シーフードジェノべパスタ', type: 'メイン', ingredients: 'ジェノべソース,シーフード冷凍,きのこ',
    note: '', url: 'https://www.notion.so/2b554ba013c28027a046f351201501f8', cook: 20 }
].freeze

ChefDB.init!
inserted = []
ChefDB.open do |db|
  # 既存の同URL重複を避けるため、url で軽くチェック
  existing = db.execute('SELECT url FROM recipes WHERE url IS NOT NULL').map { |r| r['url'] }
  RECIPES.each do |r|
    if existing.include?(r[:url])
      warn "skip (already exists): #{r[:name]}"
      next
    end
    payload = {
      'name' => r[:name],
      'type' => TYPE_MAP.fetch(r[:type]),
      'meal_type' => 'dinner',
      'ingredients' => parse_ingredients(r[:ingredients]),
      'instructions' => '',
      'url' => r[:url],
      'kids_ok' => true,
      'allergens' => [],
      'cook_time_min' => r[:cook],
      'note' => r[:note]
    }
    # encode_payload と同等処理（recipe.rb と整合）
    cols = %w[name type meal_type ingredients instructions url kids_ok allergens cook_time_min note]
    values = cols.map do |c|
      v = payload[c]
      case c
      when 'type', 'ingredients', 'allergens' then JSON.generate(v)
      when 'kids_ok' then v ? 1 : 0
      else v
      end
    end
    db.execute("INSERT INTO recipes(#{cols.join(',')}) VALUES(#{(['?'] * cols.size).join(',')})", values)
    inserted << { id: db.last_insert_row_id, name: r[:name] }
  end
end

puts JSON.pretty_generate(inserted: inserted, count: inserted.size)
