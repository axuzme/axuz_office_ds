// office/wasm/drawingfile/test/harness.js — compara o drawingfile.wasm NOSSO com o UPSTREAM (o do sdkjs) sobre um corpus.
//
// O QUE: carrega cada par glue+wasm num contexto `vm` com shims minimos de navegador (window/self/fetch/AscViewer), abre cada arquivo
//   do corpus pelo MESMO caminho do editor (CFile = AscViewer.CDrawingFile) e registra, por arquivo: erro/tipo, paginas (W,H,Dpi,
//   Rotate), info JSON, estrutura (outline), links, glifos/texto, formularios, anotacoes (+AP), pixmaps (sha256 + estatistica de pixels
//   nao-brancos) e operacoes de edicao (SplitPages/MergePages/RedactPage + reabertura do resultado). Depois compara registro a registro.
// TOLERANCIA: ZERO (igualdade exata de bytes/estrutura). Diferenca => FAIL com diff dos pixels. Nao ha tolerancia silenciosa.
// ANTI-CEGUEIRA: afirma que cada pagina de PDF com conteudo renderiza ALGUM pixel nao-branco e que os PDFs de texto devolvem texto;
//   sem isso um wasm que renderiza tudo branco "igualaria" outro igualmente quebrado.
// COBERTURA DE EXPORTS: todo Module["_X"] que a glue/wrapper chama deve estar na tabela de exports do wasm (e no conjunto do upstream).
// USO: node harness.js --up-glue F --up-wasm F --our-glue F --our-wasm F --corpus DIR [--red export|pixel] [--json out.json]
// Saida: exit 0 = igual; 1 = divergencia; 2 = erro de uso/carga. Roda no container emsdk (node 16), sem rede.
'use strict';
const vm = require('vm');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const args = {};
for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const need = (k) => { if (!args[k]) { console.error('falta --' + k); process.exit(2); } return args[k]; };

/** O que: sha256 hex de bytes. Onde: todo registro. */
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

/** O que: serializa valor para comparacao estavel (typed arrays viram sha256+len, chaves ordenadas). Onde: registros. */
function stable(v) {
	if (v === undefined) return 'undefined';
	if (v === null) return null;
	if (ArrayBuffer.isView(v) || v instanceof ArrayBuffer) {
		const u = v instanceof ArrayBuffer ? new Uint8Array(v) : new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
		return { __bytes: u.length, sha: sha(Buffer.from(u)) };
	}
	if (Array.isArray(v)) return v.map(stable);
	if (typeof v === 'object') {
		const o = {};
		for (const k of Object.keys(v).sort()) o[k] = stable(v[k]);
		return o;
	}
	return v;
}

/** O que: carrega glue+wasm num contexto isolado e espera o runtime (hook AscViewer.onLoadModule). Onde: main. */
function loadModule(label, glueFile, wasmFile) {
	return new Promise((resolve, reject) => {
		const wasm = fs.readFileSync(wasmFile);
		const ab = wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.length);
		const ctx = { console, setTimeout, clearTimeout, setInterval, clearInterval, TextDecoder, TextEncoder, Promise, URL };
		ctx.window = ctx; ctx.self = ctx;
		ctx.navigator = { userAgent: 'axuz-node-test' };
		ctx.location = { protocol: 'http:', href: 'http://localhost/' };
		ctx.fetch = () => Promise.resolve({ ok: true, arrayBuffer: () => Promise.resolve(ab) });
		ctx.AscViewer = { baseUrl: '', onLoadModule: () => resolve(ctx), CheckStreamId: () => 0, Free: () => 1 };
		vm.createContext(ctx);
		try { vm.runInContext(fs.readFileSync(glueFile, 'utf8'), ctx, { filename: glueFile }); } catch (e) { reject(new Error(label + ': glue falhou: ' + e.message)); return; }
		setTimeout(() => reject(new Error(label + ': timeout carregando o modulo')), 120000);
	});
}

/** O que: tabela de exports do wasm x chamadas Module["_X"] da glue (cobertura). Onde: checagem estatica. */
function exportCoverage(label, glueFile, wasmFile, dropName) {
	const glue = fs.readFileSync(glueFile, 'utf8');
	const mod = new WebAssembly.Module(fs.readFileSync(wasmFile));
	const exps = new Set(WebAssembly.Module.exports(mod).map((e) => e.name));
	const map = {};
	const re = /Module\["(_[A-Za-z0-9_]+)"\]\s*=\s*wasmExports\["([^"]+)"\]/g;
	let m;
	while ((m = re.exec(glue))) map[m[1]] = m[2];
	const used = new Set();
	const re2 = /Module\["(_[A-Za-z0-9_]+)"\]\(/g;
	while ((m = re2.exec(glue))) used.add(m[1]);
	if (dropName) { delete map[dropName]; }
	const problems = [];
	for (const u of used) if (!(u in map)) problems.push('chamada sem export na glue: ' + u);
	for (const [x, k] of Object.entries(map)) if (!exps.has(k)) problems.push('glue aponta export inexistente no wasm: ' + x + ' -> ' + k);
	return { label, names: Object.keys(map).sort(), used: [...used].sort(), wasmExports: exps.size, problems };
}

/** O que: pixels nao-brancos de um buffer BGRA/RGBA (anti-cegueira). Onde: pixmaps. */
function nonWhite(u8) {
	let n = 0;
	for (let i = 0; i + 3 < u8.length; i += 4) if (u8[i] !== 255 || u8[i + 1] !== 255 || u8[i + 2] !== 255) n++;
	return n;
}

/** O que: executa uma funcao capturando excecao como valor comparavel. Onde: toda chamada do wrapper. */
function guard(fn) {
	try { return stable(fn()); } catch (e) { return { __error: String(e && e.message || e).slice(0, 200) }; }
}

/** O que: roda o roteiro completo sobre um arquivo no modulo ctx e devolve o registro. Onde: main (por arquivo e por modulo). */
function runFile(ctx, name, buf, opts) {
	const F = ctx.AscViewer.CDrawingFile;
	const r = {};
	const f = new F();
	const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length);
	r.error = f.loadFromData(ab);
	r.type = f.getType();
	r.pages = (f.pages || []).map((p) => [p.W, p.H, p.Dpi, p.Rotate]);
	r.info = stable(f.info);
	r.startID = f.StartID;
	r.perm = guard(() => f.CheckPerm(4));
	r.structure = guard(() => f.getStructure());
	r.macros = guard(() => f.getMacros());
	r.forms = guard(() => f.getInteractiveFormsInfo());
	r.pix = []; r.glyphs = []; r.links = []; r.annots = []; r.annotAP = [];
	const nPages = Math.min(r.pages.length, 8);
	for (let i = 0; i < nPages; i++) {
		const [W, H] = r.pages[i];
		for (const scale of [1, 0.5]) {
			const w = Math.max(8, Math.min(900, Math.round(W * scale))), h = Math.max(8, Math.min(1200, Math.round(H * scale)));
			r.pix.push(guard(() => {
				const ptr = f._getPixmap(i, w, h, 0xFFFFFF);
				if (!ptr) return { null: true };
				const u8 = new Uint8Array(f._getUint8Array(ptr, w * h * 4));
				const o = { w, h, sha: sha(Buffer.from(u8)), nonWhite: nonWhite(u8) };
				if (opts.red === 'pixel' && opts.isOurs && i === 0 && scale === 1) o.sha = 'ADULTERADO-PELO-TESTE-RED';
				f._free(ptr);
				return o;
			}));
		}
		r.glyphs.push(guard(() => f.getGlyphs(i)));
		r.links.push(guard(() => f.getLinks(i)));
		r.annots.push(guard(() => f.getAnnotationsInfo(i)));
		r.annotAP.push(guard(() => f.getAnnotationsAP(i, Math.min(W, 400), Math.min(H, 400), 0xFFFFFF, 0, 'N')));
	}
	r.formAP = guard(() => f.getInteractiveFormsAP(0, 300, 300, 0xFFFFFF, 0, 'N', undefined));
	r.edit = {};
	if (r.error === 0 && r.type === 0 && r.pages.length > 1) {
		r.edit.split = guard(() => {
			const out = f.SplitPages([0, 1], undefined);
			if (!out) return null;
			const g = new F();
			const e = g.loadFromData(out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength));
			const res = { len: out.length, error: e, pages: (g.pages || []).length, pagesInfo: (g.pages || []).map((p) => [p.W, p.H]),
				metaOForm: Buffer.from(out).includes('/Type /MetaOForm') };
			if (e === 0 && g.pages.length) {
				const w = 200, h = 280, ptr = g._getPixmap(0, w, h, 0xFFFFFF);
				const u8 = new Uint8Array(g._getUint8Array(ptr, w * h * 4));
				res.pix0 = sha(Buffer.from(u8)); res.pix0NonWhite = nonWhite(u8);
				g._free(ptr);
			}
			g.close();
			return res;
		});
	}
	if (r.error === 0 && r.type === 0) {
		r.edit.redact = guard(() => {
			const [W, H] = r.pages[0];
			return f.RedactPage(0, [10, 10, 60, 10, 60, 30, 10, 30], undefined);
		});
		r.edit.undoRedact = guard(() => f.UndoRedact());
		r.edit.merge = guard(() => f.MergePages(ab, 0, 'm_'));
		r.edit.mergedPages = guard(() => f.getPagesInfo().length);
		r.edit.undoMerge = guard(() => f.UndoMergePages());
		r.edit.buildPdf = guard(() => {
			const out = f.BuildPdf(undefined, undefined, undefined);
			return out ? { len: out.length, head: Buffer.from(out.slice(0, 8)).toString('latin1') } : null;
		});
	}
	f.close();
	return r;
}

/** O que: DIVERGENCIA CONHECIDA E LIMITADA do SplitPages. O core fixado (76af764, "Fix bug 78847") poda no fim do split o stream
 *  /Type /MetaOForm vazio e inalcancavel (CPdfEditor::AfterSplitPages -> CDocument::RemoveUnreachableObjects); o wasm do upstream
 *  ainda o emite (1 objeto de ~80 bytes, vazio, sem /ID). So o `len` e o flag `metaOForm` podem diferir, e SO nesse sentido
 *  (upstream tem, nosso nao, diferenca de 1..128 bytes); paginas, tamanhos e pixels do resultado reaberto continuam exigidos iguais.
 *  Onde: main, antes do diff. Devolve true se normalizou (conta no relatorio). */
function normalizeKnownSplit(ru, ro) {
	const a = ru.edit && ru.edit.split, b = ro.edit && ro.edit.split;
	if (!a || !b || a.len === undefined || b.len === undefined) return false;
	const d = a.len - b.len;
	if (a.metaOForm === true && b.metaOForm === false && d > 0 && d <= 128) { a.len = b.len = 'KNOWN'; a.metaOForm = b.metaOForm = 'KNOWN'; return true; }
	return false;
}

/** O que: compara dois registros e lista as diferencas legiveis. Onde: main. */
function diffRec(a, b, p, out) {
	const sa = JSON.stringify(a), sb = JSON.stringify(b);
	if (sa === sb) return;
	if (a && b && typeof a === 'object' && typeof b === 'object') {
		for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) diffRec(a[k], b[k], p + '.' + k, out);
		return;
	}
	out.push(p + ': upstream=' + String(sa).slice(0, 120) + ' nosso=' + String(sb).slice(0, 120));
}

async function main() {
	const upG = need('up-glue'), upW = need('up-wasm'), ouG = need('our-glue'), ouW = need('our-wasm'), corpus = need('corpus');
	const failures = [];
	// 1) cobertura de exports (estatica)
	const cu = exportCoverage('upstream', upG, upW), co = exportCoverage('nosso', ouG, ouW, args.red === 'export' ? '_BuildPdf' : null);
	console.log('exports: upstream glue=%d wasm=%d | nosso glue=%d wasm=%d', cu.names.length, cu.wasmExports, co.names.length, co.wasmExports);
	for (const p of co.problems) failures.push('COBERTURA(nosso): ' + p);
	for (const p of cu.problems) failures.push('COBERTURA(upstream, informativo do harness): ' + p);
	for (const n of cu.used) if (!co.names.includes(n)) failures.push('COBERTURA: o wrapper do sdkjs chama ' + n + ' e o nosso wasm nao exporta');
	const extra = co.names.filter((n) => !cu.names.includes(n));
	if (extra.length) console.log('exports a mais no nosso (nao chamados pelo wrapper):', extra.join(' '));
	// 2) carga
	const up = await loadModule('upstream', upG, upW);
	const ou = await loadModule('nosso', ouG, ouW);
	console.log('modulos carregados (instanciacao ok: imports da glue cobrem o wasm)');
	// 3) corpus
	const files = fs.readdirSync(corpus).filter((f) => /\.(pdf|xps|djvu|ofd)$/i.test(f)).sort();
	const rec = { upstream: {}, nosso: {} };
	let blind = 0, knownSplit = 0;
	const BLANK_OK = new Set(['real-new.pdf']); // template em branco do document-server-integration: renderiza branco nos dois, de proposito
	for (const fn of files) {
		const buf = fs.readFileSync(path.join(corpus, fn));
		const ru = runFile(up, fn, buf, { red: args.red, isOurs: false });
		const ro = runFile(ou, fn, buf, { red: args.red, isOurs: true });
		rec.upstream[fn] = ru; rec.nosso[fn] = ro;
		const known = normalizeKnownSplit(ru, ro); if (known) knownSplit++;
		const d = [];
		diffRec(ru, ro, fn, d);
		const px = ru.pix.filter((x) => x && x.nonWhite > 0).length;
		const txt = ru.glyphs.filter((x) => x && x.__error === undefined && x !== null && JSON.stringify(x).length > 30).length;
		console.log('%s: erro=%s tipo=%s paginas=%d pixmaps(nao-brancos)=%d/%d glifos=%d %s', fn, ru.error, ru.type, ru.pages.length, px, ru.pix.length, txt, d.length ? 'DIFERE(' + d.length + ')' : 'igual');
		for (const x of d.slice(0, 12)) failures.push('DIFF ' + x);
		// anti-cegueira
		if (ru.error === 0 && /\.pdf$/i.test(fn)) {
			if (px === 0 && !BLANK_OK.has(fn)) { failures.push('CEGO: ' + fn + ' nao renderizou nenhum pixel nao-branco (upstream)'); blind++; }
			const po = ro.pix.filter((x) => x && x.nonWhite > 0).length;
			if (po === 0 && !BLANK_OK.has(fn)) { failures.push('CEGO: ' + fn + ' nao renderizou nenhum pixel nao-branco (nosso)'); blind++; }
			if (/text|embedded|multipage/.test(fn) && txt === 0) failures.push('CEGO: ' + fn + ' sem texto extraido (glifos)');
		}
		if (ru.error !== ro.error) failures.push('erro de abertura difere em ' + fn);
	}
	if (args.json) fs.writeFileSync(args.json, JSON.stringify(rec, null, 1));
	if (failures.length) {
		console.log('\nFALHAS (%d):', failures.length);
		failures.slice(0, 60).forEach((f) => console.log(' - ' + f));
		process.exit(1);
	}
	console.log('\nOK: %d arquivos identicos entre upstream e nosso (tolerancia zero; %d divergencias conhecidas do SplitPages: MetaOForm vazio podado no nosso)', files.length, knownSplit);
}
main().catch((e) => { console.error('ERRO:', e.message); process.exit(2); });
