#!/usr/bin/env ruby
# 献立計画。/chef plan / plan apply のバックエンド。
# 候補抽出（直近履歴・アレルギー・ルール）と plan_json の保存・確定を担う。
# 実際の対話的調整・最終献立構築は Claude (skill) 側で行う。
require 'json'
require 'date'
require 'optparse'
require_relative 'chef_db'

def week_start_of(d)
  # 月曜が起点（wday: 月=1）。日曜の場合は6日前の月曜に。
  offset = (d.wday + 6) % 7
  d - offset
end

def household_dict(db)
  db.execute('SELECT key,value FROM household').to_h { |r| [r['key'], r['value']] }
end

def allergies_dict(db)
  out = { 'hard' => [], 'soft' => [] }
  db.execute('SELECT food,member,severity,note FROM allergies').each do |r|
    h = r.reject { |k, _| k.is_a?(Integer) }
    bucket = h['severity'] == 'アレルギー' ? 'hard' : 'soft'
    out[bucket] << h
  end
  out
end

def rules_list(db)
  db.execute('SELECT day_of_week,rule_type,content,priority FROM rules ORDER BY day_of_week, priority DESC')
    .map { |r| r.reject { |k, _| k.is_a?(Integer) } }
end

def recent_ids(db, days)
  rows = db.execute("SELECT recipe_ids FROM meal_log WHERE date >= date('now', ?)", ["-#{days} days"])
  seen = []
  rows.each do |r|
    JSON.parse(r['recipe_ids'] || '[]').each { |i| seen << i.to_i }
  rescue StandardError
    next
  end
  seen.uniq.sort
end

def cmd_context(args)
  ChefDB.init!
  ChefDB.open do |db|
    ws = if args[:week_start]
           week_start_of(Date.parse(args[:week_start]))
         else
           week_start_of(Date.today + 7)
         end
    rids = recent_ids(db, args[:recent_days])
    allergies = allergies_dict(db)
    hard_foods = allergies['hard'].map { |a| a['food'] }.compact

    rows = db.execute(
      "SELECT id,name,type,meal_type,ingredients,allergens,cook_time_min,kids_ok,note FROM recipes WHERE meal_type='dinner'"
    )
    candidates = []
    rows.each do |r|
      h = r.reject { |k, _| k.is_a?(Integer) }
      text = "#{h['ingredients']} #{h['allergens']} #{h['name']}"
      next if hard_foods.any? { |f| !f.to_s.empty? && text.include?(f) }

      %w[type ingredients allergens].each do |k|
        next unless h[k]

        begin
          h[k] = JSON.parse(h[k])
        rescue JSON::ParserError
          # keep
        end
      end
      h['recently_used'] = rids.include?(h['id'])
      candidates << h
    end

    out = {
      week_start: ws.iso8601,
      household: household_dict(db),
      allergies: allergies,
      rules: rules_list(db),
      recent_recipe_ids: rids,
      recent_days: args[:recent_days],
      candidates: candidates
    }
    puts JSON.pretty_generate(out)
  end
end

def cmd_save_draft(args)
  ChefDB.init!
  raw = args[:json] || $stdin.read
  payload = JSON.parse(raw)
  ws = payload['week_start']
  abort 'ERROR: week_start required in plan json' if ws.to_s.empty?
  ChefDB.open do |db|
    existing = db.execute('SELECT id,status FROM meal_plans WHERE week_start=?', [ws]).first
    if existing && existing['status'] == 'applied' && !args[:force]
      warn JSON.generate({ error: 'already applied. --force で上書き可' })
      exit 2
    end
    if existing
      db.execute("UPDATE meal_plans SET status='draft', plan_json=?, applied_at=NULL WHERE id=?",
                 [JSON.generate(payload), existing['id']])
      pid = existing['id']
    else
      db.execute('INSERT INTO meal_plans(week_start,status,plan_json) VALUES(?,?,?)',
                 [ws, 'draft', JSON.generate(payload)])
      pid = db.last_insert_row_id
    end
    puts JSON.generate({ id: pid, week_start: ws, status: 'draft' })
  end
end

def cmd_show(args)
  ChefDB.init!
  ChefDB.open do |db|
    sql = 'SELECT * FROM meal_plans'
    params = []
    if args[:week_start]
      sql += ' WHERE week_start=?'
      params << args[:week_start]
    end
    sql += ' ORDER BY week_start DESC LIMIT 1'
    row = db.execute(sql, params).first
    if row.nil?
      puts 'null'
      return
    end
    h = row.reject { |k, _| k.is_a?(Integer) }
    h['plan_json'] = JSON.parse(h['plan_json']) rescue h['plan_json']
    puts JSON.pretty_generate(h)
  end
end

def cmd_apply(args)
  # draft を applied に昇格し、meal_log に各日の献立を自動記録する。
  # Googleカレンダー登録は別途 Claude 側で MCP 経由で行う想定。
  ChefDB.init!
  ChefDB.open do |db|
    row = db.execute('SELECT * FROM meal_plans WHERE week_start=?', [args[:week_start]]).first
    unless row
      warn JSON.generate({ error: 'draft not found' })
      exit 1
    end
    plan = JSON.parse(row['plan_json'])
    days = plan['days'] || []
    logged = []
    days.each do |day|
      d = day['date']
      rids = day['recipe_ids'] || []
      next if d.to_s.empty? || rids.empty?

      existing = db.execute("SELECT id FROM meal_log WHERE date=? AND meal_type='dinner'", [d]).first
      if existing
        db.execute('UPDATE meal_log SET recipe_ids=?, note=? WHERE id=?',
                   [JSON.generate(rids), "from plan #{row['id']}", existing['id']])
        logged << { date: d, updated: true }
      else
        db.execute('INSERT INTO meal_log(date, meal_type, recipe_ids, note) VALUES(?,?,?,?)',
                   [d, 'dinner', JSON.generate(rids), "from plan #{row['id']}"])
        logged << { date: d, updated: false }
      end
    end
    db.execute("UPDATE meal_plans SET status='applied', applied_at=CURRENT_TIMESTAMP WHERE id=?", [row['id']])
    puts JSON.generate({ id: row['id'], week_start: args[:week_start], logged: logged, status: 'applied' })
  end
end

def main
  sub = ARGV.shift
  opts = {}
  parser = OptionParser.new
  case sub
  when 'context'
    parser.on('--week-start STR') { |v| opts[:week_start] = v }
    parser.on('--recent-days N', Integer) { |v| opts[:recent_days] = v }
    opts[:recent_days] ||= 21
    parser.parse!(ARGV)
    cmd_context(opts)
  when 'save-draft'
    parser.on('--json STR') { |v| opts[:json] = v }
    parser.on('--force') { opts[:force] = true }
    parser.parse!(ARGV)
    cmd_save_draft(opts)
  when 'show'
    parser.on('--week-start STR') { |v| opts[:week_start] = v }
    parser.parse!(ARGV)
    cmd_show(opts)
  when 'apply'
    parser.on('--week-start STR') { |v| opts[:week_start] = v }
    parser.parse!(ARGV)
    abort '--week-start required' unless opts[:week_start]

    cmd_apply(opts)
  else
    warn 'usage: meal_plan.rb {context|save-draft|show|apply} [...]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
