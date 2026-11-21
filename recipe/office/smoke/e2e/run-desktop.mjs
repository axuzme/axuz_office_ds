// O1.a-pre (reuso do gate O1.0, etapa d desktop): abre/edita/salva/co-edita docx, xlsx, pptx, odt no ONLYOFFICE DS via chromium+CDP.
// Uso: node run-desktop.mjs [formatos separados por virgula]   (default: docx,xlsx,pptx,odt)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { launchChromium, Browser, sleep, OUT, SHOTS } from './cdp.mjs';

const EX = process.env.EX_URL; // app exemplo (exampleUrl sem barra final); smoke/run.sh define
if (!EX || !process.env.FILES_DIR || !process.env.DS_LOG || !process.env.SAMPLE_ODT) throw new Error('defina EX_URL, FILES_DIR, DS_LOG e SAMPLE_ODT (smoke/run.sh)');
const FILES = process.env.FILES_DIR;
const DSLOG = process.env.DS_LOG;
const SAMPLE_ODT = process.env.SAMPLE_ODT;
const RUN = Date.now().toString(36);
const results = {};
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ---------- leitura/escrita no editor ----------
const READY = 'const e=window.Asc&&window.Asc.editor; return !!(e && e.isDocumentLoadComplete && (e.wb || (e.WordControl && e.WordControl.m_oLogicDocument)))';
const READ = {
  word: 'const ld=window.Asc.editor.WordControl.m_oLogicDocument; return ld.GetText({})',
  cell: 'const ws=window.Asc.editor.wb.model.getActiveWs(); const o=[]; for(let r=0;r<12;r++)for(let c=0;c<8;c++){const v=ws.getCell3(r,c).getValue(); if(v) o.push(v);} return o.join("|")',
  slide: 'const ld=window.Asc.editor.WordControl.m_oLogicDocument; const o=[]; ld.Slides.forEach(s=>s.cSld.spTree.forEach(sp=>{const c=sp.getDocContent&&sp.getDocContent(); if(c) o.push(c.GetText({}).trim());})); return o.join("|")',
};
const kind = (ext) => ({ docx: 'word', odt: 'word', xlsx: 'cell', pptx: 'slide' })[ext];
const readText = (tab, ext) => tab.ed(READ[kind(ext)]);
const modalTexts = (tab) => tab.ed("return [...window.document.querySelectorAll('.asc-window')].filter(x=>x.offsetParent!==null).map(x=>x.innerText.trim().replace(/\\s+/g,' ').slice(0,160))");
const CTRL_END = (t) => t.press('End', 'End', 35, 2);
const cellXY = (col, row) => [98 + 64 * col, 204 + 19 * (row - 1)];

// posiciona o cursor num "slot" e digita
async function typeAt(tab, ext, slot, text) {
  const k = kind(ext);
  if (k === 'word') {
    await tab.click(700, 300); await sleep(400); await CTRL_END(tab); await sleep(200);
    if (slot !== 'first') { await tab.press('Enter', 'Enter', 13); await sleep(200); }
    await tab.type(text);
  } else if (k === 'cell') {
    const [x, y] = ({ first: cellXY(0, 1), A: cellXY(1, 3), B: cellXY(3, 6) })[slot];
    await tab.click(x, y); await sleep(400); await tab.type(text); await tab.press('Enter', 'Enter', 13);
  } else {
    const [x, y] = slot === 'A' ? [820, 560] : [820, 440]; // A=subtitulo, B/first=titulo
    await tab.click(x, y); await sleep(500); await CTRL_END(tab); await tab.type(text);
  }
  await sleep(1500);
}

// ---------- disco do host ----------
function diskText(file) {
  const p = path.join(FILES, file);
  if (!fs.existsSync(p)) return null;
  const py = 'import sys,zipfile\nz=zipfile.ZipFile(sys.argv[1])\nprint("\\n".join(z.read(n).decode("utf8","replace") for n in z.namelist() if n.endswith(".xml")))';
  const r = spawnSync('python3', ['-I', '-c', py, p], { encoding: 'utf8', maxBuffer: 64e6 });
  return r.status === 0 ? r.stdout : 'ERRO-ZIP ' + r.stderr.slice(0, 200);
}
const listDir = () => fs.readdirSync(FILES).filter((f) => !f.endsWith('-history') && f !== 'tmp').sort();

async function waitDisk(file, markers, ms = 240000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    const t = diskText(file);
    if (t && markers.every((m) => t.includes(m))) return { ok: true, secs: Math.round((Date.now() - t0) / 1000) };
    await sleep(3000);
  }
  return { ok: false, secs: Math.round((Date.now() - t0) / 1000) };
}

const dsLogSize = () => fs.statSync(DSLOG).size;
function dsLogSince(off) {
  const buf = fs.readFileSync(DSLOG).subarray(off).toString('utf8');
  return buf.split('\n').filter((l) => /\[(ERROR|WARN)\]|status|saveFromChanges|sendServerRequest|postData|forcesave|callback/i.test(l)).map((l) => l.slice(0, 260));
}

// ---------- abrir editor ----------
async function openEditor(b, label, url, ext) {
  const tab = await b.newTab(url, label);
  await tab.waitFor(() => tab.ed(READY), 90000);
  await sleep(2500);
  const modals = await modalTexts(tab).catch(() => []);
  const bad = modals.filter((m) => /error|fail|could not|erro/i.test(m));
  return { tab, modals, bad };
}
const fileNameOf = async (tab) => new URL(await tab.eval('location.href')).searchParams.get('fileName');
const edUrl = (name, user) => `${EX}/editor?mode=edit&fileName=${encodeURIComponent(name)}&userid=${user}`;
const closeEd = async (tab) => { await tab.eval('docEditor.destroyEditor(); true').catch(() => {}); await sleep(1500); };

// ---------- pipeline por arquivo ----------
async function pipeline(b, ext, fileName, { coedit = true, tag = ext } = {}) {
  const R = { ext, tag, fileName, steps: {} };
  const M1 = `AXUZ-${ext.toUpperCase()}-${RUN}-UM`;
  const M2A = `AXUZ-${ext.toUpperCase()}-${RUN}-DOIS-A`;
  const M2B = `AXUZ-${ext.toUpperCase()}-${RUN}-DOIS-B`;
  const off = dsLogSize();
  const nets0 = b.net.length;

  // fase 1: abre, edita, fecha, salva
  log(tag, 'fase 1: abrir');
  const A = await openEditor(b, `${tag}-A1`, edUrl(fileName, 'uid-1'), ext);
  R.open = { ok: A.bad.length === 0, modals: A.modals, bad: A.bad };
  R.mode = await A.tab.eval('docEditor && docEditor.config && JSON.stringify({mode:docEditor.config.editorConfig.mode, canEdit:docEditor.config.document.permissions.edit})').catch((e) => 'n/d ' + e.message);
  R.shotOpen = await A.tab.shot(`${tag}-1-aberto`);
  await typeAt(A.tab, ext, 'first', M1);
  const t1 = await readText(A.tab, ext);
  R.edit = { ok: t1.includes(M1), model: t1.slice(0, 200) };
  R.shotEdit = await A.tab.shot(`${tag}-2-editado`);
  log(tag, 'editado:', R.edit.ok, JSON.stringify(t1.slice(0, 80)));
  await closeEd(A.tab);
  R.save1 = await waitDisk(fileName, [M1]);
  R.save1.ext = fileName.split('.').pop();
  log(tag, 'salvo no disco:', JSON.stringify(R.save1));
  await b.closeTab(A.tab);

  // fase 2: co-edicao
  if (coedit) {
    log(tag, 'fase 2: co-edicao');
    const A2 = await openEditor(b, `${tag}-A2`, edUrl(fileName, 'uid-1'), ext);
    const B2 = await openEditor(b, `${tag}-B2`, edUrl(fileName, 'uid-2'), ext);
    const start = await readText(B2.tab, ext);
    R.co = { startSeesPhase1: start.includes(M1) };
    await typeAt(A2.tab, ext, 'A', M2A);
    const bSeesA = await B2.tab.waitFor(async () => (await readText(B2.tab, ext)).includes(M2A), 60000).then(() => true).catch(() => false);
    await typeAt(B2.tab, ext, 'B', M2B);
    const aSeesB = await A2.tab.waitFor(async () => (await readText(A2.tab, ext)).includes(M2B), 60000).then(() => true).catch(() => false);
    R.co.bSeesA = bSeesA; R.co.aSeesB = aSeesB;
    R.co.usersOnline = await A2.tab.ed('return JSON.stringify((window.Asc.editor.CoAuthoringApi&&window.Asc.editor.CoAuthoringApi._CoAuthoringApi&&window.Asc.editor.CoAuthoringApi._CoAuthoringApi._participants&&Object.keys(window.Asc.editor.CoAuthoringApi._CoAuthoringApi._participants))||null)').catch(() => null);
    R.co.modelA = (await readText(A2.tab, ext)).slice(0, 300);
    R.co.modelB = (await readText(B2.tab, ext)).slice(0, 300);
    R.shotCoA = await A2.tab.shot(`${tag}-3-coedit-A-uid1`);
    R.shotCoB = await B2.tab.shot(`${tag}-3-coedit-B-uid2`);
    log(tag, 'co:', JSON.stringify({ bSeesA, aSeesB }));
    await closeEd(A2.tab); await closeEd(B2.tab);
    R.co.save = await waitDisk(fileName, [M1, M2A, M2B]);
    R.co.disk = { hasM1: (diskText(fileName) || '').includes(M1), hasA: (diskText(fileName) || '').includes(M2A), hasB: (diskText(fileName) || '').includes(M2B) };
    log(tag, 'co salvo:', JSON.stringify(R.co.save), JSON.stringify(R.co.disk));
    await b.closeTab(A2.tab); await b.closeTab(B2.tab);
  }
  R.dsLog = dsLogSince(off);
  fs.writeFileSync(path.join(OUT, `docservice-${tag}.log`), R.dsLog.join('\n') + '\n');
  R.netCount = b.net.length - nets0;
  R.dirAfter = listDir().filter((f) => f.startsWith(fileName.replace(/\.[^.]+$/, '').slice(0, 8)));
  return R;
}

async function newDemo(b, ext) {
  // cria o arquivo-demo sem abrir editor: so le o redirect do exemplo
  const r = await fetch(EX + '/editor?fileExt=' + ext + '&userid=uid-1', { redirect: 'manual' });
  return new URL(r.headers.get('location'), EX).searchParams.get('fileName');
}

async function odtFlows(b) {
  const out = {};
  const up = (name) => {
    const cp = path.join(OUT, name); fs.copyFileSync(SAMPLE_ODT, cp);
    const r = execFileSync('curl', ['-s', '-F', `uploadedFile=@${cp}`, `${EX}/upload?userid=uid-1`], { encoding: 'utf8' });
    return JSON.parse(r);
  };
  // (a) abrir o .odt direto no editor
  const nameA = `axuz-e2e-${RUN}.odt`;
  out.uploadDirect = up(nameA);
  log('odt direto: upload', JSON.stringify(out.uploadDirect));
  out.direct = await pipeline(b, 'odt', nameA, { tag: 'odt-direto' });
  // (b) fluxo do exemplo: /convert (odt -> ooxml)
  const nameB = `axuz-conv-${RUN}.odt`;
  out.uploadConv = up(nameB);
  const off = dsLogSize();
  let conv = null;
  for (let i = 0; i < 40; i++) {
    const r = await fetch(`${EX}/convert?userid=uid-1`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ filename: nameB }) });
    conv = await r.json(); log('convert ->', JSON.stringify(conv));
    if (conv.step === 100 || conv.error) break; await sleep(3000);
  }
  out.convert = conv; out.convertLog = dsLogSince(off).slice(-10);
  out.dirAfterConvert = listDir().filter((f) => f.includes(`axuz-conv-${RUN}`));
  if (conv && conv.filename && conv.filename.endsWith('.docx')) {
    out.convertedZip = (execFileSync('unzip', ['-l', path.join(FILES, conv.filename)], { encoding: 'utf8' }).match(/word\/document\.xml/) || [null])[0];
    out.viaConvert = await pipeline(b, 'docx', conv.filename, { coedit: false, tag: 'odt-via-convert-docx' });
  }
  return out;
}

// ---------- rede ----------
function netReport(net) {
  const rows = {};
  for (const n of net) {
    let host; let scheme;
    try { const u = new URL(n.url); scheme = u.protocol; host = u.host; } catch { scheme = '?'; host = n.url.slice(0, 40); }
    let origin = 'n/d';
    try { origin = new URL(n.documentURL).host; } catch {}
    const loopback = /^(127\.0\.0\.1|172\.18\.0\.5|localhost)(:|$)/.test(host);
    const web = scheme === 'http:' || scheme === 'https:';
    const key = [scheme, host, web ? (loopback ? 'LOCAL(127/host)' : 'EXTERNO') : 'nao-rede', 'doc=' + origin].join(' | ');
    rows[key] = (rows[key] || 0) + 1;
  }
  return rows;
}

// ---------- main ----------
const want = (process.argv[2] || 'docx,xlsx,pptx,odt').split(',');
const { proc, ws } = await launchChromium();
const b = new Browser(ws);
try {
  await b.connect();
  for (const ext of want) {
    try {
      if (ext === 'odt') results.odt = await odtFlows(b);
      else { const name = await newDemo(b, ext); log(ext, 'arquivo:', name); results[ext] = await pipeline(b, ext, name); }
    } catch (e) { log(ext, 'FALHOU:', e.stack); results[ext] = { error: e.message }; }
    fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(results, null, 1));
  }
  const rep = netReport(b.net);
  fs.writeFileSync(path.join(OUT, 'network.json'), JSON.stringify({ total: b.net.length, grouped: rep }, null, 1));
  fs.writeFileSync(path.join(OUT, 'network-urls.txt'), [...new Set(b.net.map((n) => `${n.tab}\t${n.type}\t${n.documentURL.split('?')[0]}\t${n.url.split('?')[0]}`))].sort().join('\n') + '\n');
  log('rede:', JSON.stringify(rep, null, 1));
} finally {
  proc.kill(); await new Promise((r) => proc.once('exit', r)); await sleep(500);
  fs.rmSync(path.join(path.dirname(SHOTS), 'profile'), { recursive: true, force: true }); }
