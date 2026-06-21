---
name: note
description: chef の知識を記録する（/chef note, /chef menu）。レシピマスタの登録（URL抽出/対話）と、定番商品（材料⇔ライフ実商品の紐づけ）の登録、レシピの自然言語検索を扱う。
---

# note

chef が知識を「ノートに書き留める」入口。`/chef note` は2種類の知識を記録する:

1. **レシピ** → `recipes` テーブル（`scripts/recipe.rb`）
2. **定番商品**（我が家の定番材料 ⇔ ライフネットスーパーの実商品）→ `store_products` テーブル（`scripts/catalog.rb`）

仕様: `docs/spec/catalog.md`

## `/chef note [...]` のディスパッチ

引数を見て、レシピ登録か定番商品登録かを判定する。**URL のホストで判定**するので曖昧さは出ない。

| 入力 | 動作 |
|---|---|
| `note <ライフ商品URL>` を含む（`life-netsuper.jp/product_detail/...`） | 定番商品の登録（直前のトークンがキー名） |
| `note catalog [...]` | 定番商品の一覧/削除（下記） |
| `note <その他URL>` | レシピ登録（URL抽出） |
| `note`（引数なし） | レシピ登録（対話） |

---

## レシピ登録: `/chef note [URL]`

レシピを 1 件登録する。

### URL が指定された場合

1. WebFetch で URL からページ本文を取得
2. ページから以下を抽出する:
   - `name`: 料理名
   - `course`: `meal`（食事）/ `dessert`（デザート）。スイーツ・お菓子系URLなら `dessert`、それ以外は `meal`。デフォルト `meal`
   - `ingredients`: 材料一覧。各要素は `{"name": "鶏もも肉", "amount": "300g", "category": "肉魚"}` の形。category は `肉魚 / 野菜 / 調味料 / その他` のいずれかに振り分ける（買い物リスト集約のキー）
   - `instructions`: 手順（簡潔に。任意）
   - `cook_time_min`: 調理時間目安（分）。書かれていなければ推定
   - `type`: `["主菜"]` / `["副菜"]` / `["汁物"]` のJSON配列（複数可）。`course='dessert'` のときは `[]` でよい
   - `allergens`: 含むアレルゲン（卵・乳・小麦など）。JSON配列
   - `kids_ok`: 子供向けか（辛さ・硬さ等で判断）
3. 抽出結果をユーザーに見せて確認を取る（誤りがあれば修正）
4. 確認OKなら `ruby scripts/recipe.rb add --json '<payload>'` で登録
5. 登録された id と name を返す

### URL 省略時

対話で項目を順に埋める: 料理名 → course（meal/dessert、デフォルト meal）→ 種別（主菜/副菜/汁物。dessert なら省略可）→ 材料（複数行で受ける）→ 調理時間 → 子供OKか → アレルゲン → メモ。

材料は `name`, `amount`, `category` を確認しつつ JSON 化する。`category` が曖昧な場合は名称から推定して提示し、ユーザーに確認。

---

## 定番商品登録: `/chef note <キー名> <ライフ商品URL>`

我が家の定番材料を、ライフネットスーパーの実商品と紐づけて覚える。
order のカート投入で**検索をスキップして直行**するためのヒント（保証ではない。URLが死んだら検索フォールバック）。

例:

```
/chef note 牛乳 https://www.life-netsuper.jp/product_detail/0000004151122
```

### 手順

1. URL から商品ページを WebFetch できれば取得し、**正式商品名**（`product_name`）を拾う
   （取れなければユーザーに「正式商品名わかる？」と聞く。空でも登録は可能）
2. 別名（`aliases`）を確認する。献立リストやついで買いで出てくる**呼び方の揺れ**を拾う
   （例: 牛乳 → `["明治おいしい牛乳","おいしい牛乳"]`）。不要ならスキップ
3. 内容を読み上げて確認 → OK なら登録:

   ```
   ruby scripts/catalog.rb add --json '{"name":"牛乳","aliases":["明治おいしい牛乳"],"product_name":"明治おいしい牛乳 1000ml","url":"https://www.life-netsuper.jp/product_detail/0000004151122","category":"その他"}'
   ```

   - `name` がキー（UNIQUE）。同名で再登録すると**指定した項目だけ更新**（未指定は既存維持）
   - `product_id` は url 末尾から自動抽出されるので渡さなくてよい
4. 結果（added / updated と product_id）を報告

## 定番商品の一覧・削除: `/chef note catalog [...]`

- `note catalog` → `ruby scripts/catalog.rb list` で一覧表示（読みやすく整形）
- `note catalog <キーワード>` → `ruby scripts/catalog.rb list --query <キーワード>` で絞り込み
- `note catalog rm <キー名>` → `ruby scripts/catalog.rb rm --name <キー名>` で削除

---

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
