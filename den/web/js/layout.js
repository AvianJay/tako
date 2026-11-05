// The frame around every signed-in page: the navigation column and a
// scrolling content area.
import { api, busy, fill, h, mark, navigate, routeLink, session, t } from './core.js';

/** The navigation column. [middle] fills its scrolling part (the chat list
 *  on the chat page); [onNewChat] adds the new-chat button. */
export function sidebar(user, middle, onNewChat) {
  const signOut = h('button', { class: 'ghost small' }, t('signOut'));
  signOut.addEventListener('click', () => busy(signOut, async () => {
    try {
      await api('/v1/auth/logout', { method: 'POST', body: {} });
    } catch {}
    session.clear();
    navigate('/login', { replace: true });
  }));
  const here = location.pathname.replace(/\/+$/, '') || '/';
  const link = (href, label) => {
    const a = routeLink(href, label);
    if (here === href) a.setAttribute('aria-current', 'page');
    return a;
  };
  return h('aside', { class: 'side' },
    h('header', { class: 'side-head' }, routeLink('/', mark(), h('span', { class: 'server-name' }, session.info?.name || t('appName'))),
      onNewChat ? h('button', { class: 'icon', title: t('newChat'), 'aria-label': t('newChat'), onclick: onNewChat }, '+') : null),
    middle || h('div', { class: 'conv-list' }),
    h('footer', { class: 'side-foot' },
      h('nav', { class: 'side-nav' }, link('/', t('chats')), link('/settings', t('settings')), user.role === 'admin' ? link('/admin', t('admin')) : null),
      h('div', { class: 'who' }, h('span', { class: 'avatar' }, (user.displayName || user.username).slice(0, 1).toUpperCase()),
        h('span', { class: 'who-name' }, user.displayName || user.username), signOut)));
}

/** A settings-style page: the sidebar and [content] under a heading. */
export function page(root, user, title, ...content) {
  const shell = h('div', { class: 'shell' },
    sidebar(user),
    h('main', { class: 'page' },
      h('header', { class: 'page-head' },
        h('button', { class: 'icon ghost menu-toggle', 'aria-label': t('chats'), onclick: () => shell.classList.toggle('menu') }, '☰'),
        h('h1', title)),
      h('div', { class: 'page-body' }, ...content)));
  fill(root, shell);
  return shell;
}

/** A titled card. */
export function section(title, help, ...content) {
  return h('section', { class: 'card' }, h('h2', title), help ? h('p', { class: 'help' }, help) : null, ...content);
}

/** A simple table: [columns] are header labels, [rows] arrays of cells. */
export function table(columns, rows, empty = t('none')) {
  if (!rows.length) return h('p', { class: 'muted' }, empty);
  return h('div', { class: 'table-wrap' }, h('table',
    h('thead', h('tr', columns.map((c) => h('th', c)))),
    h('tbody', rows.map((cells) => h('tr', cells.map((c) => h('td', c)))))));
}

export const badge = (text, kind = '') => h('span', { class: `badge ${kind}` }, text);
