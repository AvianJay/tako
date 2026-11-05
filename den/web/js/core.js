// Shared helpers for the Den web app: DOM building, strings, the API client,
// the session, routing and small dialogs. User data only ever reaches the
// page as text nodes, never as HTML.

// --- Strings -------------------------------------------------------------

const strings = {
  'zh-TW': {
    appName: 'Tako Den', signIn: '登入', signOut: '登出', register: '建立帳號', username: '使用者名稱',
    displayName: '顯示名稱', password: '密碼', newPassword: '新密碼', currentPassword: '目前的密碼', inviteCode: '邀請碼',
    continueWith: '使用 {name} 繼續', or: '或', noAccount: '還沒有帳號？', haveAccount: '已經有帳號？',
    adminPasswordSignIn: '管理員用密碼登入', setupTitle: '建立管理員', setupBody: '這是這台 Den 的第一個帳號，擁有全部管理權限。',
    setupDone: '這台 Den 已經設定好了。', setupNoToken: '請用伺服器記錄裡印出的設定連結打開這一頁。',
    newChat: '新對話', chats: '對話', settings: '設定', admin: '管理', send: '送出', messagePlaceholder: '傳訊息給 Tako…',
    emptyChat: '問 Tako 任何事。這裡的對話會同步到你登入的 App。', noModels: '沒有可用的模型', thinking: '思考中…',
    save: '儲存', cancel: '取消', delete: '刪除', edit: '編輯', add: '新增', create: '建立', close: '關閉', copy: '複製',
    copied: '已複製', saved: '已儲存', deleted: '已刪除', confirmDelete: '確定要刪除「{name}」嗎？', test: '測試', enabled: '啟用',
    disabled: '停用', yes: '是', no: '否', none: '無', unlimited: '不限', inherit: '沿用預設', loading: '載入中…',
    profile: '個人資料', linkedAccounts: '連結的帳號', unlink: '取消連結', devices: '裝置與 API key',
    thisDevice: '這個瀏覽器', revoke: '撤銷', pairPhone: '產生配對碼',
    pairStep1: '在 Tako 點「或者連線至 Den…」，或打開「設定 → Tako Den」。', pairStep2: '輸入下面的伺服器位址，按「繼續」。', pairStep3: '選「輸入配對碼」，輸入下面的代碼。', validUntil: '有效到 {time}',
    createKey: '建立 API key', keyName: '名稱', keyHelp: '給其他 App 使用。Base URL 填 {url}，模型清單會自動出現。',
    keyShownOnce: '這把 key 只會顯示這一次：', myProviders: '我的模型供應商',
    myProvidersHelp: '用你自己的 API key。模型會以 me/名稱/模型 出現在你的所有裝置上，只有你看得到。',
    providerName: '代號', providerNameHelp: '小寫英數，用在模型名稱前綴，例如 openai', providerDisplay: '顯示名稱', baseUrl: 'Base URL',
    apiKey: 'API key', apiKeyKeep: '留空保持不變', models: '模型白名單', modelsHelp: '每行一個；留空表示提供上游的全部模型',
    testOk: '連線成功，找到 {count} 個模型', usage: '用量', sharedTokensToday: '今天使用共用模型 {used} tokens',
    limit: '上限 {limit}', model: '模型', day: '日期', requests: '請求', inputTokens: '輸入 tokens', outputTokens: '輸出 tokens',
    passwordChanged: '密碼已更新', server: '伺服器', serverName: '伺服器名稱', publicUrl: '公開網址',
    publicUrlHelp: '手機和 OAuth 登入用的網址，例如 https://den.example.com', publicUrlLocked: '由 TAKO_PUBLIC_URL 設定',
    registration: '註冊', regClosed: '關閉（只有管理員能新增使用者）', regInvite: '需要邀請碼', regOpen: '開放註冊',
    passwordLogin: '允許用密碼登入', passwordLoginHelp: '關閉後只能用 OAuth 登入；管理員仍可用密碼。',
    defaultPermissions: '新使用者的預設權限', useShared: '可以使用共用模型', ownProviders: '可以新增自己的模型供應商',
    dailyLimit: '每日共用 token 上限', dailyLimitHelp: '留空表示不限', privateNetworks: '允許使用者的供應商連到內網位址',
    privateNetworksHelp: '開啟後，使用者可以讓伺服器連到區網或本機服務。只在信任所有使用者時開啟。',
    users: '使用者', role: '角色', roleAdmin: '管理員', roleUser: '使用者', status: '狀態', addUser: '新增使用者',
    permissions: '權限', resetPassword: '重設密碼', usedToday: '今天 {count} tokens', sharedProviders: '共用模型供應商',
    sharedProvidersHelp: '所有被允許的使用者都能用，API key 不會離開伺服器。', access: '誰可以用', accessAll: '所有使用者',
    accessSelected: '指定的使用者', fromConfig: '來自設定檔', oauthProviders: '登入方式', oauthHelp: '讓使用者用 Google、Discord、GitHub 或任何 OpenID Connect（Authentik、Keycloak…）登入。',
    redirectUri: 'Redirect URI', redirectUriHelp: '把這個網址貼到供應商的 OAuth 設定。', needPublicUrl: '要先在「伺服器」設定公開網址。',
    clientId: 'Client ID', clientSecret: 'Client secret', issuer: 'Issuer URL', type: '類型', invites: '邀請碼',
    invitesHelp: '註冊需要邀請碼時，把連結傳給朋友。', maxUses: '可使用次數', expiresInDays: '幾天後過期', note: '備註',
    expires: '{time} 到期', expired: '已過期', copyLink: '複製連結', allUsage: '全部用量',
    user: '使用者', shared: '共用', own: '自己的', approveTitle: '允許這個裝置登入？', approveBody: '「{name}」想登入你的帳號。只有在你剛剛從這個裝置開始登入時才允許。',
    approveCode: '確認代碼和 App 上顯示的一樣：', approve: '允許', deny: '拒絕', approved: '完成了，回到 App 就能繼續。',
    denied: '已拒絕。', enterCode: '輸入 App 上顯示的代碼', deviceCodeInvalid: '代碼錯誤或已過期。', signedInAs: '登入為 {name}',
    networkError: '連不到伺服器', youAreAdmin: '你是管理員', linkedSuccess: '已連結 {name}',
    reasoning: '思考過程', 
    identityInUse: '這個帳號已經連結到另一個使用者', changePassword: '變更密碼', setPassword: '設定密碼', passwordHelp: '至少 8 個字元',
    wrongPassword: '目前的密碼不正確', signInMethod: '登入方式', account: '帳號', confirmUnlink: '取消連結 {name}？之後就不能用它登入。',
    noIdentities: '還沒有連結任何帳號', linkWith: '連結 {name}',
    noOAuth: '管理員還沒有設定 OAuth 登入。', name: '名稱', lastUsed: '上次使用', confirmRevoke: '撤銷「{name}」？它會立刻被登出。',
    devicesHelp: '登入過你帳號的 App、瀏覽器和 API key。', noUsage: '還沒有用量', customLimit: '自訂上限', confirmDeleteUser: '刪除使用者「{name}」？他的對話、記憶、裝置和供應商會一起刪除，無法復原。',
    disableAccount: '停用帳號', disableHelp: '停用後會立刻登出所有裝置，資料保留。', 
    
    noOAuthProviders: '還沒有設定任何登入方式', confirmDeleteOAuth: '刪除登入方式「{name}」？已連結的帳號會保留，重新加回同一個 ID 就能再用。',
    addSignInMethod: '新增登入方式', issuerHelp: 'OpenID Connect 的 issuer，伺服器會讀取它的 .well-known 設定', scopesDefault: '預設',
    oauthConsole: '先到 {name} 的開發者後台建立 OAuth 應用程式：', oidcHint: '在你的身分供應商（Authentik、Keycloak…）建立一個 OAuth2/OpenID 應用程式。',
    oauthId: 'ID', oauthIdHelp: '用在 Redirect URI 裡；同一種類型要設定兩個時才需要改', scopes: 'Scopes', scopesHelp: '用空格分隔；留空使用預設',
    invitesNotNeeded: '目前的註冊方式不需要邀請碼。', usesHeader: '使用次數', never: '永不過期', noInvites: '還沒有邀請碼', createInvite: '建立邀請碼',
    notePlaceholder: '給誰的', inviteShare: '把這個連結傳給對方，他就能建立帳號：', usageByUser: '每位使用者', last30Days: '最近 30 天',
    sharedTokens: '共用 tokens', ownTokens: '自己的 tokens', tab_server: '伺服器', tab_users: '使用者', tab_providers: '模型供應商',
    tab_oauth: '登入方式', tab_invites: '邀請碼', tab_usage: '用量',
    err_invalid_login: '使用者名稱或密碼不正確', err_invalid_state: '登入逾時或在別的分頁開始，請重新登入', err_account_disabled: '這個帳號已被停用', err_password_login_disabled: '這台 Den 只能用 OAuth 登入', err_registration_closed: '這台 Den 沒有開放註冊', err_invalid_invite: '邀請碼無效或已用完', err_identity_in_use: '這個帳號已經連結到另一個使用者', err_too_many_attempts: '嘗試太多次，請稍後再試', err_username_taken: '這個使用者名稱已經有人用了', err_invalid_username: '使用者名稱只能用 2–32 個英數字、底線、點或減號', err_password_too_short: '密碼至少要 8 個字元', err_name_taken: '這個代號已經有人用了', err_id_taken: '這個 ID 已經有人用了', err_private_address: '不能連到內網位址（管理員沒有開放）', err_invalid_url: '網址格式不正確', err_last_admin: '至少要保留一個啟用中的管理員', err_last_sign_in_method: '這是唯一的登入方式。先設定密碼或連結其他帳號。', err_public_url_required: '要先在管理頁設定公開網址', err_oauth_failed: 'OAuth 登入失敗，請再試一次', err_access_denied: '登入被拒絕', err_invalid_ticket: '登入連結已失效，請重新登入', err_quota_exceeded: '今天的共用模型用量已達上限', err_model_not_found: '找不到這個模型，或你沒有使用權限', err_expired: '已過期，請重新開始', err_invalid_setup_token: '設定連結不正確，請用伺服器記錄裡最新的連結', err_setup_done: '這台 Den 已經設定好了', err_forbidden: '你沒有權限做這件事', err_upstream_unreachable: '連不到模型供應商', err_upstream_error: '模型供應商回傳錯誤', err_read_only: '這個項目來自設定檔，不能在這裡修改',
  },
  en: {
    appName: 'Tako Den', signIn: 'Sign in', signOut: 'Sign out', register: 'Create account', username: 'Username',
    displayName: 'Display name', password: 'Password', newPassword: 'New password', currentPassword: 'Current password', inviteCode: 'Invite code',
    continueWith: 'Continue with {name}', or: 'or', noAccount: 'No account yet?', haveAccount: 'Already have an account?',
    adminPasswordSignIn: 'Administrator password sign-in', setupTitle: 'Create the administrator', setupBody: 'The first account on this Den, with full control.',
    setupDone: 'This Den is already set up.', setupNoToken: 'Open this page with the setup link printed in the server log.',
    newChat: 'New chat', chats: 'Chats', settings: 'Settings', admin: 'Admin', send: 'Send', messagePlaceholder: 'Message Tako…',
    emptyChat: 'Ask Tako anything. Chats here sync to the apps you sign in to.', noModels: 'No models available', thinking: 'Thinking…',
    save: 'Save', cancel: 'Cancel', delete: 'Delete', edit: 'Edit', add: 'Add', create: 'Create', close: 'Close', copy: 'Copy',
    copied: 'Copied', saved: 'Saved', deleted: 'Deleted', confirmDelete: 'Delete “{name}”?', test: 'Test', enabled: 'Enabled',
    disabled: 'Disabled', yes: 'Yes', no: 'No', none: 'None', unlimited: 'Unlimited', inherit: 'Default', loading: 'Loading…',
    profile: 'Profile', linkedAccounts: 'Linked accounts', unlink: 'Unlink', devices: 'Devices and API keys',
    thisDevice: 'This browser', revoke: 'Revoke', pairPhone: 'Create a pairing code',
    pairStep1: 'In Tako, tap “Or connect to Den…”, or open Settings → Tako Den.', pairStep2: 'Enter the server address below and tap Continue.', pairStep3: 'Choose “Enter a pairing code” and type the code below.', validUntil: 'Valid until {time}',
    createKey: 'Create API key', keyName: 'Name', keyHelp: 'For other apps. Use {url} as the base URL; the model list appears automatically.',
    keyShownOnce: 'This key is shown only once:', myProviders: 'My model providers',
    myProvidersHelp: 'With your own API key. Models appear as me/name/model on all your devices, only for you.',
    providerName: 'Id', providerNameHelp: 'Lowercase letters and digits, used as the model prefix, e.g. openai', providerDisplay: 'Display name', baseUrl: 'Base URL',
    apiKey: 'API key', apiKeyKeep: 'Leave empty to keep', models: 'Model allowlist', modelsHelp: 'One per line; empty offers every model the upstream lists',
    testOk: 'Connected; {count} models found', usage: 'Usage', sharedTokensToday: '{used} shared-model tokens today',
    limit: 'limit {limit}', model: 'Model', day: 'Day', requests: 'Requests', inputTokens: 'Input tokens', outputTokens: 'Output tokens',
    passwordChanged: 'Password changed', server: 'Server', serverName: 'Server name', publicUrl: 'Public URL',
    publicUrlHelp: 'The address phones and OAuth sign-in use, e.g. https://den.example.com', publicUrlLocked: 'Set by TAKO_PUBLIC_URL',
    registration: 'Registration', regClosed: 'Closed (only administrators add users)', regInvite: 'Invite code required', regOpen: 'Open',
    passwordLogin: 'Allow password sign-in', passwordLoginHelp: 'When off, people sign in with OAuth only; administrators can still use passwords.',
    defaultPermissions: 'Defaults for new users', useShared: 'May use shared models', ownProviders: 'May add their own providers',
    dailyLimit: 'Daily shared-token limit', dailyLimitHelp: 'Empty for no limit', privateNetworks: 'Let users’ providers reach private addresses',
    privateNetworksHelp: 'Lets users make the server connect to services on your network. Turn on only if you trust every user.',
    users: 'Users', role: 'Role', roleAdmin: 'Administrator', roleUser: 'User', status: 'Status', addUser: 'Add user',
    permissions: 'Permissions', resetPassword: 'Reset password', usedToday: '{count} tokens today', sharedProviders: 'Shared model providers',
    sharedProvidersHelp: 'Every permitted user can use these; the API keys never leave the server.', access: 'Who can use it', accessAll: 'All users',
    accessSelected: 'Selected users', fromConfig: 'From the config file', oauthProviders: 'Sign-in methods', oauthHelp: 'Let people sign in with Google, Discord, GitHub or any OpenID Connect provider (Authentik, Keycloak…).',
    redirectUri: 'Redirect URI', redirectUriHelp: 'Paste this into the provider’s OAuth settings.', needPublicUrl: 'Set the public URL under Server first.',
    clientId: 'Client ID', clientSecret: 'Client secret', issuer: 'Issuer URL', type: 'Type', invites: 'Invites',
    invitesHelp: 'When registration needs an invite, send a link to a friend.', maxUses: 'Uses', expiresInDays: 'Expires in days', note: 'Note',
    expires: 'Expires {time}', expired: 'Expired', copyLink: 'Copy link', allUsage: 'All usage',
    user: 'User', shared: 'Shared', own: 'Own', approveTitle: 'Let this device sign in?', approveBody: '“{name}” wants to sign in to your account. Allow it only if you just started signing in on that device.',
    approveCode: 'Check that the code matches the one in the app:', approve: 'Allow', deny: 'Deny', approved: 'Done. Go back to the app to continue.',
    denied: 'Denied.', enterCode: 'Enter the code shown in the app', deviceCodeInvalid: 'The code is wrong or has expired.', signedInAs: 'Signed in as {name}',
    networkError: 'Can’t reach the server', youAreAdmin: 'You are an administrator', linkedSuccess: 'Linked {name}',
    reasoning: 'Reasoning', 
    identityInUse: 'That account is linked to another user', changePassword: 'Change password', setPassword: 'Set password', passwordHelp: 'At least 8 characters',
    wrongPassword: 'The current password is wrong', signInMethod: 'Sign-in', account: 'Account', confirmUnlink: 'Unlink {name}? You won’t be able to sign in with it.',
    noIdentities: 'No linked accounts yet', linkWith: 'Link {name}',
    noOAuth: 'The administrator hasn’t set up OAuth sign-in.', name: 'Name', lastUsed: 'Last used', confirmRevoke: 'Revoke “{name}”? It is signed out at once.',
    devicesHelp: 'Apps, browsers and API keys signed in to your account.', noUsage: 'No usage yet', customLimit: 'Custom limit', confirmDeleteUser: 'Delete the user “{name}”? Their chats, memories, devices and providers are deleted too. This can’t be undone.',
    disableAccount: 'Disable account', disableHelp: 'Signs out every device at once; the data stays.', 
    
    noOAuthProviders: 'No sign-in methods yet', confirmDeleteOAuth: 'Delete the sign-in method “{name}”? Linked accounts stay and work again if the same id is added back.',
    addSignInMethod: 'Add a sign-in method', issuerHelp: 'The OpenID Connect issuer; the server reads its .well-known configuration', scopesDefault: 'Default',
    oauthConsole: 'First create an OAuth app in the {name} developer console:', oidcHint: 'Create an OAuth2/OpenID application in your identity provider (Authentik, Keycloak…).',
    oauthId: 'Id', oauthIdHelp: 'Part of the redirect URI; change it only to add two of the same type', scopes: 'Scopes', scopesHelp: 'Space-separated; empty uses the defaults',
    invitesNotNeeded: 'The current registration mode doesn’t use invites.', usesHeader: 'Uses', never: 'Never expires', noInvites: 'No invites yet', createInvite: 'Create invite',
    notePlaceholder: 'Who it’s for', inviteShare: 'Send this link; it lets them create an account:', usageByUser: 'Per user', last30Days: 'Last 30 days',
    sharedTokens: 'Shared tokens', ownTokens: 'Own tokens', tab_server: 'Server', tab_users: 'Users', tab_providers: 'Model providers',
    tab_oauth: 'Sign-in methods', tab_invites: 'Invites', tab_usage: 'Usage',
    err_invalid_login: 'Wrong username or password', err_invalid_state: 'The sign-in timed out or started in another tab; sign in again', err_account_disabled: 'This account is disabled', err_password_login_disabled: 'This Den only allows OAuth sign-in', err_registration_closed: 'Registration is closed on this Den', err_invalid_invite: 'The invite is not valid or has been used up', err_identity_in_use: 'That account is linked to another user', err_too_many_attempts: 'Too many attempts; try again later', err_username_taken: 'That username is taken', err_invalid_username: 'Usernames are 2–32 letters, digits, underscores, dots or hyphens', err_password_too_short: 'Passwords need at least 8 characters', err_name_taken: 'That id is taken', err_id_taken: 'That id is taken', err_private_address: 'Private addresses are not allowed (the administrator hasn’t enabled them)', err_invalid_url: 'That URL isn’t valid', err_last_admin: 'At least one active administrator must remain', err_last_sign_in_method: 'This is the only way to sign in. Set a password or link another account first.', err_public_url_required: 'Set the public URL on the admin page first', err_oauth_failed: 'OAuth sign-in failed; try again', err_access_denied: 'Sign-in was denied', err_invalid_ticket: 'The sign-in link expired; sign in again', err_quota_exceeded: 'Today’s shared-model limit is reached', err_model_not_found: 'Model not found, or you may not use it', err_expired: 'Expired; start again', err_invalid_setup_token: 'Wrong setup link; use the latest one in the server log', err_setup_done: 'This Den is already set up', err_forbidden: 'You don’t have permission to do that', err_upstream_unreachable: 'Can’t reach the model provider', err_upstream_error: 'The model provider returned an error', err_read_only: 'This comes from the config file and can’t be changed here',
  },
};

const lang = (navigator.languages || [navigator.language]).some((l) => /^zh/i.test(l)) ? 'zh-TW' : 'en';
document.documentElement.lang = lang === 'zh-TW' ? 'zh-Hant' : 'en';

export const hasString = (key) => key in strings[lang] || key in strings.en;

export function t(key, vars = {}) {
  const text = strings[lang][key] ?? strings.en[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (_, name) => (vars[name] ?? `{${name}}`).toString());
}

// --- DOM -----------------------------------------------------------------

/** Builds an element. Strings become text nodes; `on*` props are listeners. */
export function h(tag, props, ...children) {
  const el = document.createElement(tag);
  if (props && (typeof props !== 'object' || props instanceof Node || Array.isArray(props))) {
    children.unshift(props);
    props = null;
  }
  for (const [key, value] of Object.entries(props || {})) {
    if (value == null || value === false) continue;
    if (key.startsWith('on')) el.addEventListener(key.slice(2).toLowerCase(), value);
    else if (key === 'class') el.className = value;
    else if (key === 'style') el.style.cssText = value;
    else if (key === 'dataset') Object.assign(el.dataset, value);
    else if (key in el && typeof value !== 'string') el[key] = value;
    else el.setAttribute(key, value === true ? '' : value);
  }
  append(el, children);
  return el;
}

/** Like el.replaceChildren, but skips null and false as h() does (the DOM
 *  would show them as text). */
export function fill(el, ...children) {
  el.replaceChildren();
  append(el, children);
  return el;
}

function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child == null || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
}

export const $ = (selector, root = document) => root.querySelector(selector);

export function mark() {
  return h('span', { class: 'mark', 'aria-hidden': 'true' }, h('span', { class: 'head' }), h('span', { class: 'dots' }, h('i'), h('i'), h('i')));
}

export const time = (iso) => (iso ? new Date(iso).toLocaleString(lang) : '');
export const timeShort = (iso) => (iso ? new Date(iso).toLocaleString(lang, { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '');
export const number = (n) => (n ?? 0).toLocaleString(lang);

// --- Feedback ------------------------------------------------------------

export function toast(message, kind = 'info') {
  let host = $('#toasts');
  if (!host) document.body.append((host = h('div', { id: 'toasts', role: 'status', 'aria-live': 'polite' })));
  const item = h('div', { class: `toast ${kind}` }, message);
  host.append(item);
  setTimeout(() => item.classList.add('out'), 3200);
  setTimeout(() => item.remove(), 3700);
}

/** A modal dialog. `build(close)` returns its content; resolves with the
 *  value passed to close. */
export function dialog(title, build, { wide = false } = {}) {
  return new Promise((resolve) => {
    const el = h('dialog', { class: wide ? 'wide' : '' });
    const close = (value) => {
      el.close();
      el.remove();
      resolve(value);
    };
    el.addEventListener('cancel', (e) => {
      e.preventDefault();
      close(undefined);
    });
    el.append(h('h2', title), build(close));
    document.body.append(el);
    el.showModal();
  });
}

export async function confirmDialog(message, { title = '', danger = true, ok = t('delete') } = {}) {
  return dialog(title, (close) =>
    h('div', h('p', message), h('div', { class: 'actions' },
      h('button', { class: 'ghost', onclick: () => close(false) }, t('cancel')),
      h('button', { class: danger ? 'danger' : '', onclick: () => close(true) }, ok))));
}

export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast(t('copied'));
  } catch {
    window.prompt(t('copy'), text);
  }
}

/** A labelled form row. */
export function field(label, input, help) {
  return h('label', { class: 'field' }, h('span', { class: 'label' }, label), input, help ? h('span', { class: 'help' }, help) : null);
}

export function toggle(label, checked, help) {
  const input = h('input', { type: 'checkbox', checked });
  return { input, el: h('label', { class: 'toggle' }, input, h('span', h('b', label), help ? h('small', help) : null)) };
}

/** Runs a button's action, disabling it meanwhile and reporting errors. */
export async function busy(button, action) {
  button.disabled = true;
  try {
    return await action();
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    button.disabled = false;
  }
}

// --- Session and API -----------------------------------------------------

export const session = {
  get token() { return localStorage.getItem('den.token'); },
  get deviceId() { return localStorage.getItem('den.device'); },
  user: null,
  info: null,
  save(s) {
    localStorage.setItem('den.token', s.token);
    localStorage.setItem('den.device', s.device.id);
    session.user = s.user;
  },
  clear() {
    localStorage.removeItem('den.token');
    localStorage.removeItem('den.device');
    session.user = null;
  },
};

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export async function api(path, { method = 'GET', body, raw = false, signal } = {}) {
  let res;
  try {
    res = await fetch(path, {
      method,
      signal,
      headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...(session.token ? { authorization: `Bearer ${session.token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (e) {
    if (e.name === 'AbortError') throw e;
    throw new ApiError(0, 'network', t('networkError'));
  }
  if (res.status === 401 && session.token && !path.startsWith('/v1/auth/')) {
    session.clear();
    navigate(`/login?return=${encodeURIComponent(location.pathname + location.search)}`);
    throw new ApiError(401, 'unauthorized', 'Signed out');
  }
  if (!res.ok && res.status !== 202) {
    let code = `http_${res.status}`;
    let message = `HTTP ${res.status}`;
    try {
      const err = (await res.json()).error;
      code = err.code;
      message = hasString(`err_${code}`) ? t(`err_${code}`) : err.message;
    } catch {}
    // The server revokes a disabled account's tokens; say why on the way out.
    if (code === 'account_disabled' && session.token) {
      session.clear();
      navigate('/login?error=account_disabled', { replace: true });
    }
    throw new ApiError(res.status, code, message);
  }
  if (raw) return res;
  const text = await res.text();
  return text ? JSON.parse(text) : {};
}

/** The signed-in user. Without one, goes to the sign-in page (unless a
 *  failed request already went there with a reason) and returns null. */
export async function requireUser() {
  const user = await loadUser();
  if (!user && location.pathname !== '/login') navigate(`/login?return=${encodeURIComponent(location.pathname + location.search)}`, { replace: true });
  return user;
}

/** Loads the signed-in user, or null when there is no valid session. */
export async function loadUser() {
  if (!session.token) return null;
  try {
    const me = await api('/v1/me');
    session.user = me.user;
    return me.user;
  } catch {
    return null;
  }
}

// --- Routing -------------------------------------------------------------

const routes = new Map();
let cleanup = null;
let generation = 0;

export function route(path, render) {
  routes.set(path, render);
}

export function navigate(path, { replace = false } = {}) {
  if (replace) history.replaceState(null, '', path);
  else history.pushState(null, '', path);
  render();
}

/** Only same-site paths, so links in query strings cannot redirect away. */
export function safeReturn(value, fallback = '/') {
  return typeof value === 'string' && value.startsWith('/') && !value.startsWith('//') && !value.startsWith('/\\') ? value : fallback;
}

export async function render() {
  const mine = ++generation;
  if (cleanup) {
    try { cleanup(); } catch {}
    cleanup = null;
  }
  const path = location.pathname.replace(/\/+$/, '') || '/';
  const page = routes.get(path) || routes.get('/');
  const root = $('#app');
  root.replaceChildren(h('div', { class: 'loading' }, mark()));
  const params = new URLSearchParams(location.search);
  try {
    const result = await page({ params, root });
    // A page that finished loading after the next navigation stops at once.
    if (typeof result === 'function') {
      if (mine === generation) cleanup = result;
      else result();
    }
  } catch (e) {
    if (mine !== generation) return;
    root.replaceChildren(h('div', { class: 'center-card' }, h('p', { class: 'error' }, e.message)));
  }
}

addEventListener('popstate', render);
document.addEventListener('click', (e) => {
  const a = e.target.closest('a[data-route]');
  if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey) return;
  e.preventDefault();
  navigate(a.getAttribute('href'));
});

export const routeLink = (href, ...children) => h('a', { href, dataset: { route: '' } }, ...children);

export function newId() {
  const a = '0123456789abcdefghijklmnopqrstuvwxyz';
  let s = Date.now().toString(36).padStart(9, '0');
  for (const b of crypto.getRandomValues(new Uint8Array(12))) s += a[b % 36];
  return s;
}

export const deviceName = () => `Web · ${navigator.userAgentData?.platform || (/Mac/.test(navigator.platform) ? 'macOS' : navigator.platform) || 'browser'}`;
