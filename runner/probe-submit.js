// PROBE: real form submit, let Yelp mint its own token, capture /login/newajax.
// Answers one question: does the submit path still return "incorrect"/success, or only magic-link?
// One account, one credential, one IP. Run through probe-flow.ps1, not directly.
const http = require('http');
const net = require('net');
const fs = require('fs');
const { spawn } = require('child_process');
const os = require('os');
const path = require('path');

const OUT = process.env.OUT || 'probe.jsonl';
const PU_BASE = process.env.PU_BASE, PW = process.env.PW;
const EMAIL = process.env.EMAIL, PASS = process.env.PASS;
const PH = process.env.PROXY_HOST || 'pr.oxylabs.io', PP = parseInt(process.env.PROXY_PORT || '7777', 10);
const PW_ = process.env.PW;
const SESS = 'probe' + Math.floor(Math.random() * 1e6);
const PU = PU_BASE + '-sessid-' + SESS + '-sesstime-600';
const AUTH = 'Basic ' + Buffer.from(PU + ':' + PW).toString('base64');
const LP = 8988, CP = 9308;
const rec = o => { fs.appendFileSync(OUT, JSON.stringify(o) + '\n'); console.log(JSON.stringify(o)); };
const sleep = ms => new Promise(r => setTimeout(r, ms));

const relay = http.createServer((q, s) => {
  try { const u = new URL(q.url);
    const pr = http.request({ host: u.hostname, port: u.port || 80, method: q.method, path: u.pathname + u.search, headers: Object.assign({}, q.headers, { host: u.host }) }, r => { s.writeHead(r.statusCode, r.headers); r.pipe(s); });
    pr.on('error', () => s.destroy()); q.pipe(pr);
  } catch (e) { s.destroy(); }
});
relay.on('connect', (req, cs, head) => {
  const sock = net.connect(PP, PH, () => sock.write('CONNECT ' + req.url + ' HTTP/1.1\r\nHost: ' + req.url + '\r\nProxy-Authorization: ' + AUTH + '\r\n\r\n'));
  let buf = Buffer.alloc(0);
  function onData(d) {
    buf = Buffer.concat([buf, d]);
    const i = buf.indexOf('\r\n\r\n'); if (i < 0) return;
    sock.removeListener('data', onData);
    const rest = buf.slice(i + 4);
    const m = buf.slice(0, i).toString().match(/^HTTP\/1\.[01]\s+(\d+)/);
    if (!m || parseInt(m[1], 10) !== 200) { try { cs.end('HTTP/1.1 502 Bad Gateway\r\n\r\n'); } catch (e) {} sock.destroy(); return; }
    cs.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (rest.length) cs.write(rest);
    sock.pipe(cs); cs.pipe(sock);
    if (head && head.length) sock.write(head);
    sock.on('error', () => cs.destroy()); cs.on('error', () => sock.destroy());
  }
  sock.on('data', onData);
  sock.on('error', () => { try { cs.end('HTTP/1.1 502 Bad Gateway\r\n\r\n'); } catch (e) {} });
});

async function j(u, n) { for (let i = 0; i < n; i++) { try { const r = await fetch(u); return await r.json(); } catch (e) { await sleep(400); } } return null; }

(async () => {
  fs.writeFileSync(OUT, '');
  rec({ event: 'probe_start', email: EMAIL, sess: SESS });
  await new Promise(r => relay.listen(LP, '127.0.0.1', r));
  const udd = path.join(os.tmpdir(), 'cdp-probe-' + Date.now());
  const chrome = spawn(process.env.CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', [
    '--no-first-run', '--no-default-browser-check', '--disable-blink-features=AutomationControlled',
    '--window-size=900,700', '--lang=en-US', '--user-data-dir=' + udd,
    '--proxy-server=http://127.0.0.1:' + LP, '--remote-debugging-port=' + CP,
    'https://www.yelp.com/login/'
  ], { stdio: 'ignore' });

  const ver = await j('http://127.0.0.1:' + CP + '/json/version', 40);
  if (!ver) { rec({ event: 'abort', why: 'cdp' }); chrome.kill(); relay.close(); return; }
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  let id = 0; const pend = new Map();
  ws.addEventListener('message', ev => { let m; try { m = JSON.parse(ev.data); } catch (e) { return; } if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } });
  await new Promise((res, rej) => { ws.addEventListener('open', res); ws.addEventListener('error', rej); });
  const send = (mth, p) => new Promise(resolve => { const mid = ++id; pend.set(mid, resolve); ws.send(JSON.stringify({ id: mid, method: mth, params: p || {} })); });
  let sid = null;
  const sendS = (mth, p) => new Promise(resolve => { const mid = ++id; pend.set(mid, resolve); ws.send(JSON.stringify({ id: mid, method: mth, params: p || {}, sessionId: sid })); });
  await sleep(7000);
  const t = await send('Target.getTargets');
  if (t && t.result) { const pg = t.result.targetInfos.find(x => x.type === 'page'); if (pg) { const a = await send('Target.attachToTarget', { targetId: pg.targetId, flatten: true }); if (a && a.result) sid = a.result.sessionId; } }
  const ev = e => new Promise(resolve => {
    const mid = Math.floor(Math.random() * 1e9);
    const h = x => { try { const m = JSON.parse(x.data); if (m.id === mid) { ws.removeEventListener('message', h); resolve(m.result && m.result.result ? m.result.result.value : null); } } catch (err) {} };
    ws.addEventListener('message', h);
    ws.send(JSON.stringify({ id: mid, method: 'Runtime.evaluate', params: { expression: e, returnByValue: true, awaitPromise: true }, sessionId: sid }));
    setTimeout(() => resolve(null), 30000);
  });
  await sendS('Page.enable'); await sendS('Network.enable');

  const cap = { reqId: null, status: null, body: null };
  ws.addEventListener('message', async ev2 => {
    let m; try { m = JSON.parse(ev2.data); } catch (e) { return; }
    if (m.method === 'Network.responseReceived' && m.params.response.url.includes('/login/newajax')) { cap.reqId = m.params.requestId; cap.status = m.params.response.status; }
    if (m.method === 'Network.loadingFinished' && cap.reqId && m.params.requestId === cap.reqId) {
      const b = await sendS('Network.getResponseBody', { requestId: cap.reqId });
      if (b && b.result) cap.body = b.result.body;
    }
  });

  let ddok = false;
  for (let k = 0; k < 25; k++) {
    await sleep(2000);
    const s = await ev('JSON.stringify({l:document.documentElement.outerHTML.length,t:document.title})');
    try { const o = JSON.parse(s); if (o && o.l > 200000 && /Log In/i.test(o.t || '')) { ddok = true; break; } } catch (e) {}
  }
  rec({ event: 'ddok', ddok });
  if (!ddok) { rec({ event: 'abort', why: 'dd' }); chrome.kill(); relay.close(); return; }

  let hyd = false;
  for (let a = 0; a < 4 && !hyd; a++) {
    await sendS('Page.navigate', { url: 'https://www.yelp.com/login/' });
    for (let k = 0; k < 20; k++) {
      await sleep(1000);
      const s = await ev('JSON.stringify({f:!!document.getElementById("ajax-login"),h:!!window.hcaptcha,l:document.documentElement.outerHTML.length})');
      try { const o = JSON.parse(s); if (o && o.f && o.h && o.l > 400000) { hyd = true; break; } } catch (e) {}
    }
  }
  rec({ event: 'hydrated', ok: hyd });
  if (!hyd) { rec({ event: 'abort', why: 'hydrate' }); chrome.kill(); relay.close(); return; }

  const pre = await ev('JSON.stringify({w:document.querySelectorAll("[data-hcaptcha-widget-id]").length, cap:document.querySelectorAll(".h-captcha,[id^=hcaptcha]").length, ifr:document.querySelectorAll("iframe[src*=hcaptcha]").length})');
  rec({ event: 'widget_presence', before: JSON.parse(pre || '{}') });

  await ev('(function(){var l=document.querySelector("#ajax-login .login-with-password-link"); if(l) l.click(); return !!l;})()');
  await sleep(1200);

  const filled = await ev('(function(){var f=document.getElementById("ajax-login"); if(!f) return "noform";' +
    'var e=f.querySelector("input[name=email]"), p=f.querySelector("input[name=password]"); if(!p) return "nopass";' +
    'function set(el,v){var d=Object.getOwnPropertyDescriptor(el.constructor.prototype,"value"); d.set.call(el,v); el.dispatchEvent(new Event("input",{bubbles:true})); el.dispatchEvent(new Event("change",{bubbles:true}));}' +
    'if(e) set(e,' + JSON.stringify(EMAIL) + '); set(p,' + JSON.stringify(PASS) + '); return "ok";})()');
  rec({ event: 'filled', r: filled });

  const clicked = await ev('(function(){var b=document.querySelector("#ajax-login button.submit, #ajax-login .submit, #ajax-login button[type=submit]"); if(!b) return "nobtn"; b.click(); return "clicked";})()');
  rec({ event: 'clicked', r: clicked });

  for (let k = 0; k < 90 && !cap.body; k++) await sleep(500);
  const post = await ev('JSON.stringify({w:document.querySelectorAll("[data-hcaptcha-widget-id]").length, ifr:document.querySelectorAll("iframe[src*=hcaptcha]").length})');

  let js = null; try { js = JSON.parse(cap.body || 'null'); } catch (e) {}
  const text = (js && (js.errors || []).join(' | ')) || cap.body || '';
  const verdict = !!(js && js.success) ? 'success'
    : /incorrect/i.test(text) ? 'validated'
    : /has been closed/i.test(text) ? 'closed'
    : /unable to log you in/i.test(text) ? 'unable'
    : /login link|magic link|confirm it/i.test(text) ? 'link'
    : cap.body ? 'other' : 'no-post';

  rec({ event: 'result', verdict, status: cap.status, body: (cap.body || '').slice(0, 400), widgetPresenceAfter: JSON.parse(post || '{}'), email: EMAIL });
  try { ws.close(); } catch (e) {}
  try { chrome.kill(); } catch (e) {}
  try { fs.rmSync(udd, { recursive: true, force: true }); } catch (e) {}
  try { relay.close(); } catch (e) {}
  setTimeout(() => process.exit(verdict === 'validated' || verdict === 'success' ? 0 : 1), 800);
})().catch(e => { rec({ event: 'crash', err: String(e) }); process.exit(2); });
