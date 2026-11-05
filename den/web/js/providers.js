// Model providers, shared by the user's settings (their own providers) and
// the admin page (shared providers). [base] is `/v1/me/providers` or
// `/v1/admin/providers`.
import { api, busy, confirmDialog, dialog, field, fill, h, t, toast, toggle } from './core.js';
import { badge, table } from './layout.js';

export function providerList(base, { admin = false, users = [], onChange = () => {} } = {}) {
  const host = h('div', { class: 'providers' });
  async function load() {
    const { providers } = await api(base);
    fill(host, 
      table([t('providerDisplay'), t('baseUrl'), t('models'), t('status'), ''], providers.map((p) => [
        h('div', h('b', p.displayName || p.name), h('div', { class: 'muted mono' }, admin ? `${p.name}/…` : `me/${p.name}/…`)),
        h('span', { class: 'mono wrap' }, p.baseUrl),
        p.models.length ? p.models.join(', ') : h('span', { class: 'muted' }, t('unlimited')),
        h('div', p.enabled ? badge(t('enabled'), 'ok') : badge(t('disabled')),
          p.source === 'config' ? badge(t('fromConfig')) : null,
          admin && p.source !== 'config' && !p.access?.allUsers ? badge(t('accessSelected')) : null),
        actions(p),
      ])),
      h('div', { class: 'actions start' }, h('button', { onclick: () => edit(null) }, t('add'))));
  }

  function actions(p) {
    const test = h('button', { class: 'ghost small' }, t('test'));
    test.addEventListener('click', () => busy(test, async () => {
      const r = await api(`${base}/${p.id}/test`, { method: 'POST', body: {} });
      if (r.ok) toast(t('testOk', { count: r.models.length }));
      else toast(r.error, 'error');
    }));
    if (p.source === 'config') return h('div', { class: 'row-actions' }, test);
    const remove = h('button', { class: 'ghost small danger' }, t('delete'));
    remove.addEventListener('click', async () => {
      if (!(await confirmDialog(t('confirmDelete', { name: p.displayName || p.name })))) return;
      await busy(remove, async () => {
        await api(`${base}/${p.id}`, { method: 'DELETE' });
        toast(t('deleted'));
        onChange();
        await load();
      });
    });
    return h('div', { class: 'row-actions' }, test, h('button', { class: 'ghost small', onclick: () => edit(p) }, t('edit')), remove);
  }

  async function edit(p) {
    const saved = await dialog(p ? t('edit') : t('add'), (close) => {
      const name = h('input', { value: p?.name || '', required: true, pattern: '[a-z0-9][a-z0-9_\\-]{0,31}', autocomplete: 'off', spellcheck: false });
      const display = h('input', { value: p?.displayName || '' });
      const url = h('input', { type: 'url', value: p?.baseUrl || '', required: true, placeholder: 'https://api.openai.com/v1' });
      const key = h('input', { type: 'password', autocomplete: 'new-password', placeholder: p?.hasApiKey ? t('apiKeyKeep') : '' });
      const models = h('textarea', { rows: 3, spellcheck: false }, (p?.models || []).join('\n'));
      const enabled = toggle(t('enabled'), p ? p.enabled : true);
      const allUsers = h('select', h('option', { value: 'all' }, t('accessAll')), h('option', { value: 'some' }, t('accessSelected')));
      allUsers.value = p && p.access && !p.access.allUsers ? 'some' : 'all';
      const picks = users.filter((u) => u.role !== 'admin').map((u) => {
        const box = h('input', { type: 'checkbox', value: u.id, checked: !!p?.access?.userIds?.includes(u.id) });
        return { box, el: h('label', { class: 'check' }, box, u.displayName || u.username) };
      });
      const picker = h('div', { class: 'checks', hidden: allUsers.value === 'all' }, picks.map((x) => x.el));
      allUsers.addEventListener('change', () => (picker.hidden = allUsers.value === 'all'));
      const error = h('p', { class: 'error', hidden: true });
      const submit = h('button', { type: 'submit' }, t('save'));
      const form = h('form', { class: 'form' },
        field(t('providerName'), name, t('providerNameHelp')),
        field(t('providerDisplay'), display),
        field(t('baseUrl'), url),
        field(t('apiKey'), key),
        field(t('models'), models, t('modelsHelp')),
        enabled.el,
        admin ? field(t('access'), allUsers) : null,
        admin ? picker : null,
        error,
        h('div', { class: 'actions' }, h('button', { type: 'button', class: 'ghost', onclick: () => close(false) }, t('cancel')), submit));
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        busy(submit, async () => {
          const id = name.value.trim();
          const body = {
            name: id,
            displayName: display.value.trim() || id,
            baseUrl: url.value.trim(),
            models: models.value.split('\n').map((m) => m.trim()).filter(Boolean),
            enabled: enabled.input.checked,
          };
          // An empty field keeps the saved key when editing.
          if (key.value || !p) body.apiKey = key.value;
          if (admin) body.access = { allUsers: allUsers.value === 'all', userIds: picks.filter((x) => x.box.checked).map((x) => x.box.value) };
          try {
            await api(p ? `${base}/${p.id}` : base, { method: p ? 'PATCH' : 'POST', body });
            close(true);
          } catch (err) {
            error.hidden = false;
            error.textContent = err.message;
          }
        });
      });
      return form;
    }, { wide: true });
    if (saved) {
      toast(t('saved'));
      onChange();
      await load();
    }
  }

  load().catch((e) => fill(host, h('p', { class: 'error' }, e.message)));
  return host;
}
