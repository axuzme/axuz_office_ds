// office/wasm/drawingfile/compose_glue.js — monta o drawingfile.js (glue) a partir do runtime emscripten NOSSO + wrapper do sdkjs.
//
// O QUE: o drawingfile.js que o sdkjs distribui e a concatenacao (feita pelo Common/js/make.py do core, hoje removido) de:
//   [wrapper JS do core: base, desktop_fetch, string_utf8]  +  [runtime gerado pelo emcc]  +  [wrapper `stream.js`+`drawingfile.js`],
//   passada por closure WHITESPACE_ONLY. Os fontes dos wrappers de OUTUBRO (OFD, BuildPdf, imagens, macros) nao estao mais no core
//   publico; existem no proprio sdkjs (pdf/src/engine/drawingfile.js, texto). Aqui separamos, por AST, o que e wrapper do que e
//   runtime emscripten no arquivo do sdkjs e recompomos com o runtime que NOS geramos (mesmo wasm, mesmos nomes de import/export).
// REGRA: runtime = nomes declarados no topo do output do emcc; PRE = statements do sdkjs antes de `var Module` que nao sao funcoes do
//   runtime; POST = statements do sdkjs depois do `run();` do emcc. Falha (exit 2) se a estrutura nao bate (fail-closed).
// USO: node compose_glue.js <emcc-drawingfile.js> <sdkjs/pdf/src/engine/drawingfile.js> <saida.js>
// Roda no container emsdk (acorn vem do node_modules do emscripten). Sem rede.
const fs = require('fs');
const path = require('path');
const acorn = require(process.env.ACORN_PATH || '/emsdk/upstream/emscripten/node_modules/acorn');

/** O que: erro fatal. Onde: toda validacao estrutural. */
function die(msg) { console.error('COMPOSE_GLUE: ' + msg); process.exit(2); }

/** O que: troca exata (falha se ausente), identica ao replaceInFile do after.py. Onde: ajustes do runtime emcc. */
function mustReplace(text, from, to, what) {
	if (text.indexOf(from) < 0) return { text, done: false };
	return { text: text.split(from).join(to), done: true };
}

/** O que: nomes declarados no topo do script do emcc (funcoes e vars). Onde: separar runtime de wrapper. */
function topNames(ast) {
	const names = new Set();
	for (const s of ast.body) {
		if (s.type === 'FunctionDeclaration') names.add(s.id.name);
		else if (s.type === 'VariableDeclaration') s.declarations.forEach(d => d.id && d.id.name && names.add(d.id.name));
	}
	return names;
}

/** O que: aplica o equivalente do after.py (hook de carga do viewer, fetch do wasm e .mem do IE). Onde: runtime emcc. */
function patchRuntime(src) {
	let t = src;
	const must = (from, to) => { const r = mustReplace(t, from, to); t = r.text; return r.done; };
	if (!must('function getBinaryPromise(', 'function getBinaryPromise2(')) die('runtime sem getBinaryPromise()');
	const hook = '__ATPOSTRUN__=[function(){window["AscViewer"] && window["AscViewer"]["onLoadModule"] && window["AscViewer"]["onLoadModule"]();}];';
	const a = must('__ATPOSTRUN__=[];', hook);
	const b = must('__ATPOSTRUN__ = [];', hook);
	if (!a && !b) die('runtime sem __ATPOSTRUN__ vazio');
	must('"drawingfile.js.mem"', 'getMemoryPathIE("drawingfile.js.mem")');
	return t;
}

const [emccFile, sdkFile, outFile] = process.argv.slice(2);
if (!outFile) die('uso: compose_glue.js <emcc.js> <sdkjs drawingfile.js> <out.js>');

const emccSrc = patchRuntime(fs.readFileSync(emccFile, 'utf8'));
let emccAst;
try { emccAst = acorn.parse(emccSrc, { ecmaVersion: 2022 }); } catch (e) { die('emcc js invalido: ' + e.message); }
const E = topNames(emccAst);
if (!E.has('Module') || !E.has('run')) die('runtime emcc sem Module/run');

const sdkSrc = fs.readFileSync(sdkFile, 'utf8');
const sdkAst = acorn.parse(sdkSrc, { ecmaVersion: 2022 });
const iife = sdkAst.body.find(n => n.type === 'ExpressionStatement' && n.expression.type === 'CallExpression');
if (!iife) die('sdkjs drawingfile.js sem IIFE');
const fnNode = iife.expression.callee;
const body = fnNode.body.body;
const header = sdkSrc.slice(0, iife.start);

const mIdx = body.findIndex(s => s.type === 'VariableDeclaration' && s.declarations.some(d => d.id.name === 'Module'));
if (mIdx < 0) die('sdkjs sem "var Module"');
let runIdx = -1;
for (let i = mIdx + 1; i < body.length; i++) {
	const s = body[i];
	if (s.type === 'ExpressionStatement' && s.expression.type === 'CallExpression' &&
		s.expression.callee.type === 'Identifier' && s.expression.callee.name === 'run' && s.expression.arguments.length === 0) { runIdx = i; break; }
}
if (runIdx < 0) die('sdkjs sem run() do emcc');

const pre = [];
for (let i = 0; i < body.length; i++) {
	const s = body[i];
	if (i >= mIdx) break;
	if (s.type === 'FunctionDeclaration' && E.has(s.id.name)) continue; // funcao do runtime (veio hoistada do closure)
	pre.push(sdkSrc.slice(s.start, s.end));
}
const post = body.slice(runIdx + 1).map(s => sdkSrc.slice(s.start, s.end));
if (!post.length) die('sdkjs sem codigo apos run()');
// os statements do runtime que o sdkjs hoistou (funcoes) e que nao existem mais no nosso runtime = wrapper novo? avisa
const lost = body.slice(0, mIdx).filter(s => s.type === 'FunctionDeclaration' && !E.has(s.id.name)).map(s => s.id.name);

const out = header + '(function(window,undefined){' + pre.join('\n') + '\n' + emccSrc + '\n' + post.join('\n') + '\n})(window,undefined);\n';
try { acorn.parse(out, { ecmaVersion: 2022 }); } catch (e) { die('saida invalida: ' + e.message); }
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, out);
console.log('compose_glue: pre=%d post=%d runtimeNames=%d wrapperFuncs=%s -> %s (%d bytes)', pre.length, post.length, E.size, lost.join(','), outFile, out.length);
