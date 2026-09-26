// browser_run_code_unsafe の filename で実行する。事前に /product_search_results?keyword=<語> を開いておくこと。
// 検索 API の応答が届くまで待つ（navigate は応答前に返るため）。body の保存は browser_network_request で行う。
async (page) => {
  const isSearch = (r) => r.url().endsWith('/stailer.ShopService/SearchEcProductsWithKeyword');
  const [response] = await Promise.all([
    page.waitForResponse(isSearch, { timeout: 15000 }),
    page.reload(),
  ]);
  return { ok: response.status() === 200, keyword: decodeURIComponent(page.url().split('keyword=')[1] ?? '') };
}
