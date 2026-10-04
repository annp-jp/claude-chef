---
name: order
description: 確定済み献立の材料をライフネットスーパーのカートに自動投入する（/chef order）。仕入れリスト表示（/chef order list）も担う。Playwright MCP でブラウザ操作する。
---

# order

レストランの Chef が仕入れ業者に「発注」する世界観のドメイン。
applied 済み献立の材料を、ネットスーパー「ライフ」のカートに自動投入する。**決済はしない。**

| コマンド | 動作 |
|---|---|
| `/chef order` | ライフのカートに発注（カート投入＋配送枠確保）← 中心 |
| `/chef order list` | 仕入れリスト（発注書）を表示 |
| `/chef order settlement` | 決済（**未実装**。「決済はまだ手動でね」と返す） |

応答は「我が家のシェフ」キャラで。コマンドは `order` だが、口では「発注しとくね」「仕入れリストはこれ」と喋る。

---

## `/chef order list`

直近の確定献立から仕入れリストを生成して表示する（旧 `/chef buy`）。

### 手順

1. `ruby scripts/shopping.rb build` を実行
   - 引数なしで「直近の applied 献立」を自動選択。特定週は `--week-start YYYY-MM-DD`
2. 返ってきた JSON（`categories` がカテゴリ別集計）をユーザー向けに整形して表示
   - 各品目の `pantry: true` は常備品（`config/chef.local.yml` の `order.pantry_categories` / `pantry_items`）。買わずに「※在庫確認」に回す
   - `note` があれば品目の横に添える（例: たけのこ → 水煮）

### 出力フォーマット

```
今週（6/1〜6/5）の仕入れリスト:

【肉魚】
- 鮭の切り身  4切れ
- 鶏もも肉    400g

【野菜】
- ほうれん草  1束

【その他】
- 豆腐 1丁

※在庫確認（常備品なので買わないよ）
- 味噌 / しょうゆ / だし
```

注意:
- 同じ食材が複数レシピで使われる場合、`shopping.rb` 側で `+` 合算済（例: `200g + 200g`）。完全な数値合算はしない
- 「確定済み献立がない」エラーが返ってきたら `/chef plan apply` を案内
- 「水」「お湯」など買う対象にならないものは `shopping.rb` 側で除外済み
- 今回だけ家にある、などで外したい品目はユーザーに言ってもらい、その回だけ除く（毎回なら `pantry_items` への追加を提案する）

---

## `/chef order`

ライフネットスーパーで、仕入れリストの商品を選んでカートに入れる。**Playwright MCP でブラウザを操作し、商品の情報は画面ではなく通信から読む。**
途中で逐一確認せず自走し、迷ったもの・見つからなかったものは最後の完了報告でまとめて伝える。

### 役割分担

- **Ruby スクリプト**: 発注リスト（`shopping.rb`）、設定（`config.rb order`）、通信のデコード（`life_netsuper.rb`）。ブラウザは触らない
- **Playwright MCP（あなた）**: ログイン・配送枠・検索・カート投入
- **あなたの判断**: どの商品を入れるか（`config.rb order` の選定ルールに従う）

### ⚠️ サイト操作の大前提（ライフは Flutter Web 製）

画面は canvas 描画で、DOM も semantics ツリーも画面とずれる（`docs/spec/order/v0.3.md`）。
代わりに、画面が裏で呼んでいる Stailer の API（`rpc.stailer.jp`）の**応答を読む**（`docs/spec/order/v0.4.md`）。

- **読む**: 検索結果・在庫・価格は `scripts/playwright/search.js` が検索 API の応答をその場で解読して返す。スクショの目視で在庫を判断しない
  - 前のページの応答は次のページへ移ると取れなくなるので、`browser_network_request` で後から保存する方式は使わない
- **押す・確かめる**: カート追加は `scripts/playwright/add_items.js`。実座標でクリックし、実際に送られた `AddToCart` の商品 ID と `grpc-status` で成否を判定する
- `browser_run_code_unsafe` の filename 実行には引数を渡せないので、`ruby scripts/playwright/render.rb <search|add_items> '<JSON配列>'` で引数を埋め込んだ実行用ファイルを `.playwright-mcp/` に書き出してから実行する
- 実行環境には `URL` / `TextDecoder` / `Buffer` / `require` が無い
- 認証トークンには触らない。リクエストはすべてブラウザ自身に送らせる
- ビューポートは `add_items.js` が実行中だけ縦長にし、終わったら固定を解いてウィンドウの大きさに追従させる（`page.setViewportSize` は使わない。固定が残り、ユーザーがウィンドウを変えても表示が追従しなくなる）

### 手順

#### 0. 発注リストと設定の取得

1. `ruby scripts/shopping.rb build` を実行し JSON を取得
2. `pantry: false` の品目が**カート投入対象**。`pantry: true`（常備品）は投入せず、最後の「在庫確認リスト」に回す
3. 投入対象を一覧で見せ、「今回買わなくていいものある？」と聞いてその回だけ除く（毎回同じなら `pantry_items` への追加を提案）
4. 各商品の `amount`（必要量）・`dishes`（使用料理名）・`note`（品目ごとの指定）は検索と判定の材料にする
5. `ruby scripts/config.rb order` で選定ルール（`selection_rules`）と最低注文金額（`minimum_order_yen`）を取得。
   未設定エラーなら「`config/chef.local.yml` に `order.selection_rules` を設定してね（`.example` 参照）」と案内して終了
6. 投入対象が空、または「確定済み献立がない」なら、その旨を伝えて終了（`/chef plan apply` を案内）

#### 0.5 ついで買いの確認（献立外の追加品）

1. リスト取得後に**必ず聞く**: 「ついでに買うものある？（朝ごはんとか）」
2. 自由入力の答え（例: `バナナ、牛乳4本、超熟山形6枚切り、ウインナー`）をカート投入対象にマージする
   - `dishes` は無し。**数量指定があれば尊重**（「牛乳4本」→ 4個）、指定なしは1個
   - 商品名に含まれる規格（「6枚切り」など）は判定に使う
3. 「ない／なし」ならスキップ

#### 1. 認証情報の取得

- `ruby scripts/config.rb life-op-item` で 1Password 参照（`op://...`）を取得
- `op read "<op_item>/username"` と `op read "<op_item>/password"` で実値を取得
- 未設定エラーなら「`config/chef.local.yml` に `life_netsuper.op_item` を設定してね（`.example` 参照）」と案内して終了

> 注意: パスワードは 1Password から都度取得し、ブラウザ入力に使うだけ。ファイルやログに残さない。

#### 2. ログイン

1. `browser_navigate` で https://www.life-netsuper.jp を開く。`browser_take_screenshot` でログイン状態を確認
   （右上が「ログイン」ボタンなら未ログイン）
2. **未ログイン** → https://www.life-netsuper.jp/introduction/login を開く
   - 画面が空なら `#enable_accessibility` を click して semantics を有効化（フォーム入力のため）
   - username / password を入力 → ログインボタンを押す
   - **1回目クリックが無反応のことがある**。URL が `/`（トップ）へ変わらなければ**リトライ**する
   - ログイン失敗時は、その旨を伝えて中断（認証情報の確認を促す）

#### 3. 配送枠の確保（ライフ仕様上、注文前に必須）

1. https://www.life-netsuper.jp/delivery_select を開き、スクショで予約可能な枠（`受付中` の日付・時間帯）を読み取る
2. 予約可能な枠を**対話で提示** → ユーザーに選んでもらう（ここだけは必ず聞く）
3. 枠を選択 →「受け取り日時を設定」で確保。**確保は1時間だけ**なので、以降は止まらずに進める
   - 既に枠が確保済みなら、現在の枠を伝えて「このままでいい？」と確認

#### 4. 注文履歴（いつもの商品）の取得

トップページを開くと `OrderService/ListPastOrderHistories` が呼ばれる。
`browser_network_requests`（filter: `ListPastOrderHistories`）の最新を `response-body` で保存し、
`ruby scripts/life_netsuper.rb past-products <file>` で `{ 商品ID => 回数 }` を得る。
商品名は入っていないので、候補一覧の商品 ID と突き合わせて「いつもの」を判定する（取りこぼしはある）。

#### 5. 検索（全品の候補を先に集める）

カート投入対象の全項目について検索語を決め（材料名。規格・ブランドや `note` の指定があれば含める。例: たけのこ → `たけのこ 水煮`）、**1回でまとめて**検索する:

1. `ruby scripts/playwright/render.rb search '["ぶり","豚こま","牛乳"]'`
2. `browser_run_code_unsafe`（filename: `.playwright-mcp/search.js`）
   → `{ 検索語: [ { id, name, size, tax(税込), est_tax(グラム売りの目安・税込), per100g }, ... ] }`（在庫ありのみ）
3. 在庫ありの候補が 0 件、または明らかに関係ない商品しかない語は、言い換えて**1回だけ**同じ手順で再検索する。それでもなければ「見つからなかった」に回す

#### 6. 判定（全品まとめて）

集めた候補を見て、**`selection_rules` に上から従って**各項目の商品と個数を決める。

- 個数は複数でもよく、別の商品と組み合わせてもよい。量の満たし方や組み合わせの可否も `selection_rules` に従う
- ルールどうしがぶつかって決められないときは、その項目を「確認待ち」にして完了報告で聞く
- ルールが報告を求めているもの（例: いつものより安い候補）は完了報告用にメモする
- ついで買いの数量指定はそのまま個数にする
- 選んだ理由を1行でメモしておく（完了報告で使う）

#### 7. カート投入

選んだ全商品を**1回でまとめて**入れる:

1. `ruby scripts/playwright/render.rb add_items '[["<商品ID>",<個数>],...]'`
2. `browser_run_code_unsafe`（filename: `.playwright-mcp/add_items.js`）
   → `[ { product_id, qty, added, ok, error? }, ... ]`。失敗は中で1回だけやり直し済み
3. `ok: false` は「入れられなかった」に回す。`error` が「別の商品が送られた可能性」のときはカートを確認して報告する
4. https://www.life-netsuper.jp/cart を開き、スクショで「商品点数」と「商品合計」を確認する
   （商品一覧は画面内で別にスクロールする。点数が合っていれば一覧の目視は不要）

#### 8. 完了報告（出力のみ。DB には保存しない）

```
発注作業おわったよ！

✅ カートに追加できたもの（献立分）:
- 豚バラ 400g → 米国産等豚バラ切りおとし 290g ＋ 国内産豚バラうす切り 110g（400g ちょうどが無いので組み合わせ）
- 超熟 山型 6枚切り → パスコ 超熟山型 6枚（いつもの）
- なす 3本 → 国内産 なす(3本) 1袋

🧺 ついで買い:
- 牛乳 ×4 → スマイルライフ あじわい牛乳 1000ml

💡 いつものより安い候補もあったよ:
- 超熟 山型 → ◯◯ 198円（いつもの 236円）

⚠️ 見つからなかった／入れられなかったもの（手で探してみて）:
- ◯◯

🧂 在庫確認してね（調味料は自動で入れてないよ）:
- 味噌

配送枠: 9/27(日) 11:00〜14:00 で確保したよ。
商品合計 ¥1,849（税抜）。最低注文金額 ¥2,000 まであと ¥151 だよ。
決済はまだ手動でお願い！
```

- 追加できたもの → 項目名 → 実際に入れた商品名（組み合わせ・いつもの などの理由を括弧で）
- 最低注文金額（`minimum_order_yen`）に届いていなければ、あと何円かを必ず書く
- 在庫確認 → `pantry: true` の項目

### 注意

- 決済・購入確定はしない（`order settlement` は未実装）
- カートの数量を減らす・消す操作は API が未調査。やり直しで二重に入れないよう、投入前にカートの中身を確認してよい
- ブラウザ操作中にサイト構造で詰まったら、無理に進めず状況をユーザーに伝えて判断を仰ぐ
- 通信の形式や判定の比較は `docs/spec/order/v0.4.md`（部品）/ `v0.5.md`（Jev と Claude の比較）
