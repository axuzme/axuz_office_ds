// test.js — equivalencia fonts.wasm (ours, do fonte) x fonts.wasm (upstream do sdkjs): metricas, bitmaps, kerning, shaping.
// O QUE: carrega os dois modulos pelo PROPRIO glue (fonts.js de cada um) num vm com stubs de browser, roda o MESMO roteiro
//   em ambos (FreeType via ASC_FT_*, HarfBuzz via ASC_HB_ShapeText) e compara por hash (sha1 por item).
//   Tambem confere: todo Module["_X"] que o JS do sdkjs usa existe no glue de ours e aponta para export real do wasm.
// ONDE: roda em node dentro do container emscripten (offline), chamado por test.sh.
// Args: oursDir upstreamDir sdkjsDir fontsDir listFile [--red]   (listFile = caminhos de fonte relativos a fontsDir)
"use strict";
const fs = require("fs");
const vm = require("vm");
const path = require("path");
const crypto = require("crypto");

const [oursDir, upDir, sdkjsDir, fontsDir, listFile] = process.argv.slice(2, 7);
const RED = process.argv.includes("--red");

/** O que: hash curto de bytes. Onde: resumo de cada item comparado. */
function sha(u8) {
  return crypto.createHash("sha1").update(u8).digest("hex").slice(0, 12);
}

/** O que: carrega um par glue+wasm num vm e devolve {M: Module, src, wasmExports}. Onde: uma vez por lado (ours/upstream). */
async function load(dir) {
  const wasm = fs.readFileSync(path.join(dir, "fonts.wasm"));
  let src = fs.readFileSync(path.join(dir, "fonts.js"), "utf8");
  const re = /var Module\s*=\s*typeof Module\s*!=\s*"undefined"\s*\?\s*Module\s*:\s*\{\s*\};/;
  if (!re.test(src)) throw new Error("glue sem 'var Module=...' reconhecivel em " + dir);
  src = src.replace(re, "var Module=window.__M={};");
  let ready;
  const done = new Promise((r) => { ready = r; });
  const ab = wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.length);
  const win = {
    AscFonts: { onLoadModule: () => ready() }, navigator: { userAgent: "node" },
    location: { protocol: "http:", href: "http://x/" }, document: { currentScript: { src: "http://x/fonts.js" } },
    console, setTimeout, clearTimeout, setImmediate, WebAssembly, Uint8Array, Uint8ClampedArray,
    fetch: () => Promise.resolve({ ok: true, arrayBuffer: () => Promise.resolve(ab) }),
    TextDecoder, TextEncoder, URL, Blob: class {},
  };
  win.window = win;
  const ctx = vm.createContext(win);
  vm.runInContext(src, ctx, { filename: path.join(dir, "fonts.js") });
  void done; // onLoadModule dispara tambem no fim do script (antes do wasm): o criterio de pronto e a memoria instanciada
  const t0 = Date.now();
  while (!(win.__M && win.__M.HEAPU8 && win.__M.HEAPU8.length > 0)) {
    if (Date.now() - t0 > 60000) throw new Error("timeout carregando " + dir);
    await new Promise((r) => setTimeout(r, 20));
  }
  await new Promise((r) => setTimeout(r, 200));
  const names = WebAssembly.Module.exports(new WebAssembly.Module(wasm)).map((e) => e.name);
  return { M: win.__M, src, wasmExports: new Set(names) };
}

/** O que: roteiro de medicao de UMA fonte; devolve lista de [rotulo, resumo]. Onde: igual para ours e upstream.
 *  red=true muda o load-mode do lado testado (divergencia induzida para provar que o teste enxerga diferenca). */
function run(E, fontPath, red) {
  const M = E.M;
  const out = [];
  const data = fs.readFileSync(fontPath);
  const lib = M._ASC_FT_Init();
  M._ASC_FT_Set_TrueType_HintProp(lib, 40);
  const mem = M._ASC_FT_Malloc(data.length);
  M.HEAPU8.set(data, mem);
  const face = M._ASC_FT_Open_Face(lib, mem, data.length, 0);
  if (!face) return [["open", "FALHOU"]];
  const info = M._ASC_FT_GetFaceInfo(face);
  out.push(["faceinfo", sha(M.HEAPU8.slice(info, info + 600))]);
  M._ASC_FT_Free(info);
  const cps = [];
  for (let c = 0x20; c < 0x250; c++) cps.push(c);
  const ranges = [[0x370, 0x400], [0x400, 0x4ff], [0x590, 0x5ff], [0x600, 0x6ff], [0x900, 0x97f], [0x2000, 0x2070],
    [0x20a0, 0x20c0], [0x2190, 0x2200], [0xfb00, 0xfb07], [0xfe70, 0xfeff]];
  for (const [a, b] of ranges) for (let c = a; c < b; c++) cps.push(c);
  const gids = [];
  for (const cp of cps) {
    const g = M._ASC_FT_SetCMapForCharCode(face, cp);
    out.push(["cmap " + cp, String(g)]);
    if (g) gids.push(g);
  }
  out.push(["maxadv", String(M._ASC_FT_GetFaceMaxAdvanceX(face))]);
  const NOHINT = 0xA002;
  const HINT = 0xA000; // LOAD_MODE_DEFAULT (sem hinting) e LOAD_MODE_HINTING do sdkjs
  for (const size of [12, 24]) {
    M._ASC_FT_Set_Char_Size(face, 0, size * 64, 96, 96);
    for (const fl of [NOHINT, HINT]) {
      for (const g of gids) {
        const flag = red && size === 24 && fl === HINT ? NOHINT : fl;
        const err = M._ASC_FT_Load_Glyph(face, g, flag);
        if (err) { out.push(["load " + size + "/" + fl + "/" + g, "err" + err]); continue; }
        const p = M._ASC_FT_Get_Glyph_Measure_Params(face, 1);
        if (p) {
          const n = M.HEAP32[p >> 2];
          out.push(["measure " + size + "/" + fl + "/" + g, sha(M.HEAPU8.slice(p, p + 4 * n))]);
          M._ASC_FT_Free(p);
        }
        const modes = fl === HINT ? [0, 2, 3] : [0];
        for (const rm of modes) {
          const label = "render " + size + "/" + fl + "/" + g + "/" + rm;
          const rp = M._ASC_FT_Get_Glyph_Render_Params(face, rm);
          if (!rp) { out.push([label, "null"]); continue; }
          const h = Array.from(M.HEAP32.slice(rp >> 2, (rp >> 2) + 6));
          M._ASC_FT_Free(rp);
          const buf = M._ASC_FT_Get_Glyph_Render_Buffer(face);
          const n = Math.abs(h[4]) * h[3];
          out.push([label, h.join(",") + ":" + (n > 0 && buf ? sha(M.HEAPU8.slice(buf, buf + n)) : "-")]);
        }
      }
    }
  }
  const kn = Math.min(gids.length, 60);
  for (let i = 0; i < kn; i++) {
    for (let j = 0; j < kn; j += 3) out.push(["kern " + gids[i] + "," + gids[j], String(M._ASC_FT_GetKerningX(face, gids[i], gids[j]))]);
  }
  const texts = ["office ffi fl fi AV To Ty LT WA", "السلام عليكم لا",
    "क्ष हिन्दी कि"];
  const lp = M._malloc(8);
  M.HEAPU8.set(Buffer.from("en\0"), lp);
  const L = M._ASC_HB_LanguageFromString(lp);
  texts.forEach((t, ti) => {
    const b = Buffer.from(t + "\0", "utf8");
    const tp = M._malloc(b.length);
    M.HEAPU8.set(b, tp);
    for (const [feat, script, dir] of [[0, 0, 0], [31, 0, 0], [31, 2, 1]]) {
      const label = "shape " + ti + "/" + feat + "/" + script + "/" + dir;
      const r = M._ASC_HB_ShapeText(face, 0, tp, feat, script, dir, L);
      if (!r) { out.push([label, "null"]); continue; }
      const len = M.HEAPU8[r] | (M.HEAPU8[r + 1] << 8) | (M.HEAPU8[r + 2] << 16) | (M.HEAPU8[r + 3] << 24);
      out.push([label, len + ":" + sha(M.HEAPU8.slice(r + 12, r + len))]); // pula len(4) + ponteiro do hb_font(8)
      M._ASC_FT_Free(r);
    }
    M._free(tp);
  });
  M._ASC_FT_Done_Face(face);
  M._ASC_FT_Free(mem);
  M._ASC_FT_Done_FreeType(lib);
  return out;
}

/** O que: coleta Module["_X"] usados pelo JS do sdkjs e confere cobertura no glue de ours + glue->wasm. */
function exportCoverage(ours, up) {
  const need = new Set();
  const scan = (s) => {
    for (const m of s.matchAll(/Module\s*(?:\[\s*"([_A-Za-z0-9]+)"\s*\]|\.([_A-Za-z0-9]+))/g)) {
      const n = m[1] || m[2];
      if (n[0] === "_") need.add(n); // 'Module["ASC_HB_FontFree"]' (sem _) e typo upstream em module_js.js: nao e export
    }
  };
  for (const f of ["common/libfont/engine/fonts.js", "common/libfont/engine.js"]) scan(fs.readFileSync(path.join(sdkjsDir, f), "utf8"));
  const have = new Set(Array.from(ours.src.matchAll(/Module\["([_A-Za-z0-9]+)"\]\s*=/g)).map((m) => m[1]));
  const keys = new Set(Object.keys(ours.M));
  const miss = [...need].filter((n) => !have.has(n) && !keys.has(n));
  const dang = [...ours.src.matchAll(/wasmExports\["([^"]+)"\]/g)].map((m) => m[1]).filter((n) => !ours.wasmExports.has(n));
  // referencias do glue a exports ausentes que o PROPRIO upstream tambem tem (codigo morto do emscripten) nao contam
  const upDang = new Set([...up.src.matchAll(/wasmExports\["([^"]+)"\]/g)].map((m) => m[1]).filter((n) => !up.wasmExports.has(n)));
  return { need: need.size, miss, dangling: [...new Set(dang)].filter((n) => !upDang.has(n)) };
}

(async () => {
  const ours = await load(oursDir);
  const up = await load(upDir);
  let bad = 0;
  let total = 0;
  const cov = exportCoverage(ours, up);
  console.log("exports exigidos pelo sdkjs: " + cov.need + "; faltando em ours: " + cov.miss.length + " [" + cov.miss.join(",") +
    "]; glue->wasm sem export: " + cov.dangling.length + " [" + cov.dangling.join(",") + "]");
  if (cov.miss.length || cov.dangling.length) bad++;
  const fonts = fs.readFileSync(listFile, "utf8").split("\n").filter(Boolean);
  for (const rel of fonts) {
    const fp = path.join(fontsDir, rel);
    const a = run(ours, fp, RED);
    const b = run(up, fp, false);
    let d = 0;
    const n = Math.max(a.length, b.length);
    for (let i = 0; i < n; i++) {
      const same = a[i] && b[i] && a[i][0] === b[i][0] && a[i][1] === b[i][1];
      if (!same && d++ < 3) console.log("  DIFF", rel, JSON.stringify(a[i]), JSON.stringify(b[i]));
    }
    console.log((d === 0 ? "ok   " : "FAIL ") + rel + ": " + n + " itens, " + d + " diferencas");
    total += n;
    if (d) bad++;
  }
  console.log((bad ? "FALHOU" : "PASSOU") + ": " + fonts.length + " fontes, " + total + " itens comparados" + (RED ? " (modo --red)" : ""));
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.error("ERRO", e); process.exit(2); });
