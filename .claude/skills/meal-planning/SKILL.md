---
name: meal-planning
description: 来週の献立を提案・確定する（/chef plan, /chef plan apply）。履歴・アレルギー・曜日ルールを踏まえた提案、対話的な修正、Googleカレンダー登録までを担う。
---

# meal-planning

## `/chef plan`

来週（翌週月曜〜金曜 5日分、dinner のみ）の献立を提案する。

### 提案フロー

1. `ruby scripts/meal_plan.rb context` を実行して、以下を一括取得:
   - 対象週の月曜日 (`week_start`)
   - `household`（家族構成・食事メモ・週パターンヒント）
   - `allergies`（hard: ハードフィルタ済 / soft: ソフトフィルタ）
   - `rules`（曜日ルール）
   - `recent_recipe_ids` と `recent_days`（直近3週間）
   - `candidates`（**ハードアレルギー除外済の dinner レシピ全件**、`recently_used` フラグ付き）
2. 候補から平日5日分を組み立てる:
   - **直近3週間で使ったレシピ（`recently_used=true`）は避ける**
   - **曜日ルールに従う**（例: 月=魚、水=麺類）
   - **苦手食材はできるだけ回避**
   - **`weekly_pattern_hint`** を反映（金曜は凝ったもの可、平日は時短など）
   - 各日に主菜＋副菜（必要なら汁物）の組み合わせを選ぶ
3. 候補が薄い場合（レシピ数不足）はその旨を率直に伝え、`/chef study` で追加するか提案する
4. ユーザーに提示し、要望（自然言語）を受けて対話的に修正

### 提示フォーマット例

```
来週（5/18〜5/22）の献立提案だよ:

月: 鮭の塩焼き + ほうれん草のおひたし + 味噌汁
火: 肉じゃが + 冷奴
水: 鶏南蛮うどん + 小鉢
木: ハンバーグ + サラダ
金: 豚の生姜焼き + キャベツ千切り

要望ある？（時短にしたい、別の魚がいい、など何でも）
```

### draft 保存

### plan_json の形式

主経路・副経路どちらも同じ `plan_json` を使う:

```json
{
  "week_start": "2026-05-18",
  "days": [
    {"date": "2026-05-18", "label": "月", "recipe_ids": [12, 7, 3], "comment": "魚の日"},
    {"date": "2026-05-19", "label": "火", "recipe_ids": [22, 5]},
    ...
  ],
  "notes": "金曜は少し凝ったもの"
}
```

`recipe_ids` は `context` の `candidates` から拾った id を使う（ユーザーが新規レシピを指定した場合は先に `/chef study` で登録）。

### 副経路: draft 保存（任意）

確定はまだだけど案を残しておきたい時だけ使う。通常フローでは不要。

```
ruby scripts/meal_plan.rb save-draft --json '<JSON>'
```

draft を保存しておけば、後で `apply --week-start <YYYY-MM-DD>` で `--json` なしに確定できる。

## `/chef plan apply`（主経路）

**対話で詰めた献立をそのまま確定する**のが主経路。draft 保存は不要で、`apply --json` に組み上げた `plan_json` を直接渡す。**副作用を伴う不可逆操作**なので、実行前に必ず:

1. 組み上げた献立（week_start と日別献立）を読み上げて「これでカレンダー登録して meal_log にも記録するけどOK?」と最終確認
   - （既に draft 保存済みでそれを確定する副経路なら、先に `ruby scripts/meal_plan.rb show` で対象を表示）
2. ユーザーが OK したら以下を順に実行:
   - **Googleカレンダー登録**: `mcp__claude_ai_Google_Calendar__*` 系ツールが利用可能なら、各日付の献立を「終日予定（all-day event）」として登録する。時刻指定はせず、`start`/`end` を日付（`YYYY-MM-DD`）で渡して終日扱いにすること。登録先カレンダーは `config/chef.local.yml` の `calendar_id`（`ruby scripts/config.rb calendar-id` で取得。未設定なら `primary` を使うかユーザーに確認）。イベント名はその日の料理名（複数なら「主菜 + 副菜 + 汁物」のように連結）。MCPが未認証ならその旨を伝え、認証後に再実行するよう案内
   - **DB確定**:
     - 主経路（直接確定）: `ruby scripts/meal_plan.rb apply --json '<JSON>'`
       - meal_plans 行が無ければ作成し、applied に昇格 + 各日を meal_log に記録する
     - 副経路（draft 確定）: `ruby scripts/meal_plan.rb apply --week-start <YYYY-MM-DD>`
4. 結果をユーザーに報告（カレンダー登録件数、meal_log 記録件数）

カレンダー登録に失敗した場合は DB apply を実行する前に止めて、ユーザーに状況を伝える。
