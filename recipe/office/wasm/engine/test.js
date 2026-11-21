'use strict';
// axuz_ops/office/wasm/engine/test.js — equivalencia do engine.wasm novo (nosso) vs o versionado no sdkjs (upstream).
// O QUE: (1) toda export que o glue engine.js chama existe no .wasm novo; (2) para cada um dos 9 algoritmos e varios
//   tamanhos de entrada, hash() novo == hash() upstream == vetor conhecido (node crypto, quando o OpenSSL do node o tem);
//   (3) hash2() (senha+sal+spinCount, usado na protecao de documentos) novo == upstream.
// ONDE: roda no container node/emsdk via engine/test.sh. Uso: node test.js <ours.wasm> <upstream.wasm> <glue.js>
const crypto = require('crypto');
const { load } = require('../test-lib/harness.js');
const [oursP, upP, glueP, upGlueP] = process.argv.slice(2);
let ours, up;
try { ours = load(oursP, glueP); up = load(upP, upGlueP); } catch (e) { console.log('FALHA: ' + e.message); process.exit(1); }
const ALGS = ['md2', 'md4', 'md5', 'rmd160', 'sha1', 'sha256', 'sha384', 'sha512', 'whirlpool'];
const SIZES = [16, 16, 16, 20, 20, 32, 48, 64, 64];
const nodeName = { md5: 'md5', sha1: 'sha1', sha256: 'sha256', sha384: 'sha384', sha512: 'sha512', rmd160: 'ripemd160', whirlpool: 'whirlpool', md4: 'md4' };
let fails = 0, checks = 0;
const ok = (c, m) => { checks++; if (!c) { fails++; console.log('FALHA: ' + m); } };

// hashWith — chama _hash no modulo `m` e devolve os bytes do digest (copiados).
function hashWith(m, data, alg) {
  const p = m.fn._malloc(data.length || 1); m.u8().set(data, p);
  const r = m.fn._hash(p, data.length, alg); m.fn._free(p);
  const out = Buffer.from(m.u8().slice(r, r + SIZES[alg])); m.fn._free(r); return out;
}
// hash2With — chama _hash2 (senha NUL-terminada, sal NUL-terminado, spinCount) como o hash.js do sdkjs.
function hash2With(m, pw, salt, spin, alg) {
  const w = (s) => { const b = Buffer.concat([Buffer.from(s, 'utf8'), Buffer.from([0])]); const p = m.fn._malloc(b.length); m.u8().set(b, p); return p; };
  const pp = w(pw), sp = w(salt);
  const r = m.fn._hash2(pp, sp, spin, alg); m.fn._free(pp); m.fn._free(sp);
  const out = Buffer.from(m.u8().slice(r, r + SIZES[alg])); m.fn._free(r); return out;
}
const inputs = [Buffer.alloc(0), Buffer.from('abc'), Buffer.from('The quick brown fox jumps over the lazy dog'),
  Buffer.alloc(55, 0x61), Buffer.alloc(56, 0x62), Buffer.alloc(64, 0x63), Buffer.alloc(1000, 0x64), crypto.randomBytes(4097)];
ALGS.forEach((name, alg) => {
  for (const d of inputs) {
    const a = hashWith(ours, d, alg), b = hashWith(up, d, alg);
    ok(a.equals(b), name + ' len=' + d.length + ': novo != upstream');
    if (nodeName[name]) { try { ok(a.equals(crypto.createHash(nodeName[name]).update(d).digest()), name + ' len=' + d.length + ': != node crypto'); } catch (e) { /* node sem o algoritmo: so a comparacao com upstream vale */ } }
  }
  for (const [pw, salt, spin] of [['oleg', 'yrGivlyCImiWnryRee1OJw==', 20000], ['', 'AAAA', 1], ['senha com acentuacao ç', 'c2FsdA==', 50]]) {
    ok(hash2With(ours, pw, salt, spin, alg).equals(hash2With(up, pw, salt, spin, alg)), 'hash2 ' + name + ' spin=' + spin + ': novo != upstream');
  }
});
// vetores publicos fixos (independem do node): MD5("abc"), SHA-1("abc"), SHA-256("abc")
ok(hashWith(ours, Buffer.from('abc'), 2).toString('hex') === '900150983cd24fb0d6963f7d28e17f72', 'MD5(abc) fixo');
ok(hashWith(ours, Buffer.from('abc'), 4).toString('hex') === 'a9993e364706816aba3e25717850c26c9cd0d89d', 'SHA1(abc) fixo');
ok(hashWith(ours, Buffer.from('abc'), 5).toString('hex') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'SHA256(abc) fixo');
console.log('engine: ' + checks + ' verificacoes, ' + fails + ' falhas');
process.exit(fails ? 1 : 0);
