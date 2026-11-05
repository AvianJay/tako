// The chat page. Conversations and messages are the app's own records, read
// and written through sync, so a chat started here continues on the phone.
import { api, fill, h, mark, newId, requireUser, t, timeShort, toast } from './core.js';
import { sidebar } from './layout.js';

const PROVIDER_ID = 'tako-den';
const SYSTEM_PROMPT = 'You are Tako, a personal assistant. The user is chatting from the Tako Den web app. Reply in the language the user writes in. Use Markdown when it helps.';

export async function chatPage({ root }) {
  const user = await requireUser();
  if (!user) return;

  const db = { conversations: new Map(), messages: new Map() };
  const versions = new Map();
  let seq = 0;
  let current = null;
  let streaming = null;
  const stop = new AbortController();

  const list = h('nav', { class: 'conv-list', 'aria-label': t('chats') });
  const log = h('div', { class: 'log', 'aria-live': 'polite' });
  const title = h('h1', { class: 'chat-title' }, t('newChat'));
  const model = h('select', { class: 'model', 'aria-label': t('model') });
  const input = h('textarea', { placeholder: t('messagePlaceholder'), rows: 1, 'aria-label': t('messagePlaceholder') });
  const send = h('button', { type: 'submit', class: 'send', 'aria-label': t('send') }, t('send'));
  const composer = h('form', { class: 'composer' }, input, send);
  const shell = h('div', { class: 'shell' },
    sidebar(user, list, () => open(null)),
    h('main', { class: 'chat' },
      h('header', { class: 'chat-head' },
        h('button', { class: 'icon ghost menu-toggle', 'aria-label': t('chats'), onclick: () => shell.classList.toggle('menu') }, '☰'),
        title, model),
      log, composer));
  fill(root, shell);

  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = `${Math.min(input.scrollHeight, 220)}px`;
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      composer.requestSubmit();
    }
  });
  model.addEventListener('change', () => localStorage.setItem('den.model', model.value));
  composer.addEventListener('submit', (e) => {
    e.preventDefault();
    submit();
  });

  async function pull() {
    for (;;) {
      const page = await api(`/v1/sync/pull?since=${seq}&collections=conversations,messages`, { signal: stop.signal });
      if (page.reset) {
        db.conversations.clear();
        db.messages.clear();
        versions.clear();
        seq = 0;
        continue;
      }
      for (const r of page.changes) {
        versions.set(`${r.collection}/${r.id}`, r.version);
        const map = db[r.collection];
        if (!map) continue;
        if (r.deleted) map.delete(r.id);
        else map.set(r.id, r.data);
      }
      seq = page.seq;
      if (!page.more) break;
    }
  }

  async function push(changes) {
    const res = await api('/v1/sync/push', {
      method: 'POST',
      body: { changes: changes.map((c) => ({ ...c, baseVersion: versions.get(`${c.collection}/${c.id}`) || 0 })) },
    });
    for (const r of res.results) {
      const key = `${r.collection}/${r.id}`;
      if (r.status === 'ok') versions.set(key, r.version);
      if (r.status === 'conflict') {
        versions.set(key, r.current?.version || 0);
        const mine = changes.find((c) => c.collection === r.collection && c.id === r.id);
        // A conversation changed elsewhere: keep its other fields, move the
        // leaf to this reply.
        if (mine && r.collection === 'conversations' && r.current?.data) {
          const merged = { ...r.current.data, activeLeafId: mine.data.activeLeafId, updatedAt: mine.data.updatedAt };
          db.conversations.set(r.id, merged);
          if (current?.id === r.id) current = merged;
          await push([{ collection: 'conversations', id: r.id, data: merged }]);
        } else if (mine) {
          await push([mine]);
        }
      }
    }
  }

  async function listen() {
    while (!stop.signal.aborted) {
      try {
        const res = await api('/v1/events', { raw: true, signal: stop.signal });
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          let end;
          while ((end = buffer.indexOf('\n\n')) >= 0) {
            const block = buffer.slice(0, end);
            buffer = buffer.slice(end + 2);
            const name = /^event: (.*)$/m.exec(block)?.[1];
            if (name === 'sync' && !streaming) {
              await pull();
              renderList();
              renderLog();
            } else if (name === 'models') {
              loadModels();
            }
          }
        }
      } catch (e) {
        if (stop.signal.aborted) return;
      }
      await new Promise((r) => setTimeout(r, 3000));
    }
  }

  async function loadModels() {
    try {
      const ids = (await api('/v1/models')).data.map((m) => m.id);
      const saved = localStorage.getItem('den.model');
      fill(model, ...ids.map((id) => h('option', { value: id, selected: id === (current?.model || saved) }, id)));
      if (!ids.length) fill(model, h('option', { value: '' }, t('noModels')));
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  const visible = (c) => !c.incognito && !c.automationRuleId;
  function renderList() {
    const items = [...db.conversations.values()].filter(visible).sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')));
    fill(list, ...items.map((c) => h('a', {
      href: '#',
      class: current?.id === c.id ? 'on' : '',
      'aria-current': current?.id === c.id ? 'page' : null,
      onclick: (e) => {
        e.preventDefault();
        open(c.id);
        shell.classList.remove('menu');
      },
    }, c.title || t('newChat'))));
  }

  function path(conv) {
    const out = [];
    const seen = new Set();
    let id = conv?.activeLeafId;
    // Records come from other devices; a parent loop must not hang the page.
    while (id && !seen.has(id)) {
      seen.add(id);
      const m = db.messages.get(id);
      if (!m) break;
      out.unshift(m);
      id = m.parentId;
    }
    return out;
  }

  const textOf = (m) => (m.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
  const reasoningOf = (m) => (m.content || []).filter((b) => b.type === 'reasoning').map((b) => b.text).join('');

  function open(id) {
    current = id ? db.conversations.get(id) : null;
    if (current?.model && [...model.options].some((o) => o.value === current.model)) model.value = current.model;
    renderList();
    renderLog();
    input.focus();
  }

  function bubble(m) {
    const tools = (m.content || []).filter((b) => b.type === 'toolCall').map((b) => b.name);
    const reasoning = reasoningOf(m);
    const body = h('div', { class: 'body' });
    renderMarkdown(body, textOf(m) || (m.status === 'streaming' ? '' : tools.length ? '' : '…'));
    return h('article', { class: `msg ${m.role}`, dataset: { id: m.id } },
      reasoning ? h('details', { class: 'reasoning' }, h('summary', t('reasoning')), h('p', reasoning)) : null,
      body,
      tools.length ? h('div', { class: 'tools' }, '🔧 ', tools.join(', ')) : null,
      m.error ? h('div', { class: 'error' }, m.error) : null,
      h('time', { datetime: m.createdAt }, timeShort(m.createdAt)));
  }

  function renderLog() {
    if (current) current = db.conversations.get(current.id) || current;
    title.textContent = current?.title || t('newChat');
    const messages = path(current).filter((m) => m.role !== 'tool');
    if (!messages.length) {
      fill(log, h('div', { class: 'empty' }, mark(), h('p', t('emptyChat'))));
      return;
    }
    fill(log, ...messages.map(bubble));
    log.scrollTop = log.scrollHeight;
  }

  async function submit() {
    const text = input.value.trim();
    const chosen = model.value;
    if (!text || streaming || !chosen) return;
    input.value = '';
    input.style.height = 'auto';
    const now = new Date().toISOString();
    const offset = -new Date().getTimezoneOffset();
    if (!current) {
      current = { id: newId(), title: plainTitle(text), createdAt: now, updatedAt: now, systemPrompt: SYSTEM_PROMPT, activeLeafId: null, providerId: PROVIDER_ID, model: chosen };
    }
    const userMessage = { id: newId(), conversationId: current.id, parentId: current.activeLeafId, role: 'user', content: [{ type: 'text', text }], createdAt: now, timezoneOffsetMinutes: offset, providerId: PROVIDER_ID, model: chosen, status: 'done' };
    const history = [{ role: 'system', content: current.systemPrompt || SYSTEM_PROMPT },
      ...path(current).filter((m) => m.role !== 'tool' && textOf(m)).map((m) => ({ role: m.role, content: textOf(m) })),
      { role: 'user', content: text }];
    db.messages.set(userMessage.id, userMessage);
    current = { ...current, activeLeafId: userMessage.id, updatedAt: now, model: chosen };
    db.conversations.set(current.id, current);
    const reply = { id: newId(), conversationId: current.id, parentId: userMessage.id, role: 'assistant', content: [], createdAt: new Date().toISOString(), timezoneOffsetMinutes: offset, providerId: PROVIDER_ID, model: chosen, status: 'streaming' };
    db.messages.set(reply.id, reply);
    current = { ...current, activeLeafId: reply.id };
    db.conversations.set(current.id, current);
    streaming = reply;
    send.disabled = true;
    renderList();
    renderLog();
    try {
      await push([{ collection: 'conversations', id: current.id, data: { ...current, activeLeafId: userMessage.id } }, { collection: 'messages', id: userMessage.id, data: userMessage }]);
    } catch (e) {
      toast(e.message, 'error');
    }
    const node = log.lastElementChild;
    const body = node.querySelector('.body');
    let out = '';
    let thinking = '';
    let usage;
    try {
      const res = await api('/v1/chat/completions', { method: 'POST', raw: true, body: { model: chosen, stream: true, stream_options: { include_usage: true }, messages: history } });
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let painted = 0;
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop();
        for (const line of lines) {
          if (!line.startsWith('data:')) continue;
          const data = line.slice(5).trim();
          if (data === '[DONE]') continue;
          try {
            const chunk = JSON.parse(data);
            const delta = chunk.choices?.[0]?.delta || {};
            if (delta.content) out += delta.content;
            if (delta.reasoning_content || delta.reasoning) thinking += delta.reasoning_content || delta.reasoning;
            if (chunk.usage) usage = chunk.usage;
          } catch {}
        }
        if (Date.now() - painted > 50) {
          painted = Date.now();
          renderMarkdown(body, out || (thinking ? t('thinking') : ''));
          log.scrollTop = log.scrollHeight;
        }
      }
      reply.status = 'done';
    } catch (e) {
      reply.status = 'error';
      reply.error = e.message;
    }
    reply.content = [...(thinking ? [{ type: 'reasoning', text: thinking }] : []), { type: 'text', text: out }];
    if (usage) reply.usage = { inputTokens: usage.prompt_tokens, outputTokens: usage.completion_tokens, totalTokens: usage.total_tokens };
    db.messages.set(reply.id, reply);
    current = { ...current, updatedAt: new Date().toISOString() };
    db.conversations.set(current.id, current);
    streaming = null;
    send.disabled = false;
    renderList();
    renderLog();
    try {
      await push([{ collection: 'messages', id: reply.id, data: reply }, { collection: 'conversations', id: current.id, data: current }]);
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  await pull();
  renderList();
  open(null);
  await loadModels();
  listen();
  return () => stop.abort();
}

/** The first line of a message without Markdown markers, for a title. */
function plainTitle(text) {
  const line = text.split('\n').find((l) => l.trim()) || text;
  return line.replace(/^\s*(#{1,6}|[-*+>]|\d+\.)\s+/, '').replace(/(\*\*|__|`|~~)/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').trim().slice(0, 40);
}

/** A small, safe Markdown subset: fenced code, headings, lists, quotes,
 *  bold, italics, inline code and http(s) links. Builds DOM nodes only. */
export function renderMarkdown(target, source) {
  const out = [];
  const lines = source.replace(/\r\n?/g, '\n').split('\n');
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const fence = /^```(\S*)/.exec(line);
    if (fence) {
      const code = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) code.push(lines[i++]);
      i++;
      out.push(h('pre', h('code', { class: fence[1] ? `lang-${fence[1]}` : null }, code.join('\n'))));
      continue;
    }
    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      out.push(h(`h${Math.min(heading[1].length + 2, 6)}`, inline(heading[2])));
      i++;
      continue;
    }
    if (/^\s*([-*+]|\d+\.)\s+/.test(line)) {
      const ordered = /^\s*\d+\./.test(line);
      const items = [];
      while (i < lines.length && /^\s*([-*+]|\d+\.)\s+/.test(lines[i])) items.push(h('li', inline(lines[i++].replace(/^\s*([-*+]|\d+\.)\s+/, ''))));
      out.push(h(ordered ? 'ol' : 'ul', items));
      continue;
    }
    if (/^>\s?/.test(line)) {
      const quote = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) quote.push(lines[i++].replace(/^>\s?/, ''));
      out.push(h('blockquote', inline(quote.join('\n'))));
      continue;
    }
    if (!line.trim()) {
      i++;
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(```|#{1,4}\s|>|\s*([-*+]|\d+\.)\s)/.test(lines[i])) para.push(lines[i++]);
    out.push(h('p', inline(para.join('\n'))));
  }
  fill(target, ...out);
}

function inline(text) {
  const nodes = [];
  const pattern = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*\n]+\*)|\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(https?:\/\/[^\s<]+[^\s<.,;:!?)])/g;
  let last = 0;
  for (const m of text.matchAll(pattern)) {
    if (m.index > last) nodes.push(text.slice(last, m.index));
    if (m[1]) nodes.push(h('code', m[1].slice(1, -1)));
    else if (m[2]) nodes.push(h('strong', m[2].slice(2, -2)));
    else if (m[3]) nodes.push(h('em', m[3].slice(1, -1)));
    else if (m[4]) nodes.push(h('a', { href: m[5], target: '_blank', rel: 'noopener noreferrer' }, m[4]));
    else nodes.push(h('a', { href: m[6], target: '_blank', rel: 'noopener noreferrer' }, m[6]));
    last = m.index + m[0].length;
  }
  if (last < text.length) nodes.push(text.slice(last));
  return nodes;
}
