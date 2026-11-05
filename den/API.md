# Tako Den HTTP API, version 1

This is the contract between the Den server, its web app (`web/`) and the Tako
app. Paths are relative to the server's address.

## Conventions

- Bodies are JSON (UTF-8) unless noted. Timestamps are ISO-8601 UTC strings.
- Errors: HTTP status plus `{"error": {"code": "snake_case", "message": "Human text."}}`.
  Clients branch on `code`, never on `message`.
- Authenticated routes take `Authorization: Bearer <token>`. Tokens start with
  `tako_`. A missing, unknown or revoked token gives 401 `unauthorized`; a
  disabled account gives 403 `account_disabled` (and its tokens are revoked).
- IDs are opaque strings (base-36 time prefix plus random text, like the app).
- Secrets (provider API keys, OAuth client secrets) are write-only: responses
  carry `hasApiKey` / `hasClientSecret` instead. In a PATCH, an omitted secret
  keeps the old one and `""` clears it.
- Limits: 64 KB bodies for unauthenticated routes, 16 MB for sync, 32 MB for
  chat, 64 MB per blob.

### Shared shapes

**Session** — returned by every sign-in route:

```json
{"token": "tako_…", "device": {"id": "…", "name": "Pixel 9"}, "user": User}
```

**User** (as seen by that user):

```json
{
  "id": "…", "username": "ana", "displayName": "Ana",
  "role": "admin" | "user",
  "hasPassword": true,
  "permissions": Permissions,          // effective values
  "createdAt": "…"
}
```

**Permissions**:

```json
{
  "useSharedProviders": true,   // may use the administrator's providers
  "ownProviders": true,         // may add their own providers
  "dailyTokenLimit": null       // shared-provider input+output tokens per UTC day; null = unlimited
}
```

Administrators always have every permission and no limit. Other users get the
server defaults (`/v1/admin/settings`) overridden field by field by their own
`permissions` (a `null` field inherits). In overrides only, `dailyTokenLimit: -1`
means no limit for that user even when the default has one; effective
permissions show it as `null`.

**Provider** — an OpenAI-compatible model service:

```json
{
  "id": "…",
  "name": "openai",                 // ^[a-z0-9][a-z0-9_-]{0,31}$, not "me"; unique per scope
  "displayName": "OpenAI",
  "baseUrl": "https://api.openai.com/v1",
  "hasApiKey": true,
  "models": ["gpt-5.5"],            // allowlist; empty = whatever the upstream lists
  "enabled": true,
  "source": "admin" | "config" | "user",
  "access": {"allUsers": true, "userIds": []},   // shared providers only
  "createdAt": "…", "updatedAt": "…"
}
```

`config` providers come from `tako-den.yaml` or environment variables
(`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `OLLAMA_URL`). They are listed for
administrators but cannot be edited through the API (400 `read_only`).

Model ids seen by clients: `<name>/<model>` for shared providers and
`me/<name>/<model>` for the user's own. The first `/` after the prefix
separates provider and model; the model part may contain more slashes
(`openrouter/anthropic/claude-sonnet-5.5`).

## Server information and first start

`GET /healthz` → `ok` (text).

`GET /v1/info` (public):

```json
{
  "name": "Tako Den",               // admin setting serverName
  "version": "0.2.0",
  "setupRequired": false,           // no users exist yet
  "registration": "closed" | "invite" | "open",
  "passwordLogin": true,
  "oauth": [{"id": "google", "type": "google", "name": "Google"}],   // enabled ones only
  "features": ["sync", "gateway", "pairing", "events", "blobs", "device-login", "oauth"]
}
```

**First administrator.** If `TAKO_ADMIN_PASSWORD` is set and there are no
users, the server creates the administrator at start-up (as today). Otherwise
it prints a one-time setup link to stdout:
`Open <url>/setup?token=<setupToken> to create the administrator.`
The token lives in memory (a new one per start) until an administrator exists.

`POST /v1/setup` `{setupToken, username, password, displayName?, deviceName}` →
Session. 403 `setup_done` when a user already exists; 403 `invalid_setup_token`.

## Signing in

### Password

`POST /v1/auth/login` `{username, password, deviceName}` → Session.
- 401 `invalid_login`, 429 `too_many_attempts` (per name+address and per address).
- 403 `password_login_disabled` when the admin turned password sign-in off.
  Administrators can always sign in with a password, so a broken OAuth setup
  cannot lock the server owner out.

`POST /v1/auth/register` `{username, password, displayName?, inviteCode?, deviceName}` → Session.
- 403 `registration_closed`; 400 `invalid_invite` (invite mode without a valid code);
  400 `invalid_username` / `password_too_short` (8+) / `username_taken`.

`POST /v1/auth/logout` (auth) → `{ok: true}`; revokes the calling token.

### Device sign-in (how the app signs in through a browser)

Modelled on the OAuth device authorization grant, so the app needs no deep
links: the browser does password or OAuth sign-in, the user confirms, the app
polls.

`POST /v1/auth/device` `{deviceName, platform?}` →

```json
{"deviceCode": "…", "userCode": "ABCD-EFGH",
 "verificationUrl": "https://den.example/link?code=ABCD-EFGH",
 "expiresIn": 600, "interval": 3}
```

`POST /v1/auth/device/poll` `{deviceCode}` →
- 200 Session once approved (works once; later polls give 410),
- 202 `{"status": "pending"}`,
- 403 `access_denied`, 410 `expired` (also for unknown codes).

The confirmation page (web, signed in) uses:
- `GET /v1/auth/device/<userCode>` (auth) → `{userCode, deviceName, platform, createdAt, expiresAt}`; 404 `not_found`.
- `POST /v1/auth/device/<userCode>/approve` (auth) → `{ok: true}`: the new token belongs to the approving user.
- `POST /v1/auth/device/<userCode>/deny` (auth) → `{ok: true}`.

User codes are case-insensitive and ignore `-` and spaces.

### Pairing code (QR shown on the web, claimed by another device)

- `POST /v1/pair/codes` (auth) → `{code, expiresAt, server, uri: "tako://den/pair?server=…&code=…", qrSvg}`.
- `POST /v1/pair/claim` `{code, deviceName}` → Session. 400 `invalid_code`.

### OAuth

Provider types: `google`, `discord`, `github` and `oidc` (any OpenID Connect
issuer: Authentik, Keycloak, Authelia, Zitadel…). Every flow uses `state`;
`google`, `discord` and `oidc` also use PKCE (S256) and `oidc`/`google` a nonce.
Redirect URI: `<publicUrl>/v1/auth/oauth/<id>/callback`. OAuth needs a public URL
(admin setting or `TAKO_PUBLIC_URL`); without one, start gives 400 `public_url_required`.

`GET /v1/auth/oauth/<id>/start?return=<path>&device=<userCode>&invite=<code>` —
a browser navigation, answered with a 302 to the provider. `return` must be a
local path (starts with a single `/`), default `/`. `device` continues to the
device confirmation page after sign-in. `invite` lets a new account register in
invite mode.

`GET /v1/auth/oauth/<id>/callback?code=…&state=…` (from the provider):
1. Validates the state (single use, 10 minutes), exchanges the code, reads the
   identity (stable subject id, email, name, username hint).
2. Linking flow (state created by `/v1/me/identities/<id>/link`): attaches the
   identity to that user, then redirects to `/settings?linked=<id>`. If the
   identity belongs to another user: `/settings?error=identity_in_use`.
3. Sign-in: a known identity signs its user in. An unknown one creates a user
   only if registration is `open`, or `invite` with a valid invite; the
   username comes from the provider's username, else the email's local part,
   sanitized and made unique. Accounts are **never** merged by email.
   Disabled users and closed registration redirect to `/login?error=<code>`.
4. On success: redirects to `/oauth?ticket=<ticket>&return=<return>`, or
   `/link?code=<userCode>&ticket=<ticket>` when `device` was given. Tickets are
   single use and live 2 minutes.

`POST /v1/auth/ticket` `{ticket, deviceName}` → Session (the browser's own token).
400 `invalid_ticket`.

## The signed-in user

- `GET /v1/me` → `{user: User, device: {id, name}, seq}` (`seq`: latest sync sequence).
- `PATCH /v1/me` `{displayName}` → User.
- `POST /v1/me/password` `{currentPassword?, newPassword}` → `{ok: true}`.
  `currentPassword` is required when the user has one (403 `invalid_login`).
- `GET /v1/me/identities` → `{identities: [{id, providerId, providerName, email, name, createdAt}]}`.
- `POST /v1/me/identities/<providerId>/link` → `{url}`; the browser navigates there.
- `DELETE /v1/me/identities/<id>` → `{ok: true}`; 400 `last_sign_in_method` when
  the user would have neither a password nor an identity left.
- `GET /v1/devices` → `{devices: [{id, name, createdAt, lastSeenAt}], current}`.
- `POST /v1/devices` `{name}` → Session: an API key for another app, shown once.
- `DELETE /v1/devices/<id>` → `{ok: true}`.
- `GET /v1/usage` → `{usage: [{model, day, requests, inputTokens, outputTokens}], today: {sharedTokens, limit}}`.

### The user's own providers

Need permission `ownProviders` (else 403 `forbidden`).

- `GET /v1/me/providers` → `{providers: [Provider]}` (`source: "user"`).
- `POST /v1/me/providers` `{name, displayName?, baseUrl, apiKey?, models?, enabled?}` → Provider.
  409 `name_taken`.
- `PATCH /v1/me/providers/<id>` (partial) → Provider. `DELETE /v1/me/providers/<id>`.
- `POST /v1/me/providers/<id>/test` → `{ok: true, models: ["…"]}` or `{ok: false, error: "…"}`.

Unless the admin allows it (`userProvidersAllowPrivateNetworks`), a user's
provider may not reach loopback, private, link-local or unique-local addresses:
the host is resolved at request time and such requests fail with 400
`private_address` (create/patch reject literal private hosts up front).

## Model gateway (OpenAI-compatible)

- `GET /v1/models` (auth) → `{object: "list", data: [{id, object: "model", owned_by}]}`:
  enabled shared providers the user may use (permission `useSharedProviders`
  and provider `access`), then the user's own enabled providers. Unreachable
  upstreams are skipped; upstream lists are cached for 5 minutes.
- `POST /v1/chat/completions` (auth): forwards to the provider in the model id
  with the model part only, the provider's key, never the caller's token.
  Streams pass through unchanged. 404 `model_not_found` for unknown models and
  for models the user may not use (same answer, so it reveals nothing). With an
  allowlist, only its models are forwarded; without one, any model is forwarded
  and the upstream decides (no extra `/models` request first).
  429 `quota_exceeded` when a shared-provider request starts after today's
  shared tokens reached `dailyTokenLimit`. Usage is recorded per user, model
  and UTC day, marked shared or own.
  Upstream failures (bodies are never relayed whole; error messages are cut to
  500 characters with the provider's key masked):
  - 400, 404, 413, 422 → 400 `upstream_rejected`, message from the upstream's
    `error.message` (for example a context-length error).
  - 401, 403 → 502 `upstream_auth` (the provider refused the server's key).
  - 429 → 429 `upstream_rate_limited`, passing `Retry-After` through.
  - other statuses → 502 `upstream_error` naming the upstream status;
    connection failures → 502 `upstream_unreachable`.

## Synchronisation

Records are opaque JSON objects in collections `conversations`, `messages`,
`memories`, `automations`, `settings`, `providers` and `files`; the bodies are
the app's own JSON. Every change gets the user's next sequence number.

- `POST /v1/sync/push` `{changes: [{collection, id, baseVersion, data | deleted: true}]}` (1–500) →
  `{seq, results: [{status: "ok", collection, id, version, seq} | {status: "conflict", collection, id, current: Record|null} | {status: "rejected", collection, id, reason}]}`.
  `baseVersion` is the version the client last saw (0 for new). Each record ≤ 1 MB.
- `GET /v1/sync/pull?since=<seq>&limit=<1..1000>&collections=a,b` →
  `{changes: [Record], seq, more, reset?}` oldest first; repeat while `more`.
  `reset: true`: tombstones the device never saw were pruned (after 90 days);
  pull again from 0 and drop synced records the server no longer has.
- Record: `{collection, id, version, seq, data | deleted: true, updatedAt, deviceId}`.
- `PUT /v1/blobs/<sha256>` (raw body), `GET|HEAD /v1/blobs/<sha256>`: files by
  lowercase SHA-256, idempotent.

## Live events

`GET /v1/events` (auth): server-sent events; a comment line every 25 s.
- `sync` `{seq, deviceId}`: pull.
- `models` `{}`: the model list changed for this user (providers or permissions); refetch `/v1/models`.
- `account` `{}`: the user's role, permissions or profile changed; refetch `/v1/me`.

## Administration (role `admin`; others get 403 `forbidden`)

**Settings**

`GET /v1/admin/settings` →

```json
{
  "serverName": "Tako Den",
  "publicUrl": "https://den.example" | null,
  "publicUrlLocked": false,            // true when TAKO_PUBLIC_URL sets it
  "registration": "closed" | "invite" | "open",
  "passwordLogin": true,
  "defaultPermissions": Permissions,
  "userProvidersAllowPrivateNetworks": false
}
```

`PATCH /v1/admin/settings` (partial) → the same shape. A change that affects
models or permissions sends `models` / `account` events to the users concerned.

**Users**

- `GET /v1/admin/users` → `{users: [AdminUser]}` where AdminUser =
  User fields plus `disabled`, `permissions` (overrides, fields may be null),
  `effectivePermissions`, `identities: [{providerId, email}]`, `lastSeenAt`,
  `usageToday` (shared tokens).
- `POST /v1/admin/users` `{username, password, displayName?, role?}` → AdminUser.
- `PATCH /v1/admin/users/<id>` `{displayName?, role?, disabled?, password?, permissions?}` → AdminUser.
  Disabling revokes the user's tokens. 400 `last_admin` when no enabled
  administrator would remain.
- `DELETE /v1/admin/users/<id>` → `{ok: true}`: removes the user with their
  devices, records, blobs and providers. 400 `last_admin`.

**Shared providers**

- `GET /v1/admin/providers` → `{providers: [Provider]}` (admin and config ones).
- `POST /v1/admin/providers` `{name, displayName?, baseUrl, apiKey?, models?, enabled?, access?}` → Provider. 409 `name_taken`.
- `PATCH /v1/admin/providers/<id>`, `DELETE /v1/admin/providers/<id>`; 400 `read_only` for config providers.
- `POST /v1/admin/providers/<id>/test` → like the user version.

**OAuth providers**

OAuthProvider:

```json
{"id": "google", "type": "google", "name": "Google", "clientId": "…",
 "hasClientSecret": true, "issuer": null, "scopes": ["openid", "email", "profile"],
 "enabled": true, "source": "admin" | "config",
 "redirectUri": "https://den.example/v1/auth/oauth/google/callback" | null}
```

- `GET /v1/admin/oauth` → `{providers: [OAuthProvider]}`.
- `POST /v1/admin/oauth` `{type, id?, name?, clientId, clientSecret, issuer?, scopes?, enabled?}` → OAuthProvider.
  `id` defaults to the type, `^[a-z0-9-]{1,32}$`, unique (409 `id_taken`). `oidc` needs `issuer`.
- `PATCH /v1/admin/oauth/<id>`, `DELETE /v1/admin/oauth/<id>` (linked identities
  stay; they work again if the id is re-added).
- Environment variables `TAKO_OAUTH_<TYPE>_CLIENT_ID` / `_CLIENT_SECRET`
  (`GOOGLE`, `DISCORD`, `GITHUB`) and `TAKO_OAUTH_OIDC_ISSUER` / `_CLIENT_ID` /
  `_CLIENT_SECRET` / `_NAME` add `config` entries.

**Invites**

- `GET /v1/admin/invites` → `{invites: [{code, note, maxUses, uses, expiresAt, createdAt}]}`.
- `POST /v1/admin/invites` `{maxUses?: 1, expiresInDays?: 7, note?}` → invite.
- `DELETE /v1/admin/invites/<code>`.

**Usage**: `GET /v1/admin/usage?days=30` → `{usage: [{userId, username, model, day, requests, inputTokens, outputTokens, shared}]}`.

## Web app

The server serves the files in `web/` (embedded in the executable at build
time; `TAKO_WEB_DIR` serves a folder instead, for development). A GET for an
existing file returns it; any other GET outside `/v1/` and `/healthz` returns
`index.html`, so `/login`, `/link`, `/setup`, `/oauth`, `/settings` and
`/admin` are client-side routes. Pages are sent with:

```
Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'
Referrer-Policy: no-referrer
X-Content-Type-Options: nosniff
```
