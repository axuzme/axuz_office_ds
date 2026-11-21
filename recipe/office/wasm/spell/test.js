'use strict';
// axuz_ops/office/wasm/spell/test.js — equivalencia do spell.wasm novo vs o versionado no sdkjs (upstream).
// O QUE: mesmo dicionario (pt_BR e en_US do repo dictionaries), mesma lista de palavras (corretas, erradas por mutacao
//   deterministica e com acentos): Spellchecker_Spell e Spellchecker_Suggest do novo devem dar o MESMO resultado que o upstream
//   (inclusive a ordem das sugestoes); toda export que o glue spell.js chama existe no wasm novo.
// ONDE: container node via spell/test.sh. Uso: node test.js <ours.wasm> <up.wasm> <glue.js> <dictionaries-dir>
const fs = require('fs');
const path = require('path');
const { load } = require('../test-lib/harness.js');
const [oursP, upP, glueP, upGlueP, dictDir] = process.argv.slice(2);
let ours, up;
try { ours = load(oursP, glueP); up = load(upP, upGlueP); } catch (e) { console.log('FALHA: ' + e.message); process.exit(1); }
let fails = 0, checks = 0;
const ok = (c, m) => { checks++; if (!c) { fails++; if (fails < 25) console.log('FALHA: ' + m); } };

// cstr — aloca string UTF-8 terminada em NUL via Spellchecker_Malloc (como allocString do spell.js).
function cstr(m, s) { const b = Buffer.concat([Buffer.from(s, 'utf8'), Buffer.from([0])]); const p = m.fn._Spellchecker_Malloc(b.length); m.u8().set(b, p); return p; }
// bytes — aloca e copia um Buffer (aff/dic) para o heap; devolve ponteiro.
function bytes(m, b) { const p = m.fn._Spellchecker_Malloc(b.length); m.u8().set(b, p); return p; }
// engine — cria o engine e carrega o dicionario `lang` (aff+dic); devolve {m, eng, spell(w), suggest(w)}.
function engine(m, lang, aff, dic) {
  const eng = m.fn._Spellchecker_Create(100);
  const a = cstr(m, lang + '.aff'), d = cstr(m, lang + '.dic');
  m.fn._Spellchecker_AddDictionary(eng, a, bytes(m, aff), aff.length);
  m.fn._Spellchecker_AddDictionary(eng, d, bytes(m, dic), dic.length);
  const r = m.fn._Spellchecker_Load(eng, a, d);
  return {
    r,
    spell: (w) => { const p = cstr(m, w); const v = m.fn._Spellchecker_Spell(eng, p); m.fn._Spellchecker_Free(p); return v; },
    suggest: (w) => {
      const p = cstr(m, w); const q = m.fn._Spellchecker_Suggest(eng, p); m.fn._Spellchecker_Free(p);
      if (!q) return [];
      const h = Buffer.from(m.u8().buffer); const total = h.readInt32LE(q) - 4; const out = []; let i = 0;
      while (i < total) { const l = h.readUInt32LE(q + 4 + i); i += 4; out.push(h.toString('utf8', q + 4 + i, q + 4 + i + l)); i += l; }
      return out;
    },
  };
}
// rng — gerador deterministico (mulberry32) para a mutacao das palavras.
function rng(seed) { return () => { seed |= 0; seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

for (const lang of ['pt_BR', 'en_US']) {
  const aff = fs.readFileSync(path.join(dictDir, lang, lang + '.aff'));
  const dic = fs.readFileSync(path.join(dictDir, lang, lang + '.dic'));
  const eo = engine(ours, lang, aff, dic), eu = engine(up, lang, aff, dic);
  ok(eo.r === eu.r && eo.r !== 0, lang + ': Load rc novo=' + eo.r + ' upstream=' + eu.r);
  const lines = dic.toString('utf8').split('\n').slice(1).map((l) => l.split('/')[0].trim()).filter(Boolean);
  const rnd = rng(lang === 'pt_BR' ? 7 : 11);
  const words = [];
  for (let i = 0; i < 400; i++) words.push(lines[Math.floor(rnd() * lines.length)]);
  const wrong = words.slice(0, 150).map((w) => (w.length < 3 ? w + 'q' : w.slice(0, 1) + w.slice(2) + w[1] + 'x'));
  const extra = lang === 'pt_BR' ? ['ação', 'coração', 'naum', 'vc', 'exceção', 'concerteza', 'atravéz', 'Brasil', 'ônibus', 'xícara'] : ['color', 'colour', 'recieve', 'definately', 'teh', 'hello', 'wrold', 'beautifull'];
  for (const w of [...words, ...wrong, ...extra]) {
    ok(eo.spell(w) === eu.spell(w), lang + ' spell("' + w + '") novo=' + eo.spell(w) + ' upstream=' + eu.spell(w));
  }
  let sugg = 0;
  for (const w of [...wrong.slice(0, 80), ...extra]) {
    const a = eo.suggest(w), b = eu.suggest(w);
    ok(JSON.stringify(a) === JSON.stringify(b), lang + ' suggest("' + w + '") novo=' + JSON.stringify(a) + ' upstream=' + JSON.stringify(b));
    if (b.length) sugg++;
  }
  ok(sugg > 20, lang + ': poucas palavras com sugestao (' + sugg + '): o teste ficou cego');
  ok(eo.spell(words[0]) === 1, lang + ': palavra do proprio dicionario deveria estar correta');
  ok(eo.spell('zzqxjkv') === 0, lang + ': lixo deveria estar errado');
}
console.log('spell: ' + checks + ' verificacoes, ' + fails + ' falhas');
process.exit(fails ? 1 : 0);
