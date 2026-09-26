#!/usr/bin/env ruby
# ライフネットスーパー（Stailer 基盤）の gRPC-web 通信をデコードする。/chef order のバックエンド。
# ブラウザ操作と通信の保存は Playwright MCP が担い、このスクリプトは保存済みの body を読むだけ。
# 認証情報には触れない（リクエストはすべてブラウザ自身が送る）。
require 'json'

module LifeNetsuper
  module_function

  def read_varint(buf, pos)
    value = 0
    shift = 0
    loop do
      byte = buf.getbyte(pos)
      raise ArgumentError, 'truncated varint' if byte.nil?

      pos += 1
      value |= (byte & 0x7f) << shift
      shift += 7
      return [value, pos] if byte < 0x80
    end
  end

  # スキーマなしで 1 階層だけ読む。{ field_number => [value, ...] }（length-delimited は生バイト列）
  def parse_message(buf)
    fields = Hash.new { |h, k| h[k] = [] }
    pos = 0
    while pos < buf.bytesize
      key, pos = read_varint(buf, pos)
      field = key >> 3
      case key & 7
      when 0
        value, pos = read_varint(buf, pos)
      when 1
        value = buf.byteslice(pos, 8).unpack1('E')
        pos += 8
      when 2
        len, pos = read_varint(buf, pos)
        value = buf.byteslice(pos, len)
        pos += len
      when 5
        value = buf.byteslice(pos, 4).unpack1('e')
        pos += 4
      else
        raise ArgumentError, "unsupported wire type #{key & 7}"
      end
      raise ArgumentError, 'truncated message' if pos > buf.bytesize

      fields[field] << value
    end
    fields
  end

  # gRPC-web のフレーム列を [{ trailer: bool, data: String }] に分解する
  def frames(raw)
    raw = raw.b
    out = []
    pos = 0
    while pos + 5 <= raw.bytesize
      flag = raw.getbyte(pos)
      len = raw.byteslice(pos + 1, 4).unpack1('N')
      out << { trailer: flag.anybits?(0x80), data: raw.byteslice(pos + 5, len) }
      pos += 5 + len
    end
    out
  end

  def message_body(raw)
    frame = frames(raw).find { |f| !f[:trailer] }
    frame ? frame[:data] : ''.b
  end

  def grpc_status(raw)
    trailer = frames(raw).find { |f| f[:trailer] }
    return nil unless trailer

    trailer[:data].force_encoding('UTF-8')[/grpc-status:\s*(\d+)/, 1]&.to_i
  end

  def str(bytes)
    bytes&.dup&.force_encoding('UTF-8')
  end

  def int_str(bytes)
    s = str(bytes)
    s && !s.empty? ? s.to_i : nil
  end

  # 検索（SearchEcProductsWithKeyword）と商品詳細（ListEcProducts）は同じ商品メッセージを field 1 に並べる
  def decode_products(raw)
    parse_message(message_body(raw))[1].map { |bytes| decode_product(bytes) }
  end

  def decode_product(bytes)
    f = parse_message(bytes)
    product = {
      'product_id' => str(f[2].first),
      'name' => str(f[3].first),
      'size' => str(f[69].first).then { |s| s.nil? || s.empty? ? nil : s },
      'price' => f[7].first,
      'price_with_tax' => f[9].first&.round,
      'price_per_100g' => f[68].first,
      'out_of_stock' => f[10].first == 1,
      'badges' => f[52].map { |b| str(parse_message(b)[2].first) }.compact,
      'note' => str(f[16].first).then { |s| s.nil? || s.empty? ? nil : s },
      'image_url' => str(f[5].first)
    }
    product['gram_sale'] = gram_sale(f[70].first) if f[70].any?
    product
  end

  # グラム売り商品の目安・最小・最大（価格は税抜、括弧内の _with_tax は税込）
  def gram_sale(bytes)
    g = parse_message(bytes)
    prices = parse_message(g[1].first.to_s)
    grams = parse_message(g[2].first.to_s)
    estimate = parse_message(g[3].first.to_s)
    max = parse_message(g[4].first.to_s)
    min = parse_message(g[5].first.to_s)
    {
      'estimated_grams' => grams[1].first,
      'min_grams' => grams[3].first,
      'max_grams' => grams[2].first,
      'estimated_price' => prices[1].first,
      'estimated_price_with_tax' => int_str(estimate[1].first),
      'min_price' => prices[2].first,
      'min_price_with_tax' => int_str(min[1].first),
      'max_price' => prices[3].first,
      'max_price_with_tax' => int_str(max[1].first)
    }
  end

  # AddToCart のリクエスト。new_item は検索結果などからの初回追加、false はカート内の「＋」
  def decode_add_request(raw)
    f = parse_message(message_body(raw))
    {
      'product_id' => str(f[1].first),
      'new_item' => f[2].first == 1,
      'source' => str(f[5].first),
      'keyword' => str(f[6].first)
    }
  end
end

def usage!
  warn <<~USAGE
    usage:
      life_netsuper.rb products FILE...   # 検索/商品詳細レスポンスを商品一覧 JSON に（複数ページは結合）
      life_netsuper.rb add-request FILE   # AddToCart リクエストの中身を JSON に
      life_netsuper.rb status FILE        # レスポンスの grpc-status（0 が成功）
  USAGE
  exit 1
end

if $PROGRAM_NAME == __FILE__
  cmd, path, *more = ARGV
  usage! unless cmd && path
  raw = File.binread(path)
  result =
    case cmd
    when 'products'
      # 検索はスクロールでページ追加されるので、複数ページ分を順に渡せば商品 ID で重複を除いて結合する
      products = [path, *more].flat_map { |p| LifeNetsuper.decode_products(File.binread(p)) }
      { 'products' => products.uniq { |p| p['product_id'] } }
    when 'add-request' then LifeNetsuper.decode_add_request(raw)
    when 'status' then { 'grpc_status' => LifeNetsuper.grpc_status(raw) }
    else usage!
    end
  puts JSON.pretty_generate(result)
end
