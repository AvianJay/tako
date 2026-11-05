// The user's own settings: profile, password, linked sign-in methods,
// devices and API keys, their own model providers and usage.
import { api, busy, confirmDialog, copyText, dialog, field, fill, h, navigate, number, requireUser, session, t, time, toast } from './core.js';
import { badge, page, section, table } from './layout.js';
import { providerList } from './providers.js';

export async function settingsPage({ params, root }) {
  const user = await requireUser();
  if (!user) return;
  if (!session.info) session.info = await api('/v1/info').catch(() => null);

  // Back from an OAuth linking flow.
  if (params.has('linked')) {
    const name = session.info?.oauth?.find((o) => o.id === params.get('linked'))?.name || params.get('linked');
    toast(t('linkedSuccess', { name }));
  } else if (params.has('error')) {
    toast(params.get('error') === 'identity_in_use' ? t('identityInUse') : params.get('error'), 'error');
  }
  if (params.has('linked') || params.has('error')) history.replaceState(null, '', '/settings');

  page(root, user, t('settings'),
    profile(user),
    password(user),
    identities(user),
    devices(),
    user.permissions.ownProviders ? section(t('myProviders'), t('myProvidersHelp'), providerList('/v1/me/providers')) : null,
    usage());
}

function profile(user) {
  const display = h('input', { value: user.displayName || '', autocomplete: 'nickname' });
  const save = h('button', { type: 'submit' }, t('save'));
  const form = h('form', { class: 'form' },
    field(t('username'), h('input', { value: user.username, disabled: true })),
    field(t('displayName'), display),
    h('p', { class: 'muted' }, user.role === 'admin' ? t('youAreAdmin') : null),
    h('div', { class: 'actions start' }, save));
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    busy(save, async () => {
      session.user = await api('/v1/me', { method: 'PATCH', body: { displayName: display.value.trim() } });
      toast(t('saved'));
    });
  });
  return section(t('profile'), null, form);
}

function password(user) {
  const current = h('input', { type: 'password', autocomplete: 'current-password', required: true });
  const next = h('input', { type: 'password', autocomplete: 'new-password', required: true, minlength: 8 });
  const save = h('button', { type: 'submit' }, user.hasPassword ? t('changePassword') : t('setPassword'));
  const form = h('form', { class: 'form' },
    user.hasPassword ? field(t('currentPassword'), current) : null,
    field(t('newPassword'), next, t('passwordHelp')),
    h('div', { class: 'actions start' }, save));
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    busy(save, async () => {
      try {
        await api('/v1/me/password', { method: 'POST', body: { ...(user.hasPassword ? { currentPassword: current.value } : {}), newPassword: next.value } });
      } catch (err) {
        throw err.code === 'invalid_login' ? new Error(t('wrongPassword')) : err;
      }
      toast(t('passwordChanged'));
      // A first password adds the current-password field.
      if (!user.hasPassword) return navigate('/settings', { replace: true });
      form.reset();
    });
  });
  return section(t('password'), null, form);
}

function identities(user) {
  const host = h('div');
  const providers = session.info?.oauth || [];
  async function load() {
    const { identities } = await api('/v1/me/identities');
    const linked = new Set(identities.map((i) => i.providerId));
    fill(host, 
      table([t('signInMethod'), t('account'), ''], identities.map((i) => {
        const unlink = h('button', { class: 'ghost small danger' }, t('unlink'));
        unlink.addEventListener('click', async () => {
          if (!(await confirmDialog(t('confirmUnlink', { name: i.providerName }), { ok: t('unlink') }))) return;
          await busy(unlink, async () => {
            await api(`/v1/me/identities/${encodeURIComponent(i.id)}`, { method: 'DELETE' });
            await load();
          });
        });
        return [i.providerName, h('span', i.email || i.name || '—'), h('div', { class: 'row-actions' }, unlink)];
      }), t('noIdentities')),
      h('div', { class: 'actions start' }, providers.filter((p) => !linked.has(p.id)).map((p) => {
        const button = h('button', { class: 'ghost' }, t('linkWith', { name: p.name }));
        button.addEventListener('click', () => busy(button, async () => {
          const { url } = await api(`/v1/me/identities/${encodeURIComponent(p.id)}/link`, { method: 'POST', body: {} });
          location.href = url;
        }));
        return button;
      })));
  }
  load().catch((e) => fill(host, h('p', { class: 'error' }, e.message)));
  return section(t('linkedAccounts'), providers.length ? null : t('noOAuth'), host);
}

function devices() {
  const host = h('div');
  async function load() {
    const { devices, current } = await api('/v1/devices');
    fill(host, table([t('name'), t('lastUsed'), ''], devices.map((d) => {
      const revoke = h('button', { class: 'ghost small danger' }, t('revoke'));
      revoke.addEventListener('click', async () => {
        if (!(await confirmDialog(t('confirmRevoke', { name: d.name }), { ok: t('revoke') }))) return;
        await busy(revoke, async () => {
          await api(`/v1/devices/${encodeURIComponent(d.id)}`, { method: 'DELETE' });
          if (d.id === current) {
            session.clear();
            return navigate('/login', { replace: true });
          }
          await load();
        });
      });
      return [h('span', d.name, ' ', d.id === current ? badge(t('thisDevice'), 'ok') : null),
        h('span', { class: 'muted' }, time(d.lastSeenAt || d.createdAt)), h('div', { class: 'row-actions' }, revoke)];
    })));
  }
  const pair = h('button', t('pairPhone'));
  pair.addEventListener('click', () => busy(pair, async () => {
    const code = await api('/v1/pair/codes', { method: 'POST', body: {} });
    await dialog(t('pairPhone'), (close) => h('div', { class: 'pair' },
      h('ol', { class: 'steps' }, h('li', t('pairStep1')), h('li', t('pairStep2')), h('li', t('pairStep3'))),
      h('p', { class: 'pair-code' }, h('span', { class: 'muted' }, t('server')), h('code', code.server), h('button', { class: 'ghost small', onclick: () => copyText(code.server) }, t('copy'))),
      h('p', { class: 'pair-code' }, h('code', { class: 'big' }, code.code)),
      h('p', { class: 'muted center' }, t('validUntil', { time: time(code.expiresAt) })),
      h('div', { class: 'actions' }, h('button', { onclick: () => close() }, t('close')))));
    await load();
  }));
  const key = h('button', { class: 'ghost' }, t('createKey'));
  key.addEventListener('click', async () => {
    const created = await dialog(t('createKey'), (close) => {
      const name = h('input', { required: true, value: 'API key' });
      const form = h('form', { class: 'form' }, field(t('keyName'), name),
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close() }, t('cancel')), h('button', { type: 'submit' }, t('create'))));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        api('/v1/devices', { method: 'POST', body: { name: name.value.trim() } }).then(close, (err) => toast(err.message, 'error'));
      });
      return form;
    });
    if (!created) return;
    const baseUrl = `${location.origin}/v1`;
    await dialog(t('createKey'), (close) => h('div',
      h('p', t('keyShownOnce')),
      h('p', h('code', { class: 'secret' }, created.token), ' ', h('button', { class: 'ghost small', onclick: () => copyText(created.token) }, t('copy'))),
      h('p', { class: 'muted' }, t('keyHelp', { url: baseUrl })),
      h('div', { class: 'actions' }, h('button', { onclick: () => close() }, t('close')))));
    await load();
  });
  load().catch((e) => fill(host, h('p', { class: 'error' }, e.message)));
  return section(t('devices'), t('devicesHelp'), host, h('div', { class: 'actions start' }, pair, key));
}

function usage() {
  const host = h('div');
  api('/v1/usage').then(({ usage, today }) => {
    fill(host, 
      h('p', h('b', t('sharedTokensToday', { used: number(today.sharedTokens) })),
        today.limit == null ? null : h('span', { class: 'muted' }, ` · ${t('limit', { limit: number(today.limit) })}`)),
      today.limit ? h('progress', { max: today.limit, value: Math.min(today.sharedTokens, today.limit) }) : null,
      table([t('day'), t('model'), t('requests'), t('inputTokens'), t('outputTokens')],
        usage.map((u) => [u.day, h('span', { class: 'mono' }, u.model), number(u.requests), number(u.inputTokens), number(u.outputTokens)]), t('noUsage')));
  }, (e) => fill(host, h('p', { class: 'error' }, e.message)));
  return section(t('usage'), null, host);
}
