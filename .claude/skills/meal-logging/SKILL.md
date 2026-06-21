---
name: meal-logging
description: 「今日これ作った」を記録する（/chef log）。料理名から recipe_id を解決して meal_log テーブルに追加する。
---

# meal-logging

`/chef log <料理名> [--date YYYY-MM-DD]` を処理する。

## 手順

1. ユーザーが指定した料理名を受け取る。複数指定もあり得る（主菜＋副菜など）
2. `ruby scripts/meal_log.rb add <料理名1> [料理名2 ...] [--date YYYY-MM-DD]` を実行
   - `--date` 省略時は今日
3. 結果 JSON を確認
   - `unresolved` が空でなければ、そのレシピが未登録。ユーザーに `/chef note` での登録を促す
   - 一部解決できた場合は、未解決分だけ別途登録するか、`--allow-unknown` で名前メモ付きで記録するかを確認
4. 記録できたら「YYYY-MM-DD dinner: <料理名> を記録したよ」とフレンドリーに返す

## 補助用途

献立提案の重複回避で「直近N日のレシピid」を取得するには:
```
ruby scripts/meal_log.rb recent-ids --days 21
```
これは `meal-planning` skill から呼ばれる想定。
