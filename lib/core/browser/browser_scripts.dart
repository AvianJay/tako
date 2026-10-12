import 'dart:convert';

/// One self-installing script per call. Page text is untrusted data, and no
/// JavaScript handler is exposed to the page: results return only through
/// evaluation. The runtime is installed once per document under a random
/// non-writable property and refuses calls without the session secret.
///
/// Element ids are small integers per read. Every action checks the document
/// token and read revision (a newer document or read makes ids stale) and the
/// element fingerprint resolved before permission, so an approval cannot be
/// retargeted to a different element. Checks and actions run synchronously.
String browserScript({
  required String key,
  required String secret,
  required String operation,
  Map<String, Object?> arguments = const {},
}) =>
    '''
(() => {
  const key = ${_js(key)}, secret = ${_js(secret)};
  try {
    if (!Object.prototype.hasOwnProperty.call(window, key)) {
$_runtime
    }
    return JSON.stringify(window[key](secret, ${_js(operation)}, ${_js(arguments)}));
  } catch (error) {
    return JSON.stringify({error: 'script_error'});
  }
})()''';

/// JSON is a JavaScript literal once U+2028/U+2029 are escaped.
String _js(Object? value) => jsonEncode(value)
    .replaceAll(
      String.fromCharCode(0x2028),
      r'\u'
      '2028',
    )
    .replaceAll(
      String.fromCharCode(0x2029),
      r'\u'
      '2029',
    );

const _runtime = r'''
      const doc = document;
      const random = () => {
        try {
          const values = new Uint32Array(2);
          crypto.getRandomValues(values);
          return values[0].toString(36) + values[1].toString(36);
        } catch (_) {
          return String(Math.random()).slice(2);
        }
      };
      const token = random();
      let revision = 0;
      let nodes = new Map();
      const MAX_ELEMENTS = 150;
      const SENSITIVE = /(password|one-time-code|cc-number|cc-csc|cc-exp)/i;
      const TEXT_TYPES = /^(text|search|email|url|tel|number|date|time|datetime-local|month|week)$/i;
      const SELECTOR = 'a[href],button,input,textarea,select,summary,' +
        '[role="button"],[role="link"],[role="checkbox"],[role="radio"],' +
        '[role="switch"],[role="tab"],[role="menuitem"],[role="option"],' +
        '[role="combobox"],[role="textbox"],[role="searchbox"],' +
        '[contenteditable=""],[contenteditable="true"],[onclick]';
      const SKIP_TEXT = 'script,style,noscript,template,svg,canvas,iframe,' +
        'select,textarea,option,[hidden],[aria-hidden="true"]';
      const BLOCKS = 'p,li,h1,h2,h3,h4,h5,h6,div,section,article,header,' +
        'footer,td,th,dt,dd,blockquote,pre,tr,figcaption,label';
      const clean = value =>
        String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
      const cut = (value, max) =>
        value.length > max ? value.slice(0, max - 1) + '…' : value;
      const attr = (el, name) => clean(el.getAttribute(name));
      const textOf = el => clean(el.innerText || el.textContent);
      const labelOf = el => {
        const tag = el.tagName;
        let value = attr(el, 'aria-label');
        if (!value) {
          const ids = attr(el, 'aria-labelledby');
          if (ids) {
            value = clean(ids.split(' ').map(id => {
              const node = doc.getElementById(id);
              return node ? textOf(node) : '';
            }).join(' '));
          }
        }
        if (!value && el.labels && el.labels.length) {
          value = clean(Array.from(el.labels).map(textOf).join(' '));
        }
        if (!value && tag === 'INPUT' &&
            /^(submit|button|reset|image)$/i.test(el.type)) {
          value = clean(el.value || el.alt);
        }
        if (!value && tag !== 'INPUT' && tag !== 'TEXTAREA' &&
            tag !== 'SELECT') {
          value = textOf(el);
        }
        if (!value) {
          value = attr(el, 'placeholder') || attr(el, 'title') ||
            attr(el, 'alt') || attr(el, 'name');
        }
        if (!value) {
          const inner = el.querySelector('img[alt],[aria-label],[title]');
          if (inner) {
            value = attr(inner, 'alt') || attr(inner, 'aria-label') ||
              attr(inner, 'title');
          }
        }
        return cut(value, 120);
      };
      const sensitive = el => el.tagName === 'INPUT' &&
        (String(el.type).toLowerCase() === 'password' ||
          SENSITIVE.test(el.getAttribute('autocomplete') || ''));
      const richText = el => {
        const value = el.getAttribute('contenteditable');
        return el.isContentEditable === true ||
          value !== null && /^(|true|plaintext-only)$/i.test(value);
      };
      const editable = el => !el.disabled && !el.readOnly &&
        (el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' ||
          el.tagName === 'INPUT' && TEXT_TYPES.test(el.type || 'text') ||
          richText(el));
      const formOf = el => el.form || (el.closest ? el.closest('form') : null);
      const submits = el => {
        if (!formOf(el)) return false;
        if (el.tagName === 'BUTTON') {
          return !/^(button|reset)$/i.test(el.getAttribute('type') || 'submit');
        }
        return el.tagName === 'INPUT' && /^(submit|image)$/i.test(el.type);
      };
      const visible = el => {
        if (!el.isConnected) return false;
        const rect = el.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return false;
        const style = getComputedStyle(el);
        return style.visibility !== 'hidden' && style.display !== 'none';
      };
      const fingerprint = el => {
        const form = formOf(el);
        return JSON.stringify([
          el.tagName, String(el.type || ''), labelOf(el),
          el.getAttribute('href') || '', el.getAttribute('formaction') || '',
          el.getAttribute('name') || '', el.getAttribute('role') || '',
          form ? form.getAttribute('action') || '' : '',
          form ? String(form.method || '') : '', sensitive(el)
        ]);
      };
      const describe = el => {
        const tag = el.tagName.toLowerCase();
        const type = tag === 'input' ?
          String(el.type || 'text').toLowerCase() : attr(el, 'role');
        const flags = [];
        if (sensitive(el)) flags.push('sensitive');
        if (el.disabled || attr(el, 'aria-disabled') === 'true') {
          flags.push('disabled');
        }
        const checked = tag === 'input' && /^(checkbox|radio)$/i.test(el.type) ?
          el.checked : attr(el, 'aria-checked') === 'true';
        if (checked) flags.push('checked');
        if (attr(el, 'aria-expanded') === 'true') flags.push('expanded');
        if (attr(el, 'aria-selected') === 'true') flags.push('selected');
        if (tag === 'a' && el.hasAttribute('download')) flags.push('download');
        let label = labelOf(el);
        let options = [];
        if (tag === 'select') {
          const selected = el.selectedOptions && el.selectedOptions[0];
          if (selected) {
            label = cut(clean((label ? label + ': ' : '') +
              (selected.label || selected.text)), 120);
          }
          options = Array.from(el.options).slice(0, 12)
            .map(option => cut(clean(option.label || option.text), 40));
        }
        return {tag, type, label, flags, options};
      };
      const collect = (root, out, depth) => {
        for (const el of root.querySelectorAll(SELECTOR)) {
          if (el.tagName === 'INPUT' &&
              String(el.type).toLowerCase() === 'hidden') continue;
          out.push(el);
        }
        if (depth >= 4) return;
        for (const host of root.querySelectorAll('*')) {
          if (host.shadowRoot) collect(host.shadowRoot, out, depth + 1);
        }
      };
      const pageText = (root, max) => {
        if (!root) return {value: '', truncated: false};
        const view = innerHeight || 1;
        const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        const checked = new Map();
        const parts = [];
        let length = 0;
        let started = false;
        let truncated = false;
        let block = null;
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const raw = node.nodeValue;
          if (!raw || !raw.trim()) continue;
          const parent = node.parentElement;
          if (!parent) continue;
          let shown = checked.get(parent);
          if (shown === undefined) {
            shown = !parent.closest(SKIP_TEXT) &&
              parent.getClientRects().length > 0 &&
              getComputedStyle(parent).visibility !== 'hidden';
            checked.set(parent, shown);
          }
          if (!shown) continue;
          // Start near the current scroll position, so scrolling then
          // reading again reaches the rest of a long page.
          if (!started) {
            if (parent.getBoundingClientRect().bottom < -0.25 * view) continue;
            started = true;
          }
          const piece = clean(raw);
          const owner = parent.closest(BLOCKS);
          const separator = parts.length === 0 ? '' : owner !== block ? '\n' : ' ';
          block = owner;
          if (length + separator.length + piece.length > max) {
            const room = max - length - separator.length;
            if (room > 0) parts.push(separator + piece.slice(0, room));
            truncated = true;
            break;
          }
          parts.push(separator + piece);
          length += separator.length + piece.length;
        }
        return {value: parts.join(''), truncated};
      };
      const read = args => {
        revision += 1;
        nodes = new Map();
        for (const old of doc.querySelectorAll('[data-tako-id]')) {
          old.removeAttribute('data-tako-id');
        }
        const view = innerHeight || 1;
        const all = [];
        collect(doc, all, 0);
        const seen = new Set();
        const found = [];
        for (const el of all) {
          if (found.length >= 3000) break;
          if (seen.has(el)) continue;
          seen.add(el);
          if (!visible(el)) continue;
          if (el.closest && el.closest('[aria-hidden="true"],[inert]')) continue;
          const rect = el.getBoundingClientRect();
          const distance = rect.bottom < 0 ? -rect.bottom :
            rect.top > view ? rect.top - view : 0;
          found.push({el, distance, order: found.length});
        }
        // Prefer elements on or near the screen, then list them in page order.
        const ranked = found.slice()
          .sort((a, b) => a.distance - b.distance || a.order - b.order)
          .slice(0, MAX_ELEMENTS)
          .sort((a, b) => a.order - b.order);
        const elements = [];
        for (const item of ranked) {
          const id = elements.length + 1;
          nodes.set(id, item.el);
          try { item.el.setAttribute('data-tako-id', String(id)); } catch (_) {}
          const info = describe(item.el);
          info.id = id;
          elements.push(info);
        }
        const root = doc.querySelector('main,[role="main"]') || doc.body ||
          doc.documentElement;
        const maxText = Math.max(500, Math.min(Number(args.maxText) || 6000, 20000));
        const text = pageText(root, maxText);
        const scrolling = doc.scrollingElement || doc.documentElement;
        return {
          token, revision, url: location.href, title: clean(doc.title),
          text: text.value, textTruncated: text.truncated, elements,
          elementsTruncated: found.length > ranked.length,
          scroll: {
            y: Math.round(scrollY),
            height: Math.round(scrolling ? scrolling.scrollHeight : 0),
            view: Math.round(view)
          }
        };
      };
      const lookup = args => {
        if (args.token !== token || args.revision !== revision) {
          return {error: 'stale_ids_read_again'};
        }
        const el = nodes.get(args.id);
        if (!el) return {error: 'unknown_id'};
        if (!visible(el)) return {error: 'element_gone_read_again'};
        return {el};
      };
      const target = args => {
        const found = lookup(args);
        if (found.error) return found;
        const el = found.el;
        const info = describe(el);
        const form = formOf(el);
        const submitLabels = form ? Array.from(form.querySelectorAll(
          'button,input[type="submit"],input[type="image"]'))
          .filter(submits).slice(0, 5).map(labelOf).filter(Boolean)
          .join(' | ') : '';
        return {
          id: args.id, tag: info.tag, type: info.type, label: info.label,
          check: fingerprint(el), url: location.href, sensitive: sensitive(el),
          editable: editable(el), submits: submits(el),
          formMethod: form ? String(form.method || 'get').toLowerCase() : '',
          submitLabels,
          download: el.tagName === 'A' && el.hasAttribute('download')
        };
      };
      const fire = el => {
        el.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
      };
      const enter = type => {
        const event = new KeyboardEvent(type, {
          key: 'Enter', code: 'Enter', bubbles: true, cancelable: true,
          composed: true
        });
        try {
          Object.defineProperty(event, 'keyCode', {get: () => 13});
          Object.defineProperty(event, 'which', {get: () => 13});
        } catch (_) {}
        return event;
      };
      const act = (args, op) => {
        const found = lookup(args);
        if (found.error) return found;
        const el = found.el;
        if (fingerprint(el) !== args.check) {
          return {error: 'element_changed_read_again'};
        }
        if (el.disabled || attr(el, 'aria-disabled') === 'true') {
          return {error: 'element_disabled'};
        }
        const tag = el.tagName;
        if (op === 'click') {
          if (tag === 'INPUT' && String(el.type).toLowerCase() === 'file') {
            return {error: 'file_input_needs_user'};
          }
          const label = labelOf(el);
          try { el.scrollIntoView({block: 'center', inline: 'nearest'}); } catch (_) {}
          el.click();
          return {clicked: label || tag.toLowerCase()};
        }
        if (sensitive(el)) return {error: 'password_entry_blocked'};
        const text = String(args.text == null ? '' : args.text);
        if (tag === 'SELECT') {
          const wanted = clean(text).toLowerCase();
          const options = Array.from(el.options);
          const name = option => clean(option.label || option.text).toLowerCase();
          const match = options.find(option => name(option) === wanted ||
              String(option.value).toLowerCase() === wanted) ||
            (wanted ? options.find(option => name(option).indexOf(wanted) >= 0) : null);
          if (!match) {
            return {
              error: 'option_not_found',
              options: options.slice(0, 20)
                .map(option => cut(clean(option.label || option.text), 40))
            };
          }
          Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')
            .set.call(el, match.value);
          fire(el);
          return {selected: clean(match.label || match.text)};
        }
        if (tag === 'INPUT' || tag === 'TEXTAREA') {
          if (tag === 'INPUT' && !TEXT_TYPES.test(el.type || 'text')) {
            return {error: 'not_a_text_field'};
          }
          if (el.readOnly) return {error: 'element_read_only'};
          try { el.scrollIntoView({block: 'center'}); } catch (_) {}
          el.focus({preventScroll: true});
          const proto = tag === 'TEXTAREA' ?
            HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          // The native setter keeps framework-controlled inputs in sync.
          Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
          fire(el);
        } else if (richText(el)) {
          el.focus();
          const range = doc.createRange();
          range.selectNodeContents(el);
          const selection = getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          // execCommand keeps editors' undo state; it is deprecated, so a
          // missing or refused command falls back to replacing the text.
          if (typeof doc.execCommand !== 'function' ||
              !doc.execCommand('insertText', false, text)) {
            el.textContent = text;
            el.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
          }
        } else {
          return {error: 'not_a_text_field'};
        }
        if (args.submit) {
          const proceed = el.dispatchEvent(enter('keydown'));
          el.dispatchEvent(enter('keypress'));
          el.dispatchEvent(enter('keyup'));
          const form = formOf(el);
          // Script-dispatched keys never submit a form by themselves.
          if (proceed && form && tag !== 'TEXTAREA') {
            if (typeof form.requestSubmit === 'function') {
              form.requestSubmit();
            } else {
              form.submit();
            }
          }
        }
        return {typed: true, submitted: !!args.submit};
      };
      const scroller = () => {
        const scrolling = doc.scrollingElement || doc.documentElement;
        if (scrolling && scrolling.scrollHeight > innerHeight + 4) return null;
        let best = null;
        let bestArea = 0;
        for (const el of doc.querySelectorAll('body *')) {
          if (el.scrollHeight <= el.clientHeight + 20) continue;
          if (!/(auto|scroll|overlay)/.test(getComputedStyle(el).overflowY)) {
            continue;
          }
          const rect = el.getBoundingClientRect();
          const area =
            Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0)) *
            Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0));
          if (area > bestArea) {
            bestArea = area;
            best = el;
          }
        }
        return best;
      };
      const scroll = args => {
        const inner = scroller();
        const scrolling = doc.scrollingElement || doc.documentElement;
        const view = inner ? inner.clientHeight : innerHeight;
        const height = inner ? inner.scrollHeight :
          scrolling ? scrolling.scrollHeight : 0;
        const position = () => inner ? inner.scrollTop : scrollY;
        const before = position();
        const top = args.direction === 'top' ? 0 :
          args.direction === 'bottom' ? height :
          before + (args.direction === 'up' ? -1 : 1) * Math.round(view * 0.8);
        const element = inner || window;
        try {
          element.scrollTo({top, left: 0, behavior: 'instant'});
        } catch (_) {
          element.scrollTo(0, top);
        }
        const after = position();
        return {
          scrolled: Math.round(after - before) !== 0,
          y: Math.round(after), height: Math.round(height),
          view: Math.round(view), at_bottom: after + view >= height - 8
        };
      };
      const invoke = (provided, op, args) => {
        if (provided !== secret) return {error: 'denied'};
        if (document !== doc) return {error: 'stale_ids_read_again'};
        const input = args || {};
        if (op === 'read') return read(input);
        if (op === 'target') return target(input);
        if (op === 'click' || op === 'type') return act(input, op);
        if (op === 'scroll') return scroll(input);
        if (op === 'state') {
          return {token, state: doc.readyState, url: location.href,
            title: clean(doc.title)};
        }
        return {error: 'unsupported_operation'};
      };
      Object.defineProperty(window, key, {
        value: invoke, writable: false, configurable: false, enumerable: false
      });''';
