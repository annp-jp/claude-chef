#!/usr/bin/env ruby
# Recipe master CRUD. /chef note, /chef menu のバックエンド。
require 'json'
require 'optparse'
require_relative 'chef_db'

COLS = %w[name course type meal_type ingredients instructions url kids_ok allergens cook_time_min note].freeze
JSON_COLS = %w[type ingredients allergens].freeze

def encode_payload(payload)
  COLS.map do |c|
    v = payload[c]
    v = JSON.generate(v) if JSON_COLS.include?(c) && !v.nil? && !v.is_a?(String)
    v = (v ? 1 : 0) if c == 'kids_ok' && (v == true || v == false)
    v
  end
end

def row_to_hash(row)
  h = row.reject { |k, _| k.is_a?(Integer) }
  JSON_COLS.each do |k|
    next unless h[k]

    begin
      h[k] = JSON.parse(h[k])
    rescue JSON::ParserError
      # leave as string
    end
  end
  h
end

def cmd_add(args)
  ChefDB.init!
  raw = args[:json] || $stdin.read
  payload = JSON.parse(raw)
  abort 'ERROR: name is required' if payload['name'].to_s.empty?

  payload['meal_type'] ||= 'dinner'
  payload['course'] ||= 'meal'
  payload['kids_ok'] = true if payload['kids_ok'].nil?
  values = encode_payload(payload)
  ChefDB.open do |db|
    db.execute("INSERT INTO recipes(#{COLS.join(',')}) VALUES(#{(['?'] * COLS.size).join(',')})", values)
    id = db.last_insert_row_id
    puts JSON.generate({ id: id, name: payload['name'] })
  end
end

def cmd_list(args)
  ChefDB.init!
  sql = 'SELECT * FROM recipes'
  params = []
  if args[:query]
    sql += ' WHERE name LIKE ? OR ingredients LIKE ? OR type LIKE ? OR note LIKE ?'
    q = "%#{args[:query]}%"
    params = [q, q, q, q]
  end
  sql += ' ORDER BY id DESC'
  sql += " LIMIT #{args[:limit].to_i}" if args[:limit]
  ChefDB.open do |db|
    rows = db.execute(sql, params).map { |r| row_to_hash(r) }
    puts JSON.pretty_generate(rows)
  end
end

def cmd_show(args)
  ChefDB.init!
  ChefDB.open do |db|
    row = db.execute('SELECT * FROM recipes WHERE id=?', [args[:id]]).first
    abort 'not found' unless row

    puts JSON.pretty_generate(row_to_hash(row))
  end
end

def cmd_delete(args)
  ChefDB.init!
  ChefDB.open do |db|
    db.execute('DELETE FROM recipes WHERE id=?', [args[:id]])
    puts JSON.generate({ deleted: args[:id] })
  end
end

def main
  sub = ARGV.shift
  opts = {}
  parser = OptionParser.new
  case sub
  when 'add'
    parser.on('--json STR') { |v| opts[:json] = v }
    parser.parse!(ARGV)
    cmd_add(opts)
  when 'list'
    parser.on('--query STR') { |v| opts[:query] = v }
    parser.on('--limit N', Integer) { |v| opts[:limit] = v }
    opts[:limit] ||= 200
    parser.parse!(ARGV)
    cmd_list(opts)
  when 'show'
    parser.parse!(ARGV)
    opts[:id] = Integer(ARGV.shift)
    cmd_show(opts)
  when 'delete'
    parser.parse!(ARGV)
    opts[:id] = Integer(ARGV.shift)
    cmd_delete(opts)
  else
    warn 'usage: recipe.rb {add|list|show|delete} [...]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
