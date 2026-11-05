// Signing in: password, registration, first-run setup, the OAuth return
// page, and approving a device (the app's browser sign-in).
import { api, ApiError, deviceName, field, fill, h, hasString, loadUser, mark, navigate, routeLink, safeReturn, session, t, toast } from './core.js';

async function info() {
  if (!session.info) session.info = await api('/v1/info');
  return session.info;
}

function card(...children) {
  return h('div', { class: 'auth' }, h('div', { class: 'auth-card' }, ...children));
}

function header(subtitle) {
  return h('header', { class: 'auth-head' }, mark(), h('h1', session.info?.name || t('appName')), subtitle ? h('p', subtitle) : null);
}

const errorText = (code) => (hasString(`err_${code}`) ? t(`err_${code}`) : code);

/** OAuth buttons; each starts a browser sign-in that comes back to `ret`. */
function oauthButtons(den, ret, extra = {}) {
  if (!den.oauth.length) return null;
  return h('div', { class: 'oauth' }, den.oauth.map((p) => {
    const query = new URLSearchParams({ return: ret, ...extra });
    return h('a', { class: `button ghost oauth-${p.type}`, href: `/v1/auth/oauth/${encodeURIComponent(p.id)}/start?${query}` }, t('continueWith', { name: p.name }));
  }));
}

export async function loginPage({ params, root }) {
  const den = await info();
  if (den.setupRequired) return navigate('/setup', { replace: true });
  const ret = safeReturn(params.get('return'));
  if (await loadUser()) return navigate(ret, { replace: true });
  const error = h('p', { class: 'error', role: 'alert' }, params.get('error') ? errorText(params.get('error')) : '');
  const username = h('input', { autocomplete: 'username', required: true, autofocus: true });
  const password = h('input', { type: 'password', autocomplete: 'current-password', required: true });
  const submit = h('button', { type: 'submit' }, t('signIn'));
  const form = h('form', { class: 'stack', hidden: !den.passwordLogin },
    field(t('username'), username), field(t('password'), password), submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    submit.disabled = true;
    error.textContent = '';
    try {
      session.save(await api('/v1/auth/login', { method: 'POST', body: { username: username.value, password: password.value, deviceName: deviceName() } }));
      navigate(ret, { replace: true });
    } catch (err) {
      error.textContent = err.message;
    } finally {
      submit.disabled = false;
    }
  });
  const reveal = den.passwordLogin ? null : h('button', { class: 'link', onclick: (e) => { form.hidden = false; e.target.remove(); } }, t('adminPasswordSignIn'));
  fill(root, card(
    header(),
    oauthButtons(den, ret),
    den.oauth.length && den.passwordLogin ? h('div', { class: 'divider' }, h('span', t('or'))) : null,
    form, reveal, error,
    den.registration !== 'closed' ? h('p', { class: 'muted center' }, t('noAccount'), ' ', routeLink(`/register?return=${encodeURIComponent(ret)}`, t('register'))) : null,
  ));
}

export async function registerPage({ params, root }) {
  const den = await info();
  const ret = safeReturn(params.get('return'));
  if (den.registration === 'closed') return navigate('/login?error=registration_closed', { replace: true });
  const invite = h('input', { value: params.get('invite') || '', autocomplete: 'off', required: den.registration === 'invite' });
  const username = h('input', { autocomplete: 'username', required: true, pattern: '[A-Za-z0-9_.\\-]{2,32}' });
  const display = h('input', { autocomplete: 'name' });
  const password = h('input', { type: 'password', autocomplete: 'new-password', minlength: 8, required: true });
  const error = h('p', { class: 'error', role: 'alert' });
  const submit = h('button', { type: 'submit' }, t('register'));
  const form = h('form', { class: 'stack' },
    den.registration === 'invite' ? field(t('inviteCode'), invite) : null,
    field(t('username'), username, t('err_invalid_username')),
    field(t('displayName'), display),
    field(t('password'), password, t('passwordHelp')),
    submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    submit.disabled = true;
    error.textContent = '';
    try {
      session.save(await api('/v1/auth/register', { method: 'POST', body: { username: username.value, password: password.value, displayName: display.value || undefined, inviteCode: invite.value || undefined, deviceName: deviceName() } }));
      navigate(ret, { replace: true });
    } catch (err) {
      error.textContent = err.message;
    } finally {
      submit.disabled = false;
    }
  });
  const oauthExtra = () => (invite.value ? { invite: invite.value } : {});
  const oauth = den.oauth.length ? h('div', { class: 'oauth' }, den.oauth.map((p) =>
    h('button', { class: 'ghost', type: 'button', onclick: () => { location.href = `/v1/auth/oauth/${encodeURIComponent(p.id)}/start?${new URLSearchParams({ return: ret, ...oauthExtra() })}`; } }, t('continueWith', { name: p.name })))) : null;
  fill(root, card(header(t('register')), form, oauth ? [h('div', { class: 'divider' }, h('span', t('or'))), oauth] : null, error,
    h('p', { class: 'muted center' }, t('haveAccount'), ' ', routeLink(`/login?return=${encodeURIComponent(ret)}`, t('signIn')))));
}

export async function setupPage({ params, root }) {
  const den = await info();
  if (!den.setupRequired) {
    fill(root, card(header(), h('p', t('setupDone')), routeLink('/login', t('signIn'))));
    return;
  }
  const token = params.get('token');
  if (!token) {
    fill(root, card(header(t('setupTitle')), h('p', t('setupNoToken'))));
    return;
  }
  const username = h('input', { value: 'admin', autocomplete: 'username', required: true });
  const display = h('input', { autocomplete: 'name' });
  const password = h('input', { type: 'password', autocomplete: 'new-password', minlength: 8, required: true });
  const error = h('p', { class: 'error', role: 'alert' });
  const submit = h('button', { type: 'submit' }, t('create'));
  const form = h('form', { class: 'stack' }, h('p', { class: 'muted' }, t('setupBody')),
    field(t('username'), username), field(t('displayName'), display), field(t('password'), password, t('passwordHelp')), submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      session.save(await api('/v1/setup', { method: 'POST', body: { setupToken: token, username: username.value, password: password.value, displayName: display.value || undefined, deviceName: deviceName() } }));
      session.info = null;
      navigate('/admin', { replace: true });
    } catch (err) {
      error.textContent = err.message;
    } finally {
      submit.disabled = false;
    }
  });
  fill(root, card(header(t('setupTitle')), form, error));
}

/** Where OAuth sign-in lands: trade the one-time ticket for a token. */
export async function oauthPage({ params, root }) {
  try {
    await exchangeTicket(params.get('ticket'));
    navigate(safeReturn(params.get('return')), { replace: true });
  } catch (err) {
    fill(root, card(header(), h('p', { class: 'error' }, err.message), routeLink('/login', t('signIn'))));
  }
}

async function exchangeTicket(ticket) {
  if (!ticket) throw new ApiError(400, 'invalid_ticket', 'Missing ticket');
  session.save(await api('/v1/auth/ticket', { method: 'POST', body: { ticket, deviceName: deviceName() } }));
}

/** The app's browser sign-in: the person confirms the code shown in the app. */
export async function linkPage({ params, root }) {
  await info();
  const code = params.get('code');
  if (params.get('ticket')) {
    try {
      await exchangeTicket(params.get('ticket'));
    } catch (err) {
      toast(err.message, 'error');
    }
    history.replaceState(null, '', `/link?code=${encodeURIComponent(code || '')}`);
  }
  const user = await loadUser();
  if (!user) {
    // OAuth from here must come back to this confirmation, not just sign in.
    const den = session.info;
    const ret = `/link?code=${encodeURIComponent(code || '')}`;
    if (code && den.oauth.length) {
      fill(root, card(header(t('approveTitle')),
        h('div', { class: 'oauth' }, den.oauth.map((p) => h('a', { class: 'button ghost', href: `/v1/auth/oauth/${encodeURIComponent(p.id)}/start?${new URLSearchParams({ device: code })}` }, t('continueWith', { name: p.name })))),
        h('div', { class: 'divider' }, h('span', t('or'))),
        h('a', { class: 'button', href: `/login?return=${encodeURIComponent(ret)}`, dataset: { route: '' } }, t('signIn'))));
      return;
    }
    return navigate(`/login?return=${encodeURIComponent(ret)}`, { replace: true });
  }
  if (!code) {
    const input = h('input', { placeholder: 'ABCD-EFGH', autocomplete: 'off', required: true, class: 'code-input' });
    const form = h('form', { class: 'stack' }, field(t('enterCode'), input), h('button', { type: 'submit' }, t('signIn')));
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      navigate(`/link?code=${encodeURIComponent(input.value.trim())}`);
    });
    fill(root, card(header(t('approveTitle')), form));
    return;
  }
  let request;
  try {
    request = await api(`/v1/auth/device/${encodeURIComponent(code)}`);
  } catch {
    fill(root, card(header(t('approveTitle')), h('p', { class: 'error' }, t('deviceCodeInvalid')), routeLink('/link', t('enterCode'))));
    return;
  }
  const result = h('p', { role: 'status' });
  const decide = async (button, verdict) => {
    button.disabled = true;
    try {
      await api(`/v1/auth/device/${encodeURIComponent(code)}/${verdict}`, { method: 'POST', body: {} });
      actions.remove();
      result.textContent = verdict === 'approve' ? t('approved') : t('denied');
      result.className = verdict === 'approve' ? 'success' : 'muted';
    } catch (err) {
      result.textContent = err.message;
      result.className = 'error';
      button.disabled = false;
    }
  };
  const allow = h('button', { onclick: (e) => decide(e.currentTarget, 'approve') }, t('approve'));
  const deny = h('button', { class: 'ghost', onclick: (e) => decide(e.currentTarget, 'deny') }, t('deny'));
  const actions = h('div', { class: 'actions' }, deny, allow);
  fill(root, card(
    header(t('approveTitle')),
    h('p', t('approveBody', { name: request.platform && !request.deviceName.includes(request.platform) ? `${request.deviceName} (${request.platform})` : request.deviceName })),
    h('p', { class: 'muted' }, t('approveCode')),
    h('p', { class: 'code' }, request.userCode),
    h('p', { class: 'muted small' }, t('signedInAs', { name: user.displayName || user.username })),
    actions, result));
}
