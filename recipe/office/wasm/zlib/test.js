'use strict';
// axuz_ops/office/wasm/zlib/test.js — equivalencia do zlib.wasm novo vs o versionado no sdkjs (upstream).
// O QUE: com partes reais de .docx/.xlsx/.pptx (document-templates): (1) abrir o zip e listar caminhos/bytes de cada parte
//   (Zlib_Open/GetPaths/GetFile) — novo == upstream; (2) criar zip com as mesmas partes (Zlib_Create/AddFile/Save) em cada
//   modulo e ABRIR o resultado de um no outro (novo->upstream e upstream->novo) conferindo cada byte; (3) imagens: Image_GetFormat
//   e Raster_Encode (png/bmp/jpg do media/ dos documentos) novo == upstream; (4) toda export que o glue zlib.js chama existe.
// ONDE: container node via zlib/test.sh. Uso: node test.js <ours.wasm> <up.wasm> <glue.js> <document-templates-dir>
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { load } = require('../test-lib/harness.js');
const [oursP, upP, glueP, upGlueP, tplDir] = process.argv.slice(2);
let ours, up;
try { ours = load(oursP, glueP); up = load(upP, upGlueP); } catch (e) { console.log('FALHA: ' + e.message); process.exit(1); }
let fails = 0, checks = 0;
const ok = (c, m) => { checks++; if (!c) { fails++; if (fails < 25) console.log('FALHA: ' + m); } };
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

// readLenBuf — le o formato [int32 len][bytes] que o wasm devolve (len inclui os 4 bytes do prefixo em listas de paths).
function pathsOf(m, zip) {
  const p = m.fn._Zlib_GetPaths(zip); if (!p) return [];
  const h = Buffer.from(m.u8().buffer); let len = h.readInt32LE(p) - 4, i = 0; const out = [];
  while (i < len) { const l = h.readUInt32LE(p + 4 + i); i += 4; out.push(h.toString('utf8', p + 4 + i, p + 4 + i + l)); i += l; }
  m.fn._Zlib_Free(p); return out;
}
// open — Zlib_Open sobre os bytes do arquivo; devolve handle (0 = falha). O buffer de entrada fica vivo (freed no close).
function open(m, bytes) {
  const p = m.fn._Zlib_Malloc(bytes.length); m.u8().set(bytes, p);
  const z = m.fn._Zlib_Open(p, bytes.length); return { z, p };
}
// getFile — Zlib_GetFile(path) -> Buffer copiado ou null.
function getFile(m, z, name) {
  const b = Buffer.concat([Buffer.from(name, 'utf8'), Buffer.from([0])]); const pp = m.fn._Zlib_Malloc(b.length); m.u8().set(b, pp);
  const r = m.fn._Zlib_GetFile(z, pp); m.fn._Zlib_Free(pp);
  if (!r) return null;
  const len = Buffer.from(m.u8().buffer).readInt32LE(r); return Buffer.from(m.u8().slice(r + 4, r + 4 + len));
}
// create — monta um zip novo com `files` ([nome, Buffer]) e devolve os bytes (Zlib_Save).
function create(m, files) {
  const z = m.fn._Zlib_Create();
  for (const [name, data] of files) {
    const nb = Buffer.concat([Buffer.from(name, 'utf8'), Buffer.from([0])]); const np = m.fn._Zlib_Malloc(nb.length); m.u8().set(nb, np);
    const dp = m.fn._Zlib_Malloc(data.length || 1); m.u8().set(data, dp);
    m.fn._Zlib_AddFile(z, np, dp, data.length); m.fn._Zlib_Free(np);
  }
  const r = m.fn._Zlib_Save(z); if (!r) return null;
  const len = Buffer.from(m.u8().buffer).readInt32LE(r); const out = Buffer.from(m.u8().slice(r + 4, r + 4 + len));
  m.fn._Zlib_Close(z); return out;
}
// readAll — abre `zipBytes` em `m` e devolve Map nome->sha256 (e o handle e fechado).
function readAll(m, zipBytes) {
  const { z } = open(m, zipBytes); if (!z) return null;
  const map = new Map();
  for (const n of pathsOf(m, z)) { const d = getFile(m, z, n); map.set(n, d ? sha(d) : null); }
  m.fn._Zlib_Close(z); return map;
}
const same = (a, b) => a && b && a.size === b.size && [...a].every(([k, v]) => b.get(k) === v);

const docs = [];
for (const d of ['sample', 'new/pt-BR', 'new/en-US', 'new/zh-CN']) for (const f of fs.readdirSync(path.join(tplDir, d)).filter((x) => /\.(docx|xlsx|pptx)$/.test(x))) docs.push(path.join(tplDir, d, f));
ok(docs.length >= 4, 'poucos documentos de teste (' + docs.length + ')');
const imgs = [];
for (const f of docs) {
  const bytes = fs.readFileSync(f);
  const a = open(ours, bytes), b = open(up, bytes);
  ok(!!a.z && !!b.z, f + ': Zlib_Open falhou (novo=' + a.z + ', up=' + b.z + ')');
  if (!a.z || !b.z) continue;
  const pa = pathsOf(ours, a.z), pb = pathsOf(up, b.z);
  ok(JSON.stringify(pa) === JSON.stringify(pb) && pa.length > 3, f + ': lista de partes difere');
  const parts = [];
  for (const n of pb) {
    const da = getFile(ours, a.z, n), db = getFile(up, b.z, n);
    ok(da && db && da.equals(db), f + ' parte ' + n + ': bytes diferem ' + (da && da.length) + ' vs ' + (db && db.length));
    if (db) { parts.push([n, db]); if (/\.(png|jpe?g|bmp|gif|tiff?)$/i.test(n)) imgs.push([n, db]); }
  }
  // round-trip cruzado: zip criado por um e lido pelo outro
  const zo = create(ours, parts), zu = create(up, parts);
  ok(!!zo && !!zu, f + ': Zlib_Save falhou');
  const ref = new Map(parts.map(([n, d]) => [n, sha(d)]));
  ok(same(readAll(up, zo), ref), f + ': zip do NOVO lido pelo UPSTREAM diverge');
  ok(same(readAll(ours, zu), ref), f + ': zip do UPSTREAM lido pelo NOVO diverge');
  ok(same(readAll(ours, zo), ref), f + ': zip do novo lido pelo novo diverge');
  ok(zo && zu && zo.length === zu.length, f + ': tamanho do zip salvo difere (novo=' + (zo && zo.length) + ' up=' + (zu && zu.length) + ')');
  ours.fn._Zlib_Close(a.z); up.fn._Zlib_Close(b.z);
}
// imagens
function fmt(m, d) { const p = m.fn._Zlib_Malloc(d.length); m.u8().set(d, p); const r = m.fn._Image_GetFormat(p, d.length); m.fn._Zlib_Free(p); return r; }
function enc(m, d, f) {
  try { return enc1(m, d, f); } catch (e) { return 'THROW'; }
}
// enc1 — Raster_Encode sem protecao (um formato nao suportado lanca excecao C++ no upstream tambem; ver enc).
function enc1(m, d, f) {
  const p = m.fn._Zlib_Malloc(d.length); m.u8().set(d, p);
  const e = m.fn._Raster_Encode(p, d.length, f); m.fn._Zlib_Free(p);
  if (!e) return null;
  const size = m.fn._Raster_GetEncodedSize(e), buf = m.fn._Raster_GetEncodedBuffer(e);
  const out = Buffer.from(m.u8().slice(buf, buf + size)); m.fn._Raster_DestroyEncodedData(e); return out;
}
ok(imgs.length > 0, 'nenhuma imagem real nos documentos de teste: parte de imagem ficou cega');
for (const [n, d] of imgs.slice(0, 12)) {
  ok(fmt(ours, d) === fmt(up, d), n + ': Image_GetFormat difere');
  for (const f of [24, 1, 2]) {
    const a = enc(ours, d, f), b = enc(up, d, f);
    ok(a === b || (Buffer.isBuffer(a) && Buffer.isBuffer(b) && a.equals(b)), n + ' Raster_Encode(' + f + ') difere');
  }
}
console.log('zlib: ' + checks + ' verificacoes, ' + fails + ' falhas (docs=' + docs.length + ', imagens=' + imgs.length + ')');
process.exit(fails ? 1 : 0);
