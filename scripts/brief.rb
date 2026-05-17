#!/usr/bin/env ruby
# brief（指示書）管理。household / allergies / rules の閲覧と編集。
require 'json'
require 'optparse'
require_relative 'chef_db'

def cmd_show
  ChefDB.init!
  ChefDB.open do |db|
    out = {
      household: db.execute('SELECT key,value FROM household').to_h { |r| [r['key'], r['value']] },
      allergies: db.execute('SELECT * FROM allergies ORDER BY severity, id').map do |r|
        r.reject { |k, _| k.is_a?(Integer) }
      end,
      rules: db.execute('SELECT * FROM rules ORDER BY day_of_week, priority DESC').map do |r|
        r.reject { |k, _| k.is_a?(Integer) }
      end
    }
    puts JSON.pretty_generate(out)
  end
end

def cmd_household_set(key, value)
  ChefDB.init!
  ChefDB.open do |db|
    db.execute('INSERT INTO household(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
               [key, value])
    puts JSON.generate({ key: key, value: value })
  end
end

def cmd_allergy_add(opts)
  ChefDB.init!
  abort 'ERROR: severity must be アレルギー or 苦手' unless %w[アレルギー 苦手].include?(opts[:severity])
  ChefDB.open do |db|
    db.execute('INSERT INTO allergies(food,member,severity,note) VALUES(?,?,?,?)',
               [opts[:food], opts[:member], opts[:severity], opts[:note]])
    puts JSON.generate({ id: db.last_insert_row_id })
  end
end

def cmd_allergy_remove(id)
  ChefDB.init!
  ChefDB.open do |db|
    db.execute('DELETE FROM allergies WHERE id=?', [id])
    puts JSON.generate({ deleted: id })
  end
end

def cmd_rule_add(opts)
  ChefDB.init!
  ChefDB.open do |db|
    db.execute('INSERT INTO rules(day_of_week,rule_type,content,priority) VALUES(?,?,?,?)',
               [opts[:day], opts[:type] || 'category', opts[:content], opts[:priority] || 0])
    puts JSON.generate({ id: db.last_insert_row_id })
  end
end

def cmd_rule_remove(id)
  ChefDB.init!
  ChefDB.open do |db|
    db.execute('DELETE FROM rules WHERE id=?', [id])
    puts JSON.generate({ deleted: id })
  end
end

def main
  sub = ARGV.shift
  opts = {}
  parser = OptionParser.new
  case sub
  when 'show'
    cmd_show
  when 'household-set'
    parser.parse!(ARGV)
    key, value = ARGV.shift(2)
    abort 'usage: household-set KEY VALUE' if key.nil? || value.nil?

    cmd_household_set(key, value)
  when 'allergy-add'
    parser.on('--food STR') { |v| opts[:food] = v }
    parser.on('--member STR') { |v| opts[:member] = v }
    parser.on('--severity STR') { |v| opts[:severity] = v }
    parser.on('--note STR') { |v| opts[:note] = v }
    parser.parse!(ARGV)
    %i[food member severity].each { |k| abort "--#{k} required" unless opts[k] }
    cmd_allergy_add(opts)
  when 'allergy-remove'
    parser.parse!(ARGV)
    cmd_allergy_remove(Integer(ARGV.shift))
  when 'rule-add'
    parser.on('--day N', Integer) { |v| opts[:day] = v }
    parser.on('--type STR') { |v| opts[:type] = v }
    parser.on('--content STR') { |v| opts[:content] = v }
    parser.on('--priority N', Integer) { |v| opts[:priority] = v }
    parser.parse!(ARGV)
    abort '--day and --content required' unless opts[:day] && opts[:content]

    cmd_rule_add(opts)
  when 'rule-remove'
    parser.parse!(ARGV)
    cmd_rule_remove(Integer(ARGV.shift))
  else
    warn 'usage: brief.rb {show|household-set|allergy-add|allergy-remove|rule-add|rule-remove} [...]'
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
