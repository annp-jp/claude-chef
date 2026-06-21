#!/usr/bin/env ruby
# 調理記録。/chef log のバックエンド。
require 'json'
require 'date'
require 'optparse'
require_relative 'chef_db'

def resolve_recipe_ids(db, tokens)
  ids = []
  unresolved = []
  tokens.each do |t|
    if t =~ /\A\d+\z/
      row = db.execute('SELECT id FROM recipes WHERE id=?', [t.to_i]).first
      row ? ids << row['id'] : unresolved << t
    else
      row = db.execute('SELECT id FROM recipes WHERE name = ? ORDER BY id DESC LIMIT 1', [t]).first
      row ? ids << row['id'] : unresolved << t
    end
  end
  [ids, unresolved]
end

def cmd_add(args, recipes)
  ChefDB.init!
  d = args[:date] || Date.today.iso8601
  ChefDB.open do |db|
    ids, unresolved = resolve_recipe_ids(db, recipes)
    if !unresolved.empty? && !args[:allow_unknown]
      warn JSON.generate({ error: '未登録レシピあり。先に /chef note で登録するか --allow-unknown を渡す',
                           unresolved: unresolved })
      exit 2
    end
    note = args[:note] || (unresolved.empty? ? nil : unresolved.join(','))
    db.execute('INSERT INTO meal_log(date, meal_type, recipe_ids, note) VALUES(?,?,?,?)',
               [d, args[:meal_type] || 'dinner', JSON.generate(ids), note])
    puts JSON.generate({ id: db.last_insert_row_id, date: d, recipe_ids: ids, unresolved: unresolved })
  end
end

def cmd_list(args)
  ChefDB.init!
  sql = 'SELECT * FROM meal_log'
  params = []
  if args[:since]
    sql += ' WHERE date >= ?'
    params << args[:since]
  end
  sql += ' ORDER BY date DESC, id DESC'
  sql += " LIMIT #{args[:limit].to_i}" if args[:limit]
  ChefDB.open do |db|
    rows = db.execute(sql, params).map do |r|
      h = r.reject { |k, _| k.is_a?(Integer) }
      h['recipe_ids'] = JSON.parse(h['recipe_ids'] || '[]') rescue h['recipe_ids']
      h
    end
    puts JSON.pretty_generate(rows)
  end
end

def cmd_recent_ids(args)
  ChefDB.init!
  ChefDB.open do |db|
    rows = db.execute("SELECT recipe_ids FROM meal_log WHERE date >= date('now', ?)",
                      ["-#{args[:days].to_i} days"])
    seen = []
    rows.each do |r|
      JSON.parse(r['recipe_ids'] || '[]').each { |i| seen << i.to_i }
    rescue StandardError
      next
    end
    puts JSON.generate(seen.uniq.sort)
  end
end

def main
  sub = ARGV.shift
  opts = {}
  parser = OptionParser.new
  case sub
  when 'add'
    parser.on('--date STR') { |v| opts[:date] = v }
    parser.on('--meal-type STR') { |v| opts[:meal_type] = v }
    parser.on('--note STR') { |v| opts[:note] = v }
    parser.on('--allow-unknown') { opts[:allow_unknown] = true }
    parser.parse!(ARGV)
    recipes = ARGV.dup
    abort 'usage: meal_log.rb add <料理名|id> [...]' if recipes.empty?

    cmd_add(opts, recipes)
  when 'list'
    parser.on('--since STR') { |v| opts[:since] = v }
    parser.on('--limit N', Integer) { |v| opts[:limit] = v }
    opts[:limit] ||= 50
    parser.parse!(ARGV)
    cmd_list(opts)
  when 'recent-ids'
    parser.on('--days N', Integer) { |v| opts[:days] = v }
    opts[:days] ||= 21
    parser.parse!(ARGV)
    cmd_recent_ids(opts)
  else
    warn 'usage: meal_log.rb {add|list|recent-ids} [...]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
