// render.rb add_items で [[商品ID, 個数], ...] を埋め込んでから browser_run_code_unsafe の filename で実行する。
// 商品ページの「カートへ追加」を実座標で押し、実際に送られた AddToCart の商品 ID と grpc-status で成否を判定する。
// 実行中はボタンが画面外にならないよう縦長にし、終わったらウィンドウの大きさに戻す（戻さないとページがスクロールできなくなる）。
async (page) => {
  const items = /*ARGS*/null;
  const bytes = (buf) => Array.from(new Uint8Array(buf || [])).map((c) => String.fromCharCode(c)).join('');
  const original = await page.evaluate(() => ({ w: window.outerWidth, h: window.outerHeight }));
  await page.setViewportSize({ width: 1024, height: 1400 });

  const addOnce = async (productId) => {
    await page.goto('https://www.life-netsuper.jp/product_detail/' + productId);
    await page.evaluate(() => document.querySelector('#enable_accessibility, flt-semantics-placeholder')?.click());
    // 関連商品の「＋」も同名なので DOM 順で先頭（メイン商品）を押す。誤爆は商品 ID の照合で検知する
    const button = page.getByRole('button', { name: 'カートへ追加', exact: true }).first();
    try { await button.waitFor({ timeout: 10000 }); } catch { return 'カートへ追加ボタンが無い（在庫なし・販売終了の可能性）'; }
    await page.waitForTimeout(500); // semantics の位置が canvas に追いつくのを待つ
    const box = await button.boundingBox();
    const vp = page.viewportSize();
    if (!box || box.y < 0 || box.y + box.height > vp.height) return 'ボタンが画面外 y=' + box?.y;
    try {
      const [request] = await Promise.all([
        page.waitForRequest((r) => r.url().endsWith('/stailer.ShopService/AddToCart'), { timeout: 10000 }),
        page.mouse.click(box.x + box.width / 2, box.y + box.height / 2),
      ]);
      const response = await request.response();
      const grpc = Number(response.headers()['grpc-status'] ?? bytes(await response.body()).match(/grpc-status:\s*(\d+)/)?.[1]);
      const sent = bytes(request.postDataBuffer()).includes(productId);
      if (response.status() !== 200 || grpc !== 0) return `失敗 http=${response.status()} grpc=${grpc}`;
      if (!sent) return '別の商品が送られた可能性（カートを確認）';
      return null;
    } catch (e) {
      return 'AddToCart が飛ばなかった: ' + e.message.slice(0, 80);
    }
  };

  const results = [];
  try {
    for (const [productId, qty] of items) {
      let added = 0;
      let error = null;
      while (added < qty) {
        error = await addOnce(productId);
        // 1回だけやり直す。別の商品が入った可能性があるときは二重投入を避けてやり直さない
        if (error && !error.startsWith('別の商品')) error = await addOnce(productId);
        if (error) break;
        added += 1;
      }
      results.push({ product_id: productId, qty, added, ok: added === qty, error: error || undefined });
    }
  } finally {
    await page.setViewportSize({ width: original.w, height: Math.max(600, original.h - 90) });
  }
  return results;
}
