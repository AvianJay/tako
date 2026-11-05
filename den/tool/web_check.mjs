// Drives the web app in headless Chrome over the DevTools protocol, through
// every page: first-run setup, the admin tabs, chat with a streamed reply and
// sync with another device, settings, registering with an invite, and
// approving an app's browser sign-in. Needs a fresh server whose only
// upstream is tool/fake_upstream.mjs:
//   node tool/fake_upstream.mjs 18080
//   OLLAMA_URL=http://127.0.0.1:18080 TAKO_DATA=<empty dir> dart run bin/tako_den.dart
//   node tool/web_check.mjs http://127.0.0.1:8787 <setup token from the log>
// Environment: CHROME (browser path), WINDOW (e.g. 390,844), SHOTS (folder),
// SCHEME (light or dark; default the system's).
import { spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [, , base = 'http://127.0.0.1:8787', setupToken] = process.argv;
const chrome = process.env.CHROME ?? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const window = process.env.WINDOW ?? '1200,820';
const width = Number(window.split(',')[0]);
const scheme = process.env.SCHEME;
const shots = process.env.SHOTS ?? tmpdir();
const port = 9230;
const profile = join(tmpdir(), 'tako-den-web-check');
const password = 'correct horse';
mkdirSync(shots, { recursive: true });
rmSync(profile, { recursive: true, force: true });
const proc = spawn(
  chrome,
  ['--headless=new', '--lang=en-US', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, `--window-size=${window}`, '--no-first-run', '--no-default-browser-check', 'about:blank'],
  { stdio: 'ignore' },
);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 100 && !target; i++) {
  try {
    target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page');
  } catch {}
  if (!target) await sleep(200);
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));

let nextId = 0;
const pending = new Map();
const problems = [];
const expected = [];
ws.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
    return;
  }
  const p = msg.params;
  if (msg.method === 'Runtime.exceptionThrown') problems.push('exception: ' + (p.exceptionDetails.exception?.description ?? p.exceptionDetails.text));
  if (msg.method === 'Runtime.consoleAPICalled' && p.type === 'error') problems.push('console: ' + p.args.map((a) => a.value ?? a.description).join(' '));
  if (msg.method === 'Log.entryAdded' && p.entry.level === 'error') {
    // Error responses the steps provoke on purpose are listed, not failures.
    (/status of 4\d\d/.test(p.entry.text) ? expected : problems).push(`log: ${p.entry.text} ${p.entry.url ?? ''}`);
  }
});
const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, (msg) => (msg.error ? reject(new Error(`${method}: ${msg.error.message}`)) : resolve(msg.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });

// Page helpers, defined for every evaluation (the page's CSP does not apply
// to DevTools evaluation).
const helpers = `
  const visible = (e) => !!e && !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const scope = () => document.querySelector('dialog[open]') || document;
  const button = (text, root = scope()) => [...root.querySelectorAll('button, a')].find((e) => e.textContent.trim() === text && visible(e));
  const click = (text, root) => { const b = button(text, root); if (!b) throw new Error('no button ' + text); b.click(); return true; };
  const input = (label, root = scope()) => {
    const f = [...root.querySelectorAll('label.field, div.field')].find((e) => e.querySelector('.label')?.textContent.trim() === label);
    if (!f) throw new Error('no field ' + label);
    return f.querySelector('input, select, textarea');
  };
  const fill = (label, value, root) => {
    const e = input(label, root);
    e.value = value;
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  };
  const check = (label, on, root = scope()) => {
    const t = [...root.querySelectorAll('label.toggle')].find((e) => e.querySelector('b')?.textContent.trim() === label);
    if (!t) throw new Error('no toggle ' + label);
    const box = t.querySelector('input');
    if (box.checked !== on) box.click();
    return true;
  };
  const submit = (root = scope()) => { root.querySelector('form').requestSubmit(); return true; };
  const text = () => document.body.innerText;
  const toasts = () => document.getElementById('toasts')?.innerText ?? '';
`;
const evaluate = async (expression) => {
  const r = await send('Runtime.evaluate', { expression: `(async () => { ${helpers} return (${expression}); })()`, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(`${expression} -> ${r.exceptionDetails.exception?.description ?? r.exceptionDetails.text}`);
  return r.result.value;
};
const waitFor = async (expression, label, timeout = 15000) => {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try {
      if (await evaluate(expression)) return;
    } catch (e) {
      last = e.message;
    }
    await sleep(100);
  }
  throw new Error(`timed out waiting for ${label}${last ? ` (${last})` : ''}`);
};
const go = async (path) => {
  await send('Page.navigate', { url: base + path });
  await waitFor(`document.readyState === 'complete' && !document.querySelector('#app > .loading')`, `page ${path}`);
};
const shot = async (name) => writeFileSync(join(shots, `web-${name}-${width}${scheme ? `-${scheme}` : ''}.png`), Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64'));
const api = async (path, token, body, method) => {
  const res = await fetch(base + path, {
    method: method ?? (body ? 'POST' : 'GET'),
    headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok && res.status !== 202) throw new Error(`${path} ${res.status} ${await res.text()}`);
  return res.status === 202 ? { pending: true } : res.json();
};
const step = (name) => console.log(`- ${name}`);

let failed = false;
try {
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Log.enable');
  if (scheme) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: scheme }] });

  step('first-run setup');
  await go(`/setup?token=${encodeURIComponent(setupToken)}`);
  await shot('setup');
  await evaluate(`fill('Password', ${JSON.stringify(password)}) && fill('Display name', 'Avery') && submit()`);
  await waitFor(`location.pathname === '/admin' && text().includes('Server name')`, 'admin page after setup');
  const admin = await evaluate(`localStorage.getItem('den.token')`);

  step('admin: server settings');
  await evaluate(`fill('Server name', 'Den Test') && fill('Public URL', ${JSON.stringify(base)}) && fill('Registration', 'invite') && submit(document)`);
  await waitFor(`toasts().includes('Saved')`, 'settings saved');
  const settings = await api('/v1/admin/settings', admin);
  if (settings.serverName !== 'Den Test' || settings.registration !== 'invite' || settings.publicUrl !== base) throw new Error('settings not saved: ' + JSON.stringify(settings));
  await shot('admin-server');

  step('admin: users and permissions');
  await go('/admin?tab=users');
  await evaluate(`click('Add user')`);
  await evaluate(`fill('Username', 'ana') && fill('Password', 'ana-password') && submit()`);
  await waitFor(`!document.querySelector('dialog[open]') && text().includes('@ana')`, 'new user listed');
  await evaluate(`click('Edit', [...document.querySelectorAll('tr')].find((r) => r.textContent.includes('@ana')))`);
  await waitFor(`document.querySelector('dialog[open]')`, 'edit dialog');
  await evaluate(`fill('Daily shared-token limit', 'limit') && (input('Daily shared-token limit').parentElement.querySelector('input').value = '5000') && fill('May add their own providers', 'no') && submit()`);
  await waitFor(`!document.querySelector('dialog[open]')`, 'user saved');
  const ana = (await api('/v1/admin/users', admin)).users.find((u) => u.username === 'ana');
  if (ana.permissions.dailyTokenLimit !== 5000 || ana.permissions.ownProviders !== false || ana.effectivePermissions.useSharedProviders !== true) throw new Error('permissions not saved: ' + JSON.stringify(ana.permissions));
  await shot('admin-users');

  step('admin: shared providers');
  await go('/admin?tab=providers');
  await waitFor(`text().includes('ollama')`, 'config provider listed');
  await evaluate(`click('Add')`);
  await evaluate(`fill('Id', 'echo') && fill('Display name', 'Echo') && fill('Base URL', 'http://127.0.0.1:18080/v1') && fill('Model allowlist', 'echo-1') && submit()`);
  await waitFor(`!document.querySelector('dialog[open]') && text().includes('Echo')`, 'shared provider added');
  await evaluate(`click('Test', [...document.querySelectorAll('tr')].find((r) => r.textContent.includes('Echo')))`);
  await waitFor(`toasts().includes('1 models found')`, 'provider test');
  await shot('admin-providers');

  step('admin: sign-in methods');
  await go('/admin?tab=oauth');
  await evaluate(`click('Add')`);
  await evaluate(`fill('Type', 'discord')`);
  await waitFor(`document.querySelector('dialog[open] code').textContent.endsWith('/v1/auth/oauth/discord/callback')`, 'redirect URI preview');
  await evaluate(`fill('Client ID', '1234567890') && fill('Client secret', 'discord-secret') && submit()`);
  await waitFor(`!document.querySelector('dialog[open]') && text().includes('Discord')`, 'oauth provider added');
  const info = await api('/v1/info');
  if (!info.oauth.some((o) => o.id === 'discord')) throw new Error('discord missing from /v1/info');
  const start = await fetch(`${base}/v1/auth/oauth/discord/start?return=/`, { redirect: 'manual' });
  const location = new URL(start.headers.get('location'));
  if (location.host !== 'discord.com' || location.searchParams.get('redirect_uri') !== `${base}/v1/auth/oauth/discord/callback` || !location.searchParams.get('state')) throw new Error('bad OAuth start: ' + location);
  await shot('admin-oauth');

  step('admin: invites and usage');
  await go('/admin?tab=invites');
  await evaluate(`click('Create invite')`);
  await evaluate(`fill('Note', 'for Bob') && submit()`);
  await waitFor(`document.querySelector('dialog[open] code')?.textContent.includes('/register?invite=')`, 'invite link');
  const inviteLink = await evaluate(`document.querySelector('dialog[open] code').textContent`);
  await evaluate(`click('Close')`);
  await waitFor(`text().includes('for Bob')`, 'invite listed');
  await shot('admin-invites');
  await go('/admin?tab=usage');
  await shot('admin-usage');

  step('chat: streamed reply');
  await go('/');
  await waitFor(`[...document.querySelector('.model').options].some((o) => o.value === 'echo/echo-1')`, 'models in the picker');
  console.log('  models:', await evaluate(`[...document.querySelector('.model').options].map((o) => o.value).join(', ')`));
  await evaluate(`(document.querySelector('.model').value = 'echo/echo-1') && (document.querySelector('.composer textarea').value = 'Hello **Tako**') && document.querySelector('.composer').requestSubmit() || true`);
  await waitFor(`document.querySelector('.send').disabled && document.querySelector('.log').textContent.includes('你說')`, 'text while streaming');
  await waitFor(`!document.querySelector('.send').disabled`, 'reply finished', 20000);
  const reply = await evaluate(`document.querySelector('.msg.assistant .body').textContent`);
  const bold = await evaluate(`document.querySelector('.msg.user .body strong')?.textContent`);
  console.log('  reply:', JSON.stringify(reply), 'bold:', bold);
  if (bold !== 'Tako') throw new Error('markdown not rendered');
  await shot('chat');

  step('sync with another device');
  const phone = await api('/v1/auth/login', null, { username: 'admin', password, deviceName: 'Fake phone' });
  const pulled = await api('/v1/sync/pull?since=0', phone.token);
  const conv = pulled.changes.find((c) => c.collection === 'conversations')?.data;
  const msgs = pulled.changes.filter((c) => c.collection === 'messages').map((c) => c.data);
  const user = msgs.find((m) => m.role === 'user');
  const leaf = msgs.find((m) => m.id === conv?.activeLeafId);
  if (!(leaf?.role === 'assistant' && leaf.status === 'done' && leaf.parentId === user?.id && leaf.usage?.outputTokens > 0)) throw new Error('synced tree is wrong: ' + JSON.stringify(msgs));
  const now = new Date().toISOString();
  await api('/v1/sync/push', phone.token, {
    changes: [{ collection: 'conversations', id: 'phone-chat', baseVersion: 0, data: { id: 'phone-chat', title: 'From phone', createdAt: now, updatedAt: now, systemPrompt: '' } }],
  });
  await waitFor(`document.querySelector('.conv-list').textContent.includes('From phone')`, 'chat from the other device', 10000);
  const usage = await api('/v1/usage', phone.token);
  if (!usage.usage.some((u) => u.model === 'echo/echo-1' && u.outputTokens > 0)) throw new Error('usage not recorded: ' + JSON.stringify(usage));

  if (width <= 760) {
    await evaluate(`document.querySelector('.menu-toggle').click() || true`);
    await waitFor(`getComputedStyle(document.querySelector('.side')).display !== 'none'`, 'chat list on a phone');
    await shot('menu');
    await evaluate(`document.querySelector('.menu-toggle').click() || true`);
  }

  step('settings: pairing, API key, own provider');
  await go('/settings');
  await waitFor(`text().includes('Fake phone')`, 'device list');
  await evaluate(`click('Create a pairing code')`);
  await waitFor(`document.querySelector('dialog[open] code.big')`, 'pairing code');
  if ((await evaluate(`document.querySelector('dialog[open] .pair-code code').textContent`)) !== base) throw new Error('pairing dialog shows the wrong server');
  const pairCode = await evaluate(`document.querySelector('dialog[open] code.big').textContent`);
  await shot('pair');
  await evaluate(`click('Close')`);
  const claimed = await api('/v1/pair/claim', null, { code: pairCode, deviceName: 'Paired tablet' });
  if (claimed.user.username !== 'admin') throw new Error('pair claim failed');
  await evaluate(`click('Create API key')`);
  await evaluate(`fill('Name', 'Script') && submit()`);
  await waitFor(`document.querySelector('dialog[open] code.secret')?.textContent.startsWith('tako_')`, 'API key');
  const key = await evaluate(`document.querySelector('dialog[open] code.secret').textContent`);
  if (!(await api('/v1/models', key)).data.length) throw new Error('API key cannot list models');
  await evaluate(`click('Close')`);
  await evaluate(`click('Add', document.querySelector('.providers'))`);
  await evaluate(`fill('Id', 'local') && fill('Base URL', 'http://127.0.0.1:18080/v1') && submit()`);
  await waitFor(`document.querySelector('dialog[open] .error:not([hidden])')?.textContent.includes('Private addresses')`, 'private address refused');
  await shot('settings-private');
  await evaluate(`click('Cancel')`);
  await shot('settings');

  step('register with an invite');
  if (width <= 760) await evaluate(`document.querySelector('.menu-toggle').click() || true`);
  await evaluate(`click('Sign out')`);
  await waitFor(`location.pathname === '/login'`, 'login page');
  await shot('login');
  const invitePath = new URL(inviteLink).pathname + new URL(inviteLink).search;
  await go(invitePath);
  await evaluate(`fill('Username', 'bob') && fill('Password', 'bob-password') && submit()`);
  await waitFor(`location.pathname === '/' && document.querySelector('.model')`, 'chat after registering');
  await waitFor(`[...document.querySelector('.model').options].some((o) => o.value === 'echo/echo-1')`, 'models for the new user');
  await evaluate(`document.querySelector('a[href="/settings"]').click() || true`);
  await waitFor(`location.pathname === '/settings' && text().includes('My model providers')`, 'settings for bob', 8000);
  if (await evaluate(`!!document.querySelector('a[href="/admin"]')`)) throw new Error('admin link shown to a user');

  step('approve an app sign-in');
  const login = await api('/v1/auth/device', null, { deviceName: 'Tako · Android', platform: 'Android' });
  if ((await api('/v1/auth/device/poll', null, { deviceCode: login.deviceCode })).pending !== true) throw new Error('poll should be pending');
  await go(new URL(login.verificationUrl).pathname + new URL(login.verificationUrl).search);
  await waitFor(`text().includes(${JSON.stringify(login.userCode)}) && text().includes('Tako · Android')`, 'approval page');
  await shot('link');
  await evaluate(`click('Allow')`);
  await waitFor(`text().includes('Go back to the app')`, 'approved');
  const session = await api('/v1/auth/device/poll', null, { deviceCode: login.deviceCode });
  if (session.user?.username !== 'bob' || !session.token?.startsWith('tako_')) throw new Error('poll did not return a session: ' + JSON.stringify(session));

  step('a disabled account is signed out');
  // The browser's admin session ended when it signed out; the phone's remains.
  const bob = (await api('/v1/admin/users', phone.token)).users.find((u) => u.username === 'bob');
  await api(`/v1/admin/users/${bob.id}`, phone.token, { disabled: true }, 'PATCH');
  await go('/');
  await waitFor(`location.pathname === '/login' && text().includes('This account is disabled')`, 'login after disabling', 8000);
  console.log('ok');
} catch (e) {
  failed = true;
  console.log('FAILED:', e.message);
  await shot('failure').catch(() => {});
} finally {
  if (expected.length) console.log('expected error responses:\n  ' + expected.join('\n  '));
  console.log(problems.length ? 'page problems:\n  ' + problems.join('\n  ') : 'page problems: none');
  ws.close();
  proc.kill();
}
process.exit(failed || problems.length ? 1 : 0);
