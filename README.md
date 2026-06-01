# claude-chef

我が家の夕飯の献立を考えてくれるシェフ。Claude Code 上で `/chef` スラッシュコマンドとして動作する。

レシピマスタの管理、1週間の献立提案、買い物リスト生成までを統合的に扱う。詳細な設計思想は [`docs/spec/spec.md`](docs/spec/spec.md) を参照。

## 必要環境

- [Claude Code](https://docs.claude.com/claude-code)
- Ruby 3.0 以上（macOS 標準で OK）
- `sqlite3` gem
  ```sh
  gem install sqlite3
  ```

## セットアップ

```sh
git clone git@github.com:katsumata-ryo/claude-chef.git
cd claude-chef
```

Claude Code をこのディレクトリで起動すると、`.claude/commands/chef.md` がスラッシュコマンドとして、`.claude/skills/*` が skill として読み込まれる。

初回はシェフを迎え入れる:

```
/chef onboard
```

`data/chef.db` が作成される。続けて家族構成・アレルギー・曜日ルールを書き込む:

```
/chef brief
```

## コマンド

| コマンド | 説明 |
|---|---|
| `/chef onboard` | DB 初期化 |
| `/chef brief` | 家族・アレルギー・曜日ルールの閲覧／編集 |
| `/chef study [URL]` | レシピを登録（URL から抽出 or 対話） |
| `/chef menu [filter]` | レシピ一覧・検索 |
| `/chef log <料理名> [--date YYYY-MM-DD]` | 「今日これ作った」を記録 |
| `/chef plan` | 来週の献立提案（対話で調整） |
| `/chef plan apply` | 確定 → Googleカレンダー登録 + meal_log 記録 |
| `/chef order list` | 直近の確定献立から仕入れリスト生成（旧 `/chef buy`） |
| `/chef order` | ライフネットスーパーのカートに自動発注（Playwright MCP） |

`/chef order` は決済しない（カート投入＋配送枠確保まで）。`/chef order settlement`（決済）は未実装。

### ローカル設定

環境別の値は `config/chef.local.yml`（gitignore）に置く。雛形をコピーして自分の値を埋める:

```sh
cp config/chef.local.yml.example config/chef.local.yml
```

- `calendar_id`: Googleカレンダーの登録先
- `life_netsuper.op_item`: ライフのログイン情報の 1Password 参照（`op://vault/item-id`）

## 構成

```
.claude/
  commands/chef.md          # /chef スラッシュコマンド（ルーター）
  skills/
    recipe-library/         # study, menu
    meal-logging/           # log
    meal-planning/          # plan, plan apply
    order/                  # order, order list（ネットスーパー発注）
scripts/                    # Ruby + sqlite3。各 skill から呼ばれる
  chef_db.rb                # スキーマ・接続
  config.rb                 # ローカル設定（config/chef.local.yml）読み込み
  brief.rb                  # household/allergies/rules
  recipe.rb                 # recipes CRUD
  meal_log.rb               # meal_log
  meal_plan.rb              # meal_plans（候補抽出・draft・apply）
  shopping.rb               # 仕入れリスト集約
config/chef.local.yml       # 環境別設定（gitignore）
data/chef.db                # SQLite 本体（gitignore）
docs/spec/spec.md           # 仕様書
```

skill ごとにファイルを分離してあるので、Claude Code は呼び出し時に必要な skill だけを読み込み、コンテキストを節約する。

## データモデル

詳細は spec.md を参照。要点だけ:

- `recipes`: レシピマスタ。`ingredients` は `{name, amount, category}` の JSON 配列
- `meal_log`: 実際に作った料理の記録。重複回避（先週も食べた防止）の参照元
- `meal_plans`: 確定済み献立のアーカイブ（draft / applied）
- `household` / `allergies` / `rules`: 献立生成時のコンテキスト

アレルギーは `severity` で扱いが変わる:

- `アレルギー` → ハードフィルタ（**絶対に提案しない**）
- `苦手` → ソフトフィルタ（できるだけ避ける）

## 開発フェーズ

- **フェーズ1**: データ基盤（onboard, brief, study, menu, log）← 実装済
- **フェーズ2**: 献立生成（plan, plan apply）← 実装済
- **フェーズ3**: 仕入れリスト（order list、旧 buy）← 実装済
- **フェーズ4**: カート自動投入（order）← 実装済
- **フェーズ5**: 決済（order settlement）← 未着手

## ライセンス

個人利用向けプロジェクト。
