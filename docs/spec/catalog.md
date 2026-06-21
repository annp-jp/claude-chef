# 定番商品カタログ & `study`→`note` リネーム — v0.1

我が家の「定番材料」を、ライフネットスーパーの実商品（URL/商品ID）と紐づけて
記録しておく仕組み。`/chef order` のカート投入で「毎回ゼロから検索する」コストを
減らすのが目的。あわせて、知識を貯める入口コマンドを `study`（学習する）から
`note`（記録する）にリネームする。

このドキュメントは 2段構えの計画のうち **1段目（商品情報を持てるようにする）** の確定仕様。
2段目（order フローの変更）は別途追記する。

---

## 背景 — order の3つの課題

実機検証（`order/v0.3.md`）で確定した、カート投入時の痛み:

1. **Flutter に阻まれ商品を見つけられない**ことがある（semantics と canvas の desync）
2. **定番があるのに別商品を入れてしまう**（例: 牛乳でいつものでないものを選ぶ）
3. **MCP 操作が遅く**、検索→目視→選択→クリックの往復で時間がかかる

→ 「この材料はこの商品」と**一意に決まっているものを紐づけ**ておけば、
order 時に検索フェーズを丸ごとスキップでき、3つすべてに効く。

## 設計思想

### カタログは「保証」ではなく「ヒント／ショートカット」

商品ページは終売・リニューアル・在庫変動で**URLが死ぬ可能性がある**。
よってカタログは絶対的な参照先ではなく、あくまで近道のヒントとして扱う:

- 紐づけが**ある** → まずその URL に直行（速い・誤選択なし）
- URL が死んでいる / 商品名が画面と食い違う → **GUI 検索にフォールバック**（従来フロー）

この二段構え（ある→直行、無い/死んでる→検索）の挙動は **2段目（order フロー）** で実装する。
1段目では「持てるようにする」までを担う。

### 入口は `note`（記録する）

`chef` は知識を貯めていくキャラクター。これまで `study`（学習する）でレシピを覚えてきたが、
**レシピも定番商品も「ノートに書き留める」** という統一メタファーに寄せ、`note` にリネームする。

```
chef note <レシピURL>                              # レシピを記録（旧 study）
chef note                                          # 対話でレシピ記録（旧 study 対話）
chef note 牛乳 https://www.life-netsuper.jp/product_detail/0000004151122   # 定番商品を記録
chef note catalog                                  # 定番商品の一覧
chef note catalog rm 牛乳                           # 定番商品の削除
```

- **ディスパッチは URL のホストで判定**する。`life-netsuper.jp/product_detail/...` を含むなら
  定番商品の登録（直前のトークンがキー名）、それ以外の URL ならレシピ抽出。曖昧さが出ない。
- `/chef menu`（レシピ検索）は変更なし。
- 旧 `study` は廃止（後方互換は持たない。打ったら note を案内）。

## データモデル

`store_products` テーブルを追加する。1行 = 1定番商品。

| カラム | 型 | 例 | 用途 |
|---|---|---|---|
| `id` | INTEGER PK | | |
| `name` | TEXT UNIQUE | `牛乳` | 献立リスト／ついで買いとの**照合キー** |
| `aliases` | TEXT(JSON配列) | `["明治おいしい牛乳","おいしい牛乳"]` | 別名でも照合できる |
| `product_name` | TEXT | `明治おいしい牛乳 1000ml` | 直行時の**照合**＆死亡時の**検索キーワード** |
| `product_id` | TEXT | `0000004151122` | ライフの商品ID（URLの末尾） |
| `url` | TEXT | `https://www.life-netsuper.jp/product_detail/0000004151122` | 直行先 |
| `category` | TEXT | `その他` | 補助（任意） |
| `note` | TEXT | | 補助（任意） |
| `created_at` / `updated_at` | DATETIME | | |

- `name` を UNIQUE にし、同名は upsert（更新）。
- `url` から `product_id` を抽出して保存（URL だけ渡されても両方埋まる）。

### 照合ロジック（`catalog match`）

献立リストやついで買いの項目名から、対応する定番商品を引くための照合。

1. 正規化（前後空白除去・全半角揺れの吸収程度）した上で、`name` と各 `alias` を突き合わせる
2. 完全一致を優先（`match: "exact"`）、無ければ部分一致（`match: "partial"`）を返す
3. ヒットしなければ `null`（order は検索フォールバックへ）

照合の**消費は 2段目**（order / shopping）。1段目では `catalog match` を提供するところまで。

## スクリプト

- **`scripts/catalog.rb`** を新設（定番商品 CRUD のバックエンド）:
  - `add --json '<payload>'` — name 必須。url から product_id を補完。name 既存なら更新
  - `list [--query STR]` — 一覧（query は name/aliases/product_name の LIKE）
  - `rm --name STR` / `rm --id N` — 削除
  - `match --name STR` — 照合結果 JSON（exact/partial/null）を返す
- `scripts/recipe.rb` はレシピ専用のまま（変更なし）。
- skill `note`（旧 `recipe-library`）が URL ホストで recipe.rb / catalog.rb を出し分ける。

## 1段目の作業範囲

- [ ] `store_products` テーブル追加（`chef_db.rb`）
- [ ] `scripts/catalog.rb` 新設（add/list/rm/match）
- [ ] skill `recipe-library` → `note` にリネーム、定番商品の登録手順を追記
- [ ] `study` 参照を `note` に更新（`chef.md` / README / 各 SKILL.md / `meal_log.rb` 等）

**2段目（別途）**: order フローに「買い物リスト調整」ステップを追加（家にある物を抜く／献立外を足す、
DBに永続化）、order のカート投入をカタログ直行＋検索フォールバックの二段構えにする。
