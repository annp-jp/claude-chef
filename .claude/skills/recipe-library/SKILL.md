---
name: recipe-library
description: レシピマスタの登録・検索（/chef study, /chef menu）。URLからのレシピ抽出、対話的なレシピ入力、自然言語での検索を扱う。
---

# recipe-library

`recipes` テーブルへの追加・参照を行う。`scripts/recipe.py` を介して SQLite に書き込む。

## `/chef study [URL]`

レシピを 1 件登録する。

### URL が指定された場合

1. WebFetch で URL からページ本文を取得
2. ページから以下を抽出する:
   - `name`: 料理名
   - `ingredients`: 材料一覧。各要素は `{"name": "鶏もも肉", "amount": "300g", "category": "肉魚"}` の形。category は `肉魚 / 野菜 / 調味料 / その他` のいずれかに振り分ける（買い物リスト集約のキー）
   - `instructions`: 手順（簡潔に。任意）
   - `cook_time_min`: 調理時間目安（分）。書かれていなければ推定
   - `type`: `["主菜"]` / `["副菜"]` / `["汁物"]` のJSON配列（複数可）
   - `allergens`: 含むアレルゲン（卵・乳・小麦など）。JSON配列
   - `kids_ok`: 子供向けか（辛さ・硬さ等で判断）
3. 抽出結果をユーザーに見せて確認を取る（誤りがあれば修正）
4. 確認OKなら `ruby scripts/recipe.rb add --json '<payload>'` で登録
5. 登録された id と name を返す

### URL 省略時

対話で項目を順に埋める: 料理名 → 種別（主菜/副菜/汁物）→ 材料（複数行で受ける）→ 調理時間 → 子供OKか → アレルゲン → メモ。

材料は `name`, `amount`, `category` を確認しつつ JSON 化する。`category` が曖昧な場合は名称から推定して提示し、ユーザーに確認。

## `/chef menu [filter]`

レシピ一覧。filter は自然言語（例: 「卵を使った主菜」「30分以内」「鶏肉」）。

実装:
1. filter を観察し、SQL の LIKE 検索でカバーできるキーワード（材料名・料理名）を抽出
2. `ruby scripts/recipe.rb list --query <キーワード>` を実行
3. 返ってきた JSON を、ユーザーが指定した条件（「主菜」「30分以内」「子供OK」など）で Claude 側でフィルタしてから整形表示

表示は読みやすい一覧形式で:
```
[id] 名前 / 種別 / 調理時間
  材料: ...
  メモ: ...
```

件数が多い場合は最初の 10〜20 件 + 「他 N 件」と表示。
