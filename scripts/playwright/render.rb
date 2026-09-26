#!/usr/bin/env ruby
# browser_run_code_unsafe は filename 実行に引数を渡せないので、テンプレートの /*ARGS*/null を
# JSON に置き換えた実行用ファイルを .playwright-mcp/（git 管理外）に書き出す。
#   ruby scripts/playwright/render.rb search '["豚こま","牛乳"]'
#   ruby scripts/playwright/render.rb add_items '[["0000000126896",1],["0000004151122",4]]'
require 'json'
require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
PLACEHOLDER = '/*ARGS*/null'

def render(name, json)
  template = Pathname.new(__dir__).join("#{name}.js")
  raise ArgumentError, "unknown template: #{name}" unless template.exist?

  args = JSON.parse(json)
  raise ArgumentError, 'ARGS must be a non-empty JSON array' unless args.is_a?(Array) && !args.empty?

  source = template.read(encoding: 'UTF-8')
  raise ArgumentError, "#{name}.js has no #{PLACEHOLDER}" unless source.include?(PLACEHOLDER)

  out = ROOT.join('.playwright-mcp', "#{name}.js")
  out.dirname.mkpath
  out.write(source.sub(PLACEHOLDER, JSON.generate(args)))
  out.relative_path_from(ROOT).to_s
end

if $PROGRAM_NAME == __FILE__
  name, json = ARGV
  abort 'usage: render.rb {search|add_items} JSON_ARRAY' unless name && json
  puts render(name, json.dup.force_encoding(Encoding::UTF_8))
end
