// render.rb search で検索語を埋め込んでから browser_run_code_unsafe の filename で実行する。
// 前のページの応答は次のページへ移ると取れなくなるので、検索ごとにその場で解読して返す。
// 実行環境には TextDecoder / Buffer / require が無い。解読は scripts/life_netsuper.rb と同じ仕様。
async (page) => {
  const words = /*ARGS*/null;
  const isSearch = (r) => r.url().endsWith('/stailer.ShopService/SearchEcProductsWithKeyword');

  const utf8 = (b) => {
    let s = '', i = 0;
    while (i < b.length) {
      const c = b[i++];
      let cp;
      if (c < 0x80) cp = c;
      else if (c < 0xe0) cp = ((c & 0x1f) << 6) | (b[i++] & 0x3f);
      else if (c < 0xf0) cp = ((c & 0x0f) << 12) | ((b[i++] & 0x3f) << 6) | (b[i++] & 0x3f);
      else cp = ((c & 0x07) << 18) | ((b[i++] & 0x3f) << 12) | ((b[i++] & 0x3f) << 6) | (b[i++] & 0x3f);
      s += String.fromCodePoint(cp);
    }
    return s;
  };
  const varint = (b, p) => { let v = 0, s = 0, x; do { x = b[p++]; v += (x & 0x7f) * 2 ** s; s += 7; } while (x >= 0x80); return [v, p]; };
  const parse = (b) => {
    const f = {}; let p = 0;
    while (p < b.length) {
      let k; [k, p] = varint(b, p);
      const n = Math.floor(k / 8), t = k & 7; let v;
      if (t === 0) [v, p] = varint(b, p);
      else if (t === 1) { v = new DataView(b.buffer, b.byteOffset + p, 8).getFloat64(0, true); p += 8; }
      else if (t === 2) { let l; [l, p] = varint(b, p); v = b.subarray(p, p + l); p += l; }
      else if (t === 5) { v = null; p += 4; }
      else throw new Error('unsupported wire type ' + t);
      (f[n] ||= []).push(v);
    }
    return f;
  };
  const str = (v) => (v ? utf8(v) : '');
  const products = (buf) => {
    const b = new Uint8Array(buf);
    if (b.length < 5 || b[0] & 0x80) return [];
    const len = (b[1] << 24) | (b[2] << 16) | (b[3] << 8) | b[4];
    return (parse(b.subarray(5, 5 + len))[1] || []).map((m) => {
      const f = parse(m);
      let est;
      if (f[70]) { const g = parse(f[70][0]); if (g[3]) est = Number(str(parse(g[3][0])[1]?.[0])) || undefined; }
      return {
        id: str(f[2]?.[0]),
        name: str(f[3]?.[0]),
        size: str(f[69]?.[0]) || undefined,
        tax: f[9] ? Math.round(f[9][0]) : undefined,
        est_tax: est,
        per100g: f[68]?.[0],
        oos: f[10]?.[0] === 1,
      };
    });
  };

  const out = {};
  for (const w of words) {
    const bodies = [];
    const onRes = async (r) => { if (isSearch(r)) { try { bodies.push(await r.body()); } catch {} } };
    page.on('response', onRes);
    try {
      await Promise.all([
        page.waitForResponse(isSearch, { timeout: 20000 }),
        page.goto('https://www.life-netsuper.jp/product_search_results?keyword=' + encodeURIComponent(w)),
      ]);
      await page.waitForTimeout(2500); // スクロールで追加ページが呼ばれるのを待つ
    } catch {
      out[w] = { error: 'timeout' };
      page.off('response', onRes);
      continue;
    }
    page.off('response', onRes);
    const seen = new Set();
    out[w] = bodies.flatMap(products)
      .filter((p) => !p.oos && !seen.has(p.id) && seen.add(p.id))
      .map(({ oos, ...p }) => p);
  }
  return out;
}
