// browser_run_code_unsafe の filename で実行する。事前に /product_detail/<商品ID> を開いておくこと。
// 「カートへ追加」を押し、実際に飛んだ AddToCart の中身で成否を判定する（画面は見ない）。
async (page) => {
  const productId = page.url().match(/\/product_detail\/(\d+)/)?.[1];
  if (!productId) return { ok: false, error: `not a product_detail page: ${page.url()}` };

  // Flutter の semantics は既定で無効。ボタンを名前で探すために有効化する
  await page.evaluate(() => document.querySelector('#enable_accessibility, flt-semantics-placeholder')?.click());
  // 関連商品の「＋」も同名なので、DOM 順で先頭（メイン商品）を押す。誤爆は sent_product_id_matches で検知する
  const button = page.getByRole('button', { name: 'カートへ追加', exact: true }).first();
  try {
    await button.waitFor({ timeout: 10000 });
  } catch {
    return { ok: false, product_id: productId, error: 'カートへ追加ボタンが見つからない（在庫なし・販売終了の可能性）' };
  }

  // semantics 要素を click() すると Playwright が DOM だけスクロールして canvas とずれる。
  // スクロール不要な位置にあるときだけ、その座標を実マウスで押す
  const box = await button.boundingBox();
  const viewport = page.viewportSize();
  if (!box || box.y < 0 || box.y + box.height > viewport.height) {
    return { ok: false, product_id: productId, error: `ボタンが画面外（y=${box?.y}）。ビューポートを縦に広げて開き直して` };
  }
  const [request] = await Promise.all([
    page.waitForRequest((r) => r.url().endsWith('/stailer.ShopService/AddToCart'), { timeout: 10000 }),
    page.mouse.click(box.x + box.width / 2, box.y + box.height / 2),
  ]);
  const response = await request.response();
  const body = await response.body();
  const grpcStatus = Number(response.headers()['grpc-status'] ?? body.toString('latin1').match(/grpc-status:\s*(\d+)/)?.[1]);
  const sentId = request.postDataBuffer()?.toString('latin1').includes(productId);

  return {
    ok: response.status() === 200 && grpcStatus === 0 && sentId === true,
    product_id: productId,
    sent_product_id_matches: sentId,
    http_status: response.status(),
    grpc_status: grpcStatus,
  };
}
