'use strict';
// axuz_ops/office/wasm/test-lib/harness.js — carrega um .wasm do sdkjs no node SEM o editor, usando o glue como mapa.
//
// O QUE: o glue emscripten do sdkjs (engine.js, zlib.js, spell.js) liga nomes minificados do .wasm (export "K") aos nomes
//   reais (_malloc). Este harness le o glue como TEXTO, extrai (a) asmLibraryArg (import minificado -> funcao JS),
//   (b) Module["_x"] -> asm["K"], (c) memoria/tabela/ctor, instancia o .wasm com imports implementados aqui e devolve
//   as funcoes pelos nomes reais. Assim o MESMO glue serve a um .wasm velho e a um novo — se os nomes minificados do novo
//   nao casarem, o carregamento falha (e isso e o teste de "export table cobre o que o glue chama").
// ONDE: test.sh de engine/zlib/spell (node, offline, dentro de container node).

const fs = require('fs');

// parseGlue — extrai do texto do glue: imports (min->nome), exports (nome real -> min), memoria, tabela, ctor.
function parseGlue(text) {
  const lib = /var asmLibraryArg=\{([^}]*)\}/.exec(text);
  if (!lib) throw new Error('glue sem asmLibraryArg');
  const imports = {};
  for (const m of lib[1].matchAll(/"([\w$]+)":([\w$]+)/g)) imports[m[1]] = m[2];
  const exportsMap = {};
  for (const m of text.matchAll(/Module\["([\w$]+)"\]=function\(\)\{return\([\w$]+=Module\["[\w$]+"\]=Module\["asm"\]\["([\w$]+)"\]\)/g)) exportsMap[m[1]] = m[2];
  const mem = /wasmMemory=Module\["asm"\]\["([\w$]+)"\]/.exec(text);
  const tab = /wasmTable=Module\["asm"\]\["([\w$]+)"\]/.exec(text);
  const ctor = /addOnInit\(Module\["asm"\]\["([\w$]+)"\]\)/.exec(text);
  return { imports, exportsMap, mem: mem && mem[1], tab: tab && tab[1], ctor: ctor && ctor[1] };
}

// makeImports — implementa em JS os imports que o emscripten gera (sem syscalls reais). `state` guarda memoria/tabela.
// Onde: load. Funcoes nao conhecidas viram um stub que lanca ao ser chamado (nao ao carregar).
function makeImports(glue, state) {
  const known = {
    emscripten_memcpy_big: (d, s, n) => { state.u8().copyWithin(d, s, s + n); },
    emscripten_resize_heap: (req) => {
      const old = state.memory.buffer.byteLength;
      try { state.memory.grow(Math.ceil((Math.max(req, old * 1.25) - old) / 65536)); return 1; } catch (e) { return 0; }
    },
    abort: () => { throw new Error('abort()'); },
    assert_fail: () => { throw new Error('assert_fail'); },
    // excecoes C++ do emscripten (EXCEPTION_CATCHING): cabecalho de 16 bytes antes do objeto, throw de um numero (ptr)
    cxa_allocate_exception: (size) => state.fn.malloc(size + 16) + 16,
    cxa_throw: (ptr, type, destructor) => {
      const h = state.i32(), p = ptr - 16;
      h[(p + 4) >> 2] = type; h[(p + 8) >> 2] = destructor; h[p >> 2] = 0; state.u8()[p + 12] = 0; state.u8()[p + 13] = 0;
      throw ptr;
    },
    emscripten_throw_longjmp: () => { throw new Error('longjmp'); },
    emscripten_date_now: () => Date.now(),
    environ_sizes_get: (pc, ps) => { const h = state.i32(); h[pc >> 2] = 0; h[ps >> 2] = 0; return 0; },
    environ_get: () => 0,
    fd_write: (fd, iov, cnt, pnum) => {
      const h = state.i32(); let n = 0;
      for (let i = 0; i < cnt; i++) n += h[(iov + i * 8 + 4) >> 2];
      h[pnum >> 2] = n; return 0;
    },
    fd_close: () => 0, fd_seek: () => 0, fd_read: () => 0,
    clock: () => Math.floor(Number(process.hrtime.bigint() / 1000n)),
    strftime_l: () => 0,
    exit: () => { throw new Error('exit()'); },
    getTempRet0: () => state.tempRet, setTempRet0: (v) => { state.tempRet = v; },
  };
  const out = {};
  for (const [min, name] of Object.entries(glue.imports)) {
    const base = name.replace(/^_+/, '');
    if (known[base]) out[min] = known[base];
    else if (/^invoke_/.test(base)) out[min] = (idx, ...a) => {
      const sp = state.fn.stackSave();
      try { return state.table.get(idx)(...a); } catch (e) { state.fn.stackRestore(sp); if (e !== e + 0) throw e; state.fn.setThrew(1, 0); }
    };
    else if (/^syscall_/.test(base)) out[min] = () => -52;
    else out[min] = () => { throw new Error('import nao implementado no harness: ' + name); };
  }
  return { a: out };
}

// load — instancia `wasmPath` com o glue em `gluePath`; devolve {fn: {nome real: funcao}, u8(), i32(), memory}.
// Onde: tests. Falha com mensagem clara se o glue pedir um export que o .wasm nao tem.
function load(wasmPath, gluePath) {
  const glue = parseGlue(fs.readFileSync(gluePath, 'utf8'));
  const state = { fn: {}, tempRet: 0, memory: null, table: null, u8: () => new Uint8Array(state.memory.buffer), i32: () => new Int32Array(state.memory.buffer) };
  const mod = new WebAssembly.Module(fs.readFileSync(wasmPath));
  const have = new Set(WebAssembly.Module.exports(mod).map((e) => e.name));
  const need = [...Object.values(glue.exportsMap), glue.mem, glue.tab, glue.ctor].filter(Boolean);
  const missing = need.filter((n) => !have.has(n));
  if (missing.length) throw new Error('EXPORT_AUSENTE: o glue chama export(s) que o wasm nao tem: ' + missing.join(','));
  const inst = new WebAssembly.Instance(mod, makeImports(glue, state));
  const ex = inst.exports;
  state.memory = ex[glue.mem]; state.table = ex[glue.tab];
  if (glue.ctor) ex[glue.ctor]();
  const fn = {};
  for (const [real, min] of Object.entries(glue.exportsMap)) fn[real] = ex[min];
  state.fn = { malloc: fn._malloc, stackSave: fn.stackSave, stackRestore: fn.stackRestore, setThrew: fn._setThrew };
  return { fn, glue, state, u8: state.u8, i32: state.i32, memory: state.memory };
}

// exportsOf — nomes de exports/imports do .wasm (para comparar tabelas). Onde: test.sh, relatorio.
function exportsOf(wasmPath) {
  const m = new WebAssembly.Module(fs.readFileSync(wasmPath));
  return { exports: WebAssembly.Module.exports(m), imports: WebAssembly.Module.imports(m) };
}

module.exports = { load, parseGlue, exportsOf };
