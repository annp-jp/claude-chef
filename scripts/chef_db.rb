#!/usr/bin/env ruby
# Chef DB layer: SQLite接続とスキーマ管理。
require 'sqlite3'
require 'json'
require 'pathname'

module ChefDB
  ROOT = Pathname.new(__dir__).parent
  DB_PATH = Pathname.new(ENV['CHEF_DB'] || ROOT.join('data', 'chef.db'))

  SCHEMA = <<~SQL
    CREATE TABLE IF NOT EXISTS recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        course TEXT DEFAULT 'meal',
        type TEXT,
        meal_type TEXT DEFAULT 'dinner',
        ingredients TEXT,
        instructions TEXT,
        url TEXT,
        kids_ok INTEGER DEFAULT 1,
        allergens TEXT,
        cook_time_min INTEGER,
        note TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS meal_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date DATE NOT NULL,
        meal_type TEXT DEFAULT 'dinner',
        recipe_ids TEXT,
        note TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_meal_log_date ON meal_log(date);

    CREATE TABLE IF NOT EXISTS meal_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        week_start DATE NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        plan_json TEXT NOT NULL,
        applied_at DATETIME
    );
    CREATE INDEX IF NOT EXISTS idx_meal_plans_week ON meal_plans(week_start);

    CREATE TABLE IF NOT EXISTS household (
        key TEXT PRIMARY KEY,
        value TEXT
    );

    -- 定番商品カタログ: 我が家の定番材料 ⇔ ライフネットスーパーの実商品の紐づけ。
    -- order のカート投入で検索をスキップする「ヒント」。保証ではない（URLが死んだら検索へ）。
    CREATE TABLE IF NOT EXISTS store_products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        aliases TEXT,
        product_name TEXT,
        product_id TEXT,
        url TEXT,
        category TEXT,
        note TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS allergies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        food TEXT NOT NULL,
        member TEXT NOT NULL,
        severity TEXT NOT NULL CHECK (severity IN ('アレルギー','苦手')),
        note TEXT
    );

    CREATE TABLE IF NOT EXISTS rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_of_week INTEGER CHECK (day_of_week BETWEEN 1 AND 7),
        rule_type TEXT,
        content TEXT,
        priority INTEGER DEFAULT 0
    );
  SQL

  BRIEF_DEFAULTS = {
    'members' => '（例: リョウ(1986/大人), 配偶者(大人), 子A(2020/子供)）',
    'dietary_notes' => '（例: 子供は薄味希望、辛い物NG）',
    'weekly_pattern_hint' => '（例: 平日は時短重視、金曜は少し凝ったもの可）'
  }.freeze

  module_function

  def connect
    DB_PATH.dirname.mkpath
    db = SQLite3::Database.new(DB_PATH.to_s)
    db.results_as_hash = true
    db.execute('PRAGMA foreign_keys = ON')
    db
  end

  # スキーマ初期化。新規作成時のみ true を返す。
  def init!
    fresh = !DB_PATH.exist?
    db = connect
    begin
      db.execute_batch(SCHEMA)
      migrate!(db)
      if fresh
        BRIEF_DEFAULTS.each do |k, v|
          db.execute('INSERT OR IGNORE INTO household(key,value) VALUES(?,?)', [k, v])
        end
      end
    ensure
      db.close
    end
    fresh
  end

  # 既存DB向けの追加カラムを冪等に投入する。
  def migrate!(db)
    cols = db.execute("PRAGMA table_info(recipes)").map { |r| r['name'] }
    db.execute("ALTER TABLE recipes ADD COLUMN course TEXT DEFAULT 'meal'") unless cols.include?('course')
  end

  # ブロックに接続を渡して必ずクローズする。
  def open
    db = connect
    begin
      yield db
    ensure
      db.close
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  created = ChefDB.init!
  puts "DB ready: #{ChefDB::DB_PATH} (#{created ? 'created' : 'exists'})"
end
