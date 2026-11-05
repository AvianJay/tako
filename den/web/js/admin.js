// Administration: server settings, users and their permissions, shared
// providers, sign-in methods, invites and usage. Tabs live in `?tab=`.
import { api, busy, confirmDialog, copyText, dialog, field, fill, h, navigate, number, requireUser, routeLink, session, t, time, toast, toggle } from './core.js';
import { badge, page, section, table } from './layout.js';
import { providerList } from './providers.js';

const tabs = ['server', 'users', 'providers', 'oauth', 'invites', 'usage'];

export async function adminPage({ params, root }) {
  const user = await requireUser();
  if (!user) return;
  if (user.role !== 'admin') return navigate('/', { replace: true });
  const tab = tabs.includes(params.get('tab')) ? params.get('tab') : 'server';
  const nav = h('nav', { class: 'tabs', role: 'tablist' }, tabs.map((name) => {
    const a = routeLink(`/admin?tab=${name}`, t(`tab_${name}`));
    a.setAttribute('role', 'tab');
    if (name === tab) a.setAttribute('aria-selected', 'true');
    return a;
  }));
  const body = h('div', { class: 'tab-body' }, h('p', { class: 'muted' }, t('loading')));
  page(root, user, t('admin'), nav, body);
  const settings = await api('/v1/admin/settings');
  const content = await { server, users, providers, oauth, invites, usage }[tab](settings, user);
  fill(body, ...[content].flat());
}

// --- Server ----------------------------------------------------------------

function server(s) {
  const name = h('input', { value: s.serverName, required: true });
  const url = h('input', { type: 'url', value: s.publicUrl || '', placeholder: 'https://den.example.com', disabled: s.publicUrlLocked });
  const registration = h('select',
    h('option', { value: 'closed' }, t('regClosed')),
    h('option', { value: 'invite' }, t('regInvite')),
    h('option', { value: 'open' }, t('regOpen')));
  registration.value = s.registration;
  const passwordLogin = toggle(t('passwordLogin'), s.passwordLogin, t('passwordLoginHelp'));
  const perms = permissionFields(s.defaultPermissions, { overrides: false });
  const privateNets = toggle(t('privateNetworks'), s.userProvidersAllowPrivateNetworks, t('privateNetworksHelp'));
  const save = h('button', { type: 'submit' }, t('save'));
  const form = h('form', { class: 'form' },
    section(t('server'), null,
      field(t('serverName'), name),
      field(t('publicUrl'), url, s.publicUrlLocked ? t('publicUrlLocked') : t('publicUrlHelp'))),
    section(t('registration'), null,
      field(t('registration'), registration),
      passwordLogin.el),
    section(t('defaultPermissions'), null, perms.el, privateNets.el),
    h('div', { class: 'actions start' }, save));
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    busy(save, async () => {
      const body = {
        serverName: name.value.trim(),
        registration: registration.value,
        passwordLogin: passwordLogin.input.checked,
        defaultPermissions: perms.value(),
        userProvidersAllowPrivateNetworks: privateNets.input.checked,
      };
      if (!s.publicUrlLocked) body.publicUrl = url.value.trim().replace(/\/+$/, '') || null;
      Object.assign(s, await api('/v1/admin/settings', { method: 'PATCH', body }));
      session.info = await api('/v1/info').catch(() => session.info);
      for (const el of document.querySelectorAll('.server-name')) el.textContent = s.serverName;
      document.title = s.serverName;
      toast(t('saved'));
    });
  });
  return form;
}

/** Permission inputs. Defaults are plain values; per-user overrides add an
 *  "inherit" choice, sent as null. An override of -1 tokens is "no limit"
 *  even when the default has one. */
function permissionFields(p, { overrides }) {
  const choice = (label, value) => {
    if (!overrides) {
      const tg = toggle(label, value !== false);
      return { el: tg.el, value: () => tg.input.checked };
    }
    const select = h('select', h('option', { value: '' }, t('inherit')), h('option', { value: 'yes' }, t('yes')), h('option', { value: 'no' }, t('no')));
    select.value = value == null ? '' : value ? 'yes' : 'no';
    return { el: field(label, select), value: () => (select.value === '' ? null : select.value === 'yes') };
  };
  const shared = choice(t('useShared'), p.useSharedProviders);
  const own = choice(t('ownProviders'), p.ownProviders);
  const mode = h('select',
    overrides ? h('option', { value: 'inherit' }, t('inherit')) : null,
    h('option', { value: 'none' }, t('unlimited')),
    h('option', { value: 'limit' }, t('customLimit')));
  const limit = p.dailyTokenLimit;
  mode.value = limit == null ? (overrides ? 'inherit' : 'none') : limit < 0 ? 'none' : 'limit';
  const amount = h('input', { type: 'number', min: 0, step: 1000, value: limit != null && limit >= 0 ? String(limit) : '', placeholder: '100000', hidden: mode.value !== 'limit' });
  mode.addEventListener('change', () => {
    amount.hidden = mode.value !== 'limit';
    if (!amount.hidden) amount.focus();
  });
  return {
    el: h('div', { class: 'perm-fields' }, shared.el, own.el,
      field(t('dailyLimit'), h('div', { class: 'inline' }, mode, amount), t('dailyLimitHelp'))),
    value: () => ({
      useSharedProviders: shared.value(),
      ownProviders: own.value(),
      dailyTokenLimit: mode.value === 'limit' ? Math.max(0, Number(amount.value) || 0) : mode.value === 'none' && overrides ? -1 : null,
    }),
  };
}

// --- Users -----------------------------------------------------------------

async function users(settings, me) {
  const host = h('div');
  async function load() {
    const { users: list } = await api('/v1/admin/users');
    fill(host, 
      table([t('user'), t('signInMethod'), t('lastUsed'), t('usage'), ''], list.map((u) => [
        h('div', h('b', u.displayName || u.username), ' ', u.role === 'admin' ? badge(t('roleAdmin'), 'accent') : null,
          u.disabled ? badge(t('disabled'), 'warn') : null, h('div', { class: 'muted mono' }, `@${u.username}`)),
        h('span', { class: 'muted' }, [u.hasPassword ? t('password') : null, ...u.identities.map((i) => oauthName(i.providerId))].filter(Boolean).join(' · ') || '—'),
        h('span', { class: 'muted' }, u.lastSeenAt ? time(u.lastSeenAt) : '—'),
        h('span', { class: 'muted' }, t('usedToday', { count: number(u.usageToday) }), u.effectivePermissions?.dailyTokenLimit != null ? ` / ${number(u.effectivePermissions.dailyTokenLimit)}` : ''),
        h('div', { class: 'row-actions' },
          h('button', { class: 'ghost small', onclick: () => edit(u) }, t('edit')),
          u.id === me.id ? null : removeButton(u)),
      ])),
      h('div', { class: 'actions start' }, h('button', { onclick: add }, t('addUser'))));
  }

  function removeButton(u) {
    const button = h('button', { class: 'ghost small danger' }, t('delete'));
    button.addEventListener('click', async () => {
      if (!(await confirmDialog(t('confirmDeleteUser', { name: u.username })))) return;
      await busy(button, async () => {
        await api(`/v1/admin/users/${u.id}`, { method: 'DELETE' });
        toast(t('deleted'));
        await load();
      });
    });
    return button;
  }

  async function add() {
    const done = await dialog(t('addUser'), (close) => {
      const username = h('input', { required: true, autocomplete: 'off', spellcheck: false });
      const display = h('input');
      const pass = h('input', { type: 'password', required: true, minlength: 8, autocomplete: 'new-password' });
      const role = roleSelect('user');
      const submit = h('button', { type: 'submit' }, t('create'));
      const form = h('form', { class: 'form' }, field(t('username'), username), field(t('displayName'), display),
        field(t('password'), pass, t('passwordHelp')), field(t('role'), role),
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close(false) }, t('cancel')), submit));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        busy(submit, async () => {
          await api('/v1/admin/users', { method: 'POST', body: { username: username.value.trim(), displayName: display.value.trim() || undefined, password: pass.value, role: role.value } });
          close(true);
        });
      });
      return form;
    });
    if (done) await load();
  }

  async function edit(u) {
    const done = await dialog(u.displayName || u.username, (close) => {
      const display = h('input', { value: u.displayName || '' });
      const role = roleSelect(u.role);
      const disabled = toggle(t('disableAccount'), u.disabled, t('disableHelp'));
      const pass = h('input', { type: 'password', minlength: 8, autocomplete: 'new-password', placeholder: t('apiKeyKeep') });
      const perms = permissionFields(u.permissions || {}, { overrides: true });
      const permsBox = h('div', { hidden: u.role === 'admin' }, h('h3', t('permissions')), perms.el);
      role.addEventListener('change', () => (permsBox.hidden = role.value === 'admin'));
      const submit = h('button', { type: 'submit' }, t('save'));
      const form = h('form', { class: 'form' },
        field(t('username'), h('input', { value: u.username, disabled: true })),
        field(t('displayName'), display),
        field(t('role'), role),
        u.id === me.id ? null : disabled.el,
        field(t('resetPassword'), pass),
        permsBox,
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close(false) }, t('cancel')), submit));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        busy(submit, async () => {
          const body = { displayName: display.value.trim() || u.username, role: role.value, permissions: perms.value() };
          if (u.id !== me.id) body.disabled = disabled.input.checked;
          if (pass.value) body.password = pass.value;
          await api(`/v1/admin/users/${u.id}`, { method: 'PATCH', body });
          close(true);
        });
      });
      return form;
    }, { wide: true });
    if (done) {
      toast(t('saved'));
      await load();
    }
  }

  await load();
  return section(t('users'), null, host);
}

const roleSelect = (value) => {
  const select = h('select', h('option', { value: 'user' }, t('roleUser')), h('option', { value: 'admin' }, t('roleAdmin')));
  select.value = value;
  return select;
};

const oauthName = (id) => session.info?.oauth?.find((o) => o.id === id)?.name || id;

// --- Providers -------------------------------------------------------------

async function providers() {
  const { users: list } = await api('/v1/admin/users');
  return section(t('sharedProviders'), t('sharedProvidersHelp'), providerList('/v1/admin/providers', { admin: true, users: list }));
}

// --- OAuth -----------------------------------------------------------------

const oauthTypes = {
  google: { name: 'Google', console: 'https://console.cloud.google.com/apis/credentials' },
  discord: { name: 'Discord', console: 'https://discord.com/developers/applications' },
  github: { name: 'GitHub', console: 'https://github.com/settings/developers' },
  oidc: { name: 'OpenID Connect', console: null },
};

async function oauth(settings) {
  const host = h('div');
  const callback = (id) => (settings.publicUrl ? `${settings.publicUrl}/v1/auth/oauth/${id}/callback` : null);
  async function load() {
    const { providers: list } = await api('/v1/admin/oauth');
    fill(host, 
      settings.publicUrl ? null : h('p', { class: 'notice warn' }, t('needPublicUrl'), ' ', routeLink('/admin?tab=server', t('server'))),
      table([t('name'), t('type'), t('redirectUri'), t('status'), ''], list.map((p) => [
        h('div', h('b', p.name), h('div', { class: 'muted mono' }, p.id)),
        oauthTypes[p.type]?.name || p.type,
        p.redirectUri ? h('span', { class: 'mono wrap' }, p.redirectUri, ' ', h('button', { class: 'ghost small', onclick: () => copyText(p.redirectUri) }, t('copy'))) : '—',
        h('div', p.enabled ? badge(t('enabled'), 'ok') : badge(t('disabled')), p.source === 'config' ? badge(t('fromConfig')) : null),
        p.source === 'config' ? '' : h('div', { class: 'row-actions' },
          h('button', { class: 'ghost small', onclick: () => edit(p) }, t('edit')), removeButton(p)),
      ]), t('noOAuthProviders')),
      h('div', { class: 'actions start' }, h('button', { onclick: () => edit(null) }, t('add'))));
  }

  function removeButton(p) {
    const button = h('button', { class: 'ghost small danger' }, t('delete'));
    button.addEventListener('click', async () => {
      if (!(await confirmDialog(t('confirmDeleteOAuth', { name: p.name })))) return;
      await busy(button, async () => {
        await api(`/v1/admin/oauth/${p.id}`, { method: 'DELETE' });
        await load();
      });
    });
    return button;
  }

  async function edit(p) {
    const done = await dialog(p ? p.name : t('addSignInMethod'), (close) => {
      const type = h('select', Object.entries(oauthTypes).map(([value, o]) => h('option', { value }, o.name)));
      type.value = p?.type || 'google';
      type.disabled = !!p;
      const id = h('input', { value: p?.id || 'google', disabled: !!p, pattern: '[a-z0-9\\-]{1,32}', spellcheck: false });
      const name = h('input', { value: p?.name || 'Google' });
      const clientId = h('input', { value: p?.clientId || '', required: true, spellcheck: false, autocomplete: 'off' });
      const secret = h('input', { type: 'password', required: !p, autocomplete: 'new-password', placeholder: p?.hasClientSecret ? t('apiKeyKeep') : '' });
      const issuer = h('input', { type: 'url', value: p?.issuer || '', placeholder: 'https://auth.example.com/application/o/tako/' });
      const issuerField = field(t('issuer'), issuer, t('issuerHelp'));
      const scopes = h('input', { value: (p?.scopes || []).join(' '), placeholder: t('scopesDefault'), spellcheck: false });
      const enabled = toggle(t('enabled'), p ? p.enabled : true);
      const redirect = h('code', { class: 'wrap' });
      const consoleHint = h('p', { class: 'help' });
      let touchedName = !!p;
      let touchedId = !!p;
      name.addEventListener('input', () => (touchedName = true));
      id.addEventListener('input', () => {
        touchedId = true;
        refresh();
      });
      const refresh = () => {
        const kind = oauthTypes[type.value];
        if (!touchedId) id.value = type.value;
        if (!touchedName) name.value = type.value === 'oidc' ? 'SSO' : kind.name;
        issuerField.hidden = type.value !== 'oidc';
        issuer.required = type.value === 'oidc';
        const uri = callback(id.value || type.value);
        redirect.textContent = uri || t('needPublicUrl');
        fill(consoleHint, kind.console
          ? h('span', t('oauthConsole', { name: kind.name }), ' ', h('a', { href: kind.console, target: '_blank', rel: 'noopener noreferrer' }, kind.console))
          : t('oidcHint'));
      };
      type.addEventListener('change', refresh);
      refresh();
      const submit = h('button', { type: 'submit' }, t('save'));
      const form = h('form', { class: 'form' },
        field(t('type'), type),
        consoleHint,
        h('div', { class: 'field' }, h('span', { class: 'label' }, t('redirectUri')),
          h('div', { class: 'inline' }, redirect, h('button', { type: 'button', class: 'ghost small', onclick: () => redirect.textContent.startsWith('http') && copyText(redirect.textContent) }, t('copy'))),
          h('span', { class: 'help' }, t('redirectUriHelp'))),
        field(t('oauthId'), id, t('oauthIdHelp')),
        field(t('name'), name),
        issuerField,
        field(t('clientId'), clientId),
        field(t('clientSecret'), secret),
        field(t('scopes'), scopes, t('scopesHelp')),
        enabled.el,
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close(false) }, t('cancel')), submit));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        busy(submit, async () => {
          const body = { name: name.value.trim(), clientId: clientId.value.trim(), enabled: enabled.input.checked };
          const list = scopes.value.split(/[\s,]+/).filter(Boolean);
          if (list.length) body.scopes = list;
          if (secret.value || !p) body.clientSecret = secret.value;
          if (type.value === 'oidc') body.issuer = issuer.value.trim();
          if (!p) Object.assign(body, { type: type.value, id: id.value.trim() || type.value });
          await api(p ? `/v1/admin/oauth/${p.id}` : '/v1/admin/oauth', { method: p ? 'PATCH' : 'POST', body });
          close(true);
        });
      });
      return form;
    }, { wide: true });
    if (done) {
      toast(t('saved'));
      session.info = await api('/v1/info').catch(() => session.info);
      await load();
    }
  }

  await load();
  return section(t('oauthProviders'), t('oauthHelp'), host);
}

// --- Invites ---------------------------------------------------------------

async function invites(settings) {
  const host = h('div');
  const link = (code) => `${settings.publicUrl || location.origin}/register?invite=${encodeURIComponent(code)}`;
  async function load() {
    const { invites: list } = await api('/v1/admin/invites');
    const now = Date.now();
    fill(host, 
      settings.registration === 'invite' ? null : h('p', { class: 'notice' }, t('invitesNotNeeded'), ' ', routeLink('/admin?tab=server', t('registration'))),
      table([t('inviteCode'), t('note'), t('usesHeader'), t('status'), ''], list.map((i) => {
        const gone = (i.expiresAt && Date.parse(i.expiresAt) < now) || i.uses >= i.maxUses;
        const remove = h('button', { class: 'ghost small danger' }, t('delete'));
        remove.addEventListener('click', () => busy(remove, async () => {
          await api(`/v1/admin/invites/${encodeURIComponent(i.code)}`, { method: 'DELETE' });
          await load();
        }));
        return [h('code', i.code), i.note || '—', `${i.uses}/${i.maxUses}`,
          gone ? badge(t('expired'), 'warn') : h('span', { class: 'muted' }, i.expiresAt ? t('expires', { time: time(i.expiresAt) }) : t('never')),
          h('div', { class: 'row-actions' }, gone ? null : h('button', { class: 'ghost small', onclick: () => copyText(link(i.code)) }, t('copyLink')), remove)];
      }), t('noInvites')),
      h('div', { class: 'actions start' }, h('button', { onclick: create }, t('createInvite'))));
  }
  async function create() {
    const invite = await dialog(t('createInvite'), (close) => {
      const uses = h('input', { type: 'number', min: 1, max: 1000, value: '1', required: true });
      const days = h('input', { type: 'number', min: 1, max: 365, value: '7', required: true });
      const note = h('input', { placeholder: t('notePlaceholder') });
      const submit = h('button', { type: 'submit' }, t('create'));
      const form = h('form', { class: 'form' }, field(t('maxUses'), uses), field(t('expiresInDays'), days), field(t('note'), note),
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close() }, t('cancel')), submit));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        busy(submit, async () => close(await api('/v1/admin/invites', { method: 'POST', body: { maxUses: Number(uses.value), expiresInDays: Number(days.value), note: note.value.trim() || undefined } })));
      });
      return form;
    });
    if (!invite) return;
    await dialog(t('createInvite'), (close) => h('div',
      h('p', t('inviteShare')),
      h('p', h('code', { class: 'wrap' }, link(invite.code))),
      h('div', { class: 'actions' }, h('button', { class: 'ghost', onclick: () => copyText(link(invite.code)) }, t('copyLink')), h('button', { onclick: () => close() }, t('close')))));
    await load();
  }
  await load();
  return section(t('invites'), t('invitesHelp'), host);
}

// --- Usage -----------------------------------------------------------------

async function usage() {
  const { usage: rows } = await api('/v1/admin/usage?days=30');
  const byUser = new Map();
  for (const r of rows) {
    const total = byUser.get(r.username) || { shared: 0, own: 0, requests: 0 };
    total[r.shared ? 'shared' : 'own'] += r.inputTokens + r.outputTokens;
    total.requests += r.requests;
    byUser.set(r.username, total);
  }
  return [
    section(t('usageByUser'), t('last30Days'), table([t('user'), t('requests'), t('sharedTokens'), t('ownTokens')],
      [...byUser].sort((a, b) => b[1].shared - a[1].shared).map(([name, v]) => [name, number(v.requests), number(v.shared), number(v.own)]), t('noUsage'))),
    section(t('allUsage'), null, table([t('day'), t('user'), t('model'), '', t('requests'), t('inputTokens'), t('outputTokens')],
      rows.map((r) => [r.day, r.username, h('span', { class: 'mono' }, r.model), r.shared ? badge(t('shared')) : badge(t('own'), 'accent'),
        number(r.requests), number(r.inputTokens), number(r.outputTokens)]), t('noUsage'))),
  ];
}
