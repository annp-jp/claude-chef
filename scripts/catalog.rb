#!/usr/bin/env ruby
# 定番商品カタログ CRUD。/chef note（商品登録）, /chef order（照合）のバックエンド。
# 我が家の定番材料 ⇔ ライフネットスーパーの実商品(URL/商品ID) を紐づける。
# 仕様: docs/spec/catalog.md
require 'json'
require 'optparse'
require_relative 'chef_db'

# ライフの商品URL末尾から商品IDを抽出する（例: .../product_detail/0000004151122）。
def product_id_from_url(url)
  return nil unless url

  m = url.match(%r{product_detail/([0-9A-Za-z_-]+)})
  m && m[1]
end

# 照合用の正規化: 前後空白除去 + 全角空白を半角に潰す程度（過剰な正規化はしない）。
def normalize(str)
  str.to_s.strip.gsub(/[[:space:]]+/, '')
end

# payload の aliases は Array / JSON文字列 / カンマ区切り のいずれでも受ける。
def parse_aliases_any(val)
  return val.map(&:to_s) if val.is_a?(Array)

  parse_aliases(val)
end

def parse_aliases(val)
  return [] if val.nil? || val.to_s.strip.empty?

  parsed = JSON.parse(val)
  parsed.is_a?(Array) ? parsed.map(&:to_s) : []
rescue JSON::ParserError
  # カンマ区切りも許容
  val.to_s.split(',').map(&:strip).reject(&:empty?)
end

def row_to_hash(row)
  h = row.reject { |k, _| k.is_a?(Integer) }
  h['aliases'] = parse_aliases(h['aliases'])
  h
end

def cmd_add(args)
  ChefDB.init!
  raw = args[:json] || $stdin.read
  payload = JSON.parse(raw)
  name = payload['name'].to_s.strip
  abort 'ERROR: name is required' if name.empty?

  url = payload['url']
  pid = payload['product_id'] || product_id_from_url(url)

  ChefDB.open do |db|
    existing = db.execute('SELECT * FROM store_products WHERE name=?', [name]).first
    if existing
      # 指定された項目だけ更新（未指定は既存値を維持）。再登録で別名等が消える事故を防ぐ。
      cur = row_to_hash(existing)
      aliases = payload.key?('aliases') ? parse_aliases_any(payload['aliases']) : cur['aliases']
      db.execute(
        'UPDATE store_products SET aliases=?, product_name=?, product_id=?, url=?, ' \
        'category=?, note=?, updated_at=CURRENT_TIMESTAMP WHERE id=?',
        [JSON.generate(aliases),
         payload.fetch('product_name', cur['product_name']),
         pid || cur['product_id'],
         url || cur['url'],
         payload.fetch('category', cur['category']),
         payload.fetch('note', cur['note']),
         existing['id']]
      )
      id = existing['id']
      action = 'updated'
    else
      aliases = parse_aliases_any(payload['aliases'])
      db.execute(
        'INSERT INTO store_products(name,aliases,product_name,product_id,url,category,note) ' \
        'VALUES(?,?,?,?,?,?,?)',
        [name, JSON.generate(aliases), payload['product_name'], pid, url, payload['category'], payload['note']]
      )
      id = db.last_insert_row_id
      action = 'added'
    end
    puts JSON.generate({ id: id, name: name, product_id: pid, action: action })
  end
end

def cmd_list(args)
  ChefDB.init!
  sql = 'SELECT * FROM store_products'
  params = []
  if args[:query]
    sql += ' WHERE name LIKE ? OR aliases LIKE ? OR product_name LIKE ?'
    q = "%#{args[:query]}%"
    params = [q, q, q]
  end
  sql += ' ORDER BY name'
  ChefDB.open do |db|
    rows = db.execute(sql, params).map { |r| row_to_hash(r) }
    puts JSON.pretty_generate(rows)
  end
end

def cmd_rm(args)
  ChefDB.init!
  ChefDB.open do |db|
    if args[:id]
      db.execute('DELETE FROM store_products WHERE id=?', [args[:id]])
      puts JSON.generate({ deleted: args[:id] })
    elsif args[:name]
      db.execute('DELETE FROM store_products WHERE name=?', [args[:name]])
      puts JSON.generate({ deleted: args[:name] })
    else
      abort 'ERROR: --id または --name が必要'
    end
  end
end

# 項目名から定番商品を引く。完全一致 > 部分一致 の順。無ければ null。
def cmd_match(args)
  ChefDB.init!
  needle = normalize(args[:name])
  abort 'ERROR: --name が必要' if needle.empty?

  ChefDB.open do |db|
    rows = db.execute('SELECT * FROM store_products').map { |r| row_to_hash(r) }
    exact = nil
    partial = nil
    rows.each do |r|
      keys = [r['name'], *r['aliases']].map { |k| normalize(k) }.reject(&:empty?)
      if keys.include?(needle)
        exact = r
        break
      end
      next if partial

      partial = r if keys.any? { |k| k.include?(needle) || needle.include?(k) }
    end
    hit = exact || partial
    if hit
      puts JSON.generate({ match: exact ? 'exact' : 'partial', product: hit })
    else
      puts JSON.generate({ match: nil, product: nil })
    end
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
    parser.parse!(ARGV)
    cmd_list(opts)
  when 'rm', 'delete'
    parser.on('--id N', Integer) { |v| opts[:id] = v }
    parser.on('--name STR') { |v| opts[:name] = v }
    parser.parse!(ARGV)
    cmd_rm(opts)
  when 'match'
    parser.on('--name STR') { |v| opts[:name] = v }
    parser.parse!(ARGV)
    cmd_match(opts)
  else
    warn 'usage: catalog.rb {add|list|rm|match} [...]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
