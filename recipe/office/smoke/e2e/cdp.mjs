// Helper CDP minimo (WebSocket embutido do node 24). Sem dependencias.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = path.dirname(fileURLToPath(import.meta.url));
// saida fora do git: SMOKE_OUT (smoke/run.sh aponta para <ws>/smoke-out)
const BASE = process.env.SMOKE_OUT || HERE;
export const SHOTS = path.join(BASE, 'shots');
export const OUT = path.join(BASE, 'out');
fs.mkdirSync(SHOTS, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const PORT = 9333;

export async function launchChromium() {
  const profile = path.join(BASE, 'profile');
  fs.rmSync(profile, { recursive: true, force: true });
  const p = spawn('/usr/bin/chromium', ['--headless=new', '--no-sandbox', '--disable-web-security',
    '--disable-site-isolation-trials', '--user-data-dir=' + profile, '--remote-debugging-port=' + PORT,
    '--window-size=1400,900', '--disable-gpu', '--no-first-run', 'about:blank'], { stdio: 'ignore' });
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch('http://127.0.0.1:' + PORT + '/json/version');
      if (r.ok) { const j = await r.json(); return { proc: p, ws: j.webSocketDebuggerUrl }; }
    } catch {}
    await sleep(250);
  }
  throw new Error('chromium nao subiu');
}

export class Browser {
  constructor(wsUrl) { this.wsUrl = wsUrl; this.id = 0; this.pending = new Map(); this.net = []; this.tabs = {}; }
  async connect() {
    this.ws = new WebSocket(this.wsUrl);
    await new Promise((res, rej) => { this.ws.onopen = res; this.ws.onerror = rej; });
    this.ws.onmessage = (m) => {
      const d = JSON.parse(m.data);
      if (d.id && this.pending.has(d.id)) {
        const { res, rej } = this.pending.get(d.id); this.pending.delete(d.id);
        d.error ? rej(new Error(JSON.stringify(d.error))) : res(d.result);
      } else if (d.method) this.onEvent(d);
    };
  }
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((res, rej) => {
      this.pending.set(id, { res, rej });
      setTimeout(() => { if (this.pending.delete(id)) rej(new Error('timeout ' + method)); }, 60000);
    });
  }
  onEvent(d) {
    if (d.method === 'Network.requestWillBeSent') {
      const { request, frameId, documentURL, type } = d.params;
      this.net.push({ url: request.url, method: request.method, frameId, type, documentURL, tab: this.tabs[d.sessionId] || '?' });
    }
    if (d.method === 'Target.attachedToTarget') {
      const s = d.params.sessionId;
      this.tabs[s] = this.tabs[s] || 'sub';
      this.send('Network.enable', {}, s).catch(() => {});
      this.send('Runtime.runIfWaitingForDebugger', {}, s).catch(() => {});
    }
  }
  async newTab(url, label) {
    const { targetId } = await this.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await this.send('Target.attachToTarget', { targetId, flatten: true });
    this.tabs[sessionId] = label;
    const tab = new Tab(this, sessionId, label);
    tab.targetId = targetId;
    await tab.send('Page.enable'); await tab.send('Network.enable'); await tab.send('Runtime.enable');
    await this.send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true }, sessionId);
    await tab.send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
    if (url) await tab.goto(url);
    return tab;
  }
  async closeTab(tab) { await this.send('Target.closeTarget', { targetId: tab.targetId }).catch(() => {}); }
}

export class Tab {
  constructor(b, sessionId, label) { this.b = b; this.sessionId = sessionId; this.label = label; }
  send(m, p = {}) { return this.b.send(m, p, this.sessionId); }
  async goto(url) { await this.send('Page.navigate', { url }); await sleep(1500); }
  async eval(expr, awaitPromise = true) {
    const r = await this.send('Runtime.evaluate', { expression: expr, awaitPromise, returnByValue: true });
    if (r.exceptionDetails) throw new Error('eval: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
    return r.result.value;
  }
  // Avalia no iframe do editor (web-security off => acesso direto). `body` recebe `window` = contentWindow do iframe.
  async ed(body) {
    const src = "(async()=>{const f=document.querySelector('iframe[name=frameEditor]');const w=f.contentWindow;"
      + 'return await (async function(window){' + body + '})(w);})()';
    return this.eval(src);
  }
  async shot(name) {
    const r = await this.send('Page.captureScreenshot', { format: 'png' });
    const f = path.join(SHOTS, name + '.png'); fs.writeFileSync(f, Buffer.from(r.data, 'base64')); return f;
  }
  async type(text) { for (const ch of text) await this.send('Input.dispatchKeyEvent', { type: 'char', text: ch }); }
  async press(key, code, vk, mods = 0) {
    await this.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key, code, windowsVirtualKeyCode: vk, modifiers: mods });
    await this.send('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: vk, modifiers: mods });
  }
  async click(x, y) {
    await this.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
    await this.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await this.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  }
  async waitFor(fn, ms = 60000, step = 500) {
    const t0 = Date.now(); let last;
    while (Date.now() - t0 < ms) {
      try { last = await fn(); if (last) return last; } catch (e) { last = e.message; }
      await sleep(step);
    }
    throw new Error('waitFor timeout; ultimo=' + JSON.stringify(last));
  }
}
