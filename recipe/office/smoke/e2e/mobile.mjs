// Gate O1.0 etapa d (mobile): abre docx/xlsx/pptx com UA+viewport de celular e verifica a UI de edicao religada.
import { launchChromium, Browser, sleep, SHOTS } from './cdp.mjs';
const EX = process.env.EX_URL;
if (!EX || !process.env.FILES_DIR) throw new Error('defina EX_URL e FILES_DIR (smoke/run.sh)');
const UA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const ext = process.argv[2] || 'docx';
const { proc, ws } = await launchChromium();
const stop = () => proc.kill();
const b = new Browser(ws); await b.connect();
const oe = b.onEvent.bind(b);
b.onEvent = (d) => { if (d.method === 'Runtime.exceptionThrown') console.log('EXC', (d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text).slice(0,400), d.params.exceptionDetails.url); if (d.method==='Runtime.consoleAPICalled' && d.params.type==='error') console.log('CONSOLE.ERR', JSON.stringify(d.params.args.map(a=>a.value||a.description)).slice(0,300)); if (d.method==='Network.responseReceived' && d.params.response.status>=400) console.log('HTTP', d.params.response.status, d.params.response.url); oe(d); };
const tab = await b.newTab(null, 'mobile');
await tab.send('Emulation.setUserAgentOverride', { userAgent: UA });
await tab.send('Emulation.setDeviceMetricsOverride', { width: 412, height: 860, deviceScaleFactor: 2.6, mobile: true });
await tab.send('Emulation.setTouchEmulationEnabled', { enabled: true });
await tab.send('Emulation.setFocusEmulationEnabled', { enabled: true });
await tab.goto(EX + '/editor?fileExt=' + ext + '&userid=uid-1&type=mobile');
await sleep(45000);
const info = await tab.eval(`JSON.stringify({mode: config.editorConfig.mode, perm: config.document.permissions, cust: config.editorConfig.customization.mobile, type: 1, frame: (document.querySelector('iframe[name=frameEditor]')||{}).src})`).catch(e => 'ERR ' + e.message);
console.log('config', info);
const dom = await tab.ed(`const e=window.Asc&&window.Asc.editor; return JSON.stringify({load: e&&e.isDocumentLoadComplete, canEdit: e&&e.canEdit&&e.canEdit(), mode: e&&e.asc_getViewMode&&e.asc_getViewMode(), appopt: (window.__appOptions||null), body: window.document.body.innerText.slice(0,200), btns:[...window.document.querySelectorAll('a.link, button')].map(x=>(x.id||x.className||'').toString().slice(0,40)).slice(0,30)})`).catch(e => 'ERR ' + e.message);
console.log('dom', dom);

const MARK = 'AXUZ-MOBILE-' + ext.toUpperCase() + '-' + Date.now().toString(36);
const clickBtn = (id) => tab.ed("const b=window.document.getElementById('" + id + "'); if(!b) return 'sem-botao'; b.click(); return 'ok'");
if (ext === 'docx') {
  // UX upstream do mobile: abre em leitura; o botao flutuante (lapis) liga a edicao (changeViewerMode(false))
  console.log('FAB', await tab.ed("const f=window.document.querySelector('.fab'); if(!f) return 'sem-fab'; f.click(); return 'ok'")); await sleep(2500);
  await tab.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:150,y:200}]}); await tab.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]}); await sleep(1200);
  console.log('restr', await tab.ed('return JSON.stringify({r: window.Asc.editor.restrictions, v: window.Asc.editor.isViewMode, form: window.Asc.editor.isRestrictionForms && window.Asc.editor.isRestrictionForms()})'));
  console.log('viewMode', await tab.ed("return window.Asc.editor.isViewMode"));
  await tab.send('Input.insertText', { text: MARK }); await sleep(2500);
  const txt = await tab.ed("return window.Asc.editor.WordControl.m_oLogicDocument.GetText({})");
  console.log('texto digitado no editor:', JSON.stringify(txt), txt.includes(MARK));
  console.log('shot digitado', await tab.shot('mobile-docx-2-digitado'));
  console.log('abrir Editar:', await clickBtn('btn-edit')); await sleep(2500);
  const ed = await tab.ed("return JSON.stringify({popup: [...window.document.querySelectorAll('.popup, .sheet-modal, .page')].map(e=>e.className.toString().slice(0,40)).slice(0,8), text: window.document.body.innerText.replace(/\\s+/g,' ').slice(0,300)})");
  console.log('painel editar', ed);
  console.log('shot editar', await tab.shot('mobile-docx-3-editar'));
  console.log('MARK', MARK);
  const fname = new URL(await tab.eval('location.href')).searchParams.get('fileName');
  await tab.eval('docEditor.destroyEditor(); true').catch(()=>{});
  const fs = await import('node:fs'); const cp = await import('node:child_process');
  const f = process.env.FILES_DIR + '/' + fname;
  let ok = false;
  for (let i = 0; i < 40 && !ok; i++) { await sleep(3000); try { const r = cp.spawnSync('python3', ['-I','-c','import sys,zipfile;print(zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode())', f], {encoding:'utf8', maxBuffer: 64e6}); ok = r.stdout.includes(MARK); } catch {} }
  console.log('SALVO NO DISCO', f, ok);
}
console.log('shot', await tab.shot('mobile-' + ext + '-1'));
try { b.ws.close(); } catch {} ; stop();
process.exit(0);
